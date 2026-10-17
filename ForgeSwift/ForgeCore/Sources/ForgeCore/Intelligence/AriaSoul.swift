import Foundation

/// Versioned ARIA persona. Style can vary; rails cannot.
public enum AriaSoul: Sendable {

    public static let version = "1"
    public static let storageKey = "forge.aria.soul.v1"

    public enum Personality: String, Codable, CaseIterable, Sendable {
        case coach
        case friend
        case drillSergeant

        public var label: String {
            switch self {
            case .coach: return "Coach"
            case .friend: return "Friend"
            case .drillSergeant: return "Drill Sergeant"
            }
        }

        public var flavor: String {
            switch self {
            case .coach: return "Clear structure, even pacing, names the next move."
            case .friend: return "Warm, wry, adult company. Check-ins without a pep rally."
            case .drillSergeant: return "Short, snarky, direct. Standards without shame."
            }
        }
    }

    public enum Mode: String, Codable, CaseIterable, Sendable {
        case pacing
        case checkIn
        case challenge
        case humor
        case structure
    }

    public struct Blend: Codable, Equatable, Sendable {
        public var coach: Double
        public var friend: Double
        public var drillSergeant: Double
        public var anchor: Personality?

        public static let coach = Blend(coach: 1, friend: 0, drillSergeant: 0, anchor: .coach)
        public static let friend = Blend(coach: 0, friend: 1, drillSergeant: 0, anchor: .friend)
        public static let drillSergeant = Blend(coach: 0, friend: 0, drillSergeant: 1, anchor: .drillSergeant)

        public init(coach: Double, friend: Double, drillSergeant: Double, anchor: Personality? = nil) {
            let raw = max(0, coach) + max(0, friend) + max(0, drillSergeant)
            let denom = raw <= 0 ? 1 : raw
            self.coach = max(0, coach) / denom
            self.friend = max(0, friend) / denom
            self.drillSergeant = max(0, drillSergeant) / denom
            self.anchor = anchor
        }

        public var dominant: Personality {
            if let anchor { return anchor }
            let pairs: [(Personality, Double)] = [
                (.coach, coach), (.friend, friend), (.drillSergeant, drillSergeant),
            ]
            return pairs.max(by: { $0.1 < $1.1 })?.0 ?? .coach
        }
    }

    public struct Config: Codable, Equatable, Sendable {
        public var version: String
        public var blend: Blend

        public init(version: String = AriaSoul.version, blend: Blend = .coach) {
            self.version = version
            self.blend = blend
        }
    }

    public static let rails = [
        "Lifestyle coach, not a doctor.",
        "Never diagnose, treat, prescribe, or cure.",
        "Never say recovery.",
        "Never shame.",
        "Never push past comfort or safety.",
        "Name real progress when it is real.",
        "Anything medical, suggest a doctor.",
    ]

    public static let banned = [
        "you failed", "you did it wrong", "you messed up", "your fault",
        "recovery", "diagnos", "prescribe", "shame on you", "push through the pain",
    ]

    public static func fuse(
        experience: String,
        goals: [String],
        engagement: Double,
        override: Personality?
    ) -> Blend {
        if let override {
            return Blend(
                coach: override == .coach ? 1 : 0,
                friend: override == .friend ? 1 : 0,
                drillSergeant: override == .drillSergeant ? 1 : 0,
                anchor: override
            )
        }
        let opening = ForgeTutorial.Opening.resolve(experience: experience, goals: goals)
        switch opening {
        case .beginner:
            return Blend(coach: 0.65, friend: 0.35, drillSergeant: 0.0)
        case .competitor:
            return Blend(coach: 0.40, friend: 0.10, drillSergeant: 0.50)
        case .everyday:
            let drill = min(0.25, max(0, engagement) * 0.2)
            return Blend(coach: 0.55, friend: 0.45 - drill, drillSergeant: drill)
        }
    }

    public static func directive(_ config: Config) -> String {
        let blend = config.blend
        let flavor: String
        switch blend.dominant {
        case .coach: flavor = Personality.coach.flavor
        case .friend: flavor = Personality.friend.flavor
        case .drillSergeant: flavor = Personality.drillSergeant.flavor
        }
        return "ARIA soul v\(config.version). Dominant: \(blend.dominant.label). \(flavor) Rails: "
            + rails.joined(separator: " ")
    }

    public static func containsRailBreak(_ line: String) -> Bool {
        let lower = line.lowercased()
        return banned.contains { lower.contains($0) }
    }

    public static func sanitize(_ line: String) -> String {
        var text = line
        if containsRailBreak(text) {
            text = text.replacingOccurrences(of: "recovery", with: "readiness", options: .caseInsensitive)
            text = text.replacingOccurrences(of: "you failed", with: "we can solve this", options: .caseInsensitive)
            text = text.replacingOccurrences(of: "you did it wrong", with: "here's what can help", options: .caseInsensitive)
        }
        return text
    }
}
