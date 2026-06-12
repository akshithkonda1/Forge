import Foundation

/// Mirror of main-app shared payload for the widget extension.
enum ForgeSharedData {
    static let appGroupID = "group.com.forge.health"
    private static let readinessKey = "forge.readiness.overall"
    private static let workoutNameKey = "forge.workout.name"
    private static let hrvKey = "forge.metrics.hrv"
    private static let streakKey = "forge.streak"
    private static let strainKey = "forge.scores.strain"
    private static let recoveryKey = "forge.scores.recovery"
    private static let sleepScoreKey = "forge.scores.sleep"
    private static let sleepNeedKey = "forge.scores.sleepNeed"
    private static let briefHeadlineKey = "forge.brief.headline"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
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

    static var briefHeadline: String {
        defaults?.string(forKey: briefHeadlineKey) ?? ""
    }
}
