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

    func testTripAndGameHorizonsShapeTheSession() {
        let trip = EventTrainingPolicy.plan(fromTags: ["calendar:horizon:travel:4"])
        XCTAssertEqual(trip?.kind, "travel")
        XCTAssertTrue(trip?.reduceVolume == true)
        XCTAssertTrue(trip?.reason.localizedCaseInsensitiveContains("move") == true)
        let flightDay = EventTrainingPolicy.plan(fromTags: ["calendar:horizon:flight:0"])
        XCTAssertEqual(flightDay?.keepLight, true)
        let game = EventTrainingPolicy.plan(fromTags: ["calendar:horizon:game:2"])
        XCTAssertEqual(game?.kind, "game")
        XCTAssertTrue(game?.reason.localizedCaseInsensitiveContains("window") == true)
    }
}
