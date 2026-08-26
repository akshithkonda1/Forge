import XCTest
@testable import ForgeCore

final class FakeHealthPackTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var pinnedNow: Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 25
        parts.hour = 15
        parts.minute = 0
        return calendar.date(from: parts)!
    }

    func testShouldInstallOnlyWhenTestReadyAndEmpty() {
        XCTAssertTrue(
            FakeHealthPack.shouldInstall(debugBuild: true, testReady: true, hasRealHealthSignal: false)
        )
        XCTAssertFalse(
            FakeHealthPack.shouldInstall(debugBuild: true, testReady: true, hasRealHealthSignal: true),
            "real HealthKit samples must win"
        )
        XCTAssertFalse(
            FakeHealthPack.shouldInstall(debugBuild: false, testReady: true, hasRealHealthSignal: false)
        )
        XCTAssertFalse(
            FakeHealthPack.shouldInstall(debugBuild: true, testReady: false, hasRealHealthSignal: false)
        )
    }

    func testGenerateIsDeterministic() {
        let a = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: 7)
        let b = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: 7)
        XCTAssertEqual(a.days.count, FakeHealthPack.dayCount)
        XCTAssertEqual(a.days.map(\.isoDate), b.days.map(\.isoDate))
        XCTAssertEqual(a.days.map(\.hrvMs), b.days.map(\.hrvMs))
        XCTAssertEqual(a.today?.night.totalMinutes, b.today?.night.totalMinutes)
    }

    func testTodayHasSleepHRVAndWaterARIACanCite() {
        let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar)
        guard let today = pack.today else {
            return XCTFail("pack must have a today")
        }
        XCTAssertGreaterThan(today.night.totalMinutes, 5 * 60)
        XCTAssertGreaterThan(today.night.deepMinutes, 0)
        XCTAssertGreaterThan(today.night.remMinutes, 0)
        XCTAssertNotNil(today.night.start)
        XCTAssertNotNil(today.night.end)
        XCTAssertTrue((28...95).contains(today.hrvMs))
        XCTAssertTrue((48...78).contains(today.restingHR))
        XCTAssertGreaterThan(today.steps, 0)
        XCTAssertGreaterThan(today.hydrationMl, 0)
        XCTAssertEqual(today.isoDate, "2026-08-25")
    }

    func testStreamHasShortNightsAndWorkouts() {
        let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar)
        let short = pack.days.filter { $0.night.totalMinutes < 6.5 * 60 }
        XCTAssertGreaterThanOrEqual(short.count, 2, "ARIA needs a sleep-debt story")
        let sessions = pack.days.compactMap(\.workout)
        XCTAssertGreaterThanOrEqual(sessions.count, 8)
        XCTAssertTrue(sessions.contains { $0.type == .strength })
    }

    func testReadinessInputsAreComplete() {
        let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar)
        let inputs = pack.readinessInputs
        XCTAssertNotNil(inputs.hrvMs)
        XCTAssertNotNil(inputs.sleepMinutes)
        let score = ReadinessCalculator.score(from: inputs)
        XCTAssertGreaterThan(score.confidence, 0.5)
        XCTAssertTrue((1...100).contains(score.overall))
    }

    func testNightsAreNewestFirstAndDoNotShareDates() {
        let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar)
        let dates = pack.days.map(\.isoDate)
        XCTAssertEqual(dates.first, "2026-08-25")
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertEqual(dates, dates.sorted(by: >))
    }
}
