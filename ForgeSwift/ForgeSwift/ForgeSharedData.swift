import Foundation
import WidgetKit

/// App Group payload for widgets and Live Activities.
enum ForgeSharedData {
    static let appGroupID = "group.com.forge.health"
    private static let readinessKey = "forge.readiness.overall"
    private static let workoutNameKey = "forge.workout.name"
    private static let hrvKey = "forge.metrics.hrv"
    private static let streakKey = "forge.streak"
    private static let lastSyncedKey = "forge.lastSyncedAt"
    private static let strainKey = "forge.scores.strain"
    private static let recoveryKey = "forge.scores.recovery"
    private static let sleepScoreKey = "forge.scores.sleep"
    private static let sleepNeedKey = "forge.scores.sleepNeed"
    private static let trainingDecisionKey = "forge.scores.trainingDecision"
    private static let briefHeadlineKey = "forge.brief.headline"
    private static let briefTitleKey = "forge.brief.title"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID) ?? UserDefaults.standard
    }

    @MainActor
    static func syncFromStore(_ store: AppStore) {
        guard let defaults else { return }
        defaults.set(store.readiness.overall, forKey: readinessKey)
        defaults.set(store.todayWorkout?.name ?? "", forKey: workoutNameKey)
        defaults.set(store.dailyMetrics.hrv, forKey: hrvKey)
        defaults.set(store.currentStreak, forKey: streakKey)
        if let scores = store.dailyScores {
            defaults.set(scores.strain.score, forKey: strainKey)
            defaults.set(scores.recovery.score, forKey: recoveryKey)
            defaults.set(scores.sleep.score, forKey: sleepScoreKey)
            defaults.set(scores.sleep.sleepNeedMinutes, forKey: sleepNeedKey)
            defaults.set(scores.trainingDecision.rawValue, forKey: trainingDecisionKey)
        }
        if let brief = store.activeBrief {
            defaults.set(brief.headline, forKey: briefHeadlineKey)
            defaults.set(brief.title, forKey: briefTitleKey)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: lastSyncedKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static var readinessScore: Int {
        defaults?.integer(forKey: readinessKey) ?? 0
    }

    static var workoutName: String {
        defaults?.string(forKey: workoutNameKey) ?? "Rest Day"
    }

    static var hrv: Int {
        defaults?.integer(forKey: hrvKey) ?? 0
    }

    static var streak: Int {
        defaults?.integer(forKey: streakKey) ?? 0
    }

    static var lastSyncedAt: Date? {
        guard let ts = defaults?.double(forKey: lastSyncedKey), ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    static var strainScore: Int {
        defaults?.integer(forKey: strainKey) ?? 0
    }

    static var recoveryScore: Int {
        defaults?.integer(forKey: recoveryKey) ?? 0
    }

    static var sleepScore: Int {
        defaults?.integer(forKey: sleepScoreKey) ?? 0
    }

    static var sleepNeedMinutes: Int {
        defaults?.integer(forKey: sleepNeedKey) ?? 0
    }

    static var trainingDecision: String {
        defaults?.string(forKey: trainingDecisionKey) ?? "active_rest"
    }

    static var briefHeadline: String {
        defaults?.string(forKey: briefHeadlineKey) ?? ""
    }

    static var briefTitle: String {
        defaults?.string(forKey: briefTitleKey) ?? "ARIA Brief"
    }
}
