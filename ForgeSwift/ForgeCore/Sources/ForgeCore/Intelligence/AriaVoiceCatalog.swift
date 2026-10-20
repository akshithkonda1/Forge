import Foundation

/// ARIA voice profiles — Fish Audio library plus a small featured set.
///
/// Featured names are original traits. They never use a trademarked character
/// or a real actor. Voice ids come from `GET /ai/voice` (Fish `GET /model`).
public enum AriaVoiceCatalog: Sendable {
    public static let path = "ai/voice"
    public static let speakPath = "ai/voice/speak"
    public static let defaultModel = AriaFishAudioVoice.defaultModel
    public static let paidModel = AriaFishAudioVoice.paidModel
    public static let previewText = AriaFishAudioVoice.previewText

    public static let featuredIDs = ["warm", "calm", "neutral", "spark", "ember"]

    public struct Voice: Equatable, Sendable, Codable {
        public var id: String
        public var title: String
        public var description: String
        public var tags: [String]
        public var languages: [String]

        public init(
            id: String,
            title: String,
            description: String = "",
            tags: [String] = [],
            languages: [String] = []
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.tags = tags
            self.languages = languages
        }
    }

    public struct Profile: Equatable, Sendable, Codable, Identifiable {
        public var id: String
        public var label: String
        public var description: String
        public var speed: Double
        public var voiceID: String?
        public var voiceTitle: String?

        public init(
            id: String,
            label: String,
            description: String,
            speed: Double = 1.0,
            voiceID: String? = nil,
            voiceTitle: String? = nil
        ) {
            self.id = id
            self.label = label
            self.description = description
            self.speed = speed
            self.voiceID = voiceID
            self.voiceTitle = voiceTitle
        }

        enum CodingKeys: String, CodingKey {
            case id, label, description, speed
            case voiceID = "voice_id"
            case voiceTitle = "voice_title"
        }
    }

    public struct Selection: Equatable, Sendable, Codable {
        public var profileID: String?
        public var voiceID: String?
        public var speed: Double

        public static let storageKey = "forge.aria.voice.profile.v1"

        public init(profileID: String? = nil, voiceID: String? = nil, speed: Double = 1.0) {
            self.profileID = profileID
            self.voiceID = voiceID
            self.speed = speed
        }

        public static func load(from defaults: UserDefaults = .standard) -> Selection {
            guard let data = defaults.data(forKey: storageKey),
                  let decoded = try? JSONDecoder().decode(Selection.self, from: data) else {
                return Selection(profileID: "warm")
            }
            return decoded
        }

        public func persist(to defaults: UserDefaults = .standard) {
            if let data = try? JSONEncoder().encode(self) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }

        enum CodingKeys: String, CodingKey {
            case profileID = "profile_id"
            case voiceID = "voice_id"
            case speed
        }
    }

    public struct Envelope: Equatable, Sendable, Codable {
        public var model: String
        public var previewText: String
        public var selected: Selection
        public var featured: [Profile]
        public var voices: [Voice]
        public var page: Int
        public var pageSize: Int
        public var total: Int
        public var hasMore: Bool
        public var source: String

        enum CodingKeys: String, CodingKey {
            case model, selected, featured, voices, page, total, source
            case previewText = "preview_text"
            case pageSize = "page_size"
            case hasMore = "has_more"
        }
    }

    /// Featured recipes without live ids — used until `GET /ai/voice` returns.
    public static let recipes: [Profile] = [
        Profile(id: "warm", label: "Warm", description: "Close, unhurried, a woman in the room.", speed: 1.0),
        Profile(id: "calm", label: "Calm", description: "Even, low, a man who is not in a hurry.", speed: 0.95),
        Profile(id: "neutral", label: "Neutral", description: "Clear and even. Not styled as a man or a woman.", speed: 1.0),
        Profile(id: "spark", label: "Spark", description: "Brighter and a little faster. Still a coach, not a bit.", speed: 1.08),
        Profile(id: "ember", label: "Ember", description: "Blunt, gruff, confident. A young tomboy coach — original voice, not a character impression.", speed: 1.05),
    ]

    public static func isFeaturedID(_ id: String) -> Bool {
        featuredIDs.contains(id)
    }

    public static func recipe(id: String) -> Profile? {
        recipes.first { $0.id == id }
    }

    public static func apply(selection: Selection, to profile: Profile) -> Selection {
        Selection(
            profileID: profile.id,
            voiceID: profile.voiceID ?? selection.voiceID,
            speed: profile.speed
        )
    }

    /// Next `POST /ai/voice/speak` body. Switching the selection changes `voice_id`.
    public static func speakBody(
        text: String,
        selection: Selection,
        preview: Bool = false
    ) -> [String: Any] {
        var body: [String: Any] = [
            "text": text,
            "preview": preview,
            "speed": selection.speed,
        ]
        if let profileID = selection.profileID, !profileID.isEmpty {
            body["profile_id"] = profileID
        }
        if let voiceID = selection.voiceID, !voiceID.isEmpty {
            body["voice_id"] = voiceID
        }
        return body
    }

    public static func persistBody(_ selection: Selection) -> [String: Any] {
        var body: [String: Any] = ["speed": selection.speed]
        if let profileID = selection.profileID { body["profile_id"] = profileID }
        if let voiceID = selection.voiceID { body["voice_id"] = voiceID }
        return body
    }

    public static func catalogURL(baseURL: URL, query: String = "", page: Int = 1) -> URL? {
        guard AriaFishAudioVoice.isBackendReachable(baseURL) else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "page_size", value: "20"),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "q", value: trimmed))
        }
        components?.queryItems = items
        return components?.url
    }

    public static func labelsAvoidTrademarkedCharacters(_ profiles: [Profile]) -> Bool {
        let banned = ["toph", "aang", "katara", "zuko", "avatar", "korra"]
        let blob = profiles.map { "\($0.id) \($0.label) \($0.description)" }.joined(separator: " ").lowercased()
        return banned.allSatisfy { !blob.contains($0) }
    }
}
