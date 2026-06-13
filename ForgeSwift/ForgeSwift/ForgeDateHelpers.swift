import Foundation

enum ForgeDates {
    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone.current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        return dayFormatter.date(from: trimmed)
    }

    static func yyyyMMdd(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func monthYearTitle(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    static func mondayBasedStartOffset(for date: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    // Cached display formatters — list rows call these on every render, so
    // allocating a DateFormatter per call is wasteful. Configured once, never mutated.
    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let weekdayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    /// "2026-02-10" → "Feb 10, 2026" (falls back to the raw string)
    static func displayDate(_ raw: String) -> String {
        guard let date = parse(raw) else { return raw }
        return mediumDateFormatter.string(from: date)
    }

    /// "2026-02-10" → "Tue, Feb 10" (falls back to the raw string)
    static func displayWeekdayDate(_ raw: String) -> String {
        guard let date = parse(raw) else { return raw }
        return weekdayDateFormatter.string(from: date)
    }
}
