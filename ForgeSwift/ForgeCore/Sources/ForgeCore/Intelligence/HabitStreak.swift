import Foundation

/// Consecutive-day habit streak.
///
/// A day *qualifies* when enough of that day's habits were done. The streak is
/// the run of qualifying days ending today. Until today qualifies, the run
/// ending yesterday still counts, so the number does not drop to zero every
/// morning before the first check-off.
///
/// Pure over dates, deliberately, so it is testable without UserDefaults.
public enum HabitStreak {

    /// Share of the day's habits that must be done for the day to count.
    public static let qualifyingShare = 0.6

    /// Days kept on disk. Anything older cannot change a streak this short of
    /// a four-month run, and the store should not grow forever.
    public static let retainedDays = 120

    public static func qualifies(completed: Int, total: Int) -> Bool {
        guard total > 0 else { return false }
        return Double(completed) / Double(total) >= qualifyingShare
    }

    /// Length of the run of consecutive qualifying days ending today, or
    /// ending yesterday if today has not qualified yet.
    public static func length(
        qualifyingDays: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let days = Set(qualifyingDays.map { calendar.startOfDay(for: $0) })
        let start = calendar.startOfDay(for: today)
        var cursor = start
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: start) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// Returns `days` with `day` added (`qualifies == true`) or removed
    /// (`qualifies == false`), normalised to start-of-day, de-duplicated,
    /// sorted oldest first and trimmed to `retainedDays`.
    public static func recording(
        day: Date,
        qualifies: Bool,
        in days: [Date],
        calendar: Calendar = .current
    ) -> [Date] {
        let target = calendar.startOfDay(for: day)
        var set = Set(days.map { calendar.startOfDay(for: $0) })
        if qualifies {
            set.insert(target)
        } else {
            set.remove(target)
        }
        let sorted = set.sorted()
        return Array(sorted.suffix(retainedDays))
    }
}
