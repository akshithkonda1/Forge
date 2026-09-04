import XCTest
@testable import ForgeSwift

final class FakeCyclePackTests: XCTestCase {

    func testShouldSeedOnlyWhenTestReadyEnabledAndEmpty() {
        XCTAssertTrue(
            FakeCyclePack.shouldSeed(testReady: true, trackingEnabled: true, logsEmpty: true, alreadySeeded: false)
        )
        XCTAssertFalse(
            FakeCyclePack.shouldSeed(testReady: false, trackingEnabled: true, logsEmpty: true, alreadySeeded: false)
        )
        XCTAssertFalse(
            FakeCyclePack.shouldSeed(testReady: true, trackingEnabled: false, logsEmpty: true, alreadySeeded: false)
        )
        XCTAssertFalse(
            FakeCyclePack.shouldSeed(testReady: true, trackingEnabled: true, logsEmpty: false, alreadySeeded: false)
        )
        XCTAssertFalse(
            FakeCyclePack.shouldSeed(testReady: true, trackingEnabled: true, logsEmpty: true, alreadySeeded: true)
        )
    }

    func testGenerateIsDeterministicAndLocalOnly() {
        let now = CycleDayKey.date(from: "2026-09-03")!
        let a = FakeCyclePack.generate(now: now, seed: 2)
        let b = FakeCyclePack.generate(now: now, seed: 2)
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.isEmpty)
        XCTAssertTrue(a.allSatisfy { $0.source == FakeCyclePack.source })
        XCTAssertEqual(FakeCyclePack.currentDayInCycle(seed: 2), 12)
    }

    func testFourStartsAndTodayIsNotBleeding() {
        let now = CycleDayKey.date(from: "2026-09-03")!
        let logs = FakeCyclePack.generate(now: now, seed: 2)
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: logs)
        XCTAssertEqual(episodes.count, FakeCyclePack.cycleCount)
        XCTAssertEqual(logs.count, FakeCyclePack.cycleCount * FakeCyclePack.periodLength)

        let expectedStart = CycleDayKey.addDays("2026-09-03", -(FakeCyclePack.currentDayInCycle(seed: 2) - 1))
        XCTAssertEqual(episodes.last?.startDayKey, expectedStart)
        XCTAssertFalse(
            logs.contains { $0.dayKey == "2026-09-03" && $0.flow.isBleeding },
            "today should be mid-cycle so testers see a named phase"
        )
    }

    func testEngineReadsANamedPhaseFromThePack() {
        let now = CycleDayKey.date(from: "2026-09-03")!
        var settings = MenstrualTrackingSettings.default
        settings.enabled = true
        let snap = MenstrualCycleEngine.evaluate(
            logs: FakeCyclePack.generate(now: now, seed: 2),
            settings: settings,
            asOf: now
        )
        XCTAssertEqual(snap.dayInCycle, 12)
        XCTAssertEqual(snap.cyclesObserved, FakeCyclePack.cycleCount - 1)
        XCTAssertNotEqual(snap.phase, .unknown)
        XCTAssertFalse(snap.isCurrentlyBleeding)
    }
}
