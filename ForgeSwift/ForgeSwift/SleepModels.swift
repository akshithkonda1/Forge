import SwiftUI

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
        case .night: return "Night"
        case .alarms: return "Alarms"
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
