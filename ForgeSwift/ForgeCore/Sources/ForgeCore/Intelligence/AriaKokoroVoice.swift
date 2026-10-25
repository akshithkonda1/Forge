import Foundation

/// Kokoro-82M — ARIA's only mouth.
///
/// Speech is synthesized on this iPhone. TTS text never leaves the device.
/// There is no Fish, Polly, ElevenLabs, or Apple-voice fallback. If the
/// engine cannot load, the line stays on screen and the failure is logged
/// locally.
///
/// Package: `mattmireles/kokoro-coreml` (Apache-2.0), product `KokoroTTS`.
/// Weights: `hexgrad/Kokoro-82M` (Apache-2.0). G2P assets from
/// FluidInference/kokoro-82m-coreml are also Apache-2.0. Ship preset
/// voices only — no cloning, no custom uploads.
///
/// ARIA's locked preset is `af_heart` (Warm). The starter Core ML bundle
/// is about 210 MB (one voice, 15 s bucket). Lazy-load it on first speak
/// from an on-device bundle; do not download Hugging Face at speak time.
/// WatchOS is unsupported. This type is network-free.
public enum AriaKokoroVoice: Sendable {

    public static let provider = "kokoro"
    public static let model = "kokoro-82m"
    public static let packageURL = "https://github.com/mattmireles/kokoro-coreml"
    public static let packageProduct = "KokoroTTS"
    public static let weightsRepo = "hexgrad/Kokoro-82M"
    public static let license = "Apache-2.0"
    public static let ariaPreset = "af_heart"
    public static let catalogPath = "ai/voice"
    /// Retired. Hex no longer synthesizes speech.
    public static let retiredSpeakPath = "ai/voice/speak"
    public static let previewText =
        "I'm ARIA. Let's look at how you actually slept and what that means for training today. One next move, not a new identity."
    public static let loadFailedMessage = "Voice could not load. The text reply is shown."
    public static let starterBundleMegabytes = 210
    public static let shipsPresetVoicesOnly = true
    public static let allowsNetworkAtSpeakTime = false
    public static let allowsCloudTTS = false
    public static let appleEmergencyFallbackEnabled = false

    public static let allowedPresets: Set<String> = [
        "af_heart", "af_bella", "af_sarah", "af_aoede", "am_michael",
    ]

    public struct Config: Equatable, Sendable {
        public var voiceID: String
        public var speed: Double

        public init(voiceID: String = AriaKokoroVoice.ariaPreset, speed: Double = 1.0) {
            self.voiceID = AriaKokoroVoice.sanitizePreset(voiceID)
            self.speed = speed
        }
    }

    public static func sanitizePreset(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if allowedPresets.contains(trimmed) { return trimmed }
        return ariaPreset
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

    /// There is no cloud speak request. Always nil so tests can pin isolation.
    public static func makeSpeakRequest(text: String, baseURL: URL) -> URLRequest? {
        _ = text
        _ = baseURL
        return nil
    }

    public static func makeCatalogRequest(baseURL: URL, query: String = "") -> URLRequest? {
        guard let url = AriaVoiceCatalog.catalogURL(baseURL: baseURL, query: query) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }

    public static func makePersistRequest(baseURL: URL, selection: AriaVoiceCatalog.Selection) -> URLRequest? {
        guard isBackendReachable(baseURL) else { return nil }
        var request = URLRequest(url: baseURL.appendingPathComponent(AriaVoiceCatalog.path))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: AriaVoiceCatalog.persistBody(selection),
            options: []
        )
        return request
    }

    public static func looksLikeCloudTTSHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower.contains("fish.audio")
            || lower.contains("elevenlabs.io")
            || lower.contains("polly")
            || lower.contains("amazonaws.com")
    }
}
