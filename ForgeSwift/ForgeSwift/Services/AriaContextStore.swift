import Foundation
import Combine

/// Local persistent context + live metrics assembly for ARIA.
@MainActor
final class AriaContextStore: ObservableObject {
    static let shared = AriaContextStore()

    @Published private(set) var context: AriaContext
    @Published private(set) var lastProactiveInsight: String?

    private let defaults = UserDefaults.standard
    private let storageKey = "forge.aria.userContext"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(AriaContext.self, from: data) {
            context = saved
        } else {
            context = AriaContext(userId: "local-user")
        }
    }

    func configure(userId: String) {
        guard context.userId != userId else { return }
        context.userId = userId
        persist()
    }

    func buildRichContext(from store: AppStore) -> AriaRichContext {
        let metrics: [String: Double] = [
            "readiness": Double(store.readiness.overall),
            "hrv": Double(store.dailyMetrics.hrv),
            "resting_hr": Double(store.dailyMetrics.restingHR),
            "sleep_score": Double(store.sleepData.first?.score ?? 0),
            "deep_sleep_min": Double(store.dailyMetrics.deepSleep),
            "recovery_score": Double(store.readiness.recoveryScore),
        ]

        var patterns = context.recentPatterns
        if store.readiness.overall < 55 {
            let pattern = "low_readiness_streak"
            if !patterns.contains(pattern) { patterns.append(pattern) }
        }
        if let lastSleep = store.sleepData.first, lastSleep.score >= 85 {
            let pattern = "strong_sleep_recovery"
            if !patterns.contains(pattern) { patterns.append(pattern) }
        }

        return AriaRichContext(
            userId: context.userId,
            lifestyleTags: context.lifestyleTags,
            goals: context.currentGoals,
            constraints: context.constraints,
            recentPatterns: patterns,
            recentMetrics: metrics,
            relationshipLevel: context.relationshipLevel,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
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