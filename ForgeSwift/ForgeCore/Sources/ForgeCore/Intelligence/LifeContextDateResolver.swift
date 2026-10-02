import Foundation

// ============================================================
// MARK: - Life Context date resolution
// ============================================================
//
// Privacy contract
// ----------------
// What ARIA / the backend sees: nothing from this file directly. It turns
// "Friday at 7" into a `Date` the engine may put on a fact.
// What stays on-device: the text, for the duration of one call.
//
// Why not NSDataDetector alone: the detector resolves "Friday" against the
// clock at the moment it runs, so the same conversation would produce
// different dates on different days — and the engine promises same input,
// same facts. Relative words are resolved here against the *message's own
// timestamp*. The detector is still used (see `MessageContextEngine`) to find
// absolute dates this parser does not know, whose month and day do not depend
// on when it runs; their year is re-anchored here.

struct ResolvedWhen: Equatable, Sendable {
    enum Precision: Equatable, Sendable {
        /// "next week" — a week, not a day.
        case week
        /// A day with no time ("Saturday", "Oct 12").
        case day
        /// A day and a time ("Friday 7pm").
        case time
    }

    let date: Date
    let precision: Precision
}

enum LifeContextDateResolver {

    // MARK: Entry point

    /// Resolve the most specific date/time expression in `text`, anchored at
    /// `anchor` (the message's timestamp). `evening` tips a bare "at 7" to 7pm.
    static func resolve(_ text: String, anchor: Date, calendar: Calendar, evening: Bool) -> ResolvedWhen? {
        let normalized = normalize(text)
        let anchorDay = calendar.startOfDay(for: anchor)
        let day = resolveDay(normalized, anchor: anchor, anchorDay: anchorDay, calendar: calendar)
        let time = resolveTime(normalized, evening: evening)
        return combine(day: day, time: time, anchor: anchor, anchorDay: anchorDay, calendar: calendar)
    }

    /// Month/day (and an explicit year, when one was written) re-anchored to
    /// the message — used for absolute dates NSDataDetector found.
    static func resolveAbsolute(
        month: Int,
        day: Int,
        explicitYear: Int?,
        hour: Int?,
        minute: Int?,
        anchor: Date,
        calendar: Calendar
    ) -> ResolvedWhen? {
        let anchorDay = calendar.startOfDay(for: anchor)
        guard let date = monthDay(month: month, day: day, year: explicitYear, anchorDay: anchorDay, calendar: calendar) else {
            return nil
        }
        let found = DayCandidate(date: date, precision: .day, specificity: 3, position: 0)
        let time = hour.map { TimeCandidate(hour: $0, minute: minute ?? 0, position: 0) }
        return combine(day: found, time: time, anchor: anchor, anchorDay: anchorDay, calendar: calendar)
    }

    // MARK: Normalization

    /// Lowercase, diacritics folded; ASCII letters, digits, ':' and '/' kept,
    /// everything else a single space.
    static func normalize(_ text: String) -> String {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var out = ""
        var lastWasSpace = true
        for character in folded {
            if character.isASCII, character.isLetter || character.isNumber || character == ":" || character == "/" {
                out.append(character)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Days

    struct DayCandidate {
        let date: Date
        let precision: ResolvedWhen.Precision
        /// 3 explicit date, 2 weekday, 1 tomorrow / in N days, 0 today / weekend / next week.
        let specificity: Int
        let position: Int
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [])
    }

    private static let monthAlternation =
        "january|february|march|april|may|june|july|august|september|october|november|december|"
        + "jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec"

    private static let monthFirst = regex(#"\b("# + monthAlternation + #")\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:\s+(\d{4}))?"#)
    private static let dayFirst = regex(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?("# + monthAlternation + #")\b(?:\s+(\d{4}))?"#)
    private static let numericDate = regex(#"\b(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?\b"#)
    private static let ordinalDay = regex(#"\bthe (\d{1,2})(?:st|nd|rd|th)\b"#)
    private static let weekday = regex(
        #"\b(next |this |on )?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|tues|tue|thurs|thur|thu|fri|mon|wed|sat|sun)\b"#
    )
    private static let dayAfterTomorrow = regex(#"\bday after tomorrow\b"#)
    private static let tomorrow = regex(#"\b(tomorrow|tmrw|tmr|tomorow|tommorow|tommorrow|2moro)\b"#)
    private static let inDays = regex(#"\bin (\d{1,2}) days?\b"#)
    private static let today = regex(#"\b(today|tonight|tonite)\b|\bthis (morning|afternoon|evening)\b"#)
    private static let thisWeekend = regex(#"\bthis weekend\b"#)
    private static let nextWeekend = regex(#"\bnext weekend\b"#)
    private static let nextWeek = regex(#"\bnext week\b|\bin a week\b"#)

    /// Abbreviations that are also ordinary words ("sat down", "the sun",
    /// "we wed") count only after "on", "this" or "next".
    private static let ambiguousAbbreviations: Set<String> = ["mon", "wed", "sat", "sun"]

    private static let weekdayNumbers: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tues": 3, "tue": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thurs": 5, "thur": 5, "thu": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7,
    ]

    private static let monthNumbers: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4,
        "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sept": 9, "sep": 9, "october": 10, "oct": 10, "november": 11, "nov": 11,
        "december": 12, "dec": 12,
    ]

    static func containsMonthName(_ normalized: String) -> Bool {
        guard let monthRegex = monthFirst, let dayRegex = dayFirst else { return false }
        let range = NSRange(location: 0, length: (normalized as NSString).length)
        return monthRegex.firstMatch(in: normalized, options: [], range: range) != nil
            || dayRegex.firstMatch(in: normalized, options: [], range: range) != nil
    }

    private static func resolveDay(_ s: String, anchor: Date, anchorDay: Date, calendar: Calendar) -> DayCandidate? {
        var found: [DayCandidate] = []
        let anchorWeekday = calendar.component(.weekday, from: anchorDay)

        func add(_ date: Date?, _ precision: ResolvedWhen.Precision, _ specificity: Int, _ position: Int) {
            if let date { found.append(DayCandidate(date: date, precision: precision, specificity: specificity, position: position)) }
        }
        func offset(_ days: Int) -> Date? {
            calendar.date(byAdding: .day, value: days, to: anchorDay)
        }

        for match in matches(monthFirst, in: s) {
            guard let monthName = group(match, 1, in: s), let month = monthNumbers[monthName],
                  let dayText = group(match, 2, in: s), let day = Int(dayText) else { continue }
            let year = group(match, 3, in: s).flatMap(Int.init)
            add(monthDay(month: month, day: day, year: year, anchorDay: anchorDay, calendar: calendar), .day, 3, match.range.location)
        }
        for match in matches(dayFirst, in: s) {
            guard let dayText = group(match, 1, in: s), let day = Int(dayText),
                  let monthName = group(match, 2, in: s), let month = monthNumbers[monthName] else { continue }
            let year = group(match, 3, in: s).flatMap(Int.init)
            add(monthDay(month: month, day: day, year: year, anchorDay: anchorDay, calendar: calendar), .day, 3, match.range.location)
        }
        for match in matches(numericDate, in: s) {
            guard let monthText = group(match, 1, in: s), let month = Int(monthText),
                  let dayText = group(match, 2, in: s), let day = Int(dayText) else { continue }
            let year = group(match, 3, in: s).flatMap(Int.init).map { $0 < 100 ? 2000 + $0 : $0 }
            add(monthDay(month: month, day: day, year: year, anchorDay: anchorDay, calendar: calendar), .day, 3, match.range.location)
        }
        for match in matches(ordinalDay, in: s) {
            guard let dayText = group(match, 1, in: s), let day = Int(dayText) else { continue }
            add(ordinal(day: day, anchorDay: anchorDay, calendar: calendar), .day, 3, match.range.location)
        }
        for match in matches(weekday, in: s) {
            guard let name = group(match, 2, in: s), let target = weekdayNumbers[name] else { continue }
            let prefix = group(match, 1, in: s)?.trimmingCharacters(in: .whitespaces)
            if ambiguousAbbreviations.contains(name), prefix == nil { continue }
            var delta = (target - anchorWeekday + 7) % 7
            if prefix == "next" { delta += 7 }
            add(offset(delta), .day, 2, match.range.location)
        }
        for match in matches(dayAfterTomorrow, in: s) {
            add(offset(2), .day, 1, match.range.location)
        }
        for match in matches(tomorrow, in: s) {
            add(offset(1), .day, 1, match.range.location)
        }
        for match in matches(inDays, in: s) {
            guard let text = group(match, 1, in: s), let days = Int(text), (0...60).contains(days) else { continue }
            add(offset(days), .day, 1, match.range.location)
        }
        for match in matches(today, in: s) {
            add(anchorDay, .day, 0, match.range.location)
        }
        let saturdayDelta = (anchorWeekday == 7 || anchorWeekday == 1) ? 0 : 7 - anchorWeekday
        for match in matches(thisWeekend, in: s) {
            add(offset(saturdayDelta), .day, 0, match.range.location)
        }
        for match in matches(nextWeekend, in: s) {
            add(offset(saturdayDelta + 7), .day, 0, match.range.location)
        }
        for match in matches(nextWeek, in: s) {
            add(offset(7), .week, 0, match.range.location)
        }

        return found.min { a, b in
            if a.specificity != b.specificity { return a.specificity > b.specificity }
            return a.position < b.position
        }
    }

    /// The month/day in the message's year, or the next year when that date is
    /// already more than a day behind the message. Rejects impossible dates
    /// rather than letting the calendar roll Feb 30 into March.
    static func monthDay(month: Int, day: Int, year: Int?, anchorDay: Date, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year ?? calendar.component(.year, from: anchorDay)
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        guard year == nil,
              let floor = calendar.date(byAdding: .day, value: -1, to: anchorDay),
              date < floor else { return date }
        components.year = (components.year ?? 0) + 1
        guard let next = calendar.date(from: components),
              calendar.component(.day, from: next) == day else { return nil }
        return next
    }

    private static func ordinal(day: Int, anchorDay: Date, calendar: Calendar) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let anchorDate = calendar.component(.day, from: anchorDay)
        let month = calendar.component(.month, from: anchorDay)
        if day >= anchorDate {
            return monthDay(month: month, day: day, year: calendar.component(.year, from: anchorDay), anchorDay: anchorDay, calendar: calendar)
        }
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: anchorDay) else { return nil }
        return monthDay(
            month: calendar.component(.month, from: nextMonth),
            day: day,
            year: calendar.component(.year, from: nextMonth),
            anchorDay: anchorDay,
            calendar: calendar
        )
    }

    // MARK: Times

    struct TimeCandidate {
        let hour: Int
        let minute: Int
        let position: Int
    }

    private static let meridiemTime = regex(#"\b(\d{1,2})(?::(\d{2}))?\s?(am|pm|a m|p m)\b"#)
    private static let clockTime = regex(#"\b([01]?\d|2[0-3]):([0-5]\d)\b"#)
    private static let noon = regex(#"\bnoon\b"#)
    private static let atHour = regex(#"\b(?:at|around) (\d{1,2})\b(?!\s?(?::|am|pm|a m|p m|/|\d))"#)

    private static func resolveTime(_ s: String, evening: Bool) -> TimeCandidate? {
        if let match = matches(meridiemTime, in: s).first,
           let hourText = group(match, 1, in: s), let hour = Int(hourText), (1...12).contains(hour) {
            let minute = group(match, 2, in: s).flatMap(Int.init) ?? 0
            let isPM = (group(match, 3, in: s) ?? "").hasPrefix("p")
            guard (0...59).contains(minute) else { return nil }
            return TimeCandidate(hour: (hour % 12) + (isPM ? 12 : 0), minute: minute, position: match.range.location)
        }
        if let match = matches(clockTime, in: s).first,
           let hourText = group(match, 1, in: s), let hour = Int(hourText),
           let minuteText = group(match, 2, in: s), let minute = Int(minuteText) {
            return TimeCandidate(hour: assumeHour(hour, evening: evening), minute: minute, position: match.range.location)
        }
        if let match = matches(noon, in: s).first {
            return TimeCandidate(hour: 12, minute: 0, position: match.range.location)
        }
        if let match = matches(atHour, in: s).first,
           let hourText = group(match, 1, in: s), let hour = Int(hourText), (1...23).contains(hour) {
            return TimeCandidate(hour: assumeHour(hour, evening: evening), minute: 0, position: match.range.location)
        }
        return nil
    }

    /// No am/pm written: 1–6 are afternoon/evening; 7–11 are evening only when
    /// the message is about an evening thing (dinner, drinks, tonight); 12 and
    /// 13–23 are taken as written.
    static func assumeHour(_ hour: Int, evening: Bool) -> Int {
        switch hour {
        case 1...6: return hour + 12
        case 7...11: return evening ? hour + 12 : hour
        default: return hour
        }
    }

    // MARK: Combination

    private static func combine(
        day: DayCandidate?,
        time: TimeCandidate?,
        anchor: Date,
        anchorDay: Date,
        calendar: Calendar
    ) -> ResolvedWhen? {
        switch (day, time) {
        case (nil, nil):
            return nil
        case (let day?, nil):
            return ResolvedWhen(date: day.date, precision: day.precision)
        case (let day?, let time?):
            if day.precision == .week { return ResolvedWhen(date: day.date, precision: .week) }
            guard let dated = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day.date) else {
                return ResolvedWhen(date: day.date, precision: .day)
            }
            return ResolvedWhen(date: dated, precision: .time)
        case (nil, let time?):
            guard var dated = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: anchorDay) else {
                return nil
            }
            if dated < anchor, let next = calendar.date(byAdding: .day, value: 1, to: dated) {
                dated = next
            }
            return ResolvedWhen(date: dated, precision: .time)
        }
    }

    // MARK: Regex plumbing

    private static func matches(_ regex: NSRegularExpression?, in s: String) -> [NSTextCheckingResult] {
        guard let regex else { return [] }
        return regex.matches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length))
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in s: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return (s as NSString).substring(with: range)
    }
}
