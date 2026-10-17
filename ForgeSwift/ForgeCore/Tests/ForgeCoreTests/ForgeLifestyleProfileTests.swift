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
        XCTAssertTrue(sleepAria.contains("seizure"))
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
