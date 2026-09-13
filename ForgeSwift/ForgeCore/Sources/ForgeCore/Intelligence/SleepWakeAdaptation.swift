import Foundation

/// Adaptive smart-wake lead. Replaces the dead `computeSmartAlarmWindow`
/// math as the single source of truth: score, debt, chronotype, and a
/// rolling snooze struggle signal all widen or narrow the 15/30/45 window.
public enum SmartAlarmWindow: Sendable {
    public enum ChronotypeBias: String, Sendable {
        case lion, bear, wolf, dolphin
    }

    public static func minutes(
        base: Int,
        recentScore: Int?,
        debtHours: Double,
        bias: ChronotypeBias,
        struggleAverageSnoozes: Double = 0
    ) -> Int {
        var window = base
        if let score = recentScore {
            if score < 70 { window = min(45, window + 15) }
            else if score >= 85 { window = max(15, window - 10) }
        }
        if debtHours > 3 { window = min(45, window + 5) }
        switch bias {
        case .dolphin, .wolf: window = min(45, window + 5)
        case .lion: window = max(15, window - 5)
        case .bear: break
        }
        if struggleAverageSnoozes >= 1.5 {
            window = min(45, window + 10)
        }
        return max(15, min(45, window))
    }
}

/// Snooze count used to live only in the ringing session and reset every
/// morning. Persist a rolling fortnight so "struggles to wake up" is a
/// real signal, not a forgotten integer.
public enum WakeStruggleStore: Sendable {
    public static let defaultsKey = "forge.sleep.wakeStruggle.v1"
    public static let windowDays = 14
    public static let strugglerThreshold = 1.5

    public struct Day: Codable, Equatable, Sendable {
        public var dayKey: String
        public var snoozeCount: Int
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func record(
        snoozes: Int,
        on date: Date,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        var days = load(defaults: defaults)
        let key = dayKey(for: date, calendar: calendar)
        days.removeAll { $0.dayKey == key }
        days.append(Day(dayKey: key, snoozeCount: max(0, snoozes)))
        days.sort { $0.dayKey < $1.dayKey }
        if days.count > windowDays {
            days.removeFirst(days.count - windowDays)
        }
        save(days, defaults: defaults)
    }

    public static func averageSnoozes(defaults: UserDefaults = .standard) -> Double {
        let days = load(defaults: defaults)
        guard !days.isEmpty else { return 0 }
        let total = days.reduce(0) { $0 + $1.snoozeCount }
        return Double(total) / Double(days.count)
    }

    public static func isRepeatStruggler(defaults: UserDefaults = .standard) -> Bool {
        averageSnoozes(defaults: defaults) >= strugglerThreshold
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    private static func load(defaults: UserDefaults) -> [Day] {
        guard let data = defaults.data(forKey: defaultsKey),
              let days = try? JSONDecoder().decode([Day].self, from: data) else {
            return []
        }
        return days
    }

    private static func save(_ days: [Day], defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(days) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
