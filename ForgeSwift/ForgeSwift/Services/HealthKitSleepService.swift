import Foundation
import HealthKit
import UIKit
import CoreGraphics
import ForgeCore

/// A logged in-bed window from Apple Health. Not a scored night.
struct InBedWindow: Equatable {
    let start: Date
    let end: Date
    var hours: Double { max(0, end.timeIntervalSince(start) / 3600) }
}

/// Chronotype-aware sleep intelligence: HealthKit ingestion, scoring, adaptive wake/sunrise, and ARIA context.
@MainActor
final class HealthKitSleepService: ObservableObject {
    static let shared = HealthKitSleepService()

    @Published var userProfile: UserSleepProfile
    @Published var currentSunriseConfig: AdaptiveSunriseConfig
    @Published private(set) var isAuthorized = false

    /// Lazy ARIA notes for the Sleep tab's cards — one per card, fired only
    /// once that card actually appears, guarded on the note already being
    /// set. Same pattern as `LifestyleViewModel`'s `refreshMealNote` family:
    /// nil means "show the local heuristic," never a fake "LIVE" badge.
    @Published var aiBedtimeNote: String?
    @Published var aiGoalsNote: String?
    @Published var aiRecommendationsNote: String?

    /// Result of the last room-photo read from `/sleep/environment-check`.
    /// nil after a call means the backend declined (Bedrock off, or the
    /// call failed) — the card falls back to its local, data-driven read
    /// rather than inventing an assessment of a photo nobody analyzed.
    @Published var environmentAssessment: String?
    @Published private(set) var isAnalyzingEnvironment = false
    @Published var environmentCheckError: String?

    /// Last scored nights, so the alarm scheduler can widen/narrow the smart
    /// window from score and debt without re-querying HealthKit.
    @Published private(set) var cachedSleepData: [SleepData] = []
    /// Open in-bed clock, local until they tap I'm up and Apple Health accepts the write.
    @Published var inBedStartedAt: Date?
    /// Last in-bed window we wrote or read. Not a sleep score.
    @Published var lastInBedWindow: InBedWindow?

    /// Unusual-for-you flags from the newest scored night. Nil until a night lands.
    @Published private(set) var lastDepthResult: SleepDepthResult?

    private let healthKit = HealthKitManager.shared
    private var cachedSleepData: [SleepData] = []

    private init() {
        userProfile = Self.loadUserSleepProfile() ?? UserSleepProfile()
        currentSunriseConfig = AdaptiveSunriseConfig(
            durationMinutes: UserDefaults.standard.object(forKey: Self.sunriseDurationKey) as? Int
                ?? Chronotype.bear.baseSunriseDuration,
            colorTemp: UserDefaults.standard.object(forKey: Self.sunriseColorKey) as? Double
                ?? Chronotype.bear.baseSunriseColorTemp,
            intensity: Chronotype.bear.baseSunriseIntensity,
            rationale: "Balanced sunrise for your chronotype"
        )
        loadOpenInBed()
    }

    private static let sunriseDurationKey = "forge.sunrise.durationMinutes"
    private static let sunriseColorKey = "forge.sunrise.colorTemp"
    private static let inBedStartKey = "forge.sleep.inBedStartedAt"

    func applySunriseOverrides(durationMinutes: Int, colorTemp: Double) {
        currentSunriseConfig.durationMinutes = min(60, max(5, durationMinutes))
        currentSunriseConfig.colorTemp = min(1, max(0, colorTemp))
        UserDefaults.standard.set(currentSunriseConfig.durationMinutes, forKey: Self.sunriseDurationKey)
        UserDefaults.standard.set(currentSunriseConfig.colorTemp, forKey: Self.sunriseColorKey)
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await healthKit.requestAuthorization()
            isAuthorized = healthKit.isAuthorized
            return isAuthorized
        } catch {
            return false
        }
    }

    // MARK: - Fetch + Score

    /// Honest Day-tab empty copy. Connected-but-empty is not "reconnect."
    nonisolated static func dayEmptyCopy(healthConnected: Bool) -> (title: String, message: String, cta: String) {
        if healthConnected {
            return (
                "No scored night yet",
                "Forge reads stages from Apple Health. Until a night lands, log in-bed on Tonight — that's a real window, not a fake score.",
                "Refresh from Apple Health"
            )
        }
        return (
            "Connect Apple Health to unlock sleep",
            "Forge reads last night's stages from Apple Health. Once a night lands, ARIA can explain recovery and bedtime.",
            "Reconnect Apple Health"
        )
    }

    func refreshFromAppleHealth(into store: AppStore, days: Int = 14) async {
        loadOpenInBed()
        guard await requestAuthorization() else { return }
        let nights = await fetchRecentSleepData(days: days)
        store.mergeSleepDataLocally(nights)
        if let window = await healthKit.fetchLatestInBedWindow() {
            lastInBedWindow = InBedWindow(start: window.start, end: window.end)
        }
    }

    func beginInBed(at date: Date = Date()) {
        inBedStartedAt = date
        UserDefaults.standard.set(date, forKey: Self.inBedStartKey)
    }

    func cancelInBed() {
        inBedStartedAt = nil
        UserDefaults.standard.removeObject(forKey: Self.inBedStartKey)
    }

    @discardableResult
    func endInBed(at date: Date = Date()) async -> Bool {
        guard let start = inBedStartedAt else { return false }
        _ = await requestAuthorization()
        guard healthKit.isAuthorized else { return false }
        await healthKit.saveInBedWindow(startedAt: start, endedAt: date)
        lastInBedWindow = InBedWindow(start: start, end: max(date, start.addingTimeInterval(60)))
        cancelInBed()
        return true
    }

    @discardableResult
    func logInBedWindow(startedAt: Date, endedAt: Date) async -> Bool {
        _ = await requestAuthorization()
        guard healthKit.isAuthorized else { return false }
        await healthKit.saveInBedWindow(startedAt: startedAt, endedAt: endedAt)
        lastInBedWindow = InBedWindow(start: startedAt, end: max(endedAt, startedAt.addingTimeInterval(60)))
        return true
    }

    private func loadOpenInBed() {
        inBedStartedAt = UserDefaults.standard.object(forKey: Self.inBedStartKey) as? Date
    }

    func fetchRecentSleepData(days: Int = 14) async -> [SleepData] {
        guard isAuthorized || healthKit.isAuthorized else { return [] }
        let sessions = await healthKit.fetchRecentSleepSessions(days: days)
        let recentWakes = sessions.compactMap(\.wake)
        var baselines = SleepDepthBaselineStore.load()
        let scoredNights = sessions.map { session -> SleepData in
            let scored = scoreNight(
                totalHours: session.totalHours,
                deepMinutes: session.deepMinutes,
                remMinutes: session.remMinutes,
                awakeMinutes: session.awakeMinutes,
                profile: userProfile,
                recentWakes: recentWakes,
                baselines: baselines
            )
            return SleepData(
                date: session.date,
                totalHours: session.totalHours,
                deepMinutes: session.deepMinutes,
                remMinutes: session.remMinutes,
                lightMinutes: session.lightMinutes,
                awakeMinutes: session.awakeMinutes,
                score: scored.score,
                onset: session.onset,
                wake: session.wake
            )
        }
        rememberSleepSignals(from: scoredNights)
        .sorted { $0.date > $1.date }
        if let newest = scoredNights.first {
            lastDepthResult = scoreNight(
                totalHours: newest.totalHours,
                deepMinutes: newest.deepMinutes,
                remMinutes: newest.remMinutes,
                awakeMinutes: newest.awakeMinutes,
                profile: userProfile,
                recentWakes: recentWakes,
                baselines: baselines
            )
        } else {
            lastDepthResult = nil
        }
        rememberSleepSignals(from: scoredNights, baselines: &baselines)
        SleepDepthBaselineStore.save(baselines)
        if let flag = lastDepthResult?.headline {
            AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
                category: .appleHealth,
                kind: "sleep_depth",
                summary: flag,
                source: "sleep-depth"
            ))
        }
        return scoredNights
    }

    func scoreNight(
        totalHours: Double,
        deepMinutes: Int,
        remMinutes: Int,
        awakeMinutes: Int,
        profile: UserSleepProfile,
        recentWakes: [Date] = [],
        baselines: SleepDepthBaselines? = nil
    ) -> SleepDepthResult {
        let chronotype = profile.chronotype
        let targetHours = chronotype.targetSleepHours

        let durationScore = min(100, (totalHours / targetHours) * 100)
        let deepScore = min(100, (Double(deepMinutes) / Double(chronotype.deepSleepGoalMinutes)) * 100)
        let remScore = min(100, (Double(remMinutes) / Double(chronotype.remSleepGoalMinutes)) * 100)

        let asleepMinutes = totalHours * 60
        let efficiency = Self.sleepEfficiencyPercent(asleepMinutes: asleepMinutes, awakeMinutes: awakeMinutes)

        // Same spread→confidence map as CircadianRhythm.phase: a 3-hour circular
        // SD is "no schedule". Under five wakes there is not enough signal, so
        // keep the old neutral 80 rather than punish a new user for missing data.
        let consistency: Double
        if recentWakes.count >= 5 {
            let spread = CircadianRhythm.circularSpread(recentWakes.map { CircadianRhythm.hourOfDay($0) })
            consistency = max(0, min(100, (1 - spread / 3.0) * 100))
        } else {
            consistency = 80
        }
        let metrics = SleepNightMetrics(
            totalHours: totalHours,
            deepMinutes: Double(deepMinutes),
            remMinutes: Double(remMinutes),
            efficiencyPercent: SleepNightMetrics.efficiencyPercent(
                asleepHours: totalHours,
                awakeMinutes: Double(awakeMinutes)
            ),
            wakeConsistency: consistency
        )
        let targets = SleepChronotypeTargets(
            targetHours: chronotype.targetSleepHours,
            deepGoalMinutes: Double(chronotype.deepSleepGoalMinutes),
            remGoalMinutes: Double(chronotype.remSleepGoalMinutes)
        )
        return SleepDepthScorer.score(
            metrics: metrics,
            targets: targets,
            baselines: baselines ?? SleepDepthBaselineStore.load()
        )
    }

    /// Time actually asleep as a fraction of time in bed (asleep + awake).
    /// Same formula as `SleepData.efficiencyPercent` (Models.swift) — keep them
    /// consistent rather than each drifting to its own definition of "efficiency".
    static func sleepEfficiencyPercent(asleepMinutes: Double, awakeMinutes: Int) -> Double {
        let bed = asleepMinutes + Double(awakeMinutes)
        guard bed > 0 else { return 0 }
        return max(0, min(100, (asleepMinutes / bed) * 100))
    }

    // MARK: - Sleep Debt

    func rememberSleepSignals(from data: [SleepData]) {
        cachedSleepData = data
        var baselines = SleepDepthBaselineStore.load()
        rememberSleepSignals(from: data, baselines: &baselines)
        SleepDepthBaselineStore.save(baselines)
    }

    private func rememberSleepSignals(from data: [SleepData], baselines: inout SleepDepthBaselines) {
        cachedSleepData = data
        for night in data.reversed() {
            let metrics = SleepNightMetrics(
                totalHours: night.totalHours,
                deepMinutes: Double(night.deepMinutes),
                remMinutes: Double(night.remMinutes),
                efficiencyPercent: Double(night.efficiencyPercent),
                wakeConsistency: 80
            )
            SleepDepthScorer.observe(&baselines, metrics: metrics, nightKey: night.date)
        }
    }

    func adaptiveSmartWakeMinutes(base: Int) -> Int {
        computeSmartAlarmWindow(
            baseWindow: base,
            recentScore: cachedSleepData.first?.score,
            debt: computeSleepDebt(from: cachedSleepData),
            chronotype: userProfile.chronotype
        )
    }

    /// Hours of sleep owed over the trailing fortnight.
    ///
    /// Two things changed here relative to the obvious version, both because the
    /// obvious version reads better than it behaves:
    ///
    /// Summing a week and subtracting a target lets a surplus cancel a deficit,
    /// so a ten-hour Saturday erases two ruined weeknights and the figure says
    /// you are fine. Debt is per-night and one-directional; you cannot sleep
    /// ahead.
    ///
    /// And the target is estimated from the user's own best nights rather than
    /// read off their chronotype. A chronotype is a phase preference — when you
    /// sleep — not a quantity. Two bears do not need the same eight hours.
    func computeSleepDebt(from sleepData: [SleepData]) -> Double {
        // `sleepData` arrives newest-first; the engine's window is a suffix.
        let durations = Array(sleepData.map(\.totalHours).reversed())
        let need = CircadianRhythm.sleepNeedHours(fromAsleepHours: durations)
        return CircadianRhythm.sleepDebtHours(asleepHours: durations, need: need)
    }

    func estimatedSleepNeed(from sleepData: [SleepData]) -> Double {
        let durations = Array(sleepData.map(\.totalHours).reversed())
        return CircadianRhythm.sleepNeedHours(fromAsleepHours: durations)
    }

    func targetSleepHours() -> Double {
        userProfile.chronotype.targetSleepHours
    }

    // MARK: - Adaptive Sunrise

    func computeAdaptiveSunrise(
        debt: Double,
        recentScore: Int?,
        profile: UserSleepProfile
    ) -> AdaptiveSunriseConfig {
        let chronotype = profile.chronotype
        var duration = chronotype.baseSunriseDuration
        var colorTemp = chronotype.baseSunriseColorTemp
        var intensity = chronotype.baseSunriseIntensity
        var rationale = "Optimized for your \(chronotype.displayName) rhythm"

        if let score = recentScore, score < 70 {
            duration += 10
            colorTemp = max(0, colorTemp - 0.15)
            intensity = max(0.2, intensity - 0.15)
            rationale = "Gentler ramp — last night scored \(score)"
        }

        if debt > 3 {
            duration += 5
            intensity = max(0.2, intensity - 0.1)
            rationale = "Extra recovery — \(String(format: "%.1f", debt))h sleep debt this week"
        } else if debt > 1 {
            rationale = "Mild debt detected — slightly softer wake"
            colorTemp = max(0, colorTemp - 0.05)
        }

        let config = AdaptiveSunriseConfig(
            durationMinutes: min(60, max(5, duration)),
            colorTemp: min(1, max(0, colorTemp)),
            intensity: min(1, max(0.2, intensity)),
            rationale: rationale
        )
        currentSunriseConfig = config
        return config
    }

    // MARK: - Smart Alarm

    func computeSmartAlarmWindow(
        baseWindow: Int,
        recentScore: Int?,
        debt: Double,
        chronotype: Chronotype,
        struggleAverageSnoozes: Double? = nil
    ) -> Int {
        SmartAlarmWindow.minutes(
            base: baseWindow,
            recentScore: recentScore,
            debtHours: debt,
            bias: smartBias(for: chronotype),
            struggleAverageSnoozes: struggleAverageSnoozes ?? WakeStruggleStore.averageSnoozes()
        )
    }

    private func smartBias(for chronotype: Chronotype) -> SmartAlarmWindow.ChronotypeBias {
        switch chronotype {
        case .lion: return .lion
        case .bear: return .bear
        case .wolf: return .wolf
        case .dolphin: return .dolphin
        }
    }

    // MARK: - Adaptive Goals

    func computeAdaptiveGoals(from sleepData: [SleepData]) -> [AdaptiveSleepGoal] {
        guard let latest = sleepData.first else { return [] }
        let chronotype = userProfile.chronotype
        return [
            AdaptiveSleepGoal(
                id: "total",
                title: "Total Sleep",
                current: latest.totalHours,
                target: chronotype.targetSleepHours,
                unit: "hrs",
                icon: "bed.double.fill"
            ),
            AdaptiveSleepGoal(
                id: "deep",
                title: "Deep Sleep",
                current: Double(latest.deepMinutes) / 60,
                target: Double(chronotype.deepSleepGoalMinutes) / 60,
                unit: "hrs",
                icon: "moon.zzz.fill"
            ),
            AdaptiveSleepGoal(
                id: "score",
                title: "Sleep Score",
                current: Double(latest.score),
                target: 85,
                unit: "",
                icon: "star.fill"
            ),
        ]
    }

    // MARK: - Streak

    /// Consecutive most-recent nights scoring 75+. `sleepData` arrives
    /// newest-first, so this is a straight prefix count, not a scan.
    func computeGoodSleepStreak(from sleepData: [SleepData]) -> Int {
        sleepData.prefix(while: { $0.score >= 75 }).count
    }

    // MARK: - Recommendations

    func chronotypeRecommendations(debt: Double) -> [SleepRecommendation] {
        let chronotype = userProfile.chronotype
        var recs: [SleepRecommendation] = []

        switch chronotype {
        case .lion:
            recs.append(SleepRecommendation(
                id: "lion-sun",
                icon: "sun.max.fill",
                title: "Morning Sunlight",
                description: "10–15 min outdoor light within 30 min of waking",
                priority: "High"
            ))
            recs.append(SleepRecommendation(
                id: "lion-wind",
                icon: "moon.fill",
                title: "Early Wind-Down",
                description: "Start your routine by 9:00 PM to protect deep sleep",
                priority: "High"
            ))
        case .bear:
            recs.append(SleepRecommendation(
                id: "bear-routine",
                icon: "clock.fill",
                title: "Consistent Schedule",
                description: "Keep bedtime within ±30 min of \(formatHour(chronotype.idealWakeHour - chronotype.targetSleepHours))",
                priority: "High"
            ))
            recs.append(SleepRecommendation(
                id: "bear-caffeine",
                icon: "cup.and.saucer.fill",
                title: "Caffeine Cutoff",
                description: "Last coffee by 2:00 PM for better sleep quality",
                priority: "Medium"
            ))
        case .wolf:
            recs.append(SleepRecommendation(
                id: "wolf-dim",
                icon: "lightbulb.fill",
                title: "Dim Evenings",
                description: "Lower light 90 min before bed — wolves run late but need darkness",
                priority: "High"
            ))
            recs.append(SleepRecommendation(
                id: "wolf-morning",
                icon: "sunrise.fill",
                title: "Delayed Bright Light",
                description: "Use sunrise simulation instead of harsh overhead lights",
                priority: "Medium"
            ))
        case .dolphin:
            recs.append(SleepRecommendation(
                id: "dolphin-gentle",
                icon: "leaf.fill",
                title: "Gentle Recovery",
                description: "Prioritize a longer sunrise ramp and lighter training after poor nights",
                priority: "High"
            ))
            recs.append(SleepRecommendation(
                id: "dolphin-noise",
                icon: "waveform",
                title: "Sound Masking",
                description: "Pink noise or fan sounds can reduce micro-awakenings",
                priority: "Medium"
            ))
        }

        if debt > 2 {
            recs.insert(SleepRecommendation(
                id: "debt-recovery",
                icon: "bed.double.fill",
                title: "Sleep Debt Recovery",
                description: "Add 30–45 min tonight — you're \(String(format: "%.1f", debt))h behind this week",
                priority: "High"
            ), at: 0)
        }

        return recs
    }

    // MARK: - ARIA notes

    /// Lazy ARIA "why tonight" note for `AISleepPredictionCard` — the numeric
    /// bedtime itself comes from `EnergySchedule` (real circadian modeling,
    /// no LLM needed); this is the natural-language reasoning layered on top.
    func refreshBedtimeNote(store: AppStore, schedule: EnergySchedule) async {
        guard aiBedtimeNote == nil else { return }
        let prompt = """
        Tonight's bedtime works out to \(EnergySchedule.clockLabel(schedule.phase.onsetHour)), \
        with \(String(format: "%.1f", schedule.debtHours))h of sleep debt over the last \
        \(schedule.nightsUsed) nights. Speak as if this person is becoming someone who keeps \
        a regular night — not as if they have a streak to protect. One sentence, why tonight \
        specifically calls for that time.
        """
        let resp = await store.ariaInsight(prompt: prompt, agent: .sleep)
        aiBedtimeNote = resp.map { $0.proseSummary ?? $0.message }
    }

    /// Lazy ARIA coaching note for `AIPersonalizedGoalsView` — the goal
    /// progress bars are already real (`computeAdaptiveGoals`); this adds
    /// the "so what" ARIA would say about where they stand.
    func refreshGoalsNote(store: AppStore, goals: [AdaptiveSleepGoal]) async {
        guard aiGoalsNote == nil, let behind = goals.min(by: { ($0.current / max(0.01, $0.target)) < ($1.current / max(0.01, $1.target)) }) else { return }
        let prompt = """
        Of my sleep goals, \(behind.title) is furthest off — \(String(format: "%.1f", behind.current)) \
        of \(String(format: "%.1f", behind.target)) \(behind.unit). Speak as identity, not a score to \
        protect: what's the single highest-leverage change to close that gap? One sentence.
        """
        let resp = await store.ariaInsight(prompt: prompt, agent: .sleep)
        aiGoalsNote = resp.map { $0.proseSummary ?? $0.message }
    }

    /// Lazy ARIA note for `AISmartRecommendationsView` — layered on top of
    /// the real chronotype-driven `chronotypeRecommendations(debt:)` list,
    /// same "heuristic list + one ARIA sentence" shape as the goals note.
    func refreshRecommendationsNote(store: AppStore, debt: Double) async {
        guard aiRecommendationsNote == nil else { return }
        let prompt = """
        \(chronotypeInsightPrefix())and \(String(format: "%.1f", debt))h of sleep debt this week, \
        what's the one thing I should actually change tonight? One sentence, specific, not generic advice.
        """
        let resp = await store.ariaInsight(prompt: prompt, agent: .sleep)
        aiRecommendationsNote = resp.map { $0.proseSummary ?? $0.message }
    }

    // MARK: - Environment (vision)

    /// Sends a real photo of the room to `/sleep/environment-check`, which
    /// now actually reads it (`BedrockGateway.converse` carries an image
    /// content block; see `ai_router.py`). No fabricated readings — a nil
    /// `environmentAssessment` after this call means the backend declined
    /// (Bedrock off, or the call failed), and the card shows its local,
    /// data-driven read instead rather than inventing a description of the room.
    func analyzeSleepEnvironment(image: UIImage) async {
        isAnalyzingEnvironment = true
        defer { isAnalyzingEnvironment = false }

        guard let jpeg = image.downscaledJPEG(maxDimension: 1024, quality: 0.55) else {
            environmentCheckError = "Couldn't read that photo — try another."
            return
        }

        do {
            guard let url = URL(string: "sleep/environment-check", relativeTo: AriaService.shared.baseURL) else {
                throw ForgeAPI.Failure.notConfigured
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["image_base64": jpeg.base64EncodedString()])

            let (data, _) = try await ForgeAPI.send(request)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard (json["available"] as? Bool) == true, let text = json["assessment"] as? String else {
                environmentAssessment = Self.localEnvironmentRead(image: image)
                environmentCheckError = nil
                return
            }
            environmentAssessment = text
            environmentCheckError = nil
        } catch {
            environmentAssessment = Self.localEnvironmentRead(image: image)
            environmentCheckError = nil
        }
    }

    // MARK: - Profile

    func updateProfile(_ profile: UserSleepProfile) {
        userProfile = profile
        Self.saveUserSleepProfile(profile)
    }

    private static let profileKey = "forge.sleep.userProfile"

    /// `forge.sleep.userProfile` is one of `SecureStoreMigration.sensitiveKeys`:
    /// the migration sweeps it out of `UserDefaults` into the Keychain on every
    /// launch and deletes the plaintext copy. Reading/writing it here through
    /// anything but this same `SecureStore` would race that migration — save
    /// would resurrect a plaintext copy for the next launch to delete, and load
    /// would find nothing right after it's swept, silently resetting the profile.
    private static let secureStore: SecureStore = KeychainStore()

    static func saveUserSleepProfile(_ profile: UserSleepProfile) {
        try? secureStore.setValue(profile, forKey: profileKey)
    }

    static func loadUserSleepProfile() -> UserSleepProfile? {
        try? secureStore.value(UserSleepProfile.self, forKey: profileKey)
    }

    func chronotypeInsightPrefix() -> String {
        let chronotype = userProfile.chronotype
        return "As a \(chronotype.displayName) (\(chronotype.tagline)), "
    }

    /// On-device room read when Bedrock is off — brightness + clock, labeled as local.
    private static func localEnvironmentRead(image: UIImage) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let dark = averageBrightness(image) < 0.30
        if hour >= 22 || hour < 5 {
            return dark
                ? "On this phone: the frame looks dim and it's late — that's a real wind-down window. Keep it that way."
                : "On this phone: it's late but the frame looks bright. Dim the space if you can."
        }
        return dark
            ? "On this phone: the room already looks dim. Protect that last hour — cooler, quieter."
            : "On this phone: I read the photo locally. Darker and quieter in the last hour helps the night land."
    }

    private static func averageBrightness(_ image: UIImage) -> CGFloat {
        guard let cg = image.cgImage else { return 0.5 }
        let width = 16, height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0.5 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total: CGFloat = 0
        let count = width * height
        for i in 0..<count {
            let o = i * 4
            total += (CGFloat(pixels[o]) + CGFloat(pixels[o + 1]) + CGFloat(pixels[o + 2])) / (3 * 255)
        }
        return total / CGFloat(count)
    }

    private func formatHour(_ hour: Double) -> String {
        // Wrap into [0, 24) so a computed pre-midnight hour (e.g. 7 - 8 = -1) reads as 11 PM, not "-1 AM".
        let norm = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        let h = Int(norm) % 24
        let m = Int((norm - Double(Int(norm))) * 60)
        let period = h >= 12 ? "PM" : "AM"
        let display = h % 12 == 0 ? 12 : h % 12
        return m > 0 ? "\(display):\(String(format: "%02d", m)) \(period)" : "\(display) \(period)"
    }
}