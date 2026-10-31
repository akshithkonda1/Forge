import Foundation

/// Kokoro-82M — ARIA's only mouth.
///
/// Speech is synthesized on this iPhone. TTS text never leaves the device.
/// There is no Fish, Polly, ElevenLabs, or Apple-voice fallback. If the
/// engine cannot load, the line stays on screen and the failure is logged
/// locally.
///
/// Package: `mattmireles/kokoro-coreml` v2.0 (Apache-2.0), product `KokoroTTS`.
/// Pin is the `v2.0` tag. Weights: `hexgrad/Kokoro-82M` (Apache-2.0).
/// G2P is MisakiSwift (Apache-2.0) with no eSpeak fallback. Ship preset
/// voices only — no cloning, no custom uploads.
///
/// ARIA's locked preset is `af_heart` (Warm). The starter Core ML bundle
/// is about 210 MB (one voice, 15 s bucket). Deliver it through an
/// Apple-hosted Background Asset pack, a bundled copy, or one consented
/// first-launch download into Application Support. Hugging Face is never
/// contacted at speak time. WatchOS is unsupported. This type is network-free.
public enum AriaKokoroVoice: Sendable {

    public static let provider = "kokoro"
    public static let model = "kokoro-82m"
    public static let packageURL = "https://github.com/mattmireles/kokoro-coreml"
    public static let packageProduct = "KokoroTTS"
    /// Tagged release. Exact git object of `refs/tags/v2.0`.
    public static let packageVersion = "2.0"
    public static let packageRevision = "e4242c94c0dc5be62258cc3cf15c86c37382c3d5"
    public static let weightsRepo = "hexgrad/Kokoro-82M"
    public static let hostedModelRepo = "mattmireles/kokoro-coreml"
    /// Immutable Hugging Face commit of the schema-2 starter bundle.
    public static let hostedRevision = "034f7741bf938fd6b4b9c75c22bc72cd795f908a"
    /// SHA-256 of `HostedManifest.json` at ``hostedRevision``.
    public static let hostedManifestSHA256 =
        "f3abd5811585b8c89f1c15e647409311731b4262da4315242c69f88675bced9d"
    public static let license = "Apache-2.0"
    public static let g2p = "MisakiSwift"
    public static let ariaPreset = "af_heart"
    public static let catalogPath = "ai/voice"
    /// Retired. Hex no longer synthesizes speech.
    public static let retiredSpeakPath = "ai/voice/speak"
    public static let previewText =
        "I'm ARIA. Let's look at how you actually slept and what that means for training today. One next move, not a new identity."
    public static let loadFailedMessage = "Voice could not load. The text reply is shown."
    public static let starterBundleMegabytes = 210
    public static let starterBundleBytes = 218_081_866
    public static let shipsPresetVoicesOnly = true
    public static let allowsNetworkAtSpeakTime = false
    public static let allowsCloudTTS = false
    public static let appleEmergencyFallbackEnabled = false
    public static let usesEspeak = false
    public static let usesOnDemandResources = false

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
