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
        XCTAssertEqual(forecast.predictedScore, 75)
        XCTAssertEqual(forecast.posture, .steady)
        XCTAssertEqual(forecast.confidence, .medium)  // ACWR + personal baseline unknown
    }

    func testHeavyLoadAfterAShortNightDrags() {
        // A 6h night already shows up as today's 58 — it is not charged twice.
        var input = baseInput()
        input.currentReadiness = 58
        input.sleepMinutes = 360
        input.todayStrain = 18
        let forecast = ReadinessForecastEngine.forecast(input)
        XCTAssertLessThan(forecast.predictedScore, 60)
        XCTAssertTrue([.protect, .rest].contains(forecast.posture))
        XCTAssertTrue(forecast.drivers.contains { $0.title == "Heavy load today" })
        XCTAssertFalse(forecast.drivers.contains { $0.title == "Sleep debt" })
    }

    func testLastNightIsNotDoubleCounted() {
        var rested = baseInput()
        rested.currentReadiness = 60
        var short = rested
        short.sleepMinutes = 330
        XCTAssertEqual(
            ReadinessForecastEngine.forecast(rested).predictedScore,
            ReadinessForecastEngine.forecast(short).predictedScore
        )
    }

    func testLowDayBouncesPartwayBack() {
        var input = baseInput()
        input.currentReadiness = 45
        input.sleepMinutes = 300
        input.todayStrain = 5
        let forecast = ReadinessForecastEngine.forecast(input)
        // 75 + 0.5 × (45 − 75) = 60: halfway home, not all the way.
        XCTAssertEqual(forecast.predictedScore, 60)
        let bounce = forecast.drivers.first { $0.title == "Bounce-back" }
        XCTAssertEqual(bounce?.impact, 15)
        XCTAssertTrue(bounce?.detail.contains("short sleep") ?? false)
    }

    func testHighDayEasesBack() {
        var input = baseInput()
        input.currentReadiness = 95
        input.todayStrain = 5
        let forecast = ReadinessForecastEngine.forecast(input)
        XCTAssertEqual(forecast.predictedScore, 85)
        XCTAssertTrue(forecast.drivers.contains { $0.title == "Easing to your usual" })
    }

    func testPersonalBaselineIsTheAnchor() {
        var input = baseInput()
        input.currentReadiness = 70
        input.readinessBaseline = 82
        input.todayStrain = 5
        XCTAssertEqual(ReadinessForecastEngine.forecast(input).predictedScore, 76)
    }

    func testUnknownSleepIsNotZeroSleep() {
        // Clients send 0 minutes when the night never synced. That used to
        // read as an 8h debt (−20) and a rest day on no evidence.
        var unknown = baseInput()
        unknown.sleepMinutes = 0
        let a = ReadinessForecastEngine.forecast(unknown)
        let b = ReadinessForecastEngine.forecast(baseInput())
        XCTAssertEqual(a.predictedScore, b.predictedScore)
        XCTAssertNotEqual(a.posture, .rest)
    }

    func testUnknownReadinessStartsFromUsualWithLowConfidence() {
        var input = baseInput()
        input.currentReadiness = 0
        let forecast = ReadinessForecastEngine.forecast(input)
        XCTAssertEqual(forecast.predictedScore, ReadinessForecastEngine.defaultReadinessBaseline)
        XCTAssertEqual(forecast.confidence, .low)
        XCTAssertNotEqual(forecast.posture, .rest)
    }

    func testNewUserWithNothingIsNotToldToRestOrPush() {
        let forecast = ReadinessForecastEngine.forecast(.init(
            currentReadiness: 0, sleepMinutes: 0, hrvMs: 0, restingHR: 0, todayStrain: 0, stressLevel: nil
        ))
        XCTAssertEqual(forecast.posture, .steady)
        XCTAssertEqual(forecast.confidence, .low)
    }

    func testUnreportedStressIsUnknownNotModerate() {
        var said = baseInput()
        said.stressLevel = 80
        var unsaid = baseInput()
        unsaid.stressLevel = nil
        XCTAssertTrue(ReadinessForecastEngine.forecast(said).drivers.contains { $0.title == "High stress" })
        let quiet = ReadinessForecastEngine.forecast(unsaid)
        XCTAssertFalse(quiet.drivers.contains { $0.title.lowercased().contains("stress") })
        XCTAssertEqual(quiet.confidence, .low)  // 4 of 7 signals
    }

    func testFullSignalIsHighConfidence() {
        var input = baseInput()
        input.acwr = 1.0
        input.readinessBaseline = 78
        XCTAssertEqual(ReadinessForecastEngine.forecast(input).confidence, .high)
    }

    func testParityVectors() {
        // Same vectors as test_swift_parity_vectors in test_predictive_coach.py.
        var low = baseInput(); low.currentReadiness = 45; low.sleepMinutes = 300; low.todayStrain = 5
        var heavy = baseInput(); heavy.currentReadiness = 58; heavy.sleepMinutes = 360; heavy.todayStrain = 18
        var blank = baseInput(); blank.currentReadiness = 0; blank.sleepMinutes = 0
        var peak = baseInput()
        peak.currentReadiness = 90; peak.todayStrain = 2; peak.stressLevel = 20
        peak.acwr = 0.7; peak.readinessBaseline = 80
        let cases: [(ReadinessForecastEngine.Input, Int, ReadinessForecastEngine.Posture, ReadinessForecastEngine.Confidence)] = [
            (baseInput(), 75, .steady, .medium),
            (low, 60, .protect, .medium),
            (heavy, 55, .protect, .medium),
            (blank, 75, .steady, .low),
            (peak, 97, .push, .high),
        ]
        for (input, score, posture, confidence) in cases {
            let fc = ReadinessForecastEngine.forecast(input)
            XCTAssertEqual(fc.predictedScore, score)
            XCTAssertEqual(fc.posture, posture)
            XCTAssertEqual(fc.confidence, confidence)
        }
    }

    func testScoreClamps() {
        var input = baseInput()
        input.currentReadiness = 100
        input.todayStrain = 0
        input.stressLevel = 0
        input.acwr = 0.5
        let high = ReadinessForecastEngine.forecast(input)
        XCTAssertLessThanOrEqual(high.predictedScore, 98)

        input.currentReadiness = 1
        input.todayStrain = 21
        input.stressLevel = 100
        input.acwr = 2
        input.isLutealPhase = true
        let low = ReadinessForecastEngine.forecast(input)
        XCTAssertGreaterThanOrEqual(low.predictedScore, 5)
    }

    func testDriversSortedByImpact() {
        var input = baseInput()
        input.currentReadiness = 50
        input.todayStrain = 18
        input.stressLevel = 80
        input.acwr = 1.7
        let forecast = ReadinessForecastEngine.forecast(input)
        let impacts = forecast.drivers.map { abs($0.impact) }
        XCTAssertEqual(impacts, impacts.sorted(by: >))
    }

    func testRestPostureRecommendation() {
        var input = baseInput()
        input.currentReadiness = 40
        input.sleepMinutes = 300
        input.todayStrain = 19
        input.stressLevel = 80
        let forecast = ReadinessForecastEngine.forecast(input)
        XCTAssertEqual(forecast.posture, .rest)
        XCTAssertTrue(forecast.recommendation.lowercased().contains("rest day"))
    }

    func testChatPromptAndAriaTagsAreWhatProductionSends() {
        var input = baseInput()
        input.currentReadiness = 40
        input.sleepMinutes = 300
        input.todayStrain = 19
        input.stressLevel = 80
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
