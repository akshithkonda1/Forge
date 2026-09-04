import SwiftUI
import ForgeCore

enum Weekday: Int, CaseIterable, Codable, Identifiable {
    case sun = 1, mon, tue, wed, thu, fri, sat
    var id: Int { rawValue }
    var short: String { ["S","M","T","W","T","F","S"][rawValue - 1] }
    var full: String  { ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"][rawValue - 1] }
}

enum AlarmSoundOption: String, CaseIterable, Codable {
    case gentleRise  = "Gentle Rise"
    case forestBirds = "Forest Birds"
    case oceanWaves  = "Ocean Waves"
    case windChimes  = "Wind Chimes"
    case tibetanBell = "Tibetan Bell"
    case sunriseGlow = "Sunrise Glow"
    case rainDrop    = "Rain Drop"
    case softPiano   = "Soft Piano"

    var icon: String {
        switch self {
        case .gentleRise:  return "sunrise.fill"
        case .forestBirds: return "bird.fill"
        case .oceanWaves:  return "water.waves"
        case .windChimes:  return "wind"
        case .tibetanBell: return "bell.fill"
        case .sunriseGlow: return "sun.max.fill"
        case .rainDrop:    return "cloud.drizzle.fill"
        case .softPiano:   return "music.note"
        }
    }

    var category: String {
        switch self {
        case .gentleRise, .sunriseGlow:                return "Ambient"
        case .forestBirds, .oceanWaves, .rainDrop:     return "Nature"
        case .windChimes, .tibetanBell, .softPiano:    return "Tones"
        }
    }
}

struct ForgeAlarm: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String = "Wake Up"
    var time: Date = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    var days: [Int] = [2, 3, 4, 5, 6]          // Mon–Fri
    var sound: AlarmSoundOption = .gentleRise
    var snoozeMinutes: Int = 9
    var isSmartWake: Bool = true
    var smartWakeWindow: Int = 30               // minutes before alarm
    var isEnabled: Bool = true
    var gradualVolume: Bool = true
}

/// Next fire, smart-wake lead, and notification ids — pure so tests can pin the clock.
enum SleepWakeEngine {
    static let idPrefix = "forge.wake."
    static let category = "forge.wake"
    static let actionSnooze = "forge.wake.snooze"
    static let actionUp = "forge.wake.up"
    static let maxSnoozes = 2

    static func hourMinute(of time: Date, calendar: Calendar = .current) -> (Int, Int) {
        let c = calendar.dateComponents([.hour, .minute], from: time)
        return (c.hour ?? 7, c.minute ?? 0)
    }

    /// Empty `days` means every day. Disabled alarms never fire.
    static func nextHardFire(
        alarm: ForgeAlarm,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard alarm.isEnabled else { return nil }
        let (hour, minute) = hourMinute(of: alarm.time, calendar: calendar)
        let days = alarm.days.isEmpty ? Array(1...7) : Array(Set(alarm.days))
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard days.contains(weekday) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            guard let fire = calendar.date(from: comps) else { continue }
            if fire > now { return fire }
            // Keep this morning's alarm current for two minutes so the Wake tab can say "get up".
            if offset == 0, now.timeIntervalSince(fire) >= 0, now.timeIntervalSince(fire) < 120 {
                return fire
            }
        }
        return nil
    }

    static func smartWakeFire(hard: Date, windowMinutes: Int) -> Date {
        hard.addingTimeInterval(-TimeInterval(max(1, windowMinutes)) * 60)
    }

    static func nextAlarm(in alarms: [ForgeAlarm], now: Date = Date(), calendar: Calendar = .current) -> ForgeAlarm? {
        alarms
            .compactMap { alarm -> (ForgeAlarm, Date)? in
                guard let fire = nextHardFire(alarm: alarm, now: now, calendar: calendar) else { return nil }
                return (alarm, fire)
            }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    static func hardNotificationId(for alarmID: UUID) -> String { idPrefix + "hard." + alarmID.uuidString }
    static func smartNotificationId(for alarmID: UUID) -> String { idPrefix + "smart." + alarmID.uuidString }
    static func snoozeNotificationId(for alarmID: UUID) -> String { idPrefix + "snooze." + alarmID.uuidString }

    static func isWakeNotification(_ identifier: String) -> Bool {
        identifier.hasPrefix(idPrefix)
    }

    static func canSnooze(count: Int) -> Bool {
        count < maxSnoozes
    }

    /// First upcoming `weekday` at `hour`:`minute` on or after `now`'s calendar day.
    static func dateOnWeekday(
        _ weekday: Int,
        hour: Int,
        minute: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            guard calendar.component(.weekday, from: day) == weekday else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            return calendar.date(from: comps)
        }
        return nil
    }

    /// Smart-wake clock, including a previous-day wrap (00:15 − 30 min → 23:45 Sunday).
    static func repeatingSmartClock(
        weekday: Int,
        hour: Int,
        minute: Int,
        windowMinutes: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (weekday: Int, hour: Int, minute: Int) {
        guard let hard = dateOnWeekday(weekday, hour: hour, minute: minute, now: now, calendar: calendar) else {
            return (weekday, hour, minute)
        }
        let smart = smartWakeFire(hard: hard, windowMinutes: windowMinutes)
        return (
            calendar.component(.weekday, from: smart),
            calendar.component(.hour, from: smart),
            calendar.component(.minute, from: smart)
        )
    }

    static func minutesUntil(_ date: Date, now: Date = Date()) -> Int {
        Int((date.timeIntervalSince(now) / 60).rounded())
    }

    static func countdownLabel(until date: Date, now: Date = Date()) -> String {
        let minutes = max(0, minutesUntil(date, now: now))
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "in \(hours)h" : "in \(hours)h \(rem)m"
    }
}

enum SleepWakePhase: String, Equatable {
    case waiting, approaching, windowOpen, due, morning
}

/// Next alarm + copy for the Wake tab and the ringing screen.
struct SleepWakeCoach: Equatable {
    var phase: SleepWakePhase
    var alarm: ForgeAlarm?
    var hardFire: Date?
    var smartFire: Date?
    var minutesUntilHard: Int
    var headline: String
    var cue: String
    var ariaPrompt: String

    var countdownLabel: String {
        guard let hardFire else { return "no wake set" }
        if phase == .due { return "now" }
        return SleepWakeEngine.countdownLabel(until: hardFire)
    }

    static func make(
        alarms: [ForgeAlarm],
        now: Date = Date(),
        calendar: Calendar = .current,
        sleepScore: Int? = nil,
        lastNightHours: Double? = nil
    ) -> SleepWakeCoach {
        let alarm = SleepWakeEngine.nextAlarm(in: alarms, now: now, calendar: calendar)
        let hard = alarm.flatMap { SleepWakeEngine.nextHardFire(alarm: $0, now: now, calendar: calendar) }
        let smart: Date? = {
            guard let alarm, let hard, alarm.isSmartWake else { return nil }
            return SleepWakeEngine.smartWakeFire(hard: hard, windowMinutes: alarm.smartWakeWindow)
        }()
        let until = hard.map { SleepWakeEngine.minutesUntil($0, now: now) } ?? 0
        let hour = calendar.component(.hour, from: now)

        let phase: SleepWakePhase
        if let hard, now >= hard {
            phase = .due
        } else if let smart, now >= smart {
            phase = .windowOpen
        } else if hard != nil, until <= 90 {
            phase = .approaching
        } else if hour >= 5, hour < 10, hard == nil || until > 12 * 60 {
            phase = .morning
        } else {
            phase = .waiting
        }

        let timeLabel = hard?.formatted(date: .omitted, time: .shortened) ?? "no time"
        let (headline, cue, prompt) = copy(
            phase: phase,
            timeLabel: timeLabel,
            until: max(0, until),
            sleepScore: sleepScore,
            lastNightHours: lastNightHours
        )
        return SleepWakeCoach(
            phase: phase,
            alarm: alarm,
            hardFire: hard,
            smartFire: smart,
            minutesUntilHard: until,
            headline: headline,
            cue: cue,
            ariaPrompt: prompt
        )
    }

    static func morningPrompt(sleepScore: Int?, lastNightHours: Double?) -> String {
        let night: String
        if let sleepScore {
            night = "Last night scored \(sleepScore)."
        } else if let lastNightHours {
            night = "Last night was \(String(format: "%.1f", lastNightHours)) hours."
        } else {
            night = "Last night's sleep is unavailable."
        }
        return "I just woke up. \(night) First ten minutes: light, water, no scroll. Get me moving."
    }

    private static func copy(
        phase: SleepWakePhase,
        timeLabel: String,
        until: Int,
        sleepScore: Int?,
        lastNightHours: Double?
    ) -> (String, String, String) {
        let nightBit: String
        if let sleepScore {
            nightBit = "Last night scored \(sleepScore)."
        } else if let lastNightHours {
            nightBit = "Last night was \(String(format: "%.1f", lastNightHours)) hours."
        } else {
            nightBit = "Last night's sleep is unavailable."
        }

        switch phase {
        case .waiting:
            return (
                "Next wake \(timeLabel)",
                "Hard alarm stands. Smart wake only fires earlier if you left it on.",
                "My next alarm is \(timeLabel). Help me actually get up when it rings — no snooze spiral."
            )
        case .approaching:
            return (
                "Wake in \(until) min",
                "Don't bargain with the first alarm. Water, light, stand up.",
                "Alarm is \(timeLabel). \(nightBit) Get me up on the first ring."
            )
        case .windowOpen:
            return (
                "Smart window is open",
                "If you're already light, get up now. The hard alarm still fires at \(timeLabel).",
                "I'm in the smart-wake window before \(timeLabel). If I'm light, get me up now."
            )
        case .due:
            return (
                "Get up",
                "The day already started. Hold I'm up — snooze is rationed.",
                morningPrompt(sleepScore: sleepScore, lastNightHours: lastNightHours)
            )
        case .morning:
            return (
                "You're up",
                "Don't sit back down. Light, water, then the first real task.",
                morningPrompt(sleepScore: sleepScore, lastNightHours: lastNightHours)
            )
        }
    }
}

struct SleepSoundItem: Identifiable {
    let id: UUID = UUID()
    let name: String
    let icon: String
    let color: Color
    let category: SleepSoundCategory
}

enum SleepSoundCategory: String, CaseIterable {
    case nature  = "Nature"
    case noise   = "Noise"
    case ambient = "Ambient"
    case focus   = "Focus"
}

let allSleepSounds: [SleepSoundItem] = [
    SleepSoundItem(name: "Rain",          icon: "cloud.rain.fill",          color: .steel,              category: .nature),
    SleepSoundItem(name: "Ocean",         icon: "water.waves",               color: Color(hex: "0EA5E9"), category: .nature),
    SleepSoundItem(name: "Forest",        icon: "tree.fill",                 color: .success,            category: .nature),
    SleepSoundItem(name: "Thunder",       icon: "cloud.bolt.rain.fill",      color: Color(hex: "6366F1"), category: .nature),
    SleepSoundItem(name: "White Noise",   icon: "waveform",                  color: .textTertiary,       category: .noise),
    SleepSoundItem(name: "Brown Noise",   icon: "waveform.path",             color: Color(hex: "92400E"), category: .noise),
    SleepSoundItem(name: "Pink Noise",    icon: "waveform.path.ecg",         color: Color(hex: "EC4899"), category: .noise),
    SleepSoundItem(name: "Fan",           icon: "fan.fill",                  color: .textSecondary,      category: .noise),
    SleepSoundItem(name: "Fireplace",     icon: "flame.fill",                color: .ember,              category: .ambient),
    SleepSoundItem(name: "Café",          icon: "cup.and.saucer.fill",       color: Color(hex: "92400E"), category: .ambient),
    SleepSoundItem(name: "Tibetan Bowl",  icon: "bell.fill",                 color: Color(hex: "A78BFA"), category: .ambient),
    SleepSoundItem(name: "Wind Chimes",   icon: "wind",                      color: Color(hex: "38BDF8"), category: .ambient),
    SleepSoundItem(name: "Lo-Fi",         icon: "music.note",                color: Color(hex: "F472B6"), category: .focus),
    SleepSoundItem(name: "Binaural",      icon: "headphones",                color: Color(hex: "818CF8"), category: .focus),
    SleepSoundItem(name: "432 Hz",        icon: "tuningfork",                color: .success,            category: .focus),
    SleepSoundItem(name: "Deep Focus",    icon: "brain.fill",                color: Color(hex: "7C3AED"), category: .focus),
]

enum SleepTab: Int, CaseIterable {
    case day, night, alarms
    var title: String {
        switch self {
        case .day: return "Day"
        case .night: return "Tonight"
        case .alarms: return "Wake"
        }
    }

    /// Evening opens Tonight. Morning opens Wake. Midday stays on Day.
    static func suggested(hour: Int) -> SleepTab {
        if hour >= 19 || hour < 5 { return .night }
        if hour >= 5 && hour < 10 { return .alarms }
        return .day
    }
}

enum SleepBedtimePhase: String, Equatable {
    case dayplan, approaching, windDown, lightsOut, overdue
}

/// Clock + `WindDownPredictor` → what Sleep should say and do right now.
struct SleepBedtimeCoach: Equatable {
    var phase: SleepBedtimePhase
    var bedtime: Date
    var windDownStart: Date
    var minutesUntilBed: Int
    var minutesUntilWindDown: Int
    var headline: String
    var cue: String
    var ariaPrompt: String

    var bedtimeLabel: String {
        bedtime.formatted(date: .omitted, time: .shortened)
    }

    var countdownLabel: String {
        if phase == .overdue || phase == .lightsOut { return "now" }
        if minutesUntilBed <= 0 { return "now" }
        if minutesUntilBed < 60 { return "\(minutesUntilBed) min" }
        let hours = minutesUntilBed / 60
        let mins = minutesUntilBed % 60
        return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
    }

    /// Same bedtime, fresh phase/copy from the clock — used by the Tonight hero tick.
    func advancing(now: Date = Date()) -> SleepBedtimeCoach {
        let windowEnd = bedtime.addingTimeInterval(WindDownPredictor.windowLengthMinutes * 60)
        let untilBed = Int((bedtime.timeIntervalSince(now) / 60).rounded())
        let untilWind = Int((windDownStart.timeIntervalSince(now) / 60).rounded())
        let next: SleepBedtimePhase
        if now >= windowEnd {
            next = .overdue
        } else if now >= bedtime {
            next = .lightsOut
        } else if now >= windDownStart {
            next = .windDown
        } else if untilWind <= 90 {
            next = .approaching
        } else {
            next = .dayplan
        }
        let bedLabel = bedtime.formatted(date: .omitted, time: .shortened)
        let (headline, cue, prompt) = Self.copy(phase: next, bedLabel: bedLabel, untilBed: max(0, untilBed))
        return SleepBedtimeCoach(
            phase: next,
            bedtime: bedtime,
            windDownStart: windDownStart,
            minutesUntilBed: untilBed,
            minutesUntilWindDown: untilWind,
            headline: headline,
            cue: cue,
            ariaPrompt: prompt
        )
    }

    static func make(
        onsets: [Date],
        sleepMinutes: [Double],
        needMinutes: Double = 8 * 60,
        fallbackOnsetHour: Double? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SleepBedtimeCoach {
        let plan = WindDownPredictor.plan(
            recentOnsets: onsets,
            recentSleepMinutes: sleepMinutes,
            sleepNeedMinutes: needMinutes,
            now: now,
            calendar: calendar
        ) ?? fallbackPlan(onsetHour: fallbackOnsetHour, now: now, calendar: calendar)

        let untilBed = Int((plan.bedtimeWindowStart.timeIntervalSince(now) / 60).rounded())
        let untilWind = Int((plan.windDownStart.timeIntervalSince(now) / 60).rounded())
        let phase: SleepBedtimePhase
        if now >= plan.bedtimeWindowEnd {
            phase = .overdue
        } else if now >= plan.bedtimeWindowStart {
            phase = .lightsOut
        } else if now >= plan.windDownStart {
            phase = .windDown
        } else if untilWind <= 90 {
            phase = .approaching
        } else {
            phase = .dayplan
        }

        let bedLabel = plan.bedtimeWindowStart.formatted(date: .omitted, time: .shortened)
        let (headline, cue, prompt) = copy(phase: phase, bedLabel: bedLabel, untilBed: max(0, untilBed))
        return SleepBedtimeCoach(
            phase: phase,
            bedtime: plan.bedtimeWindowStart,
            windDownStart: plan.windDownStart,
            minutesUntilBed: untilBed,
            minutesUntilWindDown: untilWind,
            headline: headline,
            cue: cue,
            ariaPrompt: prompt
        )
    }

    static func fallbackPlan(onsetHour: Double?, now: Date, calendar: Calendar) -> WindDownPlan {
        let hour = onsetHour ?? 22.5
        let bed = dateTonight(hour: hour, now: now, calendar: calendar)
        return WindDownPlan(
            windDownStart: bed.addingTimeInterval(-WindDownPredictor.windDownLeadMinutes * 60),
            bedtimeWindowStart: bed,
            bedtimeWindowEnd: bed.addingTimeInterval(WindDownPredictor.windowLengthMinutes * 60)
        )
    }

    static func dateTonight(hour: Double, now: Date, calendar: Calendar) -> Date {
        let wrapped = ((hour.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        var whole = Int(wrapped)
        var minute = Int(((wrapped - Double(whole)) * 60).rounded())
        if minute >= 60 {
            minute = 0
            whole = (whole + 1) % 24
        }
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = whole
        comps.minute = minute
        comps.second = 0
        var date = calendar.date(from: comps) ?? now
        if date < now.addingTimeInterval(-4 * 3600) {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    private static func copy(phase: SleepBedtimePhase, bedLabel: String, untilBed: Int) -> (String, String, String) {
        switch phase {
        case .dayplan:
            return (
                "Tonight, lights out at \(bedLabel)",
                "Protect the last hour. Screens dim, caffeine done, room cooling.",
                "Help me land in bed at \(bedLabel). What should I drop between now and then?"
            )
        case .approaching:
            return (
                "Wind-down in \(untilBed) min",
                "Dim the room. Start a sound. Leave the day in another room.",
                "Wind-down starts soon and bedtime is \(bedLabel). Walk me through the next twenty minutes."
            )
        case .windDown:
            return (
                "Start winding down",
                "Lights low. Phone on the table. One sound, then you are done.",
                "It is wind-down. Get me into bed at \(bedLabel) without a lecture."
            )
        case .lightsOut:
            return (
                "It's bedtime",
                "Stop negotiating. Brown noise on, screen down, lights out.",
                "It is bedtime. Help me actually get into bed right now."
            )
        case .overdue:
            return (
                "You're still up",
                "The window already opened. Go now — tomorrow's training is already paying for this.",
                "I am past bedtime. Get me to sleep in the next ten minutes."
            )
        }
    }
}

enum VolumeRampCurve: String, CaseIterable, Codable {
    case instant  = "Instant"
    case gentle   = "Gentle"
    case gradual  = "Gradual"

    var rampSeconds: Double {
        switch self {
        case .instant: return 0.4
        case .gentle:  return 15
        case .gradual: return 60
        }
    }

    var description: String {
        switch self {
        case .instant: return "Full volume immediately"
        case .gentle:  return "Ramps up over 15 seconds"
        case .gradual: return "Slowly increases over 60 seconds"
        }
    }
    var icon: String {
        switch self {
        case .instant: return "bolt.fill"
        case .gentle:  return "chart.line.uptrend.xyaxis"
        case .gradual: return "waveform.path"
        }
    }
}

struct RoutineItem: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var icon: String
    var duration: Int        // minutes
    var isEnabled: Bool = true

    static var defaults: [RoutineItem] {[
        RoutineItem(name: "Drink Water",       icon: "drop.fill",            duration: 1),
        RoutineItem(name: "Morning Sunlight",  icon: "sun.max.fill",         duration: 10),
        RoutineItem(name: "Stretch / Mobility",icon: "figure.cooldown",      duration: 10),
        RoutineItem(name: "Cold Shower",       icon: "thermometer.snowflake", duration: 3),
        RoutineItem(name: "Journaling",        icon: "pencil.and.outline",   duration: 5),
        RoutineItem(name: "Meditation",        icon: "brain.fill",           duration: 5),
    ]}
}
