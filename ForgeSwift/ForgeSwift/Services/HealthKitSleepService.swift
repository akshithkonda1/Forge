import Foundation
import HealthKit
import ForgeCore

/// Chronotype-aware sleep intelligence: HealthKit ingestion, scoring, adaptive wake/sunrise, and ARIA context.
@MainActor
final class HealthKitSleepService: ObservableObject {
    static let shared = HealthKitSleepService()

    @Published var userProfile: UserSleepProfile
    @Published var currentSunriseConfig: AdaptiveSunriseConfig
    @Published private(set) var isAuthorized = false

    private let healthKit = HealthKitManager.shared

    private init() {
        userProfile = Self.loadUserSleepProfile() ?? UserSleepProfile()
        currentSunriseConfig = AdaptiveSunriseConfig(
            durationMinutes: Chronotype.bear.baseSunriseDuration,
            colorTemp: Chronotype.bear.baseSunriseColorTemp,
            intensity: Chronotype.bear.baseSunriseIntensity,
            rationale: "Balanced sunrise for your chronotype"
        )
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

    func fetchRecentSleepData(days: Int = 14) async -> [SleepData] {
        guard isAuthorized || healthKit.isAuthorized else { return [] }
        let sessions = await healthKit.fetchRecentSleepSessions(days: days)
        let recentWakes = sessions.compactMap(\.wake)
        return sessions.map { session in
            let scored = scoreNight(
                totalHours: session.totalHours,
                deepMinutes: session.deepMinutes,
                remMinutes: session.remMinutes,
                awakeMinutes: session.awakeMinutes,
                profile: userProfile,
                recentWakes: recentWakes
            )
            return SleepData(
                date: session.date,
                totalHours: session.totalHours,
                deepMinutes: session.deepMinutes,
                remMinutes: session.remMinutes,
                lightMinutes: session.lightMinutes,
                awakeMinutes: session.awakeMinutes,
                score: scored,
                onset: session.onset,
                wake: session.wake
            )
        }
    }

    func scoreNight(
        totalHours: Double,
        deepMinutes: Int,
        remMinutes: Int,
        awakeMinutes: Int,
        profile: UserSleepProfile,
        recentWakes: [Date] = []
    ) -> Int {
        let chronotype = profile.chronotype
        let targetHours = chronotype.targetSleepHours

        let durationScore = min(100, (totalHours / targetHours) * 100)
        let deepScore = min(100, (Double(deepMinutes) / Double(chronotype.deepSleepGoalMinutes)) * 100)
        let remScore = min(100, (Double(remMinutes) / Double(chronotype.remSleepGoalMinutes)) * 100)

        let totalMinutes = totalHours * 60
        let efficiency = totalMinutes > 0
            ? max(0, ((totalMinutes - Double(awakeMinutes)) / totalMinutes) * 100)
            : 0

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

        let weighted = durationScore * 0.35
            + deepScore * 0.25
            + remScore * 0.20
            + efficiency * 0.15
            + consistency * 0.05

        return min(100, max(0, Int(weighted.rounded())))
    }

    // MARK: - Sleep Debt

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
        chronotype: Chronotype
    ) -> Int {
        var window = baseWindow
        if let score = recentScore {
            if score < 70 { window = min(45, window + 15) }
            else if score >= 85 { window = max(15, window - 10) }
        }
        if debt > 3 { window = min(45, window + 5) }
        switch chronotype {
        case .dolphin: window = min(45, window + 5)
        case .wolf: window = min(45, window + 5)
        case .lion: window = max(15, window - 5)
        case .bear: break
        }
        return max(15, min(45, window))
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

    // MARK: - Achievements

    func computeAchievements(from sleepData: [SleepData]) -> [SleepAchievementState] {
        let streak = sleepData.prefix(while: { $0.score >= 75 }).count
        let avgDeep = sleepData.prefix(7).map(\.deepMinutes).reduce(0, +) / max(1, min(7, sleepData.count))
        let perfectWeek = sleepData.prefix(7).count == 7 && sleepData.prefix(7).allSatisfy { $0.score >= 85 }

        return [
            SleepAchievementState(
                id: "perfect-week",
                title: "Perfect Week",
                description: "7 days of 85+ scores",
                unlocked: perfectWeek,
                progress: Double(min(streak, 7)) / 7,
                colorName: "ember"
            ),
            SleepAchievementState(
                id: "deep-sleeper",
                title: "Deep Sleeper",
                description: "90+ min deep avg",
                unlocked: avgDeep >= 90,
                progress: min(1, Double(avgDeep) / 90),
                colorName: "steel"
            ),
            SleepAchievementState(
                id: "consistency",
                title: "Consistency",
                description: "7-day good-sleep streak",
                unlocked: streak >= 7,
                progress: Double(min(streak, 7)) / 7,
                colorName: "success"
            ),
        ]
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

    // MARK: - Profile

    func updateProfile(_ profile: UserSleepProfile) {
        userProfile = profile
        Self.saveUserSleepProfile(profile)
    }

    private static let profileKey = "forge.sleep.userProfile"

    static func saveUserSleepProfile(_ profile: UserSleepProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: profileKey)
    }

    static func loadUserSleepProfile() -> UserSleepProfile? {
        guard let data = UserDefaults.standard.data(forKey: profileKey),
              let profile = try? JSONDecoder().decode(UserSleepProfile.self, from: data) else {
            return nil
        }
        return profile
    }

    func chronotypeInsightPrefix() -> String {
        let chronotype = userProfile.chronotype
        return "As a \(chronotype.displayName) (\(chronotype.tagline)), "
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