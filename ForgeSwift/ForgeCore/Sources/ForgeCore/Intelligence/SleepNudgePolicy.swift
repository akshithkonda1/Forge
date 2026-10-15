import Foundation

public enum SleepNudgePolicy: Sendable {
    public static let maxPerDay = 2
    public static let quietWeekDefaultsKey = "forge.sleep.quietWeek"

    public static func isQuietWeek(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: quietWeekDefaultsKey)
    }

    public static func setQuietWeek(_ on: Bool, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: quietWeekDefaultsKey)
    }
}

