import Foundation
import SwiftUI

/// Mixer-level volume ramp. The DSP envelope is a backup; this is the gain
/// the wake session actually applies to `mainMixerNode` so Instant / Gentle /
/// Gradual / Deep / Super-deep are audible differences, not UI labels.
enum SleepVolumeRamp {
    /// Smoothstep rise. Instant (≤0.5s) is full immediately. Deep curves
    /// stay quiet longer so super-deep sleepers are not jumped.
    static func gain(elapsed: TimeInterval, seconds: Double) -> Float {
        if seconds <= 0.5 { return 1 }
        let t = min(1, max(0, elapsed / seconds))
        if t >= 1 { return 1 }
        let smooth = t * t * (3 - 2 * t)
        return Float(smooth)
    }

    static func appliesMixerRamp(_ curve: VolumeRampCurve) -> Bool {
        curve.rampSeconds > 0.5
    }
}

enum SleepMixTimer {
    /// 0 = run until Stop. Music and generated beds share this stop.
    static let options = [15, 30, 45, 60, 90, 120, 240, 0]

    static func label(_ minutes: Int) -> String {
        if minutes <= 0 { return "Until stop" }
        if minutes >= 60 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}

struct SleepForgePlaylist: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var kinds: [String]
    var minutes: Int
}

enum SleepForgePlaylistStore {
    private static let key = "forge.sleep.playlists.v1"

    static func load() -> [SleepForgePlaylist] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let lists = try? JSONDecoder().decode([SleepForgePlaylist].self, from: data) else {
            return []
        }
        return lists
    }

    static func save(_ lists: [SleepForgePlaylist]) {
        if let data = try? JSONEncoder().encode(lists) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func add(name: String, kinds: [SleepSoundKind], minutes: Int) {
        var lists = load()
        lists.insert(
            SleepForgePlaylist(name: name, kinds: kinds.map(\.rawValue), minutes: minutes),
            at: 0
        )
        if lists.count > 12 { lists = Array(lists.prefix(12)) }
        save(lists)
    }
}

enum SleepPalette {
    static let plateHex = "7EC8FF"
    static let lightStageHex = "64748B"
    static let cafeHex = "92400E"
    static let pinkHex = "EC4899"
    static let lofiHex = "F472B6"
    static let oceanHex = "0EA5E9"
    static let chimesHex = "38BDF8"
    static let binauralHex = "818CF8"
    static let deepFocusHex = "7C3AED"
    static let sunriseWarmHex = "FF8C42"
    static let sunriseMidHex = "FFD166"
    static let sunrisePaleHex = "FEFAE0"
    static let sunriseCoolHex = "C8E6FF"
    static let wakeNavyHex = "0F172A"
    static let wakeSlateHex = "1E293B"
    static let bgDeepHex = "1A1440"
    static let bgMistHex = "A9D8FF"
    static let appleMusicHex = "FA2D48"

    static var plate: Color { Color(hex: plateHex) }
    static var lightStage: Color { Color(hex: lightStageHex) }
    static var cafe: Color { Color(hex: cafeHex) }
    static var pink: Color { Color(hex: pinkHex) }
    static var lofi: Color { Color(hex: lofiHex) }
    static var ocean: Color { Color(hex: oceanHex) }
    static var chimes: Color { Color(hex: chimesHex) }
    static var binaural: Color { Color(hex: binauralHex) }
    static var deepFocus: Color { Color(hex: deepFocusHex) }
    static var sunriseWarm: Color { Color(hex: sunriseWarmHex) }
    static var sunriseMid: Color { Color(hex: sunriseMidHex) }
    static var sunrisePale: Color { Color(hex: sunrisePaleHex) }
    static var sunriseCool: Color { Color(hex: sunriseCoolHex) }
    static var wakeNavy: Color { Color(hex: wakeNavyHex) }
    static var wakeSlate: Color { Color(hex: wakeSlateHex) }
    static var bgDeep: Color { Color(hex: bgDeepHex) }
    static var bgMist: Color { Color(hex: bgMistHex) }
    static var appleMusic: Color { Color(hex: appleMusicHex) }
    static var sunriseRamp: [Color] { [sunriseWarm, sunriseMid, sunrisePale, sunriseCool] }
}
