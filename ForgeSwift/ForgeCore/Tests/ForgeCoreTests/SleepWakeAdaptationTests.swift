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
}
