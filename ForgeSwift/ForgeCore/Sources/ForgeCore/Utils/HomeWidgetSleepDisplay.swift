import Foundation

// ============================================================
// MARK: - Home widget last-night sleep copy
// ============================================================

/// Whether Home Screen / Lock Screen widgets should print last-night hours.
///
/// `HomeWidgetSnapshot.sleepHours` is a non-optional `Double` (App Group JSON
/// cannot change). After the onboarding Health fix, a missing night — Health
/// read denied, empty store, or a stale newest night — is written as
/// `sleepHours = 0` and `sleepScore = nil`. Widgets used to format that as
/// `"0.0h"`. This type is the one decision they share instead.
///
/// Rule:
/// - Hours to print: `sleepHours > 0`. Zero (the empty sentinel) and
///   negatives are not a night.
/// - A night is present (`hasSleepToShow`) when hours are printable **or**
///   a score was published. Score-only still lets the system family show
///   `"Score N"` without inventing `"0.0 hours"`.
public enum HomeWidgetSleepDisplay: Sendable {

    /// Locked empty copy for every family that can fit a phrase:
    /// accessoryRectangular, accessoryInline, system small/medium/large,
    /// and Today. Plain language — no Health, denied, or clinical wording.
    public static let emptyCopy = "No sleep yet"

    /// accessoryCircular is too small for the phrase. Moon icon + em dash.
    public static let circularEmptyCopy = "—"

    public enum HoursStyle: Equatable, Sendable {
        /// Today medium metric: `"7.4h"` or `emptyCopy`.
        case compact
        /// accessoryCircular: `"7.4h"` or `circularEmptyCopy`.
        case circular
        /// accessoryRectangular / accessoryInline: `"7.4 h last night"`.
        case lastNight
        /// system families hero number: `"7.4"`.
        case number
        /// Today large row: `"7.4 h sleep"`.
        case hoursSleep
    }

    public static func hasHoursToShow(_ hours: Double) -> Bool {
        hours > 0
    }

    public static func hasSleepToShow(sleepHours: Double, sleepScore: Int?) -> Bool {
        hasHoursToShow(sleepHours) || sleepScore != nil
    }

    public static func hasSleepToShow(_ snapshot: HomeWidgetSnapshot) -> Bool {
        hasSleepToShow(sleepHours: snapshot.sleepHours, sleepScore: snapshot.sleepScore)
    }

    public static func hoursText(_ hours: Double, style: HoursStyle) -> String {
        guard hasHoursToShow(hours) else {
            return style == .circular ? circularEmptyCopy : emptyCopy
        }
        switch style {
        case .compact, .circular:
            return String(format: "%.1fh", hours)
        case .lastNight:
            return String(format: "%.1f h last night", hours)
        case .number:
            return String(format: "%.1f", hours)
        case .hoursSleep:
            return String(format: "%.1f h sleep", hours)
        }
    }

    public static func hoursText(_ snapshot: HomeWidgetSnapshot, style: HoursStyle) -> String {
        hoursText(snapshot.sleepHours, style: style)
    }
}
