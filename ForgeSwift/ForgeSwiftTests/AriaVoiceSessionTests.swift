import XCTest
import ForgeCore
@testable import ForgeSwift

/// Dummy voice session uses the same gates as chat. Live bootstrap is never
/// the ElevenLabs API key. Apple TTS is not ARIA's production mouth.
final class AriaVoiceSessionTests: XCTestCase {

    func testDummyWinsOverLocalTestingTheSameWayChatDoes() {
        XCTAssertEqual(
            AriaVoiceTransport.resolve(shouldUseTestReadyDummy: true, isLocalTesting: true),
            .dummy,
            "Device Hub / tester / loopback must not fall through to local testing"
        )
    }

    func testLocalTestingIsSecondGate() {
        XCTAssertEqual(
            AriaVoiceTransport.resolve(shouldUseTestReadyDummy: false, isLocalTesting: true),
            .localTesting
        )
    }

    func testSafetySessionNeverUsesTheLiveAgent() {
        // The 911 / triage copy is spoken on this iPhone and the answer comes
        // back through chat; ConvAI would put its own words on an emergency.
        XCTAssertEqual(AriaVoiceTransport.live.keepingOnDevice(true), .localTesting)
        XCTAssertEqual(AriaVoiceTransport.dummy.keepingOnDevice(true), .dummy)
        XCTAssertEqual(AriaVoiceTransport.localTesting.keepingOnDevice(true), .localTesting)
        XCTAssertEqual(AriaVoiceTransport.live.keepingOnDevice(false), .live)
        XCTAssertTrue(AriaVoiceTransport.live.keepingOnDevice(true).usesOnDeviceBrain)
    }

    func testLiveIsOnlyWhenNeitherDummyNorLocal() {
        XCTAssertEqual(
            AriaVoiceTransport.resolve(shouldUseTestReadyDummy: false, isLocalTesting: false),
            .live
        )
        XCTAssertFalse(AriaVoiceTransport.dummy.requiresNetwork)
        XCTAssertFalse(AriaVoiceTransport.localTesting.requiresNetwork)
        XCTAssertTrue(AriaVoiceTransport.live.requiresNetwork)
        XCTAssertTrue(AriaVoiceTransport.dummy.usesOnDeviceBrain)
        XCTAssertFalse(AriaCharacterVoice.dummyUpgradesToLiveOnFailure)
        XCTAssertEqual(AriaCharacterVoice.liveTTSModel, AriaFishAudioVoice.defaultModel)
        XCTAssertEqual(AriaCharacterVoice.livePaidTTSModel, AriaFishAudioVoice.paidModel)
        XCTAssertEqual(AriaCharacterVoice.liveTTSModel, "s2.1-pro-free")
        XCTAssertFalse(AriaCharacterVoice.liveTTSModel.contains("s1"))
        XCTAssertFalse(AriaCharacterVoice.dummyUpgradesToFishAudioOnFailure)
    }

    func testFishAudioMouthRequiresAConfiguredKey() {
        XCTAssertFalse(
            AriaVoiceMouth.allowsCloudVoice(isDummy: true, isLocalTesting: false, offline: false)
        )
        XCTAssertFalse(
            AriaVoiceMouth.allowsCloudVoice(isDummy: false, isLocalTesting: true, offline: false)
        )
        XCTAssertFalse(
            AriaVoiceMouth.allowsCloudVoice(isDummy: false, isLocalTesting: false, offline: true)
        )
        XCTAssertTrue(
            AriaVoiceMouth.allowsCloudVoice(isDummy: false, isLocalTesting: false, offline: false)
        )
        XCTAssertFalse(
            AriaVoiceMouth.shouldEnqueueFishAudio(
                isMuted: false,
                hasKey: true,
                allowsCloudVoice: true
            ),
            "Production never sends a local Fish key"
        )
        XCTAssertFalse(
            AriaVoiceMouth.shouldEnqueueFishAudioViaBackend(
                isMuted: false,
                hasLocalKey: false,
                backendReachable: true,
                allowsCloudVoice: false
            ),
            "Dummy / offline must not POST Hex"
        )
        XCTAssertTrue(
            AriaVoiceMouth.shouldEnqueueFishAudioViaBackend(
                isMuted: false,
                hasLocalKey: false,
                backendReachable: true,
                allowsCloudVoice: true
            )
        )
        XCTAssertFalse(AriaCharacterVoice.elevenLabsProviderEnabled)
        let store = InMemorySecureStore()
        let missing = AriaVoiceMouth.currentFishAudioConfig(
            environment: [:],
            infoDictionary: [:],
            secureStore: store
        )
        XCTAssertFalse(missing.isConfigured)
        try? store.set("test-key-not-for-commit", forKey: AriaFishAudioVoice.keychainAPIKeyAccount)
        let fromKeychain = AriaVoiceMouth.currentFishAudioConfig(
            environment: [:],
            infoDictionary: [:],
            secureStore: store
        )
        XCTAssertTrue(fromKeychain.isConfigured)
        XCTAssertEqual(fromKeychain.apiKey, "test-key-not-for-commit")
        let live = AriaVoiceMouth.currentFishAudioConfig(
            environment: [AriaFishAudioVoice.apiKeyEnvironment: "env-key-not-for-commit"],
            infoDictionary: [:],
            secureStore: store
        )
        XCTAssertEqual(live.apiKey, "env-key-not-for-commit")
        XCTAssertEqual(live.model, AriaFishAudioVoice.defaultModel)
    }

    func testMuteGatesDummyAndLiveFillIn() {
        XCTAssertFalse(
            AriaVoiceMouth.shouldEnqueueAppleUtterance(
                isMuted: true,
                sessionActive: true,
                transport: .dummy,
                isDebugBuild: true
            )
        )
        XCTAssertFalse(
            AriaVoiceMouth.shouldEnqueueAppleUtterance(
                isMuted: true,
                sessionActive: true,
                transport: .live,
                isDebugBuild: true
            )
        )
        XCTAssertFalse(
            AriaVoiceMouth.shouldEnqueueAppleUtterance(
                isMuted: false,
                sessionActive: false,
                transport: .dummy,
                isDebugBuild: true
            ),
            "Onboarding / welcome / Train are not a character session"
        )
    }

    func testDummyFillInRunsInReleaseAndNeverOnLive() {
        XCTAssertTrue(
            AriaVoiceMouth.allowsDummyFillIn(transport: .dummy, isDebugBuild: true)
        )
        XCTAssertTrue(
            AriaVoiceMouth.allowsDummyFillIn(transport: .localTesting, isDebugBuild: true)
        )
        XCTAssertFalse(
            AriaVoiceMouth.allowsDummyFillIn(transport: .live, isDebugBuild: true)
        )
        XCTAssertTrue(
            AriaVoiceMouth.allowsDummyFillIn(transport: .dummy, isDebugBuild: false),
            "TestFlight Dummy-offline has no ConvAI — the fill-in mouth must run"
        )
        XCTAssertTrue(
            AriaVoiceMouth.allowsDummyFillIn(transport: .localTesting, isDebugBuild: false),
            "On-device brain still fills in outside DEBUG"
        )
        XCTAssertTrue(
            AriaVoiceMouth.shouldEnqueueAppleUtterance(
                isMuted: false,
                sessionActive: true,
                transport: .dummy,
                isDebugBuild: false
            )
        )
        XCTAssertFalse(
            AriaVoiceMouth.shouldEnqueueAppleUtterance(
                isMuted: false,
                sessionActive: true,
                transport: .live,
                isDebugBuild: true
            ),
            "Live failure / live success both refuse Apple TTS as the mouth"
        )
    }

    func testNewVoiceSessionUnmutesSoTheMouthCanRun() {
        XCTAssertTrue(
            AriaSpokenMute.shouldUnmuteForNewSession(isResumingExistingSession: false),
            "Orb / Voice mode is the ask — default mute must not keep her silent"
        )
        XCTAssertFalse(
            AriaSpokenMute.shouldUnmuteForNewSession(isResumingExistingSession: true),
            "A mid-session mute stays until they unmute"
        )
        let originalMuted = AriaSpokenMute.isMuted
        defer { AriaSpokenMute.isMuted = originalMuted }
        AriaSpokenMute.isMuted = true
        AriaSpokenMute.unmuteBecauseVoiceSessionStarted()
        XCTAssertFalse(AriaSpokenMute.isMuted)
        XCTAssertTrue(AriaSpokenMute.allowsSpeech)
    }

    func testProductionMouthIsNotAppleTTS() {
        XCTAssertFalse(AriaCharacterVoice.productionUsesAppleTTS)
        XCTAssertFalse(AriaCharacterVoice.liveFailureFallsBackToAppleTTS)
        XCTAssertEqual(AriaCharacterVoice.voiceName, "ARIA")
        XCTAssertTrue(AriaCharacterVoice.designPrompt.contains("early 30s"))
        XCTAssertTrue(AriaCharacterVoice.designPrompt.contains("sharp coach"))
        XCTAssertFalse(AriaCharacterVoice.designPrompt.lowercased().contains("tiffany"))
        XCTAssertFalse(AriaCharacterVoice.designPrompt.lowercased().contains("samantha"))
        XCTAssertFalse(AriaCharacterVoice.designPrompt.lowercased().contains("zoe"))
    }

    func testLocalBootstrapNeverCarriesASignedURLOrKey() {
        let dummy = AriaVoiceBootstrap.local(transport: .dummy)
        XCTAssertNil(dummy.signedURL)
        XCTAssertEqual(dummy.voiceName, "ARIA")
        XCTAssertEqual(dummy.transport, .dummy)
        XCTAssertTrue(
            AriaVoiceBootstrap.signedURLLooksLikeAPIKey(
                "sk_super_secret",
                apiKey: "sk_super_secret"
            )
        )
        XCTAssertTrue(
            AriaVoiceBootstrap.signedURLLooksLikeAPIKey(
                "wss://api.elevenlabs.io/v1/convai/conversation?xi-api-key=nope",
                apiKey: "other"
            )
        )
        XCTAssertFalse(
            AriaVoiceBootstrap.signedURLLooksLikeAPIKey(
                "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=agent_1&conversation_signature=short",
                apiKey: "sk_super_secret"
            )
        )
    }

    func testSwitchingVoiceProfileChangesNextSpeakVoiceID() {
        let warm = AriaVoiceCatalog.Profile(
            id: "warm",
            label: "Warm",
            description: "Close",
            voiceID: "voice-warm-1"
        )
        let ember = AriaVoiceCatalog.Profile(
            id: "ember",
            label: "Ember",
            description: "Blunt",
            speed: 1.05,
            voiceID: "voice-ember-1"
        )
        var selection = AriaVoiceCatalog.Selection()
        selection = AriaVoiceCatalog.apply(selection: selection, to: warm)
        let first = AriaFishAudioVoice.makeBackendRequest(
            text: "I'm ARIA.",
            baseURL: URL(string: "https://api.forge.test")!,
            selection: selection
        )
        let firstBody = try? JSONSerialization.jsonObject(with: first?.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(firstBody?["voice_id"] as? String, "voice-warm-1")

        selection = AriaVoiceCatalog.apply(selection: selection, to: ember)
        let next = AriaFishAudioVoice.makeBackendRequest(
            text: "I'm ARIA.",
            baseURL: URL(string: "https://api.forge.test")!,
            selection: selection
        )
        let nextBody = try? JSONSerialization.jsonObject(with: next?.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(nextBody?["voice_id"] as? String, "voice-ember-1")
        XCTAssertNotEqual(firstBody?["voice_id"] as? String, nextBody?["voice_id"] as? String)
    }

    func testSpokenLinePrefersProseSummary() {
        let reply = AriaResponse(
            proseSummary: "Sleep was short. Train easy.",
            message: "Longer card copy the orb must not read."
        )
        XCTAssertEqual(
            AriaVoiceMouth.spokenLine(from: reply),
            "Sleep was short. Train easy."
        )
        let fallback = AriaResponse(message: "Just the chat line.")
        XCTAssertEqual(AriaVoiceMouth.spokenLine(from: fallback), "Just the chat line.")
    }

    func testLiveBootstrapDecoderAcceptsSignedURLAndRejectsEmpty() throws {
        let json = """
        {"signed_url":"wss://api.elevenlabs.io/v1/convai/conversation?conversation_signature=tok","voice_name":"ARIA","sample_rate":16000}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AriaVoiceLiveBootstrap.self, from: json)
        XCTAssertTrue(decoded.signedURL.hasPrefix("wss://"))
        XCTAssertEqual(decoded.voiceName, "ARIA")
        XCTAssertFalse(
            AriaVoiceBootstrap.signedURLLooksLikeAPIKey(
                decoded.signedURL,
                apiKey: "sk_live_never_on_device"
            )
        )
    }

    func testLiveMicFramesEncodeAsUserAudioChunkNotAMissingMember() {
        let pcm = Data([0x01, 0x00, 0x02, 0x00])
        let text = ConvAIMicChunkCodec.websocketText(fromPCM: pcm)
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("user_audio_chunk") == true)
        XCTAssertTrue(text?.contains(pcm.base64EncodedString()) == true)
        XCTAssertFalse(
            text?.contains("sendBase64Chunk") == true,
            "Live mic frames must be user_audio_chunk JSON, not a missing sendBase64Chunk member"
        )
    }
}
