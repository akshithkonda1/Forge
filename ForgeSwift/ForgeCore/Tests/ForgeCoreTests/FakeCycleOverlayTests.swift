import XCTest
@testable import ForgeCore

final class FakeCycleOverlayTests: XCTestCase {

    func testTodayLandsInNamedPhaseBand() {
        for seed in 0...20 {
            let day = FakeCycleOverlay.currentDayInCycle(seed: seed)
            XCTAssertTrue((10...16).contains(day), "seed \(seed) day \(day)")
            XCTAssertNotEqual(FakeCycleOverlay.phaseLabel(dayInCycle: day), "menstruation")
        }
    }

    func testFactsAreDeterministicAndBleedOnPeriodDays() {
        let a = FakeCycleOverlay.facts(offsetFromToday: 0, seed: 2)
        let b = FakeCycleOverlay.facts(offsetFromToday: 0, seed: 2)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.dayInCycle, 12)
        XCTAssertEqual(a.phase, "fertileWindow")
        XCTAssertEqual(a.flow, "none")

        let startOffset = 12 - 1
        let start = FakeCycleOverlay.facts(offsetFromToday: startOffset, seed: 2)
        XCTAssertTrue(start.isCycleStart)
        XCTAssertEqual(start.flow, "medium")
        XCTAssertEqual(start.phase, "menstruation")
        XCTAssertEqual(start.symptoms.contains("cramps"), true)
    }

    func testLutealBBTSitsAboveFollicular() {
        let follicular = FakeCycleOverlay.facts(dayInCycle: 8, seed: 4, salt: 8)
        let luteal = FakeCycleOverlay.facts(dayInCycle: 20, seed: 4, salt: 20)
        XCTAssertNotNil(follicular.bbtCelsius)
        XCTAssertNotNil(luteal.bbtCelsius)
        XCTAssertGreaterThan(luteal.bbtCelsius!, follicular.bbtCelsius!)
    }

    func testDifferentSeedsChangePainAndSymptomsNotTheCalendar() {
        let a = FakeCycleOverlay.facts(dayInCycle: 2, seed: 1, salt: 2)
        let b = FakeCycleOverlay.facts(dayInCycle: 2, seed: 99, salt: 2)
        XCTAssertEqual(a.flow, b.flow)
        XCTAssertEqual(a.dayInCycle, b.dayInCycle)
        XCTAssertTrue(a.painScale != b.painScale || a.symptoms != b.symptoms || a.bbtCelsius != b.bbtCelsius)
    }
}
