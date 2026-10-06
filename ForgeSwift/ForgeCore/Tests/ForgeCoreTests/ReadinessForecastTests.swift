import XCTest
@testable import ForgeCore

final class ReadinessForecastTests: XCTestCase {

    private func baseInput() -> ReadinessForecastEngine.Input {
        ReadinessForecastEngine.Input(
            currentReadiness: 75,
            sleepMinutes: 480,
            hrvMs: 60,
            hrvBaselineMs: 60,
            restingHR: 55,
            restingHRBaseline: 55,
            todayStrain: 8,
            stressLevel: 30
        )
    }

    func testSteadyDayForecastsNearCurrent() {
        let forecast = ReadinessForecastEngine.forecast(baseInput())
        // Nothing moving except a neutral stress read: score holds at 75.
        XCTAssertEqual(forecast.predictedScore, 75)
        XCTAssertEqual(forecast.posture, .steady)
        XCTAssertEqual(forecast.confidence, .medium)  // ACWR unknown
    }

    func testHeavyLoadAndSleepDebtDragsScore() {
        var input = baseInput()
        input.sleepMinutes = 360  // 2h debt → -16
        input.todayStrain = 18    // heavy → -12
        let forecast = ReadinessForecastEngine.forecast(input)
        XCTAssertLessThan(forecast.predictedScore, 60)
        XCTAssertTrue([.protect, .rest].contains(forecast.posture))
        XCTAssertTrue(forecast.drivers.contains { $0.title == "Sleep debt" })
        XCTAssertTrue(forecast.drivers.contains { $0.title == "Heavy load today" })
    }

    func testSuppressedHRVMovesNeedle() {
        var input = baseInput()
        input.hrvMs = 42  // 30% below baseline → -15
        let forecast = ReadinessForecastEngine.forecast(input)
        XCTAssertTrue(forecast.drivers.contains { $0.title == "HRV suppressed" })
        XCTAssertLessThan(forecast.predictedScore, 75)
    }

    func testMissingBaselinesDegradeConfidenceNotCorrectness() {
        var input = baseInput()
        input.hrvBaselineMs = nil
        input.restingHRBaseline = nil
        input.acwr = nil
        let forecast = ReadinessForecastEngine.forecast(input)
        XCTAssertEqual(forecast.confidence, .low)
        XCTAssertTrue((5...98).contains(forecast.predictedScore))
    }

    func testScoreClamps() {
        var input = baseInput()
        input.currentReadiness = 100
        input.sleepMinutes = 600
        input.todayStrain = 0
        input.stressLevel = 0
        let high = ReadinessForecastEngine.forecast(input)
        XCTAssertLessThanOrEqual(high.predictedScore, 98)

        input.currentReadiness = 0
        input.sleepMinutes = 240
        input.todayStrain = 21
        input.stressLevel = 100
        input.hrvMs = 20
        let low = ReadinessForecastEngine.forecast(input)
        XCTAssertGreaterThanOrEqual(low.predictedScore, 5)
    }

    func testDriversSortedByImpact() {
        var input = baseInput()
        input.sleepMinutes = 360
        input.todayStrain = 18
        let forecast = ReadinessForecastEngine.forecast(input)
        let impacts = forecast.drivers.map { abs($0.impact) }
        XCTAssertEqual(impacts, impacts.sorted(by: >))
    }

    func testRestPostureRecommendation() {
        var input = baseInput()
        input.currentReadiness = 40
        input.sleepMinutes = 300
        input.todayStrain = 19
        let forecast = ReadinessForecastEngine.forecast(input)
        XCTAssertEqual(forecast.posture, .rest)
        XCTAssertTrue(forecast.recommendation.lowercased().contains("rest day"))
    }

    func testChatPromptAndAriaTagsAreWhatProductionSends() {
        var input = baseInput()
        input.currentReadiness = 40
        input.sleepMinutes = 300
        input.todayStrain = 19
        let forecast = ReadinessForecastEngine.forecast(input)
        XCTAssertTrue(forecast.chatPrompt.contains("\(forecast.predictedScore)"))
        XCTAssertTrue(forecast.chatPrompt.contains("rest"))
        XCTAssertTrue(forecast.chatPrompt.contains("How should I train around that?"))
        XCTAssertTrue(forecast.ariaTags.contains { $0.hasPrefix("forecast:tomorrow:") })
        XCTAssertTrue(forecast.ariaTags.contains("forecast:confidence:\(forecast.confidence.rawValue)"))
        XCTAssertTrue(forecast.posture.keepLight)
        XCTAssertTrue(forecast.steeringLine.lowercased().contains("rest"))
        XCTAssertEqual(forecast.glanceTitle, "Rest")
        XCTAssertTrue(forecast.glanceLine.hasPrefix("Tomorrow \(forecast.predictedScore)"))
    }

    func testProtectPostureKeepsLight() {
        XCTAssertTrue(ReadinessForecastEngine.Posture.protect.keepLight)
        XCTAssertTrue(ReadinessForecastEngine.Posture.rest.keepLight)
        XCTAssertFalse(ReadinessForecastEngine.Posture.push.keepLight)
        XCTAssertFalse(ReadinessForecastEngine.Posture.steady.keepLight)
    }
}
