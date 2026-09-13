import XCTest
@testable import ForgeSwift
import ForgeCore

/// `scoreNight`'s efficiency term used to compute (asleep - awake) / asleep
/// instead of the standard asleep / (asleep + awake). Locks the corrected
/// formula, which now matches `SleepData.efficiencyPercent` (Models.swift).
@MainActor
final class HealthKitSleepServiceScoringTests: XCTestCase {

    func testSleepEfficiencyIsAsleepOverAsleepPlusAwake() {
        let pct = HealthKitSleepService.sleepEfficiencyPercent(asleepMinutes: 360, awakeMinutes: 60)
        XCTAssertEqual(pct, 360.0 / 420.0 * 100, accuracy: 0.01)
    }

    func testSleepEfficiencyIsHundredWithNoAwakeTime() {
        let pct = HealthKitSleepService.sleepEfficiencyPercent(asleepMinutes: 420, awakeMinutes: 0)
        XCTAssertEqual(pct, 100, accuracy: 0.01)
    }

    func testSleepEfficiencyIsZeroWhenNothingWasRecorded() {
        let pct = HealthKitSleepService.sleepEfficiencyPercent(asleepMinutes: 0, awakeMinutes: 0)
        XCTAssertEqual(pct, 0, accuracy: 0.01)
    }

    func testIosHelperMatchesForgeCoreEfficiency() {
        let ios = HealthKitSleepService.sleepEfficiencyPercent(asleepMinutes: 360, awakeMinutes: 60)
        let core = SleepNightMetrics.efficiencyPercent(asleepHours: 6, awakeMinutes: 60)
        XCTAssertEqual(ios, core, accuracy: 0.01)
    }

    func testScoreNightUsesTheCorrectedEfficiencyFormula() {
        let service = HealthKitSleepService.shared
        let profile = UserSleepProfile()   // defaults to .bear chronotype
        let result = service.scoreNight(
            totalHours: 6.0,
            deepMinutes: 90,
            remMinutes: 90,
            awakeMinutes: 60,
            profile: profile,
            recentWakes: [],
            baselines: SleepDepthBaselines()
        )

        let chronotype = profile.chronotype
        let durationScore = min(100, (6.0 / chronotype.targetSleepHours) * 100)
        let deepScore = min(100, (90.0 / Double(chronotype.deepSleepGoalMinutes)) * 100)
        let remScore = min(100, (90.0 / Double(chronotype.remSleepGoalMinutes)) * 100)
        let efficiency = 360.0 / 420.0 * 100   // 360 min asleep, 60 min awake
        let consistency = 80.0                 // fewer than 5 recentWakes
        let expected = durationScore * 0.35
            + deepScore * 0.25
            + remScore * 0.20
            + efficiency * 0.15
            + consistency * 0.05

        XCTAssertEqual(result.score, Int(expected.rounded()))
        XCTAssertEqual(result.source, "chronotype")
        XCTAssertEqual(result.personalBlend, 0)
    }
}
