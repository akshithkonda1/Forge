import XCTest
@testable import ForgeCore

final class ReadinessCalculatorTests: XCTestCase {

    func testNoDataProducesZeroConfidence() {
        let score = ReadinessCalculator.score(from: ReadinessInputs())
        XCTAssertEqual(score.confidence, 0)
        XCTAssertEqual(score.overall, 0)
    }

    func testFullDataProducesFullConfidence() {
        let inputs = ReadinessInputs(
            hrvMs: 55, hrvBaselineMs: 50,
            restingHR: 52, restingHRBaseline: 54,
            sleepMinutes: 7.5 * 60,
            deepSleepMinutes: 70, remSleepMinutes: 95,
            yesterdayStrain: 0.4
        )
        let score = ReadinessCalculator.score(from: inputs)
        XCTAssertEqual(score.confidence, 1.0, accuracy: 0.001)
        XCTAssertTrue((0...100).contains(score.overall))
    }

    func testGoodNightAndRecoveredHRVLandsInGoodOrPeak() {
        let inputs = ReadinessInputs(
            hrvMs: 62, hrvBaselineMs: 50,          // HRV well above baseline
            restingHR: 50, restingHRBaseline: 54,  // RHR below baseline
            sleepMinutes: 8 * 60,
            deepSleepMinutes: 75, remSleepMinutes: 100,
            yesterdayStrain: 0.2
        )
        let score = ReadinessCalculator.score(from: inputs)
        XCTAssertGreaterThanOrEqual(score.overall, 70, "recovered inputs should score Good+")
        XCTAssertTrue(score.band == .good || score.band == .peak)
    }

    func testShortSleepAndSuppressedHRVLandsLow() {
        let inputs = ReadinessInputs(
            hrvMs: 34, hrvBaselineMs: 50,          // 32% below baseline
            restingHR: 62, restingHRBaseline: 54,  // elevated RHR
            sleepMinutes: 4.5 * 60,
            deepSleepMinutes: 20, remSleepMinutes: 30,
            yesterdayStrain: 0.9
        )
        let score = ReadinessCalculator.score(from: inputs)
        XCTAssertLessThan(score.overall, 60)
    }

    func testMissingDataLowersConfidenceNotScore() {
        let full = ReadinessCalculator.score(from: ReadinessInputs(
            hrvMs: 55, hrvBaselineMs: 50,
            sleepMinutes: 8 * 60, deepSleepMinutes: 70, remSleepMinutes: 95
        ))
        let sleepOnly = ReadinessCalculator.score(from: ReadinessInputs(
            sleepMinutes: 8 * 60, deepSleepMinutes: 70, remSleepMinutes: 95
        ))
        XCTAssertLessThan(sleepOnly.confidence, full.confidence)
        // Same great sleep shouldn't be punished just because HRV is missing.
        XCTAssertGreaterThanOrEqual(sleepOnly.sleepQuality, 85)
    }

    func testScoresAlwaysClampedTo0Through100() {
        let extreme = ReadinessCalculator.score(from: ReadinessInputs(
            hrvMs: 200, hrvBaselineMs: 20,
            restingHR: 30, restingHRBaseline: 90,
            sleepMinutes: 14 * 60,
            deepSleepMinutes: 300, remSleepMinutes: 300,
            yesterdayStrain: 0
        ))
        XCTAssertTrue((0...100).contains(extreme.overall))
        XCTAssertTrue((0...100).contains(extreme.sleepQuality))
        XCTAssertTrue((0...100).contains(extreme.recovery))
    }

    func testBandBoundariesMatchHomeTokens() {
        XCTAssertEqual(ReadinessBand(score: 85), .peak)
        XCTAssertEqual(ReadinessBand(score: 84), .good)
        XCTAssertEqual(ReadinessBand(score: 70), .good)
        XCTAssertEqual(ReadinessBand(score: 69), .fair)
        XCTAssertEqual(ReadinessBand(score: 50), .fair)
        XCTAssertEqual(ReadinessBand(score: 49), .low)
        XCTAssertEqual(ReadinessBand(score: 85).label, "Peak")
        XCTAssertEqual(ReadinessBand(score: 72).label, "Good")
        XCTAssertEqual(ReadinessBand(score: 60).label, "Fair")
        XCTAssertEqual(ReadinessBand(score: 40).label, "Low")
        XCTAssertEqual(ReadinessBand(score: 40).hex, HomeReadinessTokens.Band.low.hex)
        XCTAssertEqual(ReadinessBand(score: 40).hex, "EF4444")
        XCTAssertNotEqual(HomeReadinessTokens.missHex, HomeReadinessTokens.Band.low.hex)
        for label in ReadinessBand.allCases.map(\.label) {
            XCTAssertFalse(HomeReadinessTokens.foreignBandLabels.contains(label), label)
        }
    }

    func testParityVectors() {
        // Same vectors as test_swift_parity_vectors in test_readiness_calculator.py.
        let cases: [(ReadinessInputs, Int)] = [
            (ReadinessInputs(hrvMs: 62, hrvBaselineMs: 50, restingHR: 50, restingHRBaseline: 54,
                             sleepMinutes: 480, deepSleepMinutes: 75, remSleepMinutes: 100,
                             yesterdayStrain: 0.2), 95),
            (ReadinessInputs(hrvMs: 34, hrvBaselineMs: 50, restingHR: 62, restingHRBaseline: 54,
                             sleepMinutes: 270, deepSleepMinutes: 20, remSleepMinutes: 30,
                             yesterdayStrain: 0.9), 49),
            (ReadinessInputs(hrvMs: 45, hrvBaselineMs: 50, hrvBaselineSdLn: 0.12,
                             restingHR: 57, restingHRBaseline: 54, restingHRBaselineSd: 2.0,
                             sleepMinutes: 420), 71),
        ]
        for (inputs, expected) in cases {
            XCTAssertEqual(ReadinessCalculator.score(from: inputs).overall, expected, "\(inputs)")
        }
    }

    func testLowHRVPersonAtTheirNormalIsNotPenalised() {
        // 22 ms is normal for many people; a population table calls it poor.
        let score = ReadinessCalculator.score(from: ReadinessInputs(hrvMs: 22, hrvBaselineMs: 22))
        XCTAssertEqual(score.overall, 75)
    }

    func testHRVIsSymmetricInLogSpace() {
        // 0.8x and 1.25x are the same distance from normal in ln space.
        let low = ReadinessCalculator.hrvComponent(hrvMs: 40, baselineMs: 50)!
        let high = ReadinessCalculator.hrvComponent(hrvMs: 62.5, baselineMs: 50)!
        XCTAssertEqual(low + high, 2 * ReadinessCalculator.hrvCenter, accuracy: 1e-9)
    }

    func testSameDipMattersMoreForASteadyPerson() {
        let steady = ReadinessCalculator.hrvComponent(hrvMs: 42, baselineMs: 50, baselineSdLn: 0.10)!
        let noisy = ReadinessCalculator.hrvComponent(hrvMs: 42, baselineMs: 50, baselineSdLn: 0.40)!
        XCTAssertLessThan(steady, noisy)
        let steadyRHR = ReadinessCalculator.restingHRComponent(restingHR: 58, baseline: 54, baselineSd: 2)!
        let noisyRHR = ReadinessCalculator.restingHRComponent(restingHR: 58, baseline: 54, baselineSd: 6)!
        XCTAssertLessThan(steadyRHR, noisyRHR)
    }

    func testOversleepingEarnsNoExtraCredit() {
        let atNeed = ReadinessCalculator.score(from: ReadinessInputs(sleepMinutes: 480))
        let over = ReadinessCalculator.score(from: ReadinessInputs(sleepMinutes: 600))
        XCTAssertEqual(atNeed.sleepQuality, over.sleepQuality)
    }

    func testUnstagedNightReadsAsStagesUnknown() {
        // Older watches and phone-only tracking report sleep with no stages.
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let night = SleepNight(segments: [
            SleepStageSegment(start: start, end: start.addingTimeInterval(7 * 3600), stage: .core),
        ])
        let inputs = ReadinessHealthContext(night: night).inputs()
        XCTAssertEqual(inputs.sleepMinutes ?? 0, 420, accuracy: 0.001)
        XCTAssertNil(inputs.deepSleepMinutes)
        XCTAssertNil(inputs.remSleepMinutes)
        // 7h with unknown stages keeps the neutral architecture credit.
        XCTAssertEqual(ReadinessCalculator.score(from: inputs).sleepQuality, 84)
    }

    func testHealthContextCarriesPersonalSpread() {
        let context = ReadinessHealthContext(
            hrvMs: 45,
            hrvBaseline: PersonalBaseline(mean: 50, spread: 0.12, days: 30, logScaled: true),
            restingHR: 57,
            restingHRBaseline: PersonalBaseline(mean: 54, spread: 2, days: 30, logScaled: false)
        )
        let inputs = context.inputs()
        XCTAssertEqual(inputs.hrvBaselineSdLn, 0.12)
        XCTAssertEqual(inputs.restingHRBaselineSd, 2)
        XCTAssertTrue(context.hasAnySignal)
        XCTAssertFalse(ReadinessHealthContext().hasAnySignal)
    }

    func testBandDecodesRetiredWatchWords() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(ReadinessBand.self, from: Data("\"primed\"".utf8)), .peak)
        XCTAssertEqual(try decoder.decode(ReadinessBand.self, from: Data("\"ready\"".utf8)), .good)
        XCTAssertEqual(try decoder.decode(ReadinessBand.self, from: Data("\"moderate\"".utf8)), .fair)
        XCTAssertEqual(try decoder.decode(ReadinessBand.self, from: Data("\"recovery\"".utf8)), .low)
        XCTAssertEqual(try decoder.decode(ReadinessBand.self, from: Data("\"peak\"".utf8)), .peak)
    }
}
