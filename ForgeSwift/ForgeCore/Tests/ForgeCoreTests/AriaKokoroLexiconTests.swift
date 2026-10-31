import XCTest
import ForgeCore

final class AriaKokoroLexiconTests: XCTestCase {

    func testExpandsCoachingAcronyms() {
        XCTAssertEqual(
            AriaKokoroLexicon.expand("Your HRV dropped, and VO2 max held."),
            "Your H R V dropped, and V O 2 max held."
        )
        XCTAssertEqual(
            AriaKokoroLexicon.expand("SpO₂ 96, RHR 54 bpm."),
            "spot O 2 96, resting heart rate 54 beats per minute."
        )
        XCTAssertTrue(AriaKokoroLexicon.expand("RMSSD is the better read.").contains("R M S S D"))
    }

    func testSentenceSplitKeepsShortRepliesIntact() {
        XCTAssertEqual(
            AriaKokoroLexicon.spokenSegments(in: "Sleep was short."),
            ["Sleep was short."]
        )
    }

    func testLongReplyIsChunkedIntoSentences() {
        let text = "Sleep was short. Train easy today. One next move, not a new identity."
        let parts = AriaKokoroLexicon.spokenSegments(in: text)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0], "Sleep was short.")
        XCTAssertEqual(parts[1], "Train easy today.")
        XCTAssertTrue(parts[2].contains("next move"))
    }

    func testOversizedSentenceIsSplitFurther() {
        let long = String(repeating: "recovery ", count: 40) + "now."
        let parts = AriaKokoroLexicon.spokenSegments(in: long, maxCharacters: 40)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 40 })
    }
}
