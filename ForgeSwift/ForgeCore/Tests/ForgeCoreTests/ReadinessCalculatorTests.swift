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

    func testGoodNightAndRecoveredHRVLandsInReadyOrPrimed() {
        let inputs = ReadinessInputs(
            hrvMs: 62, hrvBaselineMs: 50,          // HRV well above baseline
            restingHR: 50, restingHRBaseline: 54,  // RHR below baseline
            sleepMinutes: 8 * 60,
            deepSleepMinutes: 75, remSleepMinutes: 100,
            yesterdayStrain: 0.2
        )
        let score = ReadinessCalculator.score(from: inputs)
        XCTAssertGreaterThanOrEqual(score.overall, 70, "recovered inputs should score Ready+")
        XCTAssertTrue(score.band == .ready || score.band == .primed)
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

    func testBandBoundariesMatchiOSTheme() {
        // Mirrors readinessLabel(for:) in ForgeSwift/Theme+Readiness.swift.
        XCTAssertEqual(ReadinessBand(score: 85), .primed)
        XCTAssertEqual(ReadinessBand(score: 84), .ready)
        XCTAssertEqual(ReadinessBand(score: 70), .ready)
        XCTAssertEqual(ReadinessBand(score: 69), .moderate)
        XCTAssertEqual(ReadinessBand(score: 55), .moderate)
        XCTAssertEqual(ReadinessBand(score: 54), .recovery)
    }
}
