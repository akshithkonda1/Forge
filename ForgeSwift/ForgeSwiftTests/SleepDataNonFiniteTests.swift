import XCTest
@testable import ForgeSwift

/// Pins Models.swift:531 / :542 — Int(totalHours * 60) trapped on NaN/inf
/// when a night had no stage data. Tess's ForgeCore NonFiniteHealthInputTests
/// cannot see SleepData; this is the app-side counterpart.
final class SleepDataNonFiniteTests: XCTestCase {

    private func night(hours: Double, staged: Bool = false) -> SleepData {
        SleepData(
            date: "2026-10-16",
            totalHours: hours,
            deepMinutes: staged ? 40 : 0,
            remMinutes: staged ? 80 : 0,
            lightMinutes: staged ? 200 : 0,
            awakeMinutes: staged ? 10 : 0,
            score: 70
        )
    }

    func testNaNHoursWithoutStagesDoesNotTrap() {
        let nanNight = night(hours: .nan)
        XCTAssertEqual(SleepData.minutes(fromHours: .nan), 0)
        XCTAssertEqual(nanNight.timeInBedMinutes, 0)
        XCTAssertEqual(nanNight.efficiencyPercent, 0)
    }

    func testInfiniteHoursWithoutStagesDoesNotTrap() {
        XCTAssertEqual(night(hours: .infinity).timeInBedMinutes, 0)
        XCTAssertEqual(night(hours: -.infinity).timeInBedMinutes, 0)
        XCTAssertEqual(night(hours: .infinity).efficiencyPercent, 0)
    }

    func testFiniteHoursStillConvert() {
        XCTAssertEqual(night(hours: 7.5).timeInBedMinutes, 450)
        let staged = night(hours: .nan, staged: true)
        XCTAssertEqual(staged.timeInBedMinutes, 330)
        XCTAssertGreaterThan(staged.efficiencyPercent, 0)
    }
}
