import XCTest
@testable import ForgeCore

final class PromptGuardTests: XCTestCase {
    func testWordingMayMoveWhenFactsHold() {
        XCTAssertTrue(
            PromptGuard.consistent(
                firstRecommendation: "Wind down earlier.",
                secondRecommendation: "Wind down earlier.",
                firstResponseType: "insight",
                secondResponseType: "insight"
            )
        )
    }

    func testDifferentRecommendationFailsDeterminism() {
        XCTAssertFalse(
            PromptGuard.consistent(
                firstRecommendation: "Lift",
                secondRecommendation: "Rest today."
            )
        )
        XCTAssertEqual(
            PromptGuard.determinismScore(
                firstRecommendation: "Lift",
                secondRecommendation: "Rest today."
            ),
            0
        )
    }

    func testHonestyFloorIsSeventy() {
        XCTAssertEqual(PromptGuard.floor, 70)
        XCTAssertTrue(PromptGuard.honest(confidence: 0.82))
        XCTAssertTrue(PromptGuard.honest(confidence: 0.4))
        XCTAssertFalse(PromptGuard.honest(confidence: 0.9, honesty: 40))
        XCTAssertTrue(PromptGuard.honest(confidence: 0.3, honesty: 100))
    }

    func testPassesRequiresHonestyAndDeterminism() {
        XCTAssertTrue(
            PromptGuard.passes(
                firstRecommendation: "Easy day",
                secondRecommendation: "Easy day",
                firstConfidence: 0.85,
                secondConfidence: 0.84
            )
        )
        XCTAssertFalse(
            PromptGuard.passes(
                firstRecommendation: "Lift",
                secondRecommendation: "Rest",
                firstConfidence: 0.9,
                secondConfidence: 0.9
            )
        )
        XCTAssertFalse(
            PromptGuard.passes(
                firstRecommendation: "Easy day",
                secondRecommendation: "Easy day",
                firstHonesty: 40,
                secondHonesty: 40
            )
        )
    }

    func testPublicLineIsAConnectionFailure() {
        XCTAssertEqual(
            PromptGuard.connectionFailureMessage,
            "Couldn't reach Forge. Check your connection."
        )
        XCTAssertEqual(PromptGuard.connectionFailureCode, "connection_failed")
    }
}
