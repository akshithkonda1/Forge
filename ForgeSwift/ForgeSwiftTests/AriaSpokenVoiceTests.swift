import XCTest
@testable import ForgeSwift

/// Locks ARIA's spoken voice so she cannot fall back to a Siri-bundle
/// identifier, and so Train mute actually gates speech.
final class AriaSpokenVoiceTests: XCTestCase {

    func testSiriIdentifiersAreRejected() {
        let siri = AriaSpokenVoice.Candidate(
            identifier: "com.apple.ttsbundle.siri_female_en-US_premium",
            name: "Siri",
            language: "en-US",
            quality: .premium,
            gender: .female
        )
        XCTAssertTrue(AriaSpokenVoice.isSiri(siri))
        XCTAssertNil(AriaSpokenVoice.pick(from: [siri]))
    }

    func testNoveltyVoicesAreRejected() {
        let bells = AriaSpokenVoice.Candidate(
            identifier: "com.apple.voice.compact.en-US.BadNews",
            name: "Bad News",
            language: "en-US",
            quality: .standard,
            gender: .unspecified
        )
        XCTAssertTrue(AriaSpokenVoice.isNovelty(bells))
        XCTAssertNil(AriaSpokenVoice.pick(from: [bells]))
    }

    func testPremiumZoeBeatsCompactSamantha() {
        let zoe = AriaSpokenVoice.Candidate(
            identifier: "com.apple.voice.premium.en-US.Zoe",
            name: "Zoe",
            language: "en-US",
            quality: .premium,
            gender: .female
        )
        let samantha = AriaSpokenVoice.Candidate(
            identifier: "com.apple.voice.compact.en-US.Samantha",
            name: "Samantha",
            language: "en-US",
            quality: .standard,
            gender: .female
        )
        let picked = AriaSpokenVoice.pick(from: [samantha, zoe])
        XCTAssertEqual(picked?.identifier, zoe.identifier)
        XCTAssertFalse(picked!.identifier.localizedCaseInsensitiveContains("siri"))
        XCTAssertGreaterThan(AriaSpokenVoice.score(zoe), AriaSpokenVoice.score(samantha))
    }

    func testPickNeverReturnsASiriVoiceEvenWhenSiriIsPremium() {
        let siri = AriaSpokenVoice.Candidate(
            identifier: "com.apple.voice.compact.en-US.siri",
            name: "Nicky (Siri)",
            language: "en-US",
            quality: .premium,
            gender: .female
        )
        let ava = AriaSpokenVoice.Candidate(
            identifier: "com.apple.voice.enhanced.en-US.Ava",
            name: "Ava",
            language: "en-US",
            quality: .enhanced,
            gender: .female
        )
        let picked = AriaSpokenVoice.pick(from: [siri, ava])
        XCTAssertEqual(picked?.name, "Ava")
        XCTAssertFalse((picked?.identifier ?? "").localizedCaseInsensitiveContains("siri"))
    }

    func testSpeechRateIsUnhurriedNotSiriClip() {
        XCTAssertLessThan(AriaSpokenVoice.rate, 0.52)
        XCTAssertGreaterThan(AriaSpokenVoice.rate, 0.40)
        XCTAssertGreaterThan(AriaSpokenVoice.pitch, 0.99)
        XCTAssertLessThan(AriaSpokenVoice.volume, 1.0)
        XCTAssertGreaterThan(AriaSpokenVoice.betweenPhraseDelay, AriaSpokenVoice.firstPhraseDelay)
    }

    func testPhrasesSplitOnSentencesAndEmDashes() {
        let parts = AriaSpeechPrep.phrases(in: "Alright — Barbell Bench Press. Pin the shoulder blades. Watch for flared elbows.")
        XCTAssertGreaterThanOrEqual(parts.count, 2)
        XCTAssertTrue(parts.contains { $0.contains("Barbell Bench Press") })
        XCTAssertTrue(parts.contains { $0.contains("Pin the shoulder blades") })
        XCTAssertNil(AriaSpeechPrep.phrases(in: "   ").first)
        XCTAssertEqual(AriaSpeechPrep.phrases(in: ""), [])
    }

    func testDecimalsDoNotSplitPhrases() {
        let parts = AriaSpeechPrep.phrases(in: "Rest 2.5 minutes then go.")
        XCTAssertTrue(parts.contains { $0.contains("2.5") })
    }

    func testTrainMuteGateRoundTrips() {
        let original = AriaTrainVoice.isEnabled
        defer { AriaTrainVoice.isEnabled = original }
        AriaTrainVoice.isEnabled = false
        XCTAssertFalse(AriaTrainVoice.isEnabled)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AriaTrainVoice.mutedKey))
        AriaTrainVoice.isEnabled = true
        XCTAssertTrue(AriaTrainVoice.isEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AriaTrainVoice.mutedKey))
    }

    func testHowToScriptStaysConversationalAndNamed() throws {
        let bench = try XCTUnwrap(ExerciseLibrary.match("Barbell Bench Press"))
        let script = ExerciseLibrary.howToScript(for: bench)
        XCTAssertTrue(script.contains("Barbell Bench Press"))
        XCTAssertTrue(script.hasPrefix("Alright"))
        XCTAssertFalse(script.contains("Here's how to do"))
        XCTAssertTrue(script.contains("Pin the shoulder blades"))
        XCTAssertTrue(script.contains("Watch for"))
        let parts = AriaSpeechPrep.phrases(in: script)
        XCTAssertGreaterThan(parts.count, 1, "ARIA should breathe between cues, not dump one Siri blob")
    }
}
