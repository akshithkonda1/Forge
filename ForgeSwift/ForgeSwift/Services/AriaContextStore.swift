import Foundation
import Combine
import ForgeCore

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

        let steps3: Double? = store.sleepData.isEmpty ? nil : Double(store.dailyMetrics.steps)
        let hrvValues: [Double] = store.sleepData.prefix(7).map { _ in Double(store.dailyMetrics.hrv) }
        let hrvBaseline: Double? = hrvValues.isEmpty ? nil : hrvValues.reduce(0, +) / Double(hrvValues.count)
        let hrvTrend: Double? = hrvBaseline.flatMap { baseline in
            guard baseline > 0 else { return nil }
            return ((Double(store.dailyMetrics.hrv) - baseline) / baseline) * 100
        }

        let workouts30d = store.workoutHistory.filter {
            guard let date = ISO8601DateFormatter().date(from: $0.date) else { return false }
            return date > Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        }.count

        let sleepDomain = ARIAContextPayload.SleepDomain(
            durationMinutes: lastSleep.map { $0.totalHours * 60 },
            efficiency: lastSleep.map { min(1.0, Double($0.score) / 100.0) },
            remMinutes: lastSleep.map { Double($0.remMinutes) },
            deepMinutes: lastSleep.map { Double($0.deepMinutes) },
            hrv: store.dailyMetrics.hrv > 0 ? Double(store.dailyMetrics.hrv) : nil,
            restingHR: store.dailyMetrics.restingHR > 0 ? Double(store.dailyMetrics.restingHR) : nil,
            nightsAvailable: nights > 0 ? nights : nil
        )
        let readinessDomain = ARIAContextPayload.ReadinessDomain(
            hrv7DayTrend: hrvTrend,
            hrv30DayBaseline: hrvBaseline,
            recoveryScore: Double(store.readiness.recoveryScore),
            hrvDaysAvailable: hrvValues.isEmpty ? nil : hrvValues.count
        )
        let weeklyLoad: Double?
        if store.workoutHistory.count >= 3 {
            let minutes = store.workoutHistory.prefix(7).reduce(0) { $0 + $1.duration }
            weeklyLoad = Double(minutes)
        } else {
            weeklyLoad = nil
        }
        let trainingDomain = ARIAContextPayload.TrainingDomain(
            lastWorkoutType: lastWorkout?.type.rawValue,
            lastWorkoutDurationMinutes: lastWorkout.map { Double($0.duration) },
            hoursSinceLastWorkout: hoursSinceWorkout,
            weeklyLoadScore: weeklyLoad
        )
        let activityCalories: Double? = store.dailyMetrics.activeCalories > 0
            ? Double(store.dailyMetrics.activeCalories)
            : nil
        let activityDomain = ARIAContextPayload.ActivityDomain(
            steps3DayAvg: steps3,
            activeCalories3DayAvg: activityCalories
        )
        let chronotypeDomain = ARIAContextPayload.ChronotypeDomain(
            typicalSleepOnset: nil,
            typicalWakeTime: nil,
            consistencyScore: nil
        )
        let bodyDomain = ARIAContextPayload.BodyDomain(
            weightKg: store.userProfile.weight,
            weightTrendKg: nil,
            bodyFatPct: nil,
            vo2Max: nil
        )
        let todayStats = HealthKitManager.shared.todayStats
        let nutritionDomain = ARIAContextPayload.NutritionDomain(
            caloriesIn3DayAvg: todayStats.map { Double($0.totalCalories) },
            proteinG3DayAvg: todayStats.map { $0.protein },
            hydrationMl3DayAvg: todayStats.map { HydrationEngine.milliliters(fromGlasses: $0.water) },
            calorieTarget: 2600
        )
        let profileDomain = ARIAContextPayload.ProfileDomain(
            primaryGoal: store.userProfile.fitnessGoals.first?.rawValue,
            experienceLevel: store.userProfile.experienceLevel.rawValue,
            coachingStyle: store.userProfile.coachingStyle.rawValue,
            constraints: context.constraints + clinicalConstraintLines()
        )
        let progressDomain = ARIAContextPayload.ProgressDomain(
            workoutsCompleted30d: workouts30d > 0 ? workouts30d : nil,
            newPersonalRecords: store.personalRecords.isEmpty ? nil : store.personalRecords.count,
            trainingLoadTrend: store.workoutHistory.count >= 3 ? "steady" : nil,
            recoveryConsistencyDelta: nil
        )
        let cyclePhaseDirective: String? = {
            guard let phaseTag = context.lifestyleTags.first(where: { $0.hasPrefix("cycle_phase:") }) else {
                return nil
            }
            let phaseRaw = String(phaseTag.dropFirst("cycle_phase:".count))
            guard let phase = MenstrualPhase(rawValue: phaseRaw), phase != .unknown else { return nil }
            let text = CyclePhaseCoachingDirective.directive(for: phase, domain: .general)
            return text.isEmpty ? nil : text
        }()
        let lifestyleDomain = ARIAContextPayload.LifestyleDomain(
            tags: context.lifestyleTags,
            recentPatterns: patterns,
            goals: context.currentGoals,
            cyclePhaseDirective: cyclePhaseDirective
        )
        return ARIAContextPayload(
            timestamp: iso.string(from: Date()),
            sleep: sleepDomain,
            readiness: readinessDomain,
            training: trainingDomain,
            activity: activityDomain,
            chronotype: chronotypeDomain,
            body: bodyDomain,
            nutrition: nutritionDomain,
            profile: profileDomain,
            progress: progressDomain,
            lifestyle: lifestyleDomain,
            clinicalData: clinicalDomain(),
            conversation: store.conversationContextPayload()
        )
    }

    private func clinicalDomain() -> ARIAContextPayload.ClinicalDataDomain? {
        guard HealthKitManager.shared.hasStructuredRecordsAccess,
              let summary = HealthKitManager.shared.clinicalSummary,
              summary.hasData else { return nil }
        let domain = summary.ariaDomain()
        return domain.isEmpty ? nil : domain
    }

    private func clinicalConstraintLines() -> [String] {
        guard HealthKitManager.shared.hasStructuredRecordsAccess,
              let summary = HealthKitManager.shared.clinicalSummary else { return [] }
        return summary.ariaConstraintLines()
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
                && !$0.hasPrefix("partner_name:") && !$0.hasPrefix("support_cycle:")
        }
        context.recentPatterns = context.recentPatterns.filter {
            !$0.hasPrefix("partner_cycle:") && !$0.hasPrefix("support_cycle:")
        }
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
        tags.append("cycle:goal:\(snap.cycleGoal?.rawValue ?? "general")")
        if let tww = snap.twwDaysElapsed {
            tags.append("cycle:tww_day:\(tww)")
        }
        if let fertile = snap.fertileScore {
            tags.append("cycle:fertile_score:\(fertile)")
        }
        if let condition = snap.condition, condition != .none {
            tags.append("cycle:condition:\(condition.rawValue)")
            let guidance = condition.ariaGuidance
            if !guidance.isEmpty,
               !context.constraints.contains(where: { $0.hasPrefix("cycle_condition_context:") }) {
                context.constraints.append("cycle_condition_context:\(guidance)")
            }
        } else {
            context.constraints.removeAll { $0.hasPrefix("cycle_condition_context:") }
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
        var settings = PartnerCycleSettings.default
        settings.enabled = true
        settings.consentAcknowledged = true
        settings.shareWithAria = true
        settings.partnerName = partnerName
        settings.relationshipLabel = relationshipLabel
        settings.supportRole = role
        applySupportedPeople([(SupportedPerson.make(settings: settings), snap)])
    }

    /// Each consented person ARIA may mention, with their own role.
    /// Never flattens a daughter through a partner lens.
    func applySupportedPeople(_ people: [(SupportedPerson, MenstrualCycleSnapshot)]) {
        var tags = context.lifestyleTags.filter {
            !$0.hasPrefix("partner_cycle:") && !$0.hasPrefix("partner_phase:") && !$0.hasPrefix("partner_day:")
                && !$0.hasPrefix("partner_name:") && !$0.hasPrefix("support_cycle:")
        }
        guard !people.isEmpty else {
            clearPartnerCycleTags()
            return
        }

        tags.append("support_cycle:count:\(people.count)")
        for (index, pair) in people.enumerated() {
            let person = pair.0
            let snap = pair.1
            let role = person.role
            let name = person.displayName
            let safeName = name
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .prefix(24)
            tags.append("support_cycle:\(index):role:\(role.rawValue)")
            tags.append("support_cycle:\(index):phase:\(snap.phase.rawValue)")
            tags.append("support_cycle:\(index):stage:\(snap.stage.rawValue)")
            if !safeName.isEmpty {
                tags.append("support_cycle:\(index):name:\(safeName)")
            }
            tags.append("support_cycle:\(index):rel:\(person.settings.relationshipLabel.lowercased().replacingOccurrences(of: " ", with: "_"))")
            if snap.periodEndConfirmed {
                tags.append("support_cycle:\(index):period_confirmed_finished")
            }
        }

        // Active / most relevant person keeps the legacy partner_cycle:* tags
        // so older prompt paths still see one current human without inventing
        // a romantic frame for everyone.
        let active = people.first(where: { $0.0.id == MenstrualHealthStore.shared.selectedPersonId }) ?? people[0]
        let snap = active.1
        let role = active.0.role
        let partnerName = active.0.displayName
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
        tags.append("partner_cycle:rel:\(active.0.settings.relationshipLabel.lowercased().replacingOccurrences(of: " ", with: "_"))")
        tags.append("partner_cycle:role:\(role.rawValue)")
        tags.append("partner_cycle:confidence:\(Int(snap.confidence * 100))")
        tags.append("partner_cycle:stage:\(snap.stage.rawValue)")
        if snap.periodEndConfirmed {
            tags.append("partner_cycle:period_confirmed_finished")
        }
        if let since = snap.daysSincePeriodEnd, since <= 3 {
            tags.append("partner_cycle:days_since_period_end:\(since)")
        }
        context.lifestyleTags = Array(Set(tags)).sorted()

        var patterns = context.recentPatterns.filter {
            !$0.hasPrefix("partner_cycle:") && !$0.hasPrefix("support_cycle:")
        }
        patterns.append("partner_cycle:\(snap.phase.rawValue)")
        if people.count > 1 {
            patterns.append("support_cycle:multi:\(people.count)")
        }
        context.recentPatterns = Array(patterns.suffix(12))

        let roster = people.map { pair in
            let who: String = {
                switch pair.0.role {
                case .child: return "Daughter/child"
                case .romantic: return "Partner"
                case .family: return "Family member"
                case .friend: return "Friend"
                case .other: return "Supported person"
                }
            }()
            return "\(who) (\(pair.0.displayName)) cycle phase: \(pair.1.phase.label)"
                + (pair.1.dayInCycle.map { " day \($0)" } ?? "")
        }.joined(separator: ". ")
        context.lastInsights.insert(roster + ".", at: 0)
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
            let glasses = Int(stats.water.rounded())
            let need = Int(HydrationEngine.glasses(
                fromMilliliters: HydrationEngine.targetMilliliters(weightKilograms: nil)
            ).rounded())
            tags.append("hydration:\(glasses)/\(need)")
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
            people: cycleStore.consentedPeople.map {
                ($0.settings, cycleStore.personSnapshots[$0.id])
            },
            readiness: readiness,
            salt: salt
        ), salt % 3 != 0 || readiness >= 60 {
            if !cycleStore.consentedPeople.isEmpty || salt % 2 == 0 {
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
