import XCTest
@testable import ForgeCore

final class SleepWakeAdaptationTests: XCTestCase {

    func testLowScoreWidensTheWindow() {
        let minutes = SmartAlarmWindow.minutes(
            base: 30,
            recentScore: 60,
            debtHours: 0,
            bias: .bear
        )
        XCTAssertEqual(minutes, 45)
    }

    func testHighScoreAndLionNarrow() {
        let minutes = SmartAlarmWindow.minutes(
            base: 30,
            recentScore: 90,
            debtHours: 0,
            bias: .lion
        )
        XCTAssertEqual(minutes, 15)
    }

    func testStrugglersWidenFurther() {
        let calm = SmartAlarmWindow.minutes(
            base: 30,
            recentScore: 80,
            debtHours: 0,
            bias: .bear,
            struggleAverageSnoozes: 0
        )
        let hard = SmartAlarmWindow.minutes(
            base: 30,
            recentScore: 80,
            debtHours: 0,
            bias: .bear,
            struggleAverageSnoozes: 2.0
        )
        XCTAssertEqual(calm, 30)
        XCTAssertEqual(hard, 40)
    }

    func testClampsToFifteenFortyFive() {
        let wide = SmartAlarmWindow.minutes(
            base: 45,
            recentScore: 40,
            debtHours: 8,
            bias: .dolphin,
            struggleAverageSnoozes: 3
        )
        XCTAssertEqual(wide, 45)
    }

    func testSnoozeHistoryAveragesAcrossMornings() {
        let suite = "forge.struggle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = cal.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 7))!
        let tuesday = cal.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 7))!
        WakeStruggleStore.record(snoozes: 2, on: monday, calendar: cal, defaults: defaults)
        WakeStruggleStore.record(snoozes: 0, on: tuesday, calendar: cal, defaults: defaults)
        XCTAssertEqual(WakeStruggleStore.averageSnoozes(defaults: defaults), 1.0, accuracy: 0.01)
        XCTAssertFalse(WakeStruggleStore.isRepeatStruggler(defaults: defaults))
        WakeStruggleStore.record(snoozes: 2, on: tuesday, calendar: cal, defaults: defaults)
        XCTAssertEqual(WakeStruggleStore.averageSnoozes(defaults: defaults), 2.0, accuracy: 0.01)
        XCTAssertTrue(WakeStruggleStore.isRepeatStruggler(defaults: defaults))
        defaults.removePersistentDomain(forName: suite)
    }

    func testCoreSleepInTheWindowFiresEarly() {
        let hard = date(2026, 9, 14, 7, 0)
        let smart = date(2026, 9, 14, 6, 30)
        let now = date(2026, 9, 14, 6, 40)
        let sampleEnd = date(2026, 9, 14, 6, 38)
        XCTAssertEqual(
            SmartWakeEarlyFire.decide(
                now: now, smartFire: smart, hardFire: hard,
                sampleEnd: sampleEnd, stage: .core
            ),
            .fireEarly
        )
    }

    func testDeepSleepInTheWindowIsIgnored() {
        let hard = date(2026, 9, 14, 7, 0)
        let smart = date(2026, 9, 14, 6, 30)
        XCTAssertEqual(
            SmartWakeEarlyFire.decide(
                now: date(2026, 9, 14, 6, 40),
                smartFire: smart, hardFire: hard,
                sampleEnd: date(2026, 9, 14, 6, 38),
                stage: .deep
            ),
            .ignore
        )
    }

    func testStaleSampleIsIgnored() {
        let hard = date(2026, 9, 14, 7, 0)
        let smart = date(2026, 9, 14, 6, 30)
        XCTAssertEqual(
            SmartWakeEarlyFire.decide(
                now: date(2026, 9, 14, 6, 55),
                smartFire: smart, hardFire: hard,
                sampleEnd: date(2026, 9, 14, 6, 20),
                stage: .core
            ),
            .ignore
        )
    }

    func testPastHardAlarmIsAlreadyPastHard() {
        XCTAssertEqual(
            SmartWakeEarlyFire.decide(
                now: date(2026, 9, 14, 7, 1),
                smartFire: date(2026, 9, 14, 6, 30),
                hardFire: date(2026, 9, 14, 7, 0),
                sampleEnd: date(2026, 9, 14, 7, 0),
                stage: .awake
            ),
            .alreadyPastHard
        )
    }

    func testEarlyFireStoreIsOncePerMorning() {
        let suite = "forge.early.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        XCTAssertFalse(SmartWakeEarlyFireStore.alreadyFired(alarmId: "a", dayKey: "2026-09-14", defaults: defaults))
        SmartWakeEarlyFireStore.markFired(alarmId: "a", dayKey: "2026-09-14", defaults: defaults)
        XCTAssertTrue(SmartWakeEarlyFireStore.alreadyFired(alarmId: "a", dayKey: "2026-09-14", defaults: defaults))
        XCTAssertFalse(SmartWakeEarlyFireStore.alreadyFired(alarmId: "a", dayKey: "2026-09-15", defaults: defaults))
        defaults.removePersistentDomain(forName: suite)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}
