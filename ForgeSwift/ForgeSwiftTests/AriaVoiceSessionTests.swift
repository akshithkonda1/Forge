import XCTest
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
        XCTAssertEqual(AriaCharacterVoice.liveTTSModel, "eleven_v3_conversational")
        XCTAssertEqual(AriaCharacterVoice.liveASRProvider, "scribe_realtime")
        XCTAssertEqual(AriaCharacterVoice.liveTurnModel, "turn_v3")
        XCTAssertEqual(AriaCharacterVoice.liveVoiceDesignModel, "eleven_ttv_v3")
        XCTAssertEqual(AriaCharacterVoice.liveConvAILLM, "claude-sonnet-4-6")
        XCTAssertFalse(AriaCharacterVoice.liveTTSModel.contains("turbo"))
        XCTAssertFalse(AriaCharacterVoice.liveASRProvider == "elevenlabs")
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

    func testDummyFillInIsDebugOnlyAndNeverLive() {
        XCTAssertTrue(
            AriaVoiceMouth.allowsDummyFillIn(transport: .dummy, isDebugBuild: true)
        )
        XCTAssertTrue(
            AriaVoiceMouth.allowsDummyFillIn(transport: .localTesting, isDebugBuild: true)
        )
        XCTAssertFalse(
            AriaVoiceMouth.allowsDummyFillIn(transport: .live, isDebugBuild: true)
        )
        XCTAssertFalse(
            AriaVoiceMouth.allowsDummyFillIn(transport: .dummy, isDebugBuild: false),
            "Release dummy still has session UX, not a second product voice"
        )
        XCTAssertTrue(
            AriaVoiceMouth.shouldEnqueueAppleUtterance(
                isMuted: false,
                sessionActive: true,
                transport: .dummy,
                isDebugBuild: true
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
