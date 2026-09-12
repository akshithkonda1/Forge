import XCTest
@testable import ForgeCore

final class AriaPromptCorrelationTests: XCTestCase {

    func testQualityOfLifeAskIsLifestyleNotTraining() {
        let asked = AriaPromptCorrelation.askedDomains(in: "what's my quality of life")
        XCTAssertEqual(asked, [.lifestyle])
        XCTAssertEqual(
            AriaPromptCorrelation.filterDomains([.training, .sleep, .lifestyle], toPrompt: "what's my quality of life"),
            [.lifestyle]
        )
    }

    func testTrainingAskStaysTraining() {
        let asked = AriaPromptCorrelation.askedDomains(in: "what should I train today")
        XCTAssertTrue(asked.contains(.training))
        XCTAssertFalse(asked.contains(.lifestyle) && asked.count == 1)
        XCTAssertEqual(
            AriaPromptCorrelation.filterDomains([.training, .lifestyle], toPrompt: "what should I train today"),
            [.training]
        )
    }

    func testMultiIntentKeepsSleepTrainEat() {
        let prompt = "I slept badly — what should I train and eat?"
        let asked = AriaPromptCorrelation.askedDomains(in: prompt)
        XCTAssertTrue(asked.contains(.sleep))
        XCTAssertTrue(asked.contains(.training))
        XCTAssertTrue(asked.contains(.nutrition), "eat in the prompt must keep nutrition even when sleep+train score higher: \(asked)")
    }

    func testTuxedoAskIsLifestyleNotASession() {
        let prompt = "what tuxedo should I wear to a wedding"
        let asked = AriaPromptCorrelation.askedDomains(in: prompt)
        XCTAssertTrue(asked.contains(.lifestyle))
        XCTAssertFalse(asked.contains(.training))
        XCTAssertTrue(AriaPromptCorrelation.correlates(reply: "A classic tux or dark suit for the wedding.", toPrompt: prompt))
        XCTAssertFalse(AriaPromptCorrelation.correlates(reply: "Squats, 4x8, then a long run.", toPrompt: prompt))
    }

    func testVaguePromptKeepsASingleLeadingDomain() {
        XCTAssertEqual(
            AriaPromptCorrelation.filterDomains([.training, .sleep, .nutrition], toPrompt: "hey"),
            [.lifestyle]
        )
    }

    func testSpokenQoLAbbreviationAnswersQualityOfLifePrompt() {
        XCTAssertTrue(
            AriaPromptCorrelation.correlates(
                reply: "Lifestyle QoL is 71/100 (steady). That's the same grade Life shows.",
                toPrompt: "what's my quality of life"
            )
        )
        XCTAssertTrue(
            AriaPromptCorrelation.correlates(
                reply: "Upper body train day, keep it honest, skip the hero session.",
                toPrompt: "what should I train today"
            )
        )
    }

    func testGroundedQoLUsesTheLivingSnapshotLine() {
        let suite = "forge.qol.corr.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let score = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(steps: 7_500))
        QualityOfLifeLivingStore.publish(score, persona: .balanced, defaults: defaults)
        // grounded() reads the process defaults; coachingLine with suite is the contract.
        let line = QualityOfLifeLivingStore.coachingLine(defaults: defaults)
        XCTAssertTrue(line.contains("\(score.overall)/100"))
        XCTAssertTrue(AriaPromptCorrelation.correlates(reply: line, toPrompt: "how's my QoL"))
        defaults.removePersistentDomain(forName: suite)
    }

    func testLifeStoryStaysOffSpecificAsks() {
        XCTAssertFalse(AriaPromptCorrelation.allowsUnpromptedLifeStory("what should I train today"))
        XCTAssertTrue(AriaPromptCorrelation.allowsUnpromptedLifeStory("hey"))
    }
}
