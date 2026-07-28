import Foundation
import Combine

/// Local persistent context + live domain assembly for ARIA v1.1.
@MainActor
final class AriaContextStore: ObservableObject {
    static let shared = AriaContextStore()

    @Published var context: AriaContext
    @Published private(set) var lastProactiveInsight: String?
    @Published private(set) var permissions: AriaPermissionsStore
    @Published private(set) var lastObservedContext: ARIAContextPayload?

    private let defaults = UserDefaults.standard
    private let storageKey = "forge.aria.userContext"
    private let permissionsKey = "forge.aria.permissions"
    private let userIdKey = "forge.aria.userId"

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(AriaContext.self, from: data) {
            context = saved
        } else {
            context = AriaContext(userId: Self.stableUserId())
        }

        if let data = defaults.data(forKey: permissionsKey),
           let saved = try? JSONDecoder().decode(AriaPermissionsStore.self, from: data) {
            permissions = saved
        } else {
            permissions = .allowAll
        }
    }

    static func stableUserId() -> String {
        if let existing = UserDefaults.standard.string(forKey: "forge.aria.userId"), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "forge.aria.userId")
        return id
    }

    func configure(userId: String? = nil) {
        let trimmed = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = trimmed.isEmpty ? Self.stableUserId() : trimmed
        guard context.userId != resolved else { return }
        context.userId = resolved
        defaults.set(resolved, forKey: userIdKey)
        persist()
    }

    func setPermission(_ domain: AriaDataDomain, allowed: Bool) {
        permissions.setAllowed(domain, allowed)
        if let data = try? JSONEncoder().encode(permissions) {
            defaults.set(data, forKey: permissionsKey)
        }
    }

    func buildARIAContext(from store: AppStore) -> ARIAContextPayload {
        let iso = ISO8601DateFormatter()
        let lastSleep = store.sleepData.first
        let nights = store.sleepData.count

        // Cross-zone consistency: keep sleep / readiness / training / cycle tight
        // before any prompt assembly so remote + local paths share one truth.
        let zone = CrossZoneConsistency.snapshot(from: store)
        let zoneConstraints = CrossZoneConsistency.coachingConstraints(for: zone)
        context.constraints.removeAll { $0.hasPrefix("cross_zone:") }
        for c in zoneConstraints where !context.constraints.contains(c) {
            context.constraints.append(c)
        }
        // Lifestyle tags that every surface (and SimRunner-shaped payloads) can read.
        context.lifestyleTags.removeAll { $0.hasPrefix("cross_zone:") }
        context.lifestyleTags.append(contentsOf: zoneConstraints.filter { !$0.contains("directive:") })

        var patterns = context.recentPatterns
        if store.readiness.overall < 55, !patterns.contains("low_readiness_streak") {
            patterns.append("low_readiness_streak")
        }
        if let lastSleep, lastSleep.score >= 85, !patterns.contains("strong_sleep_recovery") {
            patterns.append("strong_sleep_recovery")
        }
        if CrossZoneConsistency.blocksHighIntensity(zone), !patterns.contains("recovery_day_signal") {
            patterns.append("recovery_day_signal")
        }
        context.recentPatterns = patterns

        let lastWorkout = store.workoutHistory.first
        let hoursSinceWorkout: Double? = {
            guard let lastWorkout,
                  let date = ISO8601DateFormatter().date(from: lastWorkout.date) else { return nil }
            return Date().timeIntervalSince(date) / 3600
        }()

        let steps3 = store.sleepData.isEmpty ? nil : Double(store.dailyMetrics.steps)
        let hrvValues = store.sleepData.prefix(7).map { _ in Double(store.dailyMetrics.hrv) }
        let hrvBaseline = hrvValues.isEmpty ? nil : hrvValues.reduce(0, +) / Double(hrvValues.count)
        let hrvTrend: Double? = hrvBaseline.flatMap { baseline in
            guard baseline > 0 else { return nil }
            return ((Double(store.dailyMetrics.hrv) - baseline) / baseline) * 100
        }

        let workouts30d = store.workoutHistory.filter {
            guard let date = ISO8601DateFormatter().date(from: $0.date) else { return false }
            return date > Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        }.count

        let payload = ARIAContextPayload(
            timestamp: iso.string(from: Date()),
            sleep: .init(
                durationMinutes: lastSleep.map { $0.totalHours * 60 },
                efficiency: lastSleep.map { min(1, Double($0.score) / 100) },
                remMinutes: lastSleep.map { Double($0.remMinutes) },
                deepMinutes: lastSleep.map { Double($0.deepMinutes) },
                hrv: store.dailyMetrics.hrv > 0 ? Double(store.dailyMetrics.hrv) : nil,
                restingHR: store.dailyMetrics.restingHR > 0 ? Double(store.dailyMetrics.restingHR) : nil,
                nightsAvailable: nights > 0 ? nights : nil
            ),
            readiness: .init(
                hrv7DayTrend: hrvTrend,
                hrv30DayBaseline: hrvBaseline,
                recoveryScore: Double(store.readiness.recoveryScore),
                hrvDaysAvailable: hrvValues.isEmpty ? nil : hrvValues.count
            ),
            training: .init(
                lastWorkoutType: lastWorkout?.type.rawValue,
                lastWorkoutDurationMinutes: lastWorkout.map { Double($0.duration) },
                hoursSinceLastWorkout: hoursSinceWorkout,
                weeklyLoadScore: store.workoutHistory.count >= 3
                    ? Double(store.workoutHistory.prefix(7).map(\.duration).reduce(0, +))
                    : nil
            ),
            activity: .init(
                steps3DayAvg: steps3,
                activeCalories3DayAvg: store.dailyMetrics.activeCalories > 0
                    ? Double(store.dailyMetrics.activeCalories) : nil
            ),
            chronotype: .init(
                typicalSleepOnset: nil,
                typicalWakeTime: nil,
                consistencyScore: nil
            ),
            body: .init(
                weightKg: store.userProfile.weight,
                weightTrendKg: nil,
                bodyFatPct: nil,
                vo2Max: nil
            ),
            nutrition: {
                let today = HealthKitManager.shared.todayStats
                return ARIAContextPayload.NutritionDomain(
                    caloriesIn3DayAvg: today.map { Double($0.totalCalories) },
                    proteinG3DayAvg: today.map { $0.protein },
                    hydrationMl3DayAvg: today.map { $0.water * 240 },
                    calorieTarget: 2600
                )
            }(),
            profile: .init(
                primaryGoal: store.userProfile.fitnessGoals.first?.rawValue,
                experienceLevel: store.userProfile.experienceLevel.rawValue,
                coachingStyle: store.userProfile.coachingStyle.rawValue,
                constraints: context.constraints
            ),
            progress: .init(
                workoutsCompleted30d: workouts30d > 0 ? workouts30d : nil,
                newPersonalRecords: store.personalRecords.isEmpty ? nil : store.personalRecords.count,
                trainingLoadTrend: store.workoutHistory.count >= 3 ? "steady" : nil,
                recoveryConsistencyDelta: nil
            ),
            lifestyle: .init(
                tags: context.lifestyleTags,
                recentPatterns: patterns,
                goals: context.currentGoals,
                cyclePhaseDirective: {
                    guard let phaseTag = context.lifestyleTags.first(where: { $0.hasPrefix("cycle_phase:") }) else { return nil }
                    let phaseRaw = String(phaseTag.dropFirst("cycle_phase:".count))
                    guard let phase = MenstrualPhase(rawValue: phaseRaw), phase != .unknown else { return nil }
                    let text = CyclePhaseCoachingDirective.directive(for: phase, domain: .general)
                    return text.isEmpty ? nil : text
                }()
            ),
            conversation: store.conversationContextPayload()
        )
        return payload
    }

    func buildRichContext(from store: AppStore) -> AriaRichContext {
        let domain = buildARIAContext(from: store)
        let metrics: [String: Double] = [
            "readiness": Double(store.readiness.overall),
            "hrv": Double(store.dailyMetrics.hrv),
            "resting_hr": Double(store.dailyMetrics.restingHR),
            "sleep_score": Double(store.sleepData.first?.score ?? 0),
            "deep_sleep_min": Double(store.dailyMetrics.deepSleep),
            "recovery_score": Double(store.readiness.recoveryScore),
        ]
        return AriaRichContext(
            userId: context.userId,
            lifestyleTags: domain.lifestyle.tags,
            goals: domain.lifestyle.goals,
            constraints: domain.profile.constraints,
            recentPatterns: domain.lifestyle.recentPatterns,
            recentMetrics: metrics,
            relationshipLevel: context.relationshipLevel,
            timestamp: domain.timestamp
        )
    }

    func applyObservedContext(_ payload: ARIAContextPayload) {
        lastObservedContext = payload
    }

    func applyUpdates(_ updates: [String: Int]) {
        if let level = updates["relationship_level"] {
            context.relationshipLevel = min(10, max(1, level))
        }
        context.lastUpdated = Date()
        persist()
    }

    func addInsight(_ insight: String) {
        context.lastInsights.insert(insight, at: 0)
        if context.lastInsights.count > 15 {
            context.lastInsights.removeLast()
        }
        context.lastUpdated = Date()
        persist()
    }

    func updateProfile(
        goals: [String]? = nil,
        constraints: [String]? = nil,
        lifestyleTags: [String]? = nil
    ) {
        if let goals { context.currentGoals = goals }
        if let constraints { context.constraints = constraints }
        if let lifestyleTags { context.lifestyleTags = lifestyleTags }
        context.lastUpdated = Date()
        persist()
    }

    /// Sticky voice dials (voice:hype, voice:clinical, …) used by AriaVoiceEngine.
    func setVoicePreferenceTags(_ tags: [String]) {
        var next = context.lifestyleTags.filter { !$0.hasPrefix("voice:") }
        next.append(contentsOf: tags.filter { $0.hasPrefix("voice:") })
        context.lifestyleTags = Array(Set(next)).sorted()
        context.lastUpdated = Date()
        persist()
    }

    func clearVoicePreferenceTags() {
        context.lifestyleTags = context.lifestyleTags.filter { !$0.hasPrefix("voice:") }
        context.lastUpdated = Date()
        persist()
    }

    /// Quiet mode: ARIA should reduce unsolicited briefs and noise.
    func setQuietMode(_ on: Bool) {
        context.lifestyleTags = context.lifestyleTags.filter { !$0.hasPrefix("quiet_mode:") }
        if on {
            context.lifestyleTags.append("quiet_mode:true")
            context.constraints = Array(Set(context.constraints + ["quiet_mode:true"]))
        } else {
            context.constraints = context.constraints.filter { $0 != "quiet_mode:true" }
        }
        context.lastUpdated = Date()
        persist()
    }

    func clearCycleTags() {
        context.lifestyleTags = context.lifestyleTags.filter {
            !$0.hasPrefix("cycle:") && !$0.hasPrefix("cycle_phase:") && !$0.hasPrefix("cycle_day:")
                && !$0.hasPrefix("cycle_privacy:") && !$0.hasPrefix("cycle_prefer:")
                && !$0.hasPrefix("cycle:prefer:") && !$0.hasPrefix("cycle:period_feedback")
                && !$0.hasPrefix("cycle:recovery_pref:")
        }
        context.constraints.removeAll { $0.hasPrefix("cycle_period_learn:") }
        context.recentPatterns = context.recentPatterns.filter { !$0.hasPrefix("cycle:") }
        context.lastUpdated = Date()
        persist()
    }

    /// Inject continuously learned period-end coaching preferences for ARIA.
    func applyPeriodCoachingPreferences(_ prefs: PeriodCoachingPreferences) {
        var tags = context.lifestyleTags.filter {
            !$0.hasPrefix("cycle:prefer:")
                && !$0.hasPrefix("cycle:period_feedback")
                && !$0.hasPrefix("cycle:recovery_pref:")
        }
        tags.append(contentsOf: prefs.ariaTags)
        context.lifestyleTags = Array(Set(tags)).sorted()

        context.constraints.removeAll { $0.hasPrefix("cycle_period_learn:") }
        let directive = prefs.coachingDirective
        if !directive.isEmpty {
            context.constraints.append("cycle_period_learn:\(directive)")
        }
        context.lastUpdated = Date()
        persist()
    }

    func clearPartnerCycleTags() {
        context.lifestyleTags = context.lifestyleTags.filter {
            !$0.hasPrefix("partner_cycle:") && !$0.hasPrefix("partner_phase:") && !$0.hasPrefix("partner_day:")
                && !$0.hasPrefix("partner_name:")
        }
        context.recentPatterns = context.recentPatterns.filter { !$0.hasPrefix("partner_cycle:") }
        context.lastUpdated = Date()
        persist()
    }

    /// Ensure cycle privacy + ARIA analyst contract are available to the model.
    func ensureCycleAnalystDirective() {
        if !context.constraints.contains(where: { $0.hasPrefix("cycle_analyst:") }) {
            context.constraints.append("cycle_analyst:understand_evaluate_teach")
        }
        // Keep privacy directive as insight once
        if !context.lastInsights.contains(where: { $0.contains("CYCLE PRIVACY") }) {
            addInsight(CyclePrivacy.ariaDirective)
        }
        if !context.lastInsights.contains(where: { $0.contains("Understand → Evaluate → Teach") }) {
            addInsight(CycleAriaAnalyst.systemDirective)
        }
    }

    func applyCycleSnapshot(_ snap: MenstrualCycleSnapshot) {
        guard snap.trackingEnabled else {
            clearCycleTags()
            return
        }
        ensureCycleAnalystDirective()
        var tags = context.lifestyleTags.filter {
            !$0.hasPrefix("cycle:") && !$0.hasPrefix("cycle_phase:") && !$0.hasPrefix("cycle_day:")
                && !$0.hasPrefix("cycle_privacy:")
        }
        tags.append("cycle:enabled")
        tags.append("cycle_phase:\(snap.phase.rawValue)")
        if let day = snap.dayInCycle {
            tags.append("cycle_day:\(day)")
        }
        tags.append("cycle:confidence:\(Int(snap.confidence * 100))")
        tags.append("cycle:quality:\(snap.dataQuality)")
        tags.append("cycle:data_grade:\(MenstrualHealthStore.shared.lastEvaluation.qualityGrade.rawValue)")
        // Explicit privacy contract in context so any processor sees the boundary.
        tags.append("cycle_privacy:coaching_only")
        tags.append("cycle_privacy:never_sell")
        tags.append("cycle_privacy:user_controlled")
        if snap.recommendRecoveryBias {
            tags.append("cycle:recovery_bias")
        }
        if snap.isCurrentlyBleeding {
            tags.append("cycle:bleeding")
        }
        // Stage, not just phase: ARIA previously could not tell "mid-period" from
        // "period just ended", so period-specific coaching persisted after the fact.
        tags.append("cycle:stage:\(snap.stage.rawValue)")
        if snap.periodEndConfirmed {
            tags.append("cycle:period_confirmed_finished")
        }
        if let since = snap.daysSincePeriodEnd, since <= 3 {
            tags.append("cycle:days_since_period_end:\(since)")
        }
        if let days = snap.daysUntilNextPeriod {
            tags.append("cycle:days_until_next_period:\(days)")
        }
        tags.append("cycle:goal:\(snap.cycleGoal?.rawValue ?? "general")")
        if let tww = snap.twwDaysElapsed {
            tags.append("cycle:tww_day:\(tww)")
        }
        if let fertile = snap.fertileScore {
            tags.append("cycle:fertile_score:\(fertile)")
        }
        // Always rebuild the condition constraint. Guarding on "a condition constraint
        // already exists" meant switching PCOS → endometriosis kept coaching ARIA with
        // the previous condition's guidance forever.
        context.constraints.removeAll { $0.hasPrefix("cycle_condition_context:") }
        if let condition = snap.condition, condition != .none {
            tags.append("cycle:condition:\(condition.rawValue)")
            let guidance = condition.ariaGuidance
            if !guidance.isEmpty {
                context.constraints.append("cycle_condition_context:\(guidance)")
            }
        }
        context.lifestyleTags = Array(Set(tags)).sorted()

        var patterns = context.recentPatterns.filter { !$0.hasPrefix("cycle:") }
        patterns.append("cycle:\(snap.phase.rawValue)")
        if let note = snap.insights.first {
            context.lastInsights.insert("Cycle: \(note)", at: 0)
            if context.lastInsights.count > 15 {
                context.lastInsights = Array(context.lastInsights.prefix(15))
            }
        }
        context.recentPatterns = Array(patterns.suffix(12))
        context.lastUpdated = Date()
        persist()
    }

    func applyPartnerCycleSnapshot(
        _ snap: MenstrualCycleSnapshot,
        partnerName: String,
        relationshipLabel: String,
        role: CycleSupportRole = .other
    ) {
        guard snap.trackingEnabled || !partnerName.isEmpty else {
            clearPartnerCycleTags()
            return
        }
        var tags = context.lifestyleTags.filter {
            !$0.hasPrefix("partner_cycle:") && !$0.hasPrefix("partner_phase:") && !$0.hasPrefix("partner_day:")
                && !$0.hasPrefix("partner_name:")
        }
        tags.append("partner_cycle:enabled")
        tags.append("partner_phase:\(snap.phase.rawValue)")
        if let day = snap.dayInCycle {
            tags.append("partner_day:\(day)")
        }
        let safeName = partnerName
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .prefix(24)
        if !safeName.isEmpty {
            tags.append("partner_name:\(safeName)")
        }
        tags.append("partner_cycle:rel:\(relationshipLabel.lowercased().replacingOccurrences(of: " ", with: "_"))")
        tags.append("partner_cycle:role:\(role.rawValue)")
        tags.append("partner_cycle:confidence:\(Int(snap.confidence * 100))")
        // Stage drives the return from period-support coaching to everyday support.
        tags.append("partner_cycle:stage:\(snap.stage.rawValue)")
        if snap.periodEndConfirmed {
            tags.append("partner_cycle:period_confirmed_finished")
        }
        if let since = snap.daysSincePeriodEnd, since <= 3 {
            tags.append("partner_cycle:days_since_period_end:\(since)")
        }
        context.lifestyleTags = Array(Set(tags)).sorted()

        var patterns = context.recentPatterns.filter { !$0.hasPrefix("partner_cycle:") }
        patterns.append("partner_cycle:\(snap.phase.rawValue)")
        context.recentPatterns = Array(patterns.suffix(12))
        let who: String = {
            switch role {
            case .child: return "Daughter/child"
            case .romantic: return "Partner"
            case .family: return "Family member"
            case .friend: return "Friend"
            case .other: return "Supported person"
            }
        }()
        context.lastInsights.insert(
            "\(who) (\(partnerName)) cycle phase: \(snap.phase.label)" + (snap.dayInCycle.map { " day \($0)" } ?? "") + ".",
            at: 0
        )
        if context.lastInsights.count > 15 {
            context.lastInsights = Array(context.lastInsights.prefix(15))
        }
        context.lastUpdated = Date()
        persist()
    }

    /// Persists preferred narrative training theme on lifestyle tags.
    func setTrainingTheme(_ theme: AriaTrainingTheme) {
        var tags = context.lifestyleTags.filter { !$0.hasPrefix("training_theme:") }
        tags.append(theme.lifestyleTag)
        context.lifestyleTags = Array(Set(tags)).sorted()
        if theme != .classic {
            context.recentPatterns = context.recentPatterns.filter { !$0.hasPrefix("theme:") }
            context.recentPatterns.append("theme:\(theme.rawValue)")
            if context.recentPatterns.count > 12 {
                context.recentPatterns = Array(context.recentPatterns.suffix(12))
            }
        }
        context.lastUpdated = Date()
        persist()
    }

    var trainingTheme: AriaTrainingTheme {
        AriaThemeResolver.detectFromTags(context.lifestyleTags) ?? .classic
    }

    /// Seeds ARIA's living model from the finished onboarding interview.
    func seedFromOnboarding(
        name: String,
        goals: [String],
        experienceLevel: String,
        preferredWorkouts: [String],
        coachingStyle: String,
        healthConnected: Bool,
        lifestyleTags: [String] = [],
        constraints: [String] = [],
        trainingTheme: AriaTrainingTheme = .classic
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        context.currentGoals = goals
        var tags: [String] = [
            "onboarding:complete",
            "experience:\(experienceLevel)",
            "coach:\(coachingStyle)",
            healthConnected ? "healthkit:connected" : "healthkit:pending",
        ]
        tags.append(contentsOf: preferredWorkouts.prefix(4).map { "likes:\($0)" })
        tags.append(contentsOf: lifestyleTags)
        tags.append(trainingTheme.lifestyleTag)
        context.lifestyleTags = Array(Set(tags)).sorted()
        context.constraints = constraints
        context.recentPatterns = ["first_session_setup"]
        if trainingTheme != .classic {
            context.recentPatterns.append("theme:\(trainingTheme.rawValue)")
        }
        if constraints.contains(where: { $0.contains("guidance_only") }) {
            context.recentPatterns.append("guidance_only_coaching")
        }
        if !trimmed.isEmpty {
            var insight = "Met \(trimmed) during onboarding interview — coaching style \(coachingStyle), focus on \(goals.first ?? "general fitness")."
            if trainingTheme != .classic {
                insight += " Training theme: \(trainingTheme.label)."
            }
            context.lastInsights = [insight]
        } else {
            context.lastInsights = [
                "First connection established — coaching style \(coachingStyle)."
            ]
        }
        if !constraints.isEmpty {
            context.lastInsights.insert(
                "Coach boundaries set from onboarding: \(constraints.prefix(4).joined(separator: ", ")).",
                at: 0
            )
        }
        context.relationshipLevel = max(context.relationshipLevel, 2)
        context.lastUpdated = Date()
        persist()
    }

    /// Pushes live Lifestyle tab signals into ARIA's living context for Bedrock prompts.
    func syncLifestyleSignals(
        metrics: LifestyleMetrics,
        stats: DailyHealthStats?,
        recommendations: [AIRecommendation],
        loggedMeals: [MealLog]
    ) {
        var tags: [String] = [
            "qol:\(metrics.qualityOfLifeScore)",
            "stress:\(metrics.stressLevel.rawValue.lowercased())",
            "nutrition_score:\(metrics.nutritionScore)",
            "sleep_quality:\(metrics.sleepQuality)",
        ]

        if let stats {
            tags.append("protein:\(Int(stats.protein))g")
            tags.append("steps:\(stats.steps)")
            tags.append("hydration:\(Int(stats.water))/8")
            if stats.hrv > 0, stats.hrv < 40 { tags.append("recovery:low") }
            if stats.protein < 120 { tags.append("protein:deficit") }
            if stats.sleepHours < 7 { tags.append("sleep:deficit") }
            if stats.steps < 6000 { tags.append("movement:low") }
        }
        if !loggedMeals.isEmpty {
            tags.append("meals_logged:\(loggedMeals.count)")
        }

        var patterns = context.recentPatterns.filter { !$0.hasPrefix("lifestyle:") }
        for rec in recommendations.prefix(3) {
            patterns.append("lifestyle:\(rec.title)")
        }
        context.recentPatterns = Array(patterns.suffix(10))
        context.lifestyleTags = Array(Set(tags)).sorted()
        context.lastUpdated = Date()
        persist()
    }

    func shouldBeProactive() -> Bool {
        context.relationshipLevel >= 3 && !context.recentPatterns.isEmpty
    }

    func refreshProactiveInsight(from store: AppStore) {
        guard shouldBeProactive() else {
            lastProactiveInsight = nil
            return
        }
        let readiness = store.readiness.overall
        let theme = trainingTheme
        let cycleStore = MenstrualHealthStore.shared
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let salt = UInt64(day * 31 + readiness + context.relationshipLevel * 7)

        // Emotional continuity: if last turn was emotional, check in humanly.
        if let emotionTag = context.lifestyleTags.first(where: { $0.hasPrefix("emotion:") && $0 != "emotion:about_other" }),
           salt % 2 == 0 {
            let raw = emotionTag.replacingOccurrences(of: "emotion:", with: "")
            if let need = AriaEmotionalNeed(rawValue: raw), need != .crisis {
                lastProactiveInsight = need == .parentingStress || context.lifestyleTags.contains("emotion:about_other")
                    ? "Still thinking about how you're supporting them — want a softer script or just a check-in?"
                    : "Last time felt heavy (\(need.label.lowercased())). Want to vent another minute, or shift to something steady?"
                return
            }
        }

        // Human relational check-ins (partner / daughter) interleave with training prompts.
        if let relational = AriaRelationalCoach.proactiveQuestion(
            userGender: store.userProfile.gender,
            partnerSettings: cycleStore.partnerSettings,
            partnerSnapshot: cycleStore.partnerSettings.enabled ? cycleStore.partnerSnapshot : nil,
            readiness: readiness,
            salt: salt
        ), salt % 3 != 0 || readiness >= 60 {
            // Prefer relational message often when support context is live or for invites.
            if cycleStore.partnerSettings.enabled || salt % 2 == 0 {
                lastProactiveInsight = relational
                return
            }
        }

        if readiness < 55 {
            if theme == .soloLeveling {
                lastProactiveInsight = "Readiness is low — Safe Zone day. Want a Solo Leveling recovery quest?"
            } else if theme != .classic {
                lastProactiveInsight = "Recovery is dipping. Want a lighter \(theme.label) session?"
            } else {
                lastProactiveInsight = "Your recovery is dipping — want a lighter plan today?"
            }
        } else if readiness >= 85 {
            if theme == .soloLeveling {
                lastProactiveInsight = "S-Rank window. Ready for a full daily quest + gate clear?"
            } else if theme != .classic {
                lastProactiveInsight = "You're primed. I can build a \(theme.label) performance session."
            } else {
                lastProactiveInsight = "You're primed. I can line up a performance-focused session."
            }
        } else if let insight = context.lastInsights.first {
            lastProactiveInsight = "Building on last time: \(insight)"
        } else {
            lastProactiveInsight = "I've been tracking your patterns — tap to check in with ARIA."
        }
    }

    func memoryReference(for input: String) -> String? {
        guard context.relationshipLevel >= 2,
              let insight = context.lastInsights.first(where: { !$0.isEmpty }) else { return nil }
        let lower = input.lowercased()
        if lower.contains("tired") || lower.contains("recovery") || lower.contains("sleep") {
            return "Last time you felt like this, we focused on recovery — \(insight)"
        }
        return nil
    }

    func persist() {
        if let data = try? JSONEncoder().encode(context) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
