import XCTest
import ForgeCore
@testable import ForgeSwift

/// Dummy voice session uses the same gates as chat. The mouth is Kokoro only.
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
        // back through chat.
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
        XCTAssertEqual(AriaCharacterVoice.liveTTSModel, AriaKokoroVoice.model)
        XCTAssertEqual(AriaCharacterVoice.ariaPreset, "af_heart")
        XCTAssertEqual(AriaCharacterVoice.liveTTSModel, "kokoro-82m")
    }

    func testKokoroIsTheOnlyMouthAndNeverCloud() {
        XCTAssertFalse(
            AriaVoiceMouth.allowsCloudVoice(isDummy: true, isLocalTesting: false, offline: false)
        )
        XCTAssertFalse(
            AriaVoiceMouth.allowsCloudVoice(isDummy: false, isLocalTesting: true, offline: false)
        )
        XCTAssertFalse(
            AriaVoiceMouth.allowsCloudVoice(isDummy: false, isLocalTesting: false, offline: true)
        )
        XCTAssertFalse(
            AriaVoiceMouth.allowsCloudVoice(isDummy: false, isLocalTesting: false, offline: false),
            "Live also stays on-device — TTS text never leaves the phone"
        )
        XCTAssertTrue(
            AriaVoiceMouth.shouldEnqueueKokoro(isMuted: false, sessionActive: true)
        )
        XCTAssertFalse(
            AriaVoiceMouth.shouldEnqueueKokoro(isMuted: true, sessionActive: true)
        )
        XCTAssertFalse(AriaCharacterVoice.appleEmergencyFallbackEnabled)
        XCTAssertEqual(AriaVoiceMouth.currentKokoroConfig().voiceID, "af_heart")
        let ember = AriaVoiceCatalog.Selection(profileID: "ember", voiceID: "af_bella", speed: 1.05)
        XCTAssertEqual(AriaVoiceMouth.currentKokoroConfig(selection: ember).voiceID, "af_bella")
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
            AriaVoiceMouth.shouldEnqueueKokoro(isMuted: false, sessionActive: false),
            "Onboarding / welcome / Train still call Presence directly; session enqueue stays off"
        )
    }

    func testDummyAndLiveBothUseKokoroNeverApple() {
        XCTAssertTrue(
            AriaVoiceMouth.allowsDummyFillIn(transport: .dummy, isDebugBuild: true)
        )
        XCTAssertTrue(
            AriaVoiceMouth.allowsDummyFillIn(transport: .localTesting, isDebugBuild: true)
        )
        XCTAssertTrue(
            AriaVoiceMouth.allowsDummyFillIn(transport: .live, isDebugBuild: true)
        )
        XCTAssertTrue(
            AriaVoiceMouth.allowsDummyFillIn(transport: .dummy, isDebugBuild: false),
            "TestFlight Dummy-offline must still try Kokoro"
        )
        XCTAssertFalse(
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
            "Load failure must not switch to Apple TTS"
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

    func testSwitchingVoiceProfileChangesNextKokoroPreset() {
        let warm = AriaVoiceCatalog.recipe(id: "warm")!
        let ember = AriaVoiceCatalog.recipe(id: "ember")!
        var selection = AriaVoiceCatalog.Selection()
        selection = AriaVoiceCatalog.apply(selection: selection, to: warm)
        XCTAssertEqual(AriaVoiceMouth.currentKokoroConfig(selection: selection).voiceID, "af_heart")

        selection = AriaVoiceCatalog.apply(selection: selection, to: ember)
        XCTAssertEqual(AriaVoiceMouth.currentKokoroConfig(selection: selection).voiceID, "af_bella")
        XCTAssertNil(
            AriaKokoroVoice.makeSpeakRequest(
                text: "I'm ARIA.",
                baseURL: URL(string: "https://api.forge.test")!
            )
        )
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
