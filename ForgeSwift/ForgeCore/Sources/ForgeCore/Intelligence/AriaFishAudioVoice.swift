import Foundation

/// Fish Audio TTS — ARIA's configured cloud mouth when a key is present.
///
/// Docs: https://docs.fish.audio (POST `https://api.fish.audio/v1/tts`).
/// Auth is `Authorization: Bearer <key>`. The model is a request header
/// (`s2.1-pro` / `s2.1-pro-free`), not a body field. The key comes from the
/// process environment or the client Info dictionary — never a hardcoded
/// secret, and never committed. Missing or placeholder keys leave Fish
/// unconfigured; callers stay on the existing Apple / ElevenLabs path.
///
/// This type is network-free. It only resolves config and builds the
/// request so `swift test` can lock the contract without hitting the API.
public enum AriaFishAudioVoice: Sendable {

    public static let endpoint = URL(string: "https://api.fish.audio/v1/tts")!
    public static let defaultModel = "s2.1-pro-free"
    public static let paidModel = "s2.1-pro"
    public static let apiKeyEnvironment = "FISH_AUDIO_API_KEY"
    public static let modelEnvironment = "FISH_AUDIO_MODEL"
    public static let referenceEnvironment = "FISH_AUDIO_REFERENCE_ID"
    public static let infoKeyAPIKey = "FISH_AUDIO_API_KEY"
    public static let infoKeyModel = "FISH_AUDIO_MODEL"
    public static let infoKeyReference = "FISH_AUDIO_REFERENCE_ID"

    public static let allowedModels: Set<String> = [
        "s1", "s2-pro", "s2.1-pro", "s2.1-pro-free", "drama-3-preview",
    ]

    public struct Config: Equatable, Sendable {
        public var apiKey: String
        public var model: String
        public var referenceID: String?

        public init(apiKey: String, model: String, referenceID: String? = nil) {
            self.apiKey = apiKey
            self.model = model
            self.referenceID = referenceID
        }

        public var isConfigured: Bool { !apiKey.isEmpty }
    }

    /// Env wins, then Info.plist / generated client config. Empty and
    /// placeholder values are treated as missing — never a live key.
    public static func resolve(
        environment: [String: String],
        infoDictionary: [String: Any] = [:]
    ) -> Config {
        let key = firstLiveSecret(
            environment[apiKeyEnvironment],
            infoDictionary[infoKeyAPIKey] as? String
        )
        let model = sanitizeModel(
            firstNonEmpty(environment[modelEnvironment], infoDictionary[infoKeyModel] as? String)
        )
        let reference = firstNonEmpty(
            environment[referenceEnvironment],
            infoDictionary[infoKeyReference] as? String
        )
        return Config(apiKey: key ?? "", model: model, referenceID: reference)
    }

    public static func looksLikePlaceholder(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("<") || lower.hasSuffix(">") { return true }
        let tokens = ["your_api_key", "changeme", "todo", "replace", "placeholder", "xxx", "redacted"]
        return tokens.contains { lower.contains($0) }
    }

    public static func sanitizeModel(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if allowedModels.contains(trimmed) { return trimmed }
        return defaultModel
    }

    /// Bearer + `model` header + JSON `{ text, format }`. Nil when the key
    /// is missing or the line is empty — callers must not POST a blank key.
    public static func makeRequest(text: String, config: Config) -> URLRequest? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.isConfigured, !line.isEmpty else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.model, forHTTPHeaderField: "model")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "text": line,
            "format": "mp3",
            "mp3_bitrate": 128,
            "normalize": true,
            "latency": "normal",
        ]
        if let reference = config.referenceID, !reference.isEmpty {
            body["reference_id"] = reference
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    // MARK: - Internals

    private static func firstLiveSecret(_ values: String?...) -> String? {
        for value in values {
            guard let trimmed = firstNonEmpty(value) else { continue }
            if looksLikePlaceholder(trimmed) { continue }
            return trimmed
        }
        return nil
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
