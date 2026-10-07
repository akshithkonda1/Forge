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
