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

/// Decide whether a HealthKit-delivered sleep sample should ring the smart
/// wake *now*. iPhone cannot stream live stage; this reacts when Apple
/// delivers a sample, not as EEG.
public enum SmartWakeEarlyFire: Sendable {
    public enum Decision: String, Sendable, Equatable {
        case ignore
        case fireEarly
        case alreadyPastHard
    }

    /// Samples older than this are history, not "you are in this stage now".
    public static let maxSampleAge: TimeInterval = 20 * 60

    public static func decide(
        now: Date,
        smartFire: Date?,
        hardFire: Date?,
        sampleEnd: Date,
        stage: SleepStage
    ) -> Decision {
        guard let smartFire, let hardFire else { return .ignore }
        if now >= hardFire { return .alreadyPastHard }
        if now < smartFire { return .ignore }
        let age = now.timeIntervalSince(sampleEnd)
        if age < -60 || age > maxSampleAge { return .ignore }
        switch stage {
        case .core, .awake:
            return .fireEarly
        case .deep, .rem:
            return .ignore
        }
    }
}

/// One early fire per alarm per morning so a burst of HealthKit samples
/// does not stack nudges.
public enum SmartWakeEarlyFireStore: Sendable {
    public static let defaultsKey = "forge.sleep.earlyFire.v1"

    public static func alreadyFired(
        alarmId: String,
        dayKey: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        load(defaults: defaults).contains(token(alarmId: alarmId, dayKey: dayKey))
    }

    public static func markFired(
        alarmId: String,
        dayKey: String,
        defaults: UserDefaults = .standard
    ) {
        var tokens = load(defaults: defaults)
        let token = token(alarmId: alarmId, dayKey: dayKey)
        if !tokens.contains(token) {
            tokens.append(token)
        }
        if tokens.count > 28 {
            tokens.removeFirst(tokens.count - 28)
        }
        if let data = try? JSONEncoder().encode(tokens) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    private static func token(alarmId: String, dayKey: String) -> String {
        "\(alarmId)|\(dayKey)"
    }

    private static func load(defaults: UserDefaults) -> [String] {
        guard let data = defaults.data(forKey: defaultsKey),
              let tokens = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return tokens
    }
}
