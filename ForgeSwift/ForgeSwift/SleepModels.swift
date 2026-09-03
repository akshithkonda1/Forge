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

struct ForgeAlarm: Identifiable, Codable {
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
        case .alarms: return "Alarms"
        }
    }

    /// Evening and the small hours open on Tonight — that's when the page has a job.
    static func suggested(hour: Int) -> SleepTab {
        (hour >= 19 || hour < 5) ? .night : .day
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

enum VolumeRampCurve: String, CaseIterable {
    case instant  = "Instant"
    case gentle   = "Gentle"
    case gradual  = "Gradual"

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
