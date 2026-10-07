import Foundation

/// Fish Audio TTS — Hex load path, same as ElevenLabs.
///
/// Docs: https://docs.fish.audio (POST `https://api.fish.audio/v1/tts`).
/// Auth is `Authorization: Bearer <key>`. The model is a request header
/// (`s2.1-pro` / `s2.1-pro-free`), not a body field.
///
/// Production keeps the key on Lambda (`FISH_AUDIO_API_KEY` env / Secrets).
/// The phone POSTs `/ai/voice/fish-tts` and never receives the key.
/// Dummy / Device Hub may resolve a local key from env, Keychain, or
/// Info.plist — never a hardcoded secret, never committed. Dummy-offline
/// (`dummy-offline://`) does not call the backend. Missing or placeholder
/// keys leave the local path unconfigured.
///
/// This type is network-free. It only resolves config and builds the
/// request so `swift test` can lock the contract without hitting the API.
public enum AriaFishAudioVoice: Sendable {

    public static let endpoint = URL(string: "https://api.fish.audio/v1/tts")!
    public static let backendPath = "ai/voice/fish-tts"
    public static let defaultModel = "s2.1-pro-free"
    public static let paidModel = "s2.1-pro"
    public static let apiKeyEnvironment = "FISH_AUDIO_API_KEY"
    public static let modelEnvironment = "FISH_AUDIO_MODEL"
    public static let referenceEnvironment = "FISH_AUDIO_REFERENCE_ID"
    public static let infoKeyAPIKey = "FISH_AUDIO_API_KEY"
    public static let infoKeyModel = "FISH_AUDIO_MODEL"
    public static let infoKeyReference = "FISH_AUDIO_REFERENCE_ID"
    /// Keychain account. Hex Secrets / Device Hub only — generate_client_config
    /// refuses to ship `FISH_AUDIO` in Info-Add.plist.
    public static let keychainAPIKeyAccount = "forge.voice.fishAudio.apiKey"

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

    public struct BackendSpeech: Equatable, Sendable {
        public var format: String
        public var model: String
        public var audio: Data

        public init(format: String, model: String, audio: Data) {
            self.format = format
            self.model = model
            self.audio = audio
        }
    }

    /// Env wins, then Keychain / Secrets, then Info.plist. Empty and
    /// placeholder values are treated as missing — never a live key.
    public static func resolve(
        environment: [String: String],
        infoDictionary: [String: Any] = [:],
        secureStoreValue: String? = nil
    ) -> Config {
        let key = firstLiveSecret(
            environment[apiKeyEnvironment],
            secureStoreValue,
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

    /// Dummy-offline / empty API URL must never POST Hex.
    public static func isDummyOfflineAPI(_ url: URL) -> Bool {
        (url.scheme ?? "").lowercased() == "dummy-offline"
    }

    public static func isBackendReachable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "dummy-offline" { return false }
        guard scheme == "http" || scheme == "https" else { return false }
        return !(url.host ?? "").isEmpty
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

    /// Hex proxy. No Fish key on the wire — ForgeAPI attaches Cognito later.
    public static func makeBackendRequest(text: String, baseURL: URL) -> URLRequest? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, isBackendReachable(baseURL) else { return nil }
        var request = URLRequest(url: baseURL.appendingPathComponent(backendPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": line], options: [])
        return request
    }

    public static func decodeBackendSpeech(_ data: Data) -> BackendSpeech? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let encoded = json["audio_base64"] as? String, !encoded.isEmpty,
              let audio = Data(base64Encoded: encoded), !audio.isEmpty else {
            return nil
        }
        let format = firstNonEmpty(json["format"] as? String) ?? "mp3"
        return BackendSpeech(format: format, model: sanitizeModel(json["model"] as? String), audio: audio)
    }

    /// Hex invariant: Lambda must not echo `FISH_AUDIO_API_KEY` to the phone.
    public static func payloadLooksLikeAPIKey(_ data: Data, apiKey: String) -> Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let blob = String(data: data, encoding: .utf8) else { return false }
        return blob.contains(trimmed)
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
