import XCTest
@testable import ForgeCore

final class OnDeviceBodyModelTests: XCTestCase {

    func testProjectsHRVTrendAndSleepDebtWithoutNetwork() {
        let hrv = [60.0, 58, 55, 52, 50, 48, 46]
        let sleep = [480.0, 470, 400, 390, 380, 360, 300]
        let steps = [8000.0, 8100, 7900]
        let projection = OnDeviceBodyModel.project(
            dailyHRV: hrv,
            dailySleepMinutes: sleep,
            dailySteps: steps
        )
        XCTAssertEqual(projection.hrvDaysAvailable, 7)
        XCTAssertNotNil(projection.hrv30DayBaseline)
        XCTAssertNotNil(projection.hrv7DayTrend)
        XCTAssertLessThan(projection.hrv7DayTrend ?? 0, 0)
        XCTAssertNotNil(projection.sleepDebt7dHours)
        XCTAssertGreaterThan(projection.sleepDebt7dHours ?? 0, 0)
        XCTAssertEqual(projection.stepsBaseline, 8000)
    }

    func testDailyStoryNilWhenNothingNotable() {
        XCTAssertNil(OnDeviceDailyStory.build(
            hrvTrend: 1,
            sleepMinutes: 480,
            sleepBaselineMinutes: 480,
            steps3Day: 8000,
            stepsBaseline: 8000
        ))
    }

    func testDailyStoryFromFallingHRV() {
        let story = OnDeviceDailyStory.build(
            hrvTrend: -12,
            sleepMinutes: 480,
            sleepBaselineMinutes: 480,
            steps3Day: 8000,
            stepsBaseline: 8000
        )
        XCTAssertEqual(story?.insights.first?.domain, "readiness")
        XCTAssertTrue(story?.narrative.contains("HRV") == true)
    }
}
