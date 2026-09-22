import XCTest
@testable import ForgeCore

final class PromptGuardTests: XCTestCase {
    func testSameSpeakMatches() {
        XCTAssertTrue(
            PromptGuard.consistent(
                firstMessage: "You slept enough.",
                secondMessage: "you  slept enough."
            )
        )
    }

    func testDifferentSpeakFails() {
        XCTAssertFalse(
            PromptGuard.consistent(
                firstMessage: "Go train.",
                secondMessage: "Rest today.",
                firstRecommendation: "Lift",
                secondRecommendation: "Lift"
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
