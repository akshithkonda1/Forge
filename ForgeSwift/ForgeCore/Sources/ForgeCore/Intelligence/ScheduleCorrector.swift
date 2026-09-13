import Foundation

/// An explicit wake target and the first morning it should hold.
///
/// Sleep-medicine guidance is a 15–20 minute shift per night — jet-lag style —
/// not a single jump. `CircadianRhythm.phase()` is the current body-clock;
/// this is the destination and the ratchet toward it.
public struct ScheduleGoal: Codable, Equatable, Sendable {
    public var targetWakeHour: Double
    public var cutoverStart: Date
    public var maxShiftMinutesPerNight: Double
    public var createdAt: Date
    public var isActive: Bool

    public static let defaultMaxShiftMinutes = 15.0
    public static let hardMaxShiftMinutes = 20.0

    public init(
        targetWakeHour: Double,
        cutoverStart: Date,
        maxShiftMinutesPerNight: Double = ScheduleGoal.defaultMaxShiftMinutes,
        createdAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.targetWakeHour = CircadianRhythm.normalizedHour(targetWakeHour)
        self.cutoverStart = cutoverStart
        self.maxShiftMinutesPerNight = min(
            ScheduleGoal.hardMaxShiftMinutes,
            max(5, maxShiftMinutesPerNight)
        )
        self.createdAt = createdAt
        self.isActive = isActive
    }
}

/// Tonight's step on the ladder toward `ScheduleGoal`.
public struct ScheduleCorrectionStep: Equatable, Sendable {
    public var recommendedWakeHour: Double
    public var recommendedOnsetHour: Double
    public var shiftMinutesTonight: Double
    public var remainingGapMinutes: Double
    public var nightsRemainingEstimate: Int
    public var reachedTarget: Bool
    public var currentWakeHour: Double
    public var confidence: Double
    public var targetWakeHour: Double

    public init(
        recommendedWakeHour: Double,
        recommendedOnsetHour: Double,
        shiftMinutesTonight: Double,
        remainingGapMinutes: Double,
        nightsRemainingEstimate: Int,
        reachedTarget: Bool,
        currentWakeHour: Double,
        confidence: Double,
        targetWakeHour: Double
    ) {
        self.recommendedWakeHour = recommendedWakeHour
        self.recommendedOnsetHour = recommendedOnsetHour
        self.shiftMinutesTonight = shiftMinutesTonight
        self.remainingGapMinutes = remainingGapMinutes
        self.nightsRemainingEstimate = nightsRemainingEstimate
        self.reachedTarget = reachedTarget
        self.currentWakeHour = currentWakeHour
        self.confidence = confidence
        self.targetWakeHour = targetWakeHour
    }

    public var guidanceLine: String {
        let target = ScheduleCorrector.clockLabel(targetWakeHour)
        if reachedTarget {
            return "Wake target is \(target) — you're on it."
        }
        let minutes = Int(abs(shiftMinutesTonight).rounded())
        let direction = shiftMinutesTonight < 0 ? "earlier" : "later"
        let nights = max(1, nightsRemainingEstimate)
        return "Shifting \(minutes) min \(direction) toward \(target) — about \(nights) night\(nights == 1 ? "" : "s")."
    }

    public var coachingReply: String {
        let target = ScheduleCorrector.clockLabel(targetWakeHour)
        let bed = ScheduleCorrector.clockLabel(recommendedOnsetHour)
        if reachedTarget {
            return "You're already up at \(target). I'll keep bedtime near \(bed) so sleep holds tonight."
        }
        let minutes = Int(abs(shiftMinutesTonight).rounded())
        let direction = shiftMinutesTonight < 0 ? "earlier" : "later"
        return "I'll get you up at \(target) — \(minutes) min \(direction) tonight so sleep lands near \(bed)."
    }
}

/// Goal-directed phase advance/delay. Stateless: current phase in, tonight's
/// onset/wake out. Persistence lives in `ScheduleGoalStore`.
public enum ScheduleCorrector: Sendable {

    public static let reachedThresholdMinutes = 5.0

    /// Shortest signed hour delta on the clock, −12...12.
    public static func signedHourDelta(from: Double, to: Double) -> Double {
        var delta = CircadianRhythm.normalizedHour(to) - CircadianRhythm.normalizedHour(from)
        if delta > 12 { delta -= 24 }
        if delta < -12 { delta += 24 }
        return delta
    }

    public static func clockLabel(_ hour: Double) -> String {
        let normalized = CircadianRhythm.normalizedHour(hour)
        var whole = Int(normalized)
        var minute = Int(((normalized - Double(whole)) * 60).rounded())
        if minute >= 60 {
            minute = 0
            whole = (whole + 1) % 24
        }
        let suffix = whole >= 12 ? "pm" : "am"
        let h12 = whole % 12 == 0 ? 12 : whole % 12
        return String(format: "%d:%02d %@", h12, minute, suffix)
    }

    public static func tonight(
        goal: ScheduleGoal,
        nights: [CircadianRhythm.Night],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ScheduleCorrectionStep? {
        guard goal.isActive else { return nil }
        guard let phase = CircadianRhythm.phase(from: nights, calendar: calendar) else { return nil }

        let need = CircadianRhythm.sleepNeedHours(from: nights)
        let gapHours = signedHourDelta(from: phase.wakeHour, to: goal.targetWakeHour)
        let gapMinutes = gapHours * 60
        let reached = abs(gapMinutes) < reachedThresholdMinutes
        let maxShiftHours = goal.maxShiftMinutesPerNight / 60.0

        let startToday = calendar.startOfDay(for: now)
        let cutoverDay = calendar.startOfDay(for: goal.cutoverStart)
        let daysUntil = calendar.dateComponents([.day], from: startToday, to: cutoverDay).day ?? 0

        let shiftHours: Double
        if reached {
            shiftHours = 0
        } else if daysUntil > 0 {
            let planned = gapHours / Double(daysUntil)
            shiftHours = min(maxShiftHours, max(-maxShiftHours, planned))
        } else {
            shiftHours = min(maxShiftHours, max(-maxShiftHours, gapHours))
        }

        let tonightWake = CircadianRhythm.normalizedHour(phase.wakeHour + shiftHours)
        let tonightOnset = CircadianRhythm.normalizedHour(tonightWake - need)
        let remaining = abs(gapMinutes - shiftHours * 60)
        let nightsLeft: Int
        if reached {
            nightsLeft = 0
        } else {
            nightsLeft = max(1, Int(ceil(abs(gapHours) / max(0.01, maxShiftHours))))
        }

        return ScheduleCorrectionStep(
            recommendedWakeHour: tonightWake,
            recommendedOnsetHour: tonightOnset,
            shiftMinutesTonight: shiftHours * 60,
            remainingGapMinutes: remaining,
            nightsRemainingEstimate: nightsLeft,
            reachedTarget: reached,
            currentWakeHour: phase.wakeHour,
            confidence: phase.confidence,
            targetWakeHour: goal.targetWakeHour
        )
    }
}

public enum ScheduleGoalStore: Sendable {
    public static let defaultsKey = "forge.sleep.scheduleGoal.v1"

    public static func save(_ goal: ScheduleGoal, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(goal) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    public static func load(defaults: UserDefaults = .standard) -> ScheduleGoal? {
        guard let data = defaults.data(forKey: defaultsKey),
              let goal = try? JSONDecoder().decode(ScheduleGoal.self, from: data),
              goal.isActive else { return nil }
        return goal
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

/// Conversational "up at 6am starting Monday" → `ScheduleGoal`.
public enum ScheduleGoalParser: Sendable {

    public static func isScheduleAsk(_ text: String) -> Bool {
        parse(text) != nil
    }

    public static func parse(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ScheduleGoal? {
        let lower = text.lowercased()
        guard hasScheduleCue(lower) else { return nil }
        guard let hour = parseWakeHour(in: lower) else { return nil }
        let cutover = parseCutover(in: lower, now: now, calendar: calendar)
        return ScheduleGoal(
            targetWakeHour: hour,
            cutoverStart: cutover,
            createdAt: now
        )
    }

    private static func hasScheduleCue(_ lower: String) -> Bool {
        let cues = [
            "up at", "wake at", "wake me", "get up at", "be up at",
            "getting up at", "alarm at", "wake time", "start waking",
            "waking up at", "need to be up",
        ]
        return cues.contains { lower.contains($0) }
    }

    static func parseWakeHour(in lower: String) -> Double? {
        let pattern = #"(?:up at|wake(?: me)?(?: up)? at|get up at|be up at|getting up at|waking up at|alarm at|wake time(?: of)?|need to be up(?: at)?)\s+(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: range),
              match.numberOfRanges >= 2,
              let hourRange = Range(match.range(at: 1), in: lower),
              var hour = Int(lower[hourRange]) else { return nil }
        var minute = 0
        if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound,
           let minRange = Range(match.range(at: 2), in: lower) {
            minute = Int(lower[minRange]) ?? 0
        }
        var isPM: Bool?
        if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound,
           let ampmRange = Range(match.range(at: 3), in: lower) {
            let stamp = lower[ampmRange]
            if stamp.contains("p") { isPM = true }
            if stamp.contains("a") { isPM = false }
        }
        hour = min(23, max(0, hour))
        minute = min(59, max(0, minute))
        if let isPM {
            if isPM, hour < 12 { hour += 12 }
            if isPM == false, hour == 12 { hour = 0 }
        } else if hour == 0 || hour == 24 {
            hour = 0
        } else if hour > 24 {
            return nil
        }
        // Bare "6" on a wake ask is 6am, not 18:00.
        if isPM == nil, hour >= 13, hour <= 23 {
            // already 24h
        } else if isPM == nil, hour == 12 {
            hour = 12
        }
        return Double(hour) + Double(minute) / 60.0
    }

    static func parseCutover(in lower: String, now: Date, calendar: Calendar) -> Date {
        let weekdays: [(Int, [String])] = [
            (1, ["sunday"]),
            (2, ["monday"]),
            (3, ["tuesday"]),
            (4, ["wednesday"]),
            (5, ["thursday"]),
            (6, ["friday"]),
            (7, ["saturday"]),
        ]
        for (code, names) in weekdays {
            if names.contains(where: { lower.contains($0) }) {
                return nextWeekday(code, from: now, calendar: calendar)
            }
        }
        return now
    }

    static func nextWeekday(_ weekday: Int, from now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if calendar.component(.weekday, from: day) == weekday { return day }
        }
        return start
    }
}
