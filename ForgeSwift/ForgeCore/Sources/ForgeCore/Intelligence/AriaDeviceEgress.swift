import Foundation

/// What left this phone today — computed facts only.
///
/// Health samples, personal patterns, and memory stay on-device. A remote
/// model may receive bands and change flags, never HRV, sleep minutes,
/// condition names, or medication. Server voice is a separate opt-in event.
/// Nothing here is an ad or analytics SDK.
public enum AriaDeviceEgress: Sendable {

    public static let storageKey = "forge.aria.device.egress.v1"
    public static let backupExcluded = true
    public static let maxEvents = 80

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case chatFacts
        case serverVoice
        case account

        public var label: String {
            switch self {
            case .chatFacts: return "Computed facts for chat"
            case .serverVoice: return "Server voice"
            case .account: return "Account"
            }
        }
    }

    public struct Event: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var at: Date
        public var kind: Kind
        public var summary: String
        public var factKeys: [String]

        public init(
            id: String = UUID().uuidString,
            at: Date = Date(),
            kind: Kind,
            summary: String,
            factKeys: [String] = []
        ) {
            self.id = id
            self.at = at
            self.kind = kind
            self.summary = summary
            self.factKeys = factKeys
        }
    }

    public struct Log: Codable, Equatable, Sendable {
        public var events: [Event]

        public static let empty = Log(events: [])

        public init(events: [Event] = []) {
            self.events = events
        }
    }

    public struct Facts: Equatable, Sendable {
        public var sleepBand: String
        public var readinessBand: String
        public var gym: String
        public var patternFlags: [String]
        public var safetyChanged: Bool

        public var keys: [String] {
            var out = ["sleep_band", "readiness_band"]
            if !gym.isEmpty { out.append("gym") }
            if !patternFlags.isEmpty { out.append("pattern_flags") }
            if safetyChanged { out.append("safety_changed") }
            return out
        }

        public var asRemoteMap: [String: String] {
            var map: [String: String] = [
                "sleep_band": sleepBand,
                "readiness_band": readinessBand,
            ]
            if !gym.isEmpty { map["gym"] = gym }
            if !patternFlags.isEmpty {
                map["pattern_flags"] = patternFlags.joined(separator: ",")
            }
            if safetyChanged { map["safety_changed"] = "true" }
            return map
        }

        public var summary: String {
            var bits = ["sleep \(sleepBand)", "readiness \(readinessBand)"]
            if !gym.isEmpty { bits.append("gym \(gym)") }
            if !patternFlags.isEmpty {
                bits.append("\(patternFlags.count) pattern flag\(patternFlags.count == 1 ? "" : "s")")
            }
            if safetyChanged { bits.append("safety rule applied") }
            return bits.joined(separator: ", ")
        }
    }

    public static func computedFacts(
        sleepHours: Double?,
        readiness: Int?,
        gymLabel: String,
        patternFlags: [String],
        safetyChanged: Bool
    ) -> Facts {
        Facts(
            sleepBand: sleepBand(sleepHours),
            readinessBand: readinessBand(readiness),
            gym: gymLabel,
            patternFlags: patternFlags,
            safetyChanged: safetyChanged
        )
    }

    public static func record(
        _ log: Log,
        kind: Kind,
        summary: String,
        factKeys: [String],
        now: Date = Date()
    ) -> Log {
        var next = log
        let event = Event(
            at: now,
            kind: kind,
            summary: sanitize(summary),
            factKeys: factKeys
        )
        next.events.append(event)
        if next.events.count > maxEvents {
            next.events = Array(next.events.suffix(maxEvents))
        }
        return next
    }

    public static func today(
        _ log: Log,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Event] {
        let start = calendar.startOfDay(for: now)
        return log.events.filter { $0.at >= start }.reversed()
    }

    public static func load(defaults: UserDefaults = .standard) -> Log {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Log.self, from: data) else {
            return .empty
        }
        return decoded
    }

    public static func save(_ log: Log, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(log) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public static func containsRawHealth(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("hrv") { return true }
        if lower.contains("ms") && lower.contains("heart") { return true }
        if ForgeConditionSafety.containsBannedSpeech(text) { return true }
        if lower.contains("mg caffeine") { return true }
        return false
    }

    public static func sleepBand(_ hours: Double?) -> String {
        guard let hours else { return "unknown" }
        if hours < 6.0 { return "short" }
        if hours < 7.0 { return "fair" }
        if hours < 8.5 { return "solid" }
        return "long"
    }

    public static func readinessBand(_ score: Int?) -> String {
        guard let score else { return "unknown" }
        return HomeReadinessTokens.label(for: score).lowercased()
    }

    private static func sanitize(_ summary: String) -> String {
        let trimmed = String(summary.prefix(180))
        if containsRawHealth(trimmed) {
            return "Computed facts only"
        }
        return trimmed
    }
}
