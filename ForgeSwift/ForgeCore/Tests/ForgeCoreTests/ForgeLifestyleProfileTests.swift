import XCTest
@testable import ForgeCore

final class ForgeLifestyleProfileTests: XCTestCase {

    func testTwoTwentySixYearOldsDivergeOnHomeAriaTutorialAndOnboarding() {
        let sleep = ForgeLifestylePersonas.seizuresSleepCare
        let social = ForgeLifestylePersonas.socialPartnered

        XCTAssertNotEqual(
            ForgeLifestyleProfile.homeSections(sleep),
            ForgeLifestyleProfile.homeSections(social)
        )
        XCTAssertTrue(sleep.deEmphasizesWorkouts)
        XCTAssertFalse(social.deEmphasizesWorkouts)

        let sleepAria = ForgeLifestyleProfile.ariaEmphasis(sleep).lowercased()
        let socialAria = ForgeLifestyleProfile.ariaEmphasis(social).lowercased()
        XCTAssertTrue(sleepAria.contains("declared a condition") || sleepAria.contains("safety rules"))
        XCTAssertFalse(sleepAria.contains("seizure"))
        XCTAssertFalse(sleepAria.contains("medication"))
        XCTAssertFalse(sleepAria.contains("identity"))
        XCTAssertTrue(socialAria.contains("nights out") || socialAria.contains("drinking") || socialAria.contains("non-judgmental"))

        XCTAssertEqual(ForgeLifestyleProfile.tutorialHighlight(sleep), .sleep)
        XCTAssertNotEqual(
            ForgeLifestyleProfile.tutorialPrompt(beat: .welcome, profile: sleep),
            ForgeLifestyleProfile.tutorialPrompt(beat: .welcome, profile: social)
        )

        XCTAssertTrue(ForgeLifestyleProfile.onboardingBeats(sleep).contains(.relationship))
        XCTAssertTrue(ForgeLifestyleProfile.onboardingBeats(sleep).contains(.healthConstraints) == false)
        XCTAssertTrue(ForgeLifestyleProfile.onboardingBeats(social).isEmpty || !ForgeLifestyleProfile.onboardingBeats(social).contains(.relationship))
    }

    func testEvolveNeverGuessesConditionsFromSignals() {
        var current = ForgeLifestyleProfile.Snapshot()
        current.healthConstraints = [.diabetes]
        let kept = ForgeLifestyleProfile.evolve(
            current: current,
            signals: .init(
                conversation: ["I had a seizure last night"],
                conditions: [.epilepsy]
            )
        )
        XCTAssertEqual(kept.healthConstraints, [.diabetes])

        let blank = ForgeLifestyleProfile.evolve(
            signals: .init(
                conversation: ["epilepsy", "climbing"],
                conditions: [.epilepsy, .seizures]
            )
        )
        XCTAssertTrue(blank.healthConstraints.isEmpty)
        let emphasis = ForgeLifestyleProfile.ariaEmphasis(current).lowercased()
        XCTAssertFalse(emphasis.contains("medication"))
        XCTAssertFalse(emphasis.contains("seizure"))
    }

    func testRedactionAndSkipStayOnDevice() {
        let snap = ForgeLifestylePersonas.seizuresSleepCare
        let payload = ForgeLifestyleProfile.serverContext(snap)
        XCTAssertTrue(ForgeLifestyleProfile.containsSensitiveServerLeak(payload, policy: snap.share) == false)
        XCTAssertNil(payload["health_constraints"])
        XCTAssertNil(payload["relationship"])
        XCTAssertEqual(ForgeLifestyleProfile.ConversationBeat.relationship.skipLabel, "Skip")
    }

    func testHobbyPathWeightsHomeAndSeizuresStaySafer() {
        let sleep = ForgeLifestylePersonas.seizuresSleepCare
        let restore = ForgeLifestyleProfile.homeSections(sleep, hobbyPath: .restoreQuiet)
        XCTAssertEqual(restore[1], .briefing)
        XCTAssertTrue(ForgeLifestyleProfile.activityFraming(sleep).lowercased().contains("doctor"))
        XCTAssertTrue(ForgeLifestyleProfile.activityFraming(sleep).lowercased().contains("predictable"))
    }
}
