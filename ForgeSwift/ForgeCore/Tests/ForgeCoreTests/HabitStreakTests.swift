import XCTest
@testable import ForgeCore

final class HabitStreakTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ offset: Int, from today: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 15))!
    }

    func testEmptyHistoryIsZero() {
        XCTAssertEqual(HabitStreak.length(qualifyingDays: [], today: today, calendar: calendar), 0)
    }

    func testRunEndingTodayCountsEveryDay() {
        let days = (0...4).map { day(-$0, from: today) }
        XCTAssertEqual(HabitStreak.length(qualifyingDays: days, today: today, calendar: calendar), 5)
    }

    func testRunEndingYesterdayStillCountsBeforeTodayQualifies() {
        let days = (1...3).map { day(-$0, from: today) }
        XCTAssertEqual(HabitStreak.length(qualifyingDays: days, today: today, calendar: calendar), 3)
    }

    func testGapBreaksTheRun() {
        let days = [day(0, from: today), day(-1, from: today), day(-3, from: today), day(-4, from: today)]
        XCTAssertEqual(HabitStreak.length(qualifyingDays: days, today: today, calendar: calendar), 2)
    }

    func testMissingTodayAndYesterdayIsZero() {
        let days = [day(-2, from: today), day(-3, from: today)]
        XCTAssertEqual(HabitStreak.length(qualifyingDays: days, today: today, calendar: calendar), 0)
    }

    func testTimeOfDayDoesNotSplitADay() {
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 6))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 23))!
        XCTAssertEqual(
            HabitStreak.length(qualifyingDays: [morning, night], today: today, calendar: calendar), 2
        )
    }

    func testQualifiesThreshold() {
        XCTAssertFalse(HabitStreak.qualifies(completed: 0, total: 0))
        XCTAssertFalse(HabitStreak.qualifies(completed: 3, total: 6))
        XCTAssertTrue(HabitStreak.qualifies(completed: 4, total: 6))
        XCTAssertTrue(HabitStreak.qualifies(completed: 3, total: 5))
    }

    func testRecordingAddsIsIdempotentAndRemoves() {
        var days = HabitStreak.recording(day: today, qualifies: true, in: [], calendar: calendar)
        days = HabitStreak.recording(day: today, qualifies: true, in: days, calendar: calendar)
        XCTAssertEqual(days.count, 1)
        days = HabitStreak.recording(day: today, qualifies: false, in: days, calendar: calendar)
        XCTAssertTrue(days.isEmpty)
    }

    func testRecordingTrimsToRetainedWindow() {
        var days: [Date] = []
        for offset in 0..<(HabitStreak.retainedDays + 10) {
            days = HabitStreak.recording(day: day(-offset, from: today), qualifies: true, in: days, calendar: calendar)
        }
        XCTAssertEqual(days.count, HabitStreak.retainedDays)
        XCTAssertEqual(days.last, calendar.startOfDay(for: today))
    }
}
