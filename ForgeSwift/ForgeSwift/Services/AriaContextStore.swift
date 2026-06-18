import Foundation
import Combine

/// Local persistent context + live domain assembly for ARIA v1.1.
@MainActor
final class AriaContextStore: ObservableObject {
    static let shared = AriaContextStore()

    @Published private(set) var context: AriaContext
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

        var patterns = context.recentPatterns
        if store.readiness.overall < 55, !patterns.contains("low_readiness_streak") {
            patterns.append("low_readiness_streak")
        }
        if let lastSleep, lastSleep.score >= 85, !patterns.contains("strong_sleep_recovery") {
            patterns.append("strong_sleep_recovery")
        }
        context.recentPatterns = patterns

        let lastWorkout = store.workoutHistory.first
        let hoursSinceWorkout: Double? = {
            guard let lastWorkout,
                  let date = ISO8601DateFormatter().date(from: lastWorkout.date) else { return nil }
            return Date().timeIntervalSince(date) / 3600
        }()

        let steps3 = store.sleepData.isEmpty ? nil : Double(store.dailyMetrics.steps)
        let hrvValues = store.sleepData.prefix(7).map { Double(store.dailyMetrics.hrv) }
        let hrvBaseline = hrvValues.isEmpty ? nil : hrvValues.reduce(0, +) / Double(hrvValues.count)
        let hrvTrend: Double? = hrvBaseline.map { baseline in
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
            nutrition: .init(
                caloriesIn3DayAvg: nil,
                proteinG3DayAvg: nil,
                hydrationMl3DayAvg: nil,
                calorieTarget: nil
            ),
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
                goals: context.currentGoals
            )
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

    func shouldBeProactive() -> Bool {
        context.relationshipLevel >= 3 && !context.recentPatterns.isEmpty
    }

    func refreshProactiveInsight(from store: AppStore) {
        guard shouldBeProactive() else {
            lastProactiveInsight = nil
            return
        }
        let readiness = store.readiness.overall
        if readiness < 55 {
            lastProactiveInsight = "Your recovery is dipping — want a lighter plan today?"
        } else if readiness >= 85 {
            lastProactiveInsight = "You're primed. I can line up a performance-focused session."
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

    private func persist() {
        if let data = try? JSONEncoder().encode(context) {
            defaults.set(data, forKey: storageKey)
        }
    }
}