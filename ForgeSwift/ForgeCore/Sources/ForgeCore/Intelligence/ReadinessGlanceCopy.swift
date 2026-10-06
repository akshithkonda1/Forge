import Foundation

// ============================================================
// MARK: - Readiness glance copy
// ============================================================

/// Wrist / widget lines for today's readiness vs tomorrow's forecast.
///
/// Complications used to only show today. In the evening, tomorrow is the
/// decision that matters — and the copy has to live here so Watch views
/// and tests call the same function.
public enum ReadinessGlanceCopy {

    /// Evening starts at 18:00 local. Before that, today still wins the ring.
    public static let eveningHour = 18

    public static func isEvening(hour: Int) -> Bool {
        hour >= eveningHour || hour < 4
    }

    /// Accessory inline / rectangular headline. Evening prefers tomorrow
    /// when a forecast exists; otherwise today's score.
    public static func complicationLine(
        today: Int?,
        tomorrow: Int?,
        postureRaw: String?,
        hour: Int
    ) -> String {
        if isEvening(hour: hour), let tomorrow {
            let title = postureTitle(postureRaw)
            if let title {
                return "Tomorrow \(tomorrow) · \(title)"
            }
            return "Tomorrow \(tomorrow)"
        }
        if let today {
            return "Readiness \(today)"
        }
        return "Readiness syncing…"
    }

    /// Short Home line under today's ring. Nil when we have nothing to say.
    public static func homeTomorrowLine(score: Int?, postureRaw: String?) -> String? {
        guard let score else { return nil }
        if let title = postureTitle(postureRaw) {
            return "Tomorrow \(score) · \(title)"
        }
        return "Tomorrow \(score)"
    }

    public static func accessibilityLine(
        today: Int?,
        tomorrow: Int?,
        postureRaw: String?,
        hour: Int
    ) -> String {
        let headline = complicationLine(
            today: today,
            tomorrow: tomorrow,
            postureRaw: postureRaw,
            hour: hour
        )
        if isEvening(hour: hour), tomorrow != nil {
            return "\(headline). A guide for tomorrow, not a grade."
        }
        return headline
    }

    public static func postureTitle(_ raw: String?) -> String? {
        guard let raw, let posture = ReadinessForecastEngine.Posture(rawValue: raw) else {
            return nil
        }
        return posture.glanceTitle
    }
}
