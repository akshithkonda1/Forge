import XCTest
import ForgeCore

final class AriaVoiceEngineRegistryTests: XCTestCase {

    override func tearDown() {
        AriaVoiceEngineRegistry.shared.resetForTests()
        super.tearDown()
    }

    func testSecondEngineSwitchAndRemoveFallsBackToKokoro() async {
        let registry = AriaVoiceEngineRegistry()
        let kokoro = FakeVoiceEngine(id: AriaVoiceEngineID.kokoro)
        let other = FakeVoiceEngine(id: "other-on-device")
        registry.register(kokoro)
        registry.register(other)
        XCTAssertEqual(
            Set(registry.registeredIDs),
            Set([AriaVoiceEngineID.kokoro, "other-on-device"])
        )
        XCTAssertEqual(registry.selectedEngineID, AriaVoiceEngineSelection.defaultID)

        registry.select("other-on-device")
        let switched = await registry.speak(
            "Hello from ARIA.",
            voiceID: AriaKokoroVoice.ariaPreset,
            speed: 1.0
        )
        XCTAssertTrue(switched)
        XCTAssertEqual(other.speakCount, 1)
        XCTAssertEqual(kokoro.speakCount, 0)
        XCTAssertEqual(other.lastText, "Hello from ARIA.")

        registry.unregister("other-on-device")
        XCTAssertEqual(registry.selectedEngineID, AriaVoiceEngineID.kokoro)
        XCTAssertNil(registry.engine(for: "other-on-device"))

        let afterRemove = await registry.speak(
            "Back on Kokoro.",
            voiceID: AriaKokoroVoice.ariaPreset,
            speed: 1.0
        )
        XCTAssertTrue(afterRemove)
        XCTAssertEqual(other.speakCount, 1, "removed engine must not keep speaking")
        XCTAssertEqual(kokoro.speakCount, 1)
        XCTAssertEqual(kokoro.lastText, "Back on Kokoro.")
    }

    func testMissingOrFailedEngineDoesNotFallBackToAnotherVoice() async {
        let registry = AriaVoiceEngineRegistry()
        let kokoro = FakeVoiceEngine(id: AriaVoiceEngineID.kokoro)
        let other = FakeVoiceEngine(id: "other-on-device")
        other.succeeds = false
        registry.register(kokoro)
        registry.register(other)

        registry.select("other-on-device")
        let failed = await registry.speak(
            "Hello from ARIA.",
            voiceID: AriaKokoroVoice.ariaPreset,
            speed: 1.0
        )
        XCTAssertFalse(failed)
        XCTAssertEqual(other.speakCount, 1)
        XCTAssertEqual(kokoro.speakCount, 0, "a failed engine must not hand off")

        registry.select("not-registered")
        let missing = await registry.speak(
            "Hello from ARIA.",
            voiceID: AriaKokoroVoice.ariaPreset,
            speed: 1.0
        )
        XCTAssertFalse(missing)
        XCTAssertEqual(kokoro.speakCount, 0)
        XCTAssertEqual(other.speakCount, 1)
        XCTAssertEqual(
            AriaKokoroVoice.loadFailedMessage,
            "Voice could not load. The text reply is shown."
        )
    }

    func testSanitizeEmptySelectionIsKokoro() {
        XCTAssertEqual(AriaVoiceEngineSelection.sanitize(nil), AriaVoiceEngineID.kokoro)
        XCTAssertEqual(AriaVoiceEngineSelection.sanitize("  "), AriaVoiceEngineID.kokoro)
        XCTAssertEqual(AriaVoiceEngineSelection.sanitize("other-on-device"), "other-on-device")
        XCTAssertEqual(AriaVoiceEngineSelection.defaultID, AriaVoiceEngineID.kokoro)
    }
}

private final class FakeVoiceEngine: AriaVoiceEngine {
    let id: String
    var succeeds = true
    var speakCount = 0
    var lastText: String?

    init(id: String) {
        self.id = id
    }

    func speak(_ text: String, voiceID: String, speed: Double) async -> Bool {
        _ = voiceID
        _ = speed
        speakCount += 1
        lastText = text
        return succeeds
    }

    func stop() {}
}
