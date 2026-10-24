import XCTest
import ForgeCore

final class AriaKokoroVoiceTests: XCTestCase {

    func testARIAPresetIsAfHeartAndApacheLicensed() {
        XCTAssertEqual(AriaKokoroVoice.ariaPreset, "af_heart")
        XCTAssertEqual(AriaKokoroVoice.model, "kokoro-82m")
        XCTAssertEqual(AriaKokoroVoice.provider, "kokoro")
        XCTAssertEqual(AriaKokoroVoice.license, "Apache-2.0")
        XCTAssertEqual(AriaKokoroVoice.weightsRepo, "hexgrad/Kokoro-82M")
        XCTAssertTrue(AriaKokoroVoice.packageURL.contains("kokoro-coreml"))
        XCTAssertEqual(AriaKokoroVoice.packageProduct, "KokoroTTS")
        XCTAssertTrue(AriaKokoroVoice.shipsPresetVoicesOnly)
        XCTAssertFalse(AriaKokoroVoice.allowsNetworkAtSpeakTime)
        XCTAssertFalse(AriaKokoroVoice.allowsCloudTTS)
        XCTAssertFalse(AriaKokoroVoice.appleEmergencyFallbackEnabled)
        XCTAssertEqual(AriaKokoroVoice.starterBundleMegabytes, 210)
        XCTAssertTrue(AriaKokoroVoice.allowedPresets.contains("af_heart"))
        XCTAssertFalse(AriaKokoroVoice.allowedPresets.contains("s2.1-pro-free"))
    }

    func testUnknownPresetFallsBackToARIA() {
        XCTAssertEqual(AriaKokoroVoice.sanitizePreset("af_bella"), "af_bella")
        XCTAssertEqual(AriaKokoroVoice.sanitizePreset("not-a-voice"), "af_heart")
        XCTAssertEqual(AriaKokoroVoice.sanitizePreset(nil), "af_heart")
        XCTAssertEqual(AriaKokoroVoice.sanitizePreset("s2.1-pro"), "af_heart")
    }

    func testSpeakRequestIsAlwaysNilEvenWhenBackendLooksLive() {
        let live = URL(string: "https://api.forge.test")!
        XCTAssertTrue(AriaKokoroVoice.isBackendReachable(live))
        XCTAssertNil(AriaKokoroVoice.makeSpeakRequest(text: "I'm ARIA.", baseURL: live))
        XCTAssertNil(
            AriaKokoroVoice.makeSpeakRequest(
                text: "I'm ARIA.",
                baseURL: ForgeAuthConfig.dummyOfflineAPI
            )
        )
        XCTAssertEqual(AriaKokoroVoice.retiredSpeakPath, "ai/voice/speak")
    }

    func testDummyOfflineNeverBuildsACatalogOrPersistRequest() {
        XCTAssertTrue(AriaKokoroVoice.isDummyOfflineAPI(ForgeAuthConfig.dummyOfflineAPI))
        XCTAssertFalse(AriaKokoroVoice.isBackendReachable(ForgeAuthConfig.dummyOfflineAPI))
        XCTAssertNil(AriaKokoroVoice.makeCatalogRequest(baseURL: ForgeAuthConfig.dummyOfflineAPI))
        XCTAssertNil(
            AriaKokoroVoice.makePersistRequest(
                baseURL: ForgeAuthConfig.dummyOfflineAPI,
                selection: AriaVoiceCatalog.Selection(profileID: "warm")
            )
        )
    }

    func testCatalogPersistIsSelectionOnlyNeverASpeakBody() {
        let live = URL(string: "https://api.forge.test")!
        let request = AriaKokoroVoice.makePersistRequest(
            baseURL: live,
            selection: AriaVoiceCatalog.Selection(profileID: "ember", voiceID: "af_bella", speed: 1.05)
        )
        XCTAssertEqual(request?.httpMethod, "PUT")
        XCTAssertEqual(request?.url, live.appendingPathComponent(AriaVoiceCatalog.path))
        XCTAssertFalse((request?.url?.path ?? "").contains("speak"))
        let body = try? JSONSerialization.jsonObject(with: request?.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(body?["voice_id"] as? String, "af_bella")
        XCTAssertNil(body?["text"])
        XCTAssertNil(body?["audio_base64"])
    }

    func testCloudTTSHostsAreRefused() {
        XCTAssertTrue(AriaKokoroVoice.looksLikeCloudTTSHost("api.fish.audio"))
        XCTAssertTrue(AriaKokoroVoice.looksLikeCloudTTSHost("api.elevenlabs.io"))
        XCTAssertTrue(AriaKokoroVoice.looksLikeCloudTTSHost("polly.us-east-1.amazonaws.com"))
        XCTAssertFalse(AriaKokoroVoice.looksLikeCloudTTSHost("api.forge.test"))
    }
}
