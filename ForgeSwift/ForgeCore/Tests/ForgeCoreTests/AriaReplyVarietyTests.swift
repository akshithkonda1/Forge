import XCTest
@testable import ForgeCore

final class AriaReplyVarietyTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "forge.aria.variety.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testCopyPasteNormalizesToTheSamePrompt() {
        let typed = "what's my quality of life"
        let pasted = "What’s my  quality of life\n"
        let nbsp = "what's\u{00a0}my quality of life"
        XCTAssertEqual(
            AriaReplyVariety.normalizePrompt(typed),
            AriaReplyVariety.normalizePrompt(pasted)
        )
        XCTAssertEqual(
            AriaReplyVariety.normalizePrompt(typed),
            AriaReplyVariety.normalizePrompt(nbsp)
        )
    }

    func testSamePromptTwiceYieldsUniqueGroundedReplies() {
        let prompt = "what's my quality of life"
        let score = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(steps: 8_000))
        QualityOfLifeLivingStore.publish(score, persona: .balanced, defaults: defaults)

        AriaReplyVariety.beginTurn(prompt: prompt, defaults: defaults)
        let first = AriaReplyVariety.distinct(
            prompt: prompt,
            draft: QualityOfLifeLivingStore.coachingLine(
                defaults: defaults,
                variety: AriaReplyVariety.occurrence(for: prompt, defaults: defaults)
            ),
            defaults: defaults
        )
        AriaReplyVariety.beginTurn(prompt: prompt, defaults: defaults)
        let second = AriaReplyVariety.distinct(
            prompt: prompt,
            draft: QualityOfLifeLivingStore.coachingLine(
                defaults: defaults,
                variety: AriaReplyVariety.occurrence(for: prompt, defaults: defaults)
            ),
            defaults: defaults
        )

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.contains("\(score.overall)/100"))
        XCTAssertTrue(second.contains("\(score.overall)/100"))
        XCTAssertTrue(AriaPromptCorrelation.correlates(reply: first, toPrompt: prompt))
        XCTAssertTrue(AriaPromptCorrelation.correlates(reply: second, toPrompt: prompt))
    }

    func testIdenticalDraftIsRewrittenOnTheSecondPaste() {
        let prompt = "what should I train today"
        let canned = "Upper body, keep it honest, skip the hero session."
        AriaReplyVariety.beginTurn(prompt: prompt, defaults: defaults)
        let first = AriaReplyVariety.distinct(prompt: prompt, draft: canned, defaults: defaults)
        AriaReplyVariety.beginTurn(prompt: prompt, defaults: defaults)
        let second = AriaReplyVariety.distinct(prompt: prompt, draft: canned, defaults: defaults)
        XCTAssertEqual(first, canned)
        XCTAssertNotEqual(second, first)
        XCTAssertTrue(AriaPromptCorrelation.correlates(reply: second, toPrompt: prompt))
        XCTAssertTrue(second.lowercased().contains("train") || second.lowercased().contains("session"))
    }

    func testPickRotatesAcrossPastes() {
        let prompt = "what should I eat"
        let bank = ["Keep food simple.", "Protein first.", "Eat what you'll finish."]
        AriaReplyVariety.beginTurn(prompt: prompt, defaults: defaults)
        let a = AriaReplyVariety.pick(bank, prompt: prompt, defaults: defaults)
        AriaReplyVariety.beginTurn(prompt: prompt, defaults: defaults)
        let b = AriaReplyVariety.pick(bank, prompt: prompt, defaults: defaults)
        XCTAssertNotEqual(a, b)
    }

    func testSaltChangesWhenTheSamePromptIsPastedAgain() {
        let prompt = "what tuxedo should I wear"
        XCTAssertNotEqual(
            AriaReplyVariety.salt(prompt: prompt, occurrence: 1),
            AriaReplyVariety.salt(prompt: prompt, occurrence: 2)
        )
        XCTAssertEqual(
            AriaReplyVariety.salt(prompt: prompt, occurrence: 1, extra: 9),
            AriaReplyVariety.salt(prompt: prompt, occurrence: 1, extra: 9)
        )
    }
}
