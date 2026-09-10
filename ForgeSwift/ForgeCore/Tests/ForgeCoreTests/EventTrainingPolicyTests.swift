import XCTest
@testable import ForgeCore

final class EventTrainingPolicyTests: XCTestCase {

    func testWeddingInTwoWeeksIsProgressiveSuitWork() {
        let plan = EventTrainingPolicy.plan(fromTags: ["calendar:horizon:wedding:14"])
        XCTAssertEqual(plan?.kind, "wedding")
        XCTAssertEqual(plan?.daysUntil, 14)
        XCTAssertEqual(plan?.emphasis, ["chest", "arms", "abs"])
        XCTAssertEqual(plan?.progressive, true)
        XCTAssertEqual(plan?.reduceVolume, true)
        XCTAssertEqual(plan?.keepLight, false)
        XCTAssertTrue(plan?.reason.localizedCaseInsensitiveContains("suit") == true)
    }

    func testWeddingDayProtectsTheEvent() {
        let plan = EventTrainingPolicy.weddingPlan(daysUntil: 0)
        XCTAssertTrue(plan.keepLight)
        XCTAssertTrue(plan.emphasis.isEmpty)
        XCTAssertTrue(plan.reason.localizedCaseInsensitiveContains("protect"))
    }

    func testSpokenWeddingMatchesHorizonShape() {
        XCTAssertEqual(SpokenEventParser.daysUntilWedding(in: "wedding in 2 weeks"), 14)
        let spoken = EventTrainingPolicy.weddingPlan(daysUntil: 14)
        let tagged = EventTrainingPolicy.plan(fromTags: ["calendar:horizon:wedding:14"])
        XCTAssertEqual(spoken.emphasis, tagged?.emphasis)
        XCTAssertEqual(spoken.progressive, tagged?.progressive)
    }
}
