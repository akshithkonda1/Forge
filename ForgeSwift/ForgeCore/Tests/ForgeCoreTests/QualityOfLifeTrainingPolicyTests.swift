import XCTest
@testable import ForgeCore

final class QualityOfLifeTrainingPolicyTests: XCTestCase {

    func testDepletedKeepsLightAndCapsDuration() {
        let plan = QualityOfLifeTrainingPolicy.plan(overall: 42, band: .depleted)
        XCTAssertEqual(plan?.keepLight, true)
        XCTAssertEqual(plan?.reduceVolume, true)
        XCTAssertEqual(plan?.maxDuration, 30)
        XCTAssertTrue(plan?.reason.localizedCaseInsensitiveContains("QoL") == true)
    }

    func testStrainedWithWeakMindKeepsLight() {
        let plan = QualityOfLifeTrainingPolicy.plan(
            overall: 62,
            band: .strained,
            mindScore: 40,
            sleepScore: 80
        )
        XCTAssertEqual(plan?.keepLight, true)
        XCTAssertEqual(plan?.reduceVolume, true)
        XCTAssertLessThanOrEqual(plan?.maxDuration ?? 99, 35)
    }

    func testStrainedWithoutWeakPillarsStillReducesVolume() {
        let plan = QualityOfLifeTrainingPolicy.plan(
            overall: 65,
            band: .strained,
            mindScore: 80,
            sleepScore: 80
        )
        XCTAssertEqual(plan?.keepLight, false)
        XCTAssertEqual(plan?.reduceVolume, true)
        XCTAssertEqual(plan?.maxDuration, 40)
    }

    func testSteadyAndThrivingDoNotClamp() {
        XCTAssertNil(QualityOfLifeTrainingPolicy.plan(overall: 75, band: .steady))
        XCTAssertNil(QualityOfLifeTrainingPolicy.plan(overall: 90, band: .thriving))
    }

    func testParsesTagsIncludingBandAndPillars() {
        let plan = QualityOfLifeTrainingPolicy.plan(fromTags: [
            "qol:48",
            "qol:band:depleted",
            "qol:pillar:mind:40",
            "qol:pillar:sleep:55",
        ])
        XCTAssertEqual(plan?.overall, 48)
        XCTAssertEqual(plan?.band, .depleted)
        XCTAssertEqual(plan?.keepLight, true)
    }
}
