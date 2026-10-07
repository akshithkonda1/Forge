import Foundation

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

enum SleepHud {
    static let plateHex = "7EC8FF"
    static let tickCount = 36
}
