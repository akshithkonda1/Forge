import Foundation

/// One phone wind-down per evening. Lifestyle @ 21:00 and LifestyleServices
/// `sleep-wind-down` used to both fire; Watch `WindDownScheduler` stays on
/// the wrist and is not this identifier.
public enum SleepWindDownNotice: Sendable {
    public static let phoneIdentifier = "forge.notification.sleep.winddown"
    public static let retiredPhoneIdentifiers = [
        "forge.notification.lifestyle.sleep",
        "sleep-wind-down",
    ]
    public static let fallbackHour = 21
    public static let fallbackMinute = 0
    public static let leadMinutes = 60

    /// Personal bedtime minus one hour, else 21:00.
    public static func fireHourMinute(bedtimeHour: Double?) -> (hour: Int, minute: Int) {
        let hour: Double
        if let bedtimeHour {
            hour = CircadianRhythm.normalizedHour(bedtimeHour - Double(leadMinutes) / 60.0)
        } else {
            return (fallbackHour, fallbackMinute)
        }
        var whole = Int(hour)
        var minute = Int(((hour - Double(whole)) * 60).rounded())
        if minute >= 60 {
            minute = 0
            whole = (whole + 1) % 24
        }
        if minute < 0 {
            minute = 0
        }
        return (whole, minute)
    }

    /// Implied bedtime from a saved wake target. Nil when nobody set one.
    public static func inferredBedtimeHour(
        goal: ScheduleGoal? = ScheduleGoalStore.load(),
        needHours: Double = CircadianRhythm.defaultSleepNeedHours
    ) -> Double? {
        guard let goal, goal.isActive else { return nil }
        return CircadianRhythm.normalizedHour(goal.targetWakeHour - needHours)
    }

    public static let caffeineIdentifier = "forge.notification.sleep.caffeine"
    public static let caffeineLeadHours = 8
    public static let caffeineFallbackHour = 14
    public static let caffeineFallbackMinute = 0

    /// Caffeine cutoff, then wind-down — two sleep nudges, never a third.
    public static var dailyIdentifiers: [String] {
        [caffeineIdentifier, phoneIdentifier]
    }

    public static func caffeineHourMinute(bedtimeHour: Double?) -> (hour: Int, minute: Int) {
        let hour: Double
        if let bedtimeHour {
            hour = CircadianRhythm.normalizedHour(bedtimeHour - Double(caffeineLeadHours))
        } else {
            return (caffeineFallbackHour, caffeineFallbackMinute)
        }
        var whole = Int(hour)
        var minute = Int(((hour - Double(whole)) * 60).rounded())
        if minute >= 60 {
            minute = 0
            whole = (whole + 1) % 24
        }
        if minute < 0 { minute = 0 }
        return (whole, minute)
    }

    /// Lifestyle-coach bodies. No scores, no HRV, no shame, no "recovery".
    public static func phoneBody(lowReadinessDay: Bool = false) -> String {
        if lowReadinessDay {
            return "A lighter land tonight. Dim the room when you're ready."
        }
        return "Tonight's window is opening. A quieter last hour helps the night land."
    }

    public static func caffeineBody() -> String {
        "Last caffeine window. A calmer afternoon helps you land later."
    }
}
