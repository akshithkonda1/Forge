import AVFoundation
import XCTest
@testable import ForgeSwift

/// Locks ARIA's spoken voice: neural, one utterance, never compact Samantha
/// when a better English voice exists, never Siri, never the language-constructor
/// fallback that silently becomes Hawking-style formant TTS.
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

    func testEloquenceIsRejectedAsRobotic() {
        let reed = AriaSpokenVoice.Candidate(
            identifier: "com.apple.eloquence.en-US.Reed",
            name: "Reed",
            language: "en-US",
            quality: .standard,
            gender: .male
        )
        XCTAssertTrue(AriaSpokenVoice.isNovelty(reed))
        XCTAssertNil(AriaSpokenVoice.pick(from: [reed]))
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
        XCTAssertTrue(AriaSpokenVoice.isNeural(zoe))
        XCTAssertTrue(AriaSpokenVoice.isCompactFormant(samantha))
        XCTAssertFalse(AriaSpokenVoice.isCompactFormant(zoe))
    }

    func testEnhancedAvaBeatsCompactSamanthaEvenWhenSamanthaIsListedFirst() {
        let ava = AriaSpokenVoice.Candidate(
            identifier: "com.apple.voice.enhanced.en-US.Ava",
            name: "Ava",
            language: "en-US",
            quality: .enhanced,
            gender: .female
        )
        let samantha = AriaSpokenVoice.Candidate(
            identifier: "com.apple.voice.compact.en-US.Samantha",
            name: "Samantha",
            language: "en-US",
            quality: .standard,
            gender: .female
        )
        XCTAssertEqual(AriaSpokenVoice.pick(from: [samantha, ava])?.identifier, ava.identifier)
    }

    func testNeuralPoolIgnoresCompactWhenAnyEnhancedExists() {
        let compactNicky = AriaSpokenVoice.Candidate(
            identifier: "com.apple.voice.compact.en-US.Nicky",
            name: "Nicky",
            language: "en-US",
            quality: .standard,
            gender: .female
        )
        let enhancedAva = AriaSpokenVoice.Candidate(
            identifier: "com.apple.voice.enhanced.en-US.Ava",
            name: "Ava",
            language: "en-US",
            quality: .enhanced,
            gender: .female
        )
        XCTAssertEqual(
            AriaSpokenVoice.pick(from: [compactNicky, enhancedAva])?.identifier,
            enhancedAva.identifier
        )
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

    func testSamanthaSubstitutionIsRejected() {
        let zoe = "com.apple.voice.premium.en-US.Zoe"
        let samantha = "com.apple.voice.compact.en-US.Samantha"
        XCTAssertFalse(
            AriaSpokenVoice.shouldSpeak(
                requestedId: zoe,
                catalogIds: [samantha],
                resolvedId: samantha
            ),
            "Unknown neural ids must not be treated as installed Samantha"
        )
        XCTAssertFalse(
            AriaSpokenVoice.shouldSpeak(
                requestedId: zoe,
                catalogIds: [zoe],
                resolvedId: samantha
            ),
            "iOS substituting Samantha for a neural id must be rejected"
        )
        XCTAssertTrue(
            AriaSpokenVoice.shouldSpeak(
                requestedId: zoe,
                catalogIds: [zoe],
                resolvedId: zoe
            )
        )
    }

    func testLanguageConstructorFallbackIsDisabled() {
        XCTAssertFalse(AriaSpokenVoice.allowsLanguageConstructorFallback)
        XCTAssertNil(
            AriaSpokenVoice.preferredVoice(from: []),
            "Empty catalog must be silence, not compact Samantha from Voice(language:)"
        )
    }

    func testPreferredVoiceStaysInsideTheCatalogAndAvoidsSiri() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        guard let preferred = AriaSpokenVoice.preferredVoice(from: voices) else { return }
        XCTAssertTrue(
            voices.contains { $0.identifier == preferred.identifier },
            "Spoken voice must be an identifier-matched catalog entry, not a language fallback"
        )
        XCTAssertFalse(preferred.identifier.localizedCaseInsensitiveContains("siri"))
        XCTAssertFalse(preferred.name.localizedCaseInsensitiveContains("siri"))
    }

    func testSpeechRateMatchesNaturalConversation() {
        XCTAssertEqual(AriaSpokenVoice.rate, AVSpeechUtteranceDefaultSpeechRate, accuracy: 0.001)
        XCTAssertEqual(AriaSpokenVoice.pitch, 1.0, accuracy: 0.001)
        XCTAssertEqual(AriaSpokenVoice.volume, 1.0, accuracy: 0.001)
        XCTAssertEqual(AriaSpokenVoice.betweenPhraseDelay, 0)
        XCTAssertEqual(AriaSpokenVoice.firstPhraseDelay, 0)
        XCTAssertEqual(AriaSpokenVoice.phraseTailDelay, 0)
    }

    func testSpeechIsOneContinuousLineNotHawkingPackets() {
        let parts = AriaSpeechPrep.phrases(
            in: "Alright — Barbell Bench Press. Pin the shoulder blades. Watch for flared elbows."
        )
        XCTAssertEqual(parts.count, 1, "Multiple utterances reset intonation like DECtalk")
        XCTAssertTrue(parts[0].contains("Barbell Bench Press"))
        XCTAssertTrue(parts[0].contains("Pin the shoulder blades"))
        XCTAssertFalse(parts[0].contains("—"))
        XCTAssertNil(AriaSpeechPrep.phrases(in: "   ").first)
        XCTAssertEqual(AriaSpeechPrep.phrases(in: ""), [])
        XCTAssertEqual(AriaSpeechPrep.spokenLine(in: "   "), nil)
    }

    func testDecimalsStayIntactInTheSpokenLine() {
        let line = AriaSpeechPrep.spokenLine(in: "Rest 2.5 minutes then go.")
        XCTAssertEqual(line, "Rest 2.5 minutes then go.")
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

    func testHowToScriptStaysConversationalNamedAndOneUtterance() throws {
        let bench = try XCTUnwrap(ExerciseLibrary.match("Barbell Bench Press"))
        let script = ExerciseLibrary.howToScript(for: bench)
        XCTAssertTrue(script.contains("Barbell Bench Press"))
        XCTAssertTrue(script.hasPrefix("Alright"))
        XCTAssertFalse(script.contains("Here's how to do"))
        XCTAssertTrue(script.contains("Pin the shoulder blades"))
        XCTAssertTrue(script.contains("Watch for"))
        let parts = AriaSpeechPrep.phrases(in: script)
        XCTAssertEqual(parts.count, 1, "How-to must be one neural utterance, not chopped cues")
        let utts = AriaSpeechPrep.utterances(from: script, voiceOver: false)
        XCTAssertEqual(utts.count, 1)
        XCTAssertEqual(utts[0].rate, AVSpeechUtteranceDefaultSpeechRate, accuracy: 0.02)
        XCTAssertEqual(utts[0].pitchMultiplier, 1.0, accuracy: 0.01)
        XCTAssertEqual(utts[0].volume, 1.0, accuracy: 0.01)
        XCTAssertEqual(utts[0].preUtteranceDelay, 0, accuracy: 0.001)
        XCTAssertEqual(utts[0].postUtteranceDelay, 0, accuracy: 0.001)
        XCTAssertTrue(utts[0].speechString.contains("Barbell Bench Press"))
        XCTAssertTrue(utts[0].speechString.contains("Pin the shoulder blades"))
    }
}
