import Foundation

/// ARIA's speaker identity and the voice-session routing contract.
///
/// Creating a voice here means a locked **speaker**, not a new LLM. The brain
/// is still Forge (`AriaDummyOrchestrator` / `LocalTestingOrchestrator` /
/// `aria_engine`). The mouth is:
///
/// * **Dummy / Device Hub / loopback** — session UX is real; spoken audio is a
///   DEBUG-only local fill-in so testers can hear that a mouth ran. Not compact
///   Samantha, not a second product voice, and **never** ElevenLabs.
/// * **Local testing** — same session UX, on-device brain, DEBUG fill-in.
/// * **Live** — ElevenLabs ConvAI with the designed `voice_id` named ARIA.
///   Apple catalog TTS is never the production mouth. Live failure is silence.
///
/// This file must stay network-free (`URLSession` / `URLRequest` / ElevenLabs
/// hosts). Routing is decided here; live I/O lives in `AriaVoiceSession`.
enum AriaCharacterVoice: Sendable {
    static let voiceName = "ARIA"

    /// Single Voice Design prompt. Iterate this string only if previews are
    /// wrong — never randomize per device.
    static let designPrompt = """
        American English. Woman, early 30s. Warm low-mid pitch, close-mic, dry, unhurried. Sounds like a sharp coach in the room, not a customer-service agent, GPS, or audiobook narrator. Slight smile, no valley-girl uptalk, no theatrical breathiness.
        """

    /// Preview line ElevenLabs requires when auto-text is off. Spoken content
    /// is coaching, not a demo reel.
    static let designPreviewText = """
        I'm ARIA. Let's look at how you actually slept and what that means for training today. One next move, not a new identity.
        """

    /// Locked live-mouth stack. Byte-for-byte with ``elevenlabs_voice.py``.
    /// Dummy never uses these; live ConvAI does.
    static let liveTTSModel = "eleven_v3_conversational"
    static let liveASRProvider = "scribe_realtime"
    static let liveTurnModel = "turn_v3"
    static let liveVoiceDesignModel = "eleven_ttv_v3"
    static let liveConvAILLM = "claude-sonnet-4-6"

    /// Production never uses Apple Zoe / Samantha as ARIA.
    static let productionUsesAppleTTS = false

    /// Live stream failure stays quiet. Dummy never silently "upgrades" to cloud.
    static let liveFailureFallsBackToAppleTTS = false
    static let dummyUpgradesToLiveOnFailure = false
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

    var requiresNetwork: Bool { self == .live }
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

    /// DEBUG dummy/local fill-in only. Release builds, and live, stay silent
    /// unless ConvAI is actually streaming.
    static func allowsDummyFillIn(
        transport: AriaVoiceTransport,
        isDebugBuild: Bool = AriaVoiceMouth.isDebugBuild
    ) -> Bool {
        guard isDebugBuild else { return false }
        return transport.usesOnDeviceBrain
    }

    static func shouldEnqueueAppleUtterance(
        isMuted: Bool,
        sessionActive: Bool,
        transport: AriaVoiceTransport?,
        isDebugBuild: Bool = AriaVoiceMouth.isDebugBuild
    ) -> Bool {
        guard !isMuted, sessionActive, let transport else { return false }
        return allowsDummyFillIn(transport: transport, isDebugBuild: isDebugBuild)
    }

    static func spokenLine(from reply: AriaResponse) -> String {
        let prose = reply.proseSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !prose.isEmpty { return prose }
        return reply.message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Local session config. Dummy and loopback short-circuit here — never call
/// `GET /ai/voice/bootstrap`. Live builds fetch a short-lived ConvAI URL.
struct AriaVoiceBootstrap: Equatable, Sendable {
    var transport: AriaVoiceTransport
    /// ConvAI signed WebSocket URL. Never the ElevenLabs API key.
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

    /// True when a live bootstrap leaked the provider key onto the phone.
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
