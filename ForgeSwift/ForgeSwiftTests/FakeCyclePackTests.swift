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
        XCTAssertTrue(a.contains { $0.bbtCelsius != nil })
        XCTAssertTrue(a.contains { $0.ovulationTest == .lhSurge })
        XCTAssertTrue(a.contains { ($0.painScale ?? 0) >= 6 })
        XCTAssertTrue(a.contains { $0.symptoms.contains(.cramps) })
    }

    func testFourStartsAndTodayIsNotBleeding() {
        let now = CycleDayKey.date(from: "2026-09-03")!
        let logs = FakeCyclePack.generate(now: now, seed: 2)
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: logs)
        XCTAssertEqual(episodes.count, FakeCyclePack.cycleCount)
        let bleedingDays = logs.filter { $0.flow.isBleeding }.count
        XCTAssertEqual(bleedingDays, FakeCyclePack.cycleCount * FakeCyclePack.periodLength)
        XCTAssertGreaterThan(logs.count, bleedingDays)

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

    func testShouldRefreshWhenSessionSeedChangesAndLogsAreStillThePack() {
        let packLogs = FakeCyclePack.generate(now: CycleDayKey.date(from: "2026-09-03")!, seed: 2)
        XCTAssertTrue(
            FakeCyclePack.shouldApply(
                testReady: true,
                trackingEnabled: true,
                logs: packLogs,
                blockedAfterWipe: false,
                storedSeed: 2,
                sessionSeed: 99,
                alreadySeeded: true
            )
        )
        XCTAssertFalse(
            FakeCyclePack.shouldApply(
                testReady: true,
                trackingEnabled: true,
                logs: packLogs,
                blockedAfterWipe: false,
                storedSeed: 99,
                sessionSeed: 99,
                alreadySeeded: true
            )
        )
        let mixed = packLogs + [CycleDayLog(dayKey: "2026-09-03", flow: .none, source: "manual")]
        XCTAssertFalse(
            FakeCyclePack.shouldApply(
                testReady: true,
                trackingEnabled: true,
                logs: mixed,
                blockedAfterWipe: false,
                storedSeed: 2,
                sessionSeed: 99,
                alreadySeeded: true
            ),
            "user-entered days must not be overwritten"
        )
        XCTAssertFalse(
            FakeCyclePack.shouldApply(
                testReady: true,
                trackingEnabled: true,
                logs: [],
                blockedAfterWipe: true,
                storedSeed: nil,
                sessionSeed: 1,
                alreadySeeded: true
            ),
            "an explicit wipe must not be refilled"
        )
    }
}
