import XCTest
import ForgeCore

final class AriaFishAudioVoiceTests: XCTestCase {

    func testMissingKeyLeavesFishUnconfigured() {
        let empty = AriaFishAudioVoice.resolve(environment: [:], infoDictionary: [:])
        XCTAssertFalse(empty.isConfigured)
        XCTAssertEqual(empty.model, AriaFishAudioVoice.defaultModel)
        XCTAssertEqual(AriaFishAudioVoice.defaultModel, "s2.1-pro-free")
        XCTAssertNil(AriaFishAudioVoice.makeRequest(text: "Hey — I'm ARIA.", config: empty))
    }

    func testPlaceholderAndWhitespaceKeysAreRejected() {
        let placeholders = ["", "   ", "<token>", "YOUR_API_KEY", "changeme", "todo-key", "redacted"]
        for value in placeholders {
            let config = AriaFishAudioVoice.resolve(
                environment: [AriaFishAudioVoice.apiKeyEnvironment: value]
            )
            XCTAssertFalse(config.isConfigured, value)
            XCTAssertTrue(AriaFishAudioVoice.looksLikePlaceholder(value) || value.trimmingCharacters(in: .whitespaces).isEmpty, value)
        }
    }

    func testEnvironmentWinsOverInfoDictionary() {
        let config = AriaFishAudioVoice.resolve(
            environment: [
                AriaFishAudioVoice.apiKeyEnvironment: " env-key ",
                AriaFishAudioVoice.modelEnvironment: AriaFishAudioVoice.paidModel,
            ],
            infoDictionary: [
                AriaFishAudioVoice.infoKeyAPIKey: "plist-key",
                AriaFishAudioVoice.infoKeyModel: "s2.1-pro-free",
            ]
        )
        XCTAssertTrue(config.isConfigured)
        XCTAssertEqual(config.apiKey, "env-key")
        XCTAssertEqual(config.model, "s2.1-pro")
        XCTAssertFalse(config.apiKey.contains("plist"))
    }

    func testInfoDictionaryFillsWhenEnvIsEmpty() {
        let config = AriaFishAudioVoice.resolve(
            environment: [:],
            infoDictionary: [
                AriaFishAudioVoice.infoKeyAPIKey: "plist-live-key",
                AriaFishAudioVoice.infoKeyModel: "s2.1-pro-free",
                AriaFishAudioVoice.infoKeyReference: "voice-ref",
            ]
        )
        XCTAssertEqual(config.apiKey, "plist-live-key")
        XCTAssertEqual(config.model, "s2.1-pro-free")
        XCTAssertEqual(config.referenceID, "voice-ref")
    }

    func testSecureStoreWinsOverInfoDictionaryAndLosesToEnv() {
        let fromStore = AriaFishAudioVoice.resolve(
            environment: [:],
            infoDictionary: [AriaFishAudioVoice.infoKeyAPIKey: "plist-key"],
            secureStoreValue: " keychain-key "
        )
        XCTAssertEqual(fromStore.apiKey, "keychain-key")
        let fromEnv = AriaFishAudioVoice.resolve(
            environment: [AriaFishAudioVoice.apiKeyEnvironment: "env-key"],
            infoDictionary: [AriaFishAudioVoice.infoKeyAPIKey: "plist-key"],
            secureStoreValue: "keychain-key"
        )
        XCTAssertEqual(fromEnv.apiKey, "env-key")
        let placeholderStore = AriaFishAudioVoice.resolve(
            environment: [:],
            secureStoreValue: "YOUR_API_KEY"
        )
        XCTAssertFalse(placeholderStore.isConfigured)
        XCTAssertEqual(AriaFishAudioVoice.keychainAPIKeyAccount, "forge.voice.fishAudio.apiKey")
    }

    func testDummyOfflineNeverBuildsABackendRequest() {
        XCTAssertTrue(AriaFishAudioVoice.isDummyOfflineAPI(ForgeAuthConfig.dummyOfflineAPI))
        XCTAssertFalse(AriaFishAudioVoice.isBackendReachable(ForgeAuthConfig.dummyOfflineAPI))
        XCTAssertNil(
            AriaFishAudioVoice.makeBackendRequest(
                text: "I'm ARIA.",
                baseURL: ForgeAuthConfig.dummyOfflineAPI
            )
        )
        let live = URL(string: "https://api.forge.test")!
        XCTAssertTrue(AriaFishAudioVoice.isBackendReachable(live))
        let request = AriaFishAudioVoice.makeBackendRequest(text: "  I'm ARIA.  ", baseURL: live)
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url, live.appendingPathComponent(AriaFishAudioVoice.backendPath))
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request?.value(forHTTPHeaderField: "model"))
        let body = try? JSONSerialization.jsonObject(with: request?.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(body?["text"] as? String, "I'm ARIA.")
        XCTAssertNil(
            AriaFishAudioVoice.makeBackendRequest(text: "   ", baseURL: live)
        )
    }

    func testBackendSpeechDecodesAudioAndNeverTreatsTheKeyAsAudio() {
        let audio = Data([0xFF, 0xFB, 0x90, 0x00])
        let payload: [String: Any] = [
            "format": "mp3",
            "model": "s2.1-pro-free",
            "audio_base64": audio.base64EncodedString(),
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let speech = AriaFishAudioVoice.decodeBackendSpeech(data)
        XCTAssertEqual(speech?.format, "mp3")
        XCTAssertEqual(speech?.model, "s2.1-pro-free")
        XCTAssertEqual(speech?.audio, audio)
        XCTAssertFalse(
            AriaFishAudioVoice.payloadLooksLikeAPIKey(data, apiKey: "sk_live_never_on_phone")
        )
        let leak = #"{"audio_base64":"sk_live_never_on_phone"}"#.data(using: .utf8)!
        XCTAssertTrue(
            AriaFishAudioVoice.payloadLooksLikeAPIKey(leak, apiKey: "sk_live_never_on_phone")
        )
        XCTAssertNil(AriaFishAudioVoice.decodeBackendSpeech(Data("{}".utf8)))
    }

    func testUnknownModelFallsBackToFreeTier() {
        XCTAssertEqual(AriaFishAudioVoice.sanitizeModel("not-a-model"), "s2.1-pro-free")
        XCTAssertEqual(AriaFishAudioVoice.sanitizeModel(nil), "s2.1-pro-free")
        XCTAssertEqual(AriaFishAudioVoice.sanitizeModel("s2.1-pro"), "s2.1-pro")
        XCTAssertEqual(AriaFishAudioVoice.sanitizeModel("s2.1-pro-free"), "s2.1-pro-free")
    }

    func testRequestUsesBearerAndModelHeaderWithoutEmbeddingAHardcodedSecret() {
        let config = AriaFishAudioVoice.Config(
            apiKey: "test-key-not-for-commit",
            model: "s2.1-pro-free",
            referenceID: "aria-ref"
        )
        let request = AriaFishAudioVoice.makeRequest(text: "  I'm ARIA.  ", config: config)
        XCTAssertEqual(request?.url, AriaFishAudioVoice.endpoint)
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key-not-for-commit")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "model"), "s2.1-pro-free")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try? JSONSerialization.jsonObject(with: request?.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(body?["text"] as? String, "I'm ARIA.")
        XCTAssertEqual(body?["format"] as? String, "mp3")
        XCTAssertEqual(body?["reference_id"] as? String, "aria-ref")
        XCTAssertFalse((request?.url?.absoluteString ?? "").contains("test-key"))
    }

    func testBlankTextDoesNotBuildARequest() {
        let config = AriaFishAudioVoice.Config(apiKey: "test-key-not-for-commit", model: "s2.1-pro")
        XCTAssertNil(AriaFishAudioVoice.makeRequest(text: "   ", config: config))
    }
}
