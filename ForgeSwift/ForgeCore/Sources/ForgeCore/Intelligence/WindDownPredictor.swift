import Foundation

// MARK: - WindDownPredictor
//
// Local heuristic for "when should tonight start winding down?" — no
// network, no model, just circadian common sense made explicit:
//
//   typical onset  = median time-of-day of recent sleep onsets
//   sleep debt     = mean shortfall vs sleep need over recent nights
//   tonight's window = typical onset, pulled earlier by debt/2
//                      (capped at 45 min — dramatic shifts backfire)
//   wind-down start  = 20 min before the window opens
//
// Epistemic honesty: fewer than 3 recent onsets → nil. The UI says
// "still learning your rhythm" instead of inventing a bedtime.

public struct WindDownPlan: Equatable, Sendable {
    public var windDownStart: Date
    public var bedtimeWindowStart: Date
    public var bedtimeWindowEnd: Date

    public init(windDownStart: Date, bedtimeWindowStart: Date, bedtimeWindowEnd: Date) {
        self.windDownStart = windDownStart
        self.bedtimeWindowStart = bedtimeWindowStart
        self.bedtimeWindowEnd = bedtimeWindowEnd
    }
}

public enum WindDownPredictor {

    public static let maxEarlierShiftMinutes = 45.0
    public static let windowLengthMinutes = 45.0
    public static let windDownLeadMinutes = 20.0

    /// - Parameters:
    ///   - recentOnsets: sleep-start timestamps from recent nights
    ///   - recentSleepMinutes: asleep minutes for those nights
    ///   - sleepNeedMinutes: target (default 8h)
    ///   - now: "today" anchor, injectable for tests
    public static func plan(
        recentOnsets: [Date],
        recentSleepMinutes: [Double],
        sleepNeedMinutes: Double = 8 * 60,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WindDownPlan? {
        guard recentOnsets.count >= 3 else { return nil }

        // Median onset as minutes-since-noon: 22:30 → 630, 00:15 → 735.
        // Anchoring at noon keeps the midnight crossing monotonic for any
        // realistic sleeper.
        let onsetMinutes = recentOnsets.map { minutesSinceNoon(of: $0, calendar: calendar) }.sorted()
        let median = onsetMinutes[onsetMinutes.count / 2]

        // Debt pulls tonight earlier, gently.
        let debt: Double
        if recentSleepMinutes.isEmpty {
            debt = 0
        } else {
            let shortfalls = recentSleepMinutes.map { max(0, sleepNeedMinutes - $0) }
            debt = shortfalls.reduce(0, +) / Double(shortfalls.count)
        }
        let shift = min(debt / 2, maxEarlierShiftMinutes)

        let targetMinutes = median - shift
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) else { return nil }
        var windowStart = noon.addingTimeInterval(targetMinutes * 60)
        // If we're computing after midnight (already inside "tonight"),
        // the anchor noon is the following day's — pull back one day.
        if windowStart.timeIntervalSince(now) > 20 * 3600 {
            windowStart.addTimeInterval(-24 * 3600)
        }

        return WindDownPlan(
            windDownStart: windowStart.addingTimeInterval(-windDownLeadMinutes * 60),
            bedtimeWindowStart: windowStart,
            bedtimeWindowEnd: windowStart.addingTimeInterval(windowLengthMinutes * 60)
        )
    }

    static func minutesSinceNoon(of date: Date, calendar: Calendar = .current) -> Double {
        let hour = Double(calendar.component(.hour, from: date))
        let minute = Double(calendar.component(.minute, from: date))
        let raw = (hour * 60 + minute) - 12 * 60
        return raw < 0 ? raw + 24 * 60 : raw
    }
}
