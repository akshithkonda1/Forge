import XCTest
@testable import ForgeCore

/// These assertions hold on the exact/prefix/fuzzy paths alone — none of them
/// depend on what `NLTagger` happens to lemmatize a given word to, so they
/// pass identically on every platform, including the non-Darwin fallback
/// tokenizer. That's deliberate: lemmatization is a bonus signal this engine
/// takes when the platform offers it, never something a caller can rely on.
final class ContextualParsingEngineTests: XCTestCase {

    // MARK: - The bug this engine exists to fix

    func testRestDoesNotFireInsideRestaurant() {
        XCTAssertFalse(ContextualParsingEngine.containsWord("let's pick a restaurant for dinner", "rest"))
    }

    func testNapDoesNotFireInsideNapkin() {
        XCTAssertFalse(ContextualParsingEngine.containsWord("grab a napkin please", "nap"))
    }

    func testSexDoesNotFireInsideExercise() {
        XCTAssertFalse(ContextualParsingEngine.containsWord("what exercise should I do", "sex"))
    }

    func testWholeWordStillMatches() {
        XCTAssertTrue(ContextualParsingEngine.containsWord("I need to rest today", "rest"))
        XCTAssertTrue(ContextualParsingEngine.containsWord("time for a nap", "nap"))
    }

    // MARK: - Ordinary inflections must not regress

    func testCommonSuffixesStillMatch() {
        XCTAssertTrue(ContextualParsingEngine.containsWord("my knee hurts today", "hurt"))
        XCTAssertTrue(ContextualParsingEngine.containsWord("still eating breakfast", "eat"))
        XCTAssertFalse(ContextualParsingEngine.containsWord("I ate already", "eat"), "\"ate\" isn't \"eat\" + a suffix")
    }

    func testDeliberateStemKeywordsStillCatchEveryInflection() {
        for word in ["hydrate", "hydrating", "hydration"] {
            XCTAssertTrue(ContextualParsingEngine.containsWord("remember to \(word)", "hydrat"), word)
        }
        for word in ["ovulate", "ovulating", "ovulation"] {
            XCTAssertTrue(ContextualParsingEngine.containsWord("tracking \(word)", "ovulat"), word)
        }
    }

    func testStemLeftoverMustLookLikeARealInflection() {
        // "ing"/"ion" are real inflections (allowed); a leftover that isn't
        // a plausible ending is exactly the "nap"/"napkin" shape of false
        // positive, so it stays blocked even past the stem.
        XCTAssertTrue(ContextualParsingEngine.containsWord("hydrated meals only", "hydrat"))
        XCTAssertFalse(ContextualParsingEngine.containsWord("ovulatory cycle tracking", "ovulat"))
    }

    // MARK: - Typo tolerance

    func testOneLetterTypoStillMatches() {
        XCTAssertTrue(ContextualParsingEngine.containsWord("I feel so tird today", "tired"))
        XCTAssertTrue(ContextualParsingEngine.containsWord("how did I sleeep", "sleep"))
    }

    func testShortWordsRequireAnExactMatch() {
        // Below the fuzzy floor: any "typo" at this length is usually just a
        // different real word, so no fuzzy tolerance is applied.
        XCTAssertFalse(ContextualParsingEngine.containsWord("let's go run a test", "rest"))
    }

    func testTypoTooFarAwayDoesNotMatch() {
        XCTAssertFalse(ContextualParsingEngine.containsWord("completely unrelated word", "tired"))
    }

    // MARK: - Phrase matching

    func testMultiWordPhraseMatchesWithBoundaries() {
        XCTAssertTrue(ContextualParsingEngine.containsPhrase("what should i eat for lunch", "what should"))
        XCTAssertFalse(ContextualParsingEngine.containsPhrase("somewhat shouldering the load", "what should"))
    }

    func testShortAcronymNeedsNoManualPadding() {
        // The real needle lists used to pad entries like this as " pr " to
        // fake a word boundary, which missed "pr" at the very start or end
        // of a message. Plain "pr" now works correctly in every position.
        XCTAssertTrue(ContextualParsingEngine.containsPhrase("what's my pr?", "pr"))
        XCTAssertTrue(ContextualParsingEngine.containsPhrase("pr day today", "pr"))
        XCTAssertFalse(ContextualParsingEngine.containsPhrase("this is private", "pr"))
    }

    func testMatchesDispatchesByNeedleShape() {
        XCTAssertTrue(ContextualParsingEngine.matches("time to rest", "rest"))
        XCTAssertTrue(ContextualParsingEngine.matches("what should i train today", "what should"))
        XCTAssertFalse(ContextualParsingEngine.matches("restaurant night", "rest"))
    }

    func testMatchesAnyShortCircuitsOnFirstHit() {
        let needles = ["recover", "recovery", "tired", "exhausted"]
        XCTAssertTrue(ContextualParsingEngine.matchesAny("so tired after that session", needles))
        XCTAssertFalse(ContextualParsingEngine.matchesAny("great restaurant last night", needles))
    }

    // MARK: - Clause splitting for multi-intent messages

    func testSplitsOnCommaWithNoOtherConnective() {
        // This was the gap: no dash, semicolon, or "and"/"then"/"also" to
        // split on before commas were added to the normalization step.
        let parts = ContextualParsingEngine.splitClauses("I slept badly, want to hit the gym")
        XCTAssertEqual(parts, ["I slept badly", "want to hit the gym"])
    }

    func testSplitsOnConnectivesAndDashes() {
        XCTAssertEqual(
            ContextualParsingEngine.splitClauses("what should I train and eat"),
            ["what should I train", "eat"]
        )
        XCTAssertEqual(
            ContextualParsingEngine.splitClauses("I slept badly — what should I train"),
            ["I slept badly", "what should I train"]
        )
    }

    func testSingleClauseTextIsNotSplit() {
        XCTAssertEqual(ContextualParsingEngine.splitClauses("how did I sleep last night"), ["how did I sleep last night"])
    }

    func testEmptyTextSplitsToNothing() {
        XCTAssertEqual(ContextualParsingEngine.splitClauses("   "), [])
    }
}
