import XCTest
@testable import ForgeCore

final class OnlineStatTests: XCTestCase {

    func testWelfordMeanAndSampleStd() {
        var stat = OnlineStat(alpha: 0.3)
        for value in [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0] {
            stat.update(value)
        }
        XCTAssertEqual(stat.n, 8)
        XCTAssertEqual(stat.mean, 5.0, accuracy: 1e-9)
        // Same series Wikipedia uses for σ = 2 (divide by n). Welford here
        // matches Python `OnlineStat`: sample std, divide by n-1 → √(32/7).
        let sampleStd = (32.0 / 7.0).squareRoot()
        XCTAssertEqual(stat.std, sampleStd, accuracy: 1e-9)
        XCTAssertEqual(stat.zscore(7), 2.0 / sampleStd, accuracy: 1e-9)
        XCTAssertEqual(stat.last, 9.0)
    }

    func testSingleSampleHasZeroSpread() {
        var stat = OnlineStat()
        stat.update(8)
        XCTAssertEqual(stat.std, 0)
        XCTAssertEqual(stat.zscore(8), 0)
        XCTAssertLessThan(stat.zscore(5), -10)
        XCTAssertEqual(stat.ewma, 8)
    }

    func testRoundTripPreservesMoments() {
        var stat = OnlineStat(alpha: 0.4)
        stat.update(6.5)
        stat.update(7.2)
        stat.update(8.1)
        let data = try! JSONEncoder().encode(stat)
        let decoded = try! JSONDecoder().decode(OnlineStat.self, from: data)
        XCTAssertEqual(decoded.n, 3)
        XCTAssertEqual(decoded.mean, stat.mean, accuracy: 1e-12)
        XCTAssertEqual(decoded.std, stat.std, accuracy: 1e-12)
        XCTAssertEqual(decoded.ewma, stat.ewma, accuracy: 1e-12)
        XCTAssertEqual(decoded.alpha, 0.4)
    }
}

final class SleepDepthScorerTests: XCTestCase {

    private let bear = SleepChronotypeTargets(
        targetHours: 8,
        deepGoalMinutes: 90,
        remGoalMinutes: 90
    )

    private func typicalNight(
        hours: Double = 8,
        deep: Double = 90,
        rem: Double = 90,
        efficiency: Double = 90,
        consistency: Double = 80
    ) -> SleepNightMetrics {
        SleepNightMetrics(
            totalHours: hours,
            deepMinutes: deep,
            remMinutes: rem,
            efficiencyPercent: efficiency,
            wakeConsistency: consistency
        )
    }

    func testColdStartMatchesChronotypeFormula() {
        let metrics = typicalNight(hours: 8, deep: 90, rem: 90, efficiency: 90, consistency: 80)
        let chrono = SleepDepthScorer.chronotypeScore(metrics: metrics, targets: bear)
        let result = SleepDepthScorer.score(
            metrics: metrics,
            targets: bear,
            baselines: SleepDepthBaselines()
        )
        XCTAssertEqual(result.score, chrono)
        XCTAssertEqual(result.personalBlend, 0)
        XCTAssertEqual(result.source, "chronotype")
        XCTAssertTrue(result.unusualFlags.isEmpty)
        XCTAssertGreaterThanOrEqual(chrono, 90)
    }

    func testHonestEfficiencyUsesTimeInBed() {
        let percent = SleepNightMetrics.efficiencyPercent(asleepHours: 7, awakeMinutes: 60)
        XCTAssertEqual(percent, 87.5, accuracy: 0.01)
    }

    func testObserveIsIdempotentForTheSameNight() {
        var baselines = SleepDepthBaselines()
        let night = typicalNight()
        SleepDepthScorer.observe(&baselines, metrics: night, nightKey: "2026-09-01")
        SleepDepthScorer.observe(&baselines, metrics: typicalNight(hours: 5), nightKey: "2026-09-01")
        XCTAssertEqual(baselines.sampleCount, 1)
        XCTAssertEqual(baselines.duration.last, 8)
    }

    func testAShortNightIsUnusualAfterAStableBaseline() {
        var baselines = SleepDepthBaselines()
        for day in 1...10 {
            SleepDepthScorer.observe(
                &baselines,
                metrics: typicalNight(hours: 8, deep: 90, rem: 90, efficiency: 92),
                nightKey: String(format: "2026-09-%02d", day)
            )
        }
        let short = typicalNight(hours: 5.0, deep: 40, rem: 40, efficiency: 70)
        let result = SleepDepthScorer.score(metrics: short, targets: bear, baselines: baselines)
        XCTAssertGreaterThan(result.personalBlend, 0)
        XCTAssertFalse(result.unusualFlags.isEmpty, "\(result.unusualFlags)")
        XCTAssertTrue(
            result.unusualFlags.contains(where: { $0.lowercased().contains("shorter") }),
            "\(result.unusualFlags)"
        )
        XCTAssertLessThan(result.score, SleepDepthScorer.chronotypeScore(metrics: short, targets: bear) + 5)
    }

    func testATypicalNightAgainstSelfIsNotFlagged() {
        var baselines = SleepDepthBaselines()
        for day in 1...8 {
            SleepDepthScorer.observe(
                &baselines,
                metrics: typicalNight(hours: 7.8 + Double(day % 2) * 0.2),
                nightKey: String(format: "2026-09-%02d", day)
            )
        }
        let result = SleepDepthScorer.score(
            metrics: typicalNight(hours: 7.9),
            targets: bear,
            baselines: baselines
        )
        XCTAssertTrue(result.unusualFlags.isEmpty, "\(result.unusualFlags)")
    }
}
