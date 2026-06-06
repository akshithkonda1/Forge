import Foundation

/// Mirror of main-app shared payload for the widget extension.
enum ForgeSharedData {
    static let appGroupID = "group.com.forge.health"
    private static let readinessKey = "forge.readiness.overall"
    private static let workoutNameKey = "forge.workout.name"
    private static let hrvKey = "forge.metrics.hrv"
    private static let streakKey = "forge.streak"

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
}
