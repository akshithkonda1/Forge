import Foundation
import ForgeCore

/// ARIA's speaker identity and the voice-session routing contract.
///
/// Creating a voice here means a locked **speaker**, not a new LLM. The brain
/// is still Forge (`AriaDummyOrchestrator` / `LocalTestingOrchestrator` /
/// `aria_engine`). The mouth is Kokoro-82M on this iPhone:
///
/// * **Every transport** — Dummy, Device Hub, local testing, dummy-offline,
///   and live — speaks with the same on-device Kokoro preset. TTS text never
///   leaves the phone.
/// * **Load failure** — if Kokoro cannot load, the line stays on screen and
///   the failure is logged locally. There is no Apple, Fish, Polly, or
///   ElevenLabs fallback.
///
/// This file must stay network-free (`URLSession` / `URLRequest`). Routing is
/// decided here; playback lives in `AriaPresence`.
enum AriaCharacterVoice: Sendable {
    static let voiceName = "ARIA"

    /// Single Voice Design prompt. Iterate this string only if previews are
    /// wrong — never randomize per device.
    static let designPrompt = """
        American English. Woman, early 30s. Warm low-mid pitch, close-mic, dry, unhurried. Sounds like a sharp coach in the room, not a customer-service agent, GPS, or audiobook narrator. Slight smile, no valley-girl uptalk, no theatrical breathiness.
        """

    /// Preview line for the Settings sample. Spoken content is coaching,
    /// not a demo reel.
    static let designPreviewText = AriaKokoroVoice.previewText

    /// Locked on-device mouth. Byte-for-byte with ``kokoro_voice.py``.
    static let liveTTSModel = AriaKokoroVoice.model
    static let ariaPreset = AriaKokoroVoice.ariaPreset

    /// Production never uses Apple Zoe / Samantha as ARIA.
    static let productionUsesAppleTTS = false

    /// Load failure stays quiet. Do not ask Apple to cover for Kokoro.
    static let liveFailureFallsBackToAppleTTS = false
    static let dummyUpgradesToLiveOnFailure = false
    static let appleEmergencyFallbackEnabled = AriaKokoroVoice.appleEmergencyFallbackEnabled
}

/// Same gates as `AriaService.sendMessage`, in the same order: test-ready dummy
/// first, then local testing, then live. Dummy must win on Device Hub /
/// continue-as-tester / loopback or we break the dummy orchestra the same way
/// chat did when local-testing stole that path.
enum AriaVoiceTransport: String, Equatable, Sendable {
    case dummy
    case localTesting
    case live

    /// Pure so tests can pin Device Hub vs local vs live without spinning audio
    /// or touching `URLSession`.
    static func resolve(
        shouldUseTestReadyDummy: Bool,
        isLocalTesting: Bool
    ) -> AriaVoiceTransport {
        if shouldUseTestReadyDummy { return .dummy }
        if isLocalTesting { return .localTesting }
        return .live
    }

    @MainActor
    static func resolveCurrent() -> AriaVoiceTransport {
        resolve(
            shouldUseTestReadyDummy: AriaService.shouldUseTestReadyDummy,
            isLocalTesting: AriaOperatingMode.current.isLocalTesting
        )
    }

    var usesOnDeviceBrain: Bool {
        self == .dummy || self == .localTesting
    }

    /// Chat / brain may need the network. The mouth never does.
    var requiresNetwork: Bool { self == .live }

    /// A safety session speaks ARIA's own 911 / triage copy on this iPhone
    /// and hears the answer with on-device speech, so chat decides it.
    func keepingOnDevice(_ onDevice: Bool) -> AriaVoiceTransport {
        onDevice && requiresNetwork ? .localTesting : self
    }
}

/// Who is allowed to make sound, and with what renderer.
enum AriaVoiceMouth: Sendable {
    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Dummy / local-testing / live all use Kokoro. Release Dummy-offline
    /// must still try the on-device engine.
    static func allowsDummyFillIn(
        transport: AriaVoiceTransport,
        isDebugBuild: Bool = AriaVoiceMouth.isDebugBuild
    ) -> Bool {
        _ = isDebugBuild
        _ = transport
        return true
    }

    /// Apple TTS is never ARIA's mouth.
    static func shouldEnqueueAppleUtterance(
        isMuted: Bool,
        sessionActive: Bool,
        transport: AriaVoiceTransport?,
        isDebugBuild: Bool = AriaVoiceMouth.isDebugBuild
    ) -> Bool {
        _ = isMuted
        _ = sessionActive
        _ = transport
        _ = isDebugBuild
        return false
    }

    static func spokenLine(from reply: AriaResponse) -> String {
        let prose = reply.proseSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !prose.isEmpty { return prose }
        return reply.message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cloud TTS is gone. Dummy / live / offline all stay on-device.
    static func allowsCloudVoice(
        isDummy: Bool,
        isLocalTesting: Bool,
        offline: Bool
    ) -> Bool {
        _ = isDummy
        _ = isLocalTesting
        _ = offline
        return false
    }

    /// Kokoro is the only enqueue. Mute and an idle session stay silent.
    static func shouldEnqueueKokoro(
        isMuted: Bool,
        sessionActive: Bool
    ) -> Bool {
        !isMuted && sessionActive
    }

    static func currentKokoroConfig(
        selection: AriaVoiceCatalog.Selection = AriaVoiceCatalog.Selection.load()
    ) -> AriaKokoroVoice.Config {
        AriaKokoroVoice.Config(
            voiceID: selection.voiceID
                ?? AriaVoiceCatalog.recipe(id: selection.profileID ?? "warm")?.voiceID
                ?? AriaKokoroVoice.ariaPreset,
            speed: selection.speed
        )
    }
}

/// Local session config. Dummy and loopback short-circuit here.
struct AriaVoiceBootstrap: Equatable, Sendable {
    var transport: AriaVoiceTransport
    /// Retired ConvAI field. Kokoro speak does not use a signed URL.
    var signedURL: String?
    var voiceName: String
    var sampleRate: Int
    var promptContext: String?

    static let dummySampleRate = 16_000

    static func local(transport: AriaVoiceTransport) -> AriaVoiceBootstrap {
        AriaVoiceBootstrap(
            transport: transport,
            signedURL: nil,
            voiceName: AriaCharacterVoice.voiceName,
            sampleRate: dummySampleRate,
            promptContext: nil
        )
    }

    /// True when a live bootstrap leaked a provider key onto the phone.
    static func signedURLLooksLikeAPIKey(_ signedURL: String, apiKey: String) -> Bool {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return false }
        if signedURL == trimmedKey { return true }
        if signedURL.contains(trimmedKey) { return true }
        let lower = signedURL.lowercased()
        return lower.contains("xi-api-key")
    }
}

struct AriaVoiceLiveBootstrap: Equatable, Sendable {
    var signedURL: String
    var conversationID: String?
    var voiceName: String
    var promptContext: String?
    var sampleRate: Int

    enum CodingKeys: String, CodingKey {
        case signedURL = "signed_url"
        case conversationID = "conversation_id"
        case voiceName = "voice_name"
        case promptContext = "prompt_context"
        case sampleRate = "sample_rate"
        case token
    }
}

extension AriaVoiceLiveBootstrap: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let url = try c.decodeIfPresent(String.self, forKey: .signedURL)
            ?? c.decodeIfPresent(String.self, forKey: .token)
            ?? ""
        signedURL = url
        conversationID = try c.decodeIfPresent(String.self, forKey: .conversationID)
        voiceName = try c.decodeIfPresent(String.self, forKey: .voiceName) ?? AriaCharacterVoice.voiceName
        promptContext = try c.decodeIfPresent(String.self, forKey: .promptContext)
        sampleRate = try c.decodeIfPresent(Int.self, forKey: .sampleRate) ?? AriaVoiceBootstrap.dummySampleRate
    }
}
