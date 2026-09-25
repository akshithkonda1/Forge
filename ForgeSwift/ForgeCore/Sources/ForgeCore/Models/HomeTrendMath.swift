import Foundation

/// Home sleep-trend and Reduce Motion decisions. Pure Foundation — no SwiftUI.
///
/// Locked keys later read from `shared/readiness.json` (do not add or read
/// that file yet): plot floor 30, `ruleMarkY` = raw Int-truncated average.
public enum HomeTrendMath {
    public static let plotFloor = 30
    public static let plotCap = 100

    public static func isFrozen(reduceMotion: Bool, minimal: Bool) -> Bool {
        reduceMotion || minimal
    }

    /// Grow-from-zero: ungrown and motion-on plots 0. Reduce Motion is the
    /// still pose — the full (already floored) score even when not grown.
    public static func plottedScore(_ score: Int, grown: Bool, reduceMotion: Bool) -> Int {
        grown || reduceMotion ? score : 0
    }

    /// Chart RuleMark y. Integer truncation of the raw (unfloored) scores.
    public static func ruleMarkY(_ rawScores: [Int]) -> Int? {
        guard !rawScores.isEmpty else { return nil }
        return rawScores.reduce(0, +) / rawScores.count
    }

    public static func clampedPlotScore(_ raw: Int) -> Int {
        min(plotCap, max(plotFloor, raw))
    }

    /// Weekday abbreviation (`EEE`). Default local calendar / autoupdating
    /// locale. Never UTC unless the injected calendar is UTC.
    public static func weekdayLabel(
        for date: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}
