import XCTest
@testable import ForgeCore

final class ScheduleCorrectorTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    func testParserReadsSixAmStartingMonday() {
        let saturday = date(2026, 9, 12, 18, 0) // Saturday
        let goal = ScheduleGoalParser.parse(
            "I need to be up at 6am starting Monday",
            now: saturday,
            calendar: calendar
        )
        XCTAssertEqual(goal?.targetWakeHour, 6.0)
        XCTAssertEqual(calendar.component(.weekday, from: goal!.cutoverStart), 2)
        XCTAssertEqual(calendar.component(.day, from: goal!.cutoverStart), 14)
    }

    func testParserBareSixIsMorning() {
        let goal = ScheduleGoalParser.parse(
            "wake me at 6 starting Tuesday",
            now: date(2026, 9, 10, 12, 0),
            calendar: calendar
        )
        XCTAssertEqual(goal?.targetWakeHour, 6.0)
    }

    func testParserIgnoresTrainingAsks() {
        XCTAssertNil(ScheduleGoalParser.parse("what should I train today"))
        XCTAssertNil(ScheduleGoalParser.parse("what's up at the gym"))
    }

    func testParserReadsEveningClock() {
        let goal = ScheduleGoalParser.parse(
            "wake me at 6:30pm",
            now: date(2026, 9, 13, 12, 0),
            calendar: calendar
        )
        XCTAssertEqual(goal?.targetWakeHour, 18.5)
    }

    func testCoachingReplyKeepsUpAtStem() {
        let nights = habitualNights(wakeHour: 8.0, count: 7, ending: date(2026, 9, 13, 8, 0))
        let goal = ScheduleGoal(
            targetWakeHour: 6.0,
            cutoverStart: date(2026, 9, 1, 0, 0)
        )
        let step = ScheduleCorrector.tonight(
            goal: goal,
            nights: nights,
            now: date(2026, 9, 13, 21, 0),
            calendar: calendar
        )!
        XCTAssertTrue(step.coachingReply.contains("up at"), step.coachingReply)
        XCTAssertTrue(step.coachingReply.contains("sleep"), step.coachingReply)
        XCTAssertTrue(step.guidanceLine.contains("earlier"), step.guidanceLine)
    }

    func testRatchetCapsAtFifteenMinutes() {
        let nights = habitualNights(wakeHour: 8.0, count: 7, ending: date(2026, 9, 13, 8, 0))
        let goal = ScheduleGoal(
            targetWakeHour: 6.0,
            cutoverStart: date(2026, 9, 10, 0, 0),
            createdAt: date(2026, 9, 10, 0, 0)
        )
        let step = ScheduleCorrector.tonight(
            goal: goal,
            nights: nights,
            now: date(2026, 9, 13, 21, 0),
            calendar: calendar
        )
        XCTAssertNotNil(step)
        XCTAssertFalse(step!.reachedTarget)
        XCTAssertEqual(step!.shiftMinutesTonight, -15, accuracy: 0.6)
        XCTAssertEqual(step!.recommendedWakeHour, 7.75, accuracy: 0.05)
    }

    func testSpreadsShiftAcrossNightsUntilCutover() {
        let nights = habitualNights(wakeHour: 8.0, count: 7, ending: date(2026, 9, 11, 8, 0))
        let saturday = date(2026, 9, 12, 20, 0)
        let goal = ScheduleGoal(
            targetWakeHour: 7.0,
            cutoverStart: date(2026, 9, 14, 0, 0),
            createdAt: saturday
        )
        let step = ScheduleCorrector.tonight(
            goal: goal,
            nights: nights,
            now: saturday,
            calendar: calendar
        )
        XCTAssertNotNil(step)
        // 60 min gap, 2 nights until Monday → 30 min planned, capped at 15.
        XCTAssertEqual(step!.shiftMinutesTonight, -15, accuracy: 0.6)
    }

    func testReachedWhenAlreadyOnTarget() {
        let nights = habitualNights(wakeHour: 6.0, count: 7, ending: date(2026, 9, 13, 6, 0))
        let goal = ScheduleGoal(
            targetWakeHour: 6.0,
            cutoverStart: date(2026, 9, 10, 0, 0)
        )
        let step = ScheduleCorrector.tonight(
            goal: goal,
            nights: nights,
            now: date(2026, 9, 13, 21, 0),
            calendar: calendar
        )
        XCTAssertEqual(step?.reachedTarget, true)
        XCTAssertEqual(step?.shiftMinutesTonight ?? 99, 0, accuracy: 0.6)
        XCTAssertTrue(step?.guidanceLine.contains("on it") == true)
    }

    func testBedtimeIsNeedHoursBeforeWake() {
        let nights = habitualNights(wakeHour: 8.0, asleep: 8.0, count: 7, ending: date(2026, 9, 13, 8, 0))
        let goal = ScheduleGoal(
            targetWakeHour: 6.0,
            cutoverStart: date(2026, 9, 1, 0, 0)
        )
        let step = ScheduleCorrector.tonight(
            goal: goal,
            nights: nights,
            now: date(2026, 9, 13, 21, 0),
            calendar: calendar
        )!
        let span = CircadianRhythm.normalizedHour(step.recommendedWakeHour - step.recommendedOnsetHour)
        XCTAssertEqual(span, 8.0, accuracy: 0.15)
    }

    func testStoreRoundTrip() {
        let suite = "forge.schedule.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let goal = ScheduleGoal(targetWakeHour: 6.5, cutoverStart: date(2026, 9, 14, 0, 0))
        ScheduleGoalStore.save(goal, defaults: defaults)
        let loaded = ScheduleGoalStore.load(defaults: defaults)
        XCTAssertEqual(loaded?.targetWakeHour, 6.5)
        ScheduleGoalStore.clear(defaults: defaults)
        XCTAssertNil(ScheduleGoalStore.load(defaults: defaults))
        defaults.removePersistentDomain(forName: suite)
    }

    func testSignedDeltaPrefersTheShortWayAroundMidnight() {
        XCTAssertEqual(ScheduleCorrector.signedHourDelta(from: 23, to: 1), 2, accuracy: 0.01)
        XCTAssertEqual(ScheduleCorrector.signedHourDelta(from: 1, to: 23), -2, accuracy: 0.01)
    }

    private func habitualNights(
        wakeHour: Double,
        asleep: Double = 8.0,
        count: Int,
        ending: Date
    ) -> [CircadianRhythm.Night] {
        (0..<count).compactMap { offset -> CircadianRhythm.Night? in
            guard let wakeDay = calendar.date(byAdding: .day, value: -(count - 1 - offset), to: ending) else {
                return nil
            }
            var comps = calendar.dateComponents([.year, .month, .day], from: wakeDay)
            let whole = Int(wakeHour)
            comps.hour = whole
            comps.minute = Int(((wakeHour - Double(whole)) * 60).rounded())
            comps.second = 0
            guard let wake = calendar.date(from: comps) else { return nil }
            let onset = wake.addingTimeInterval(-asleep * 3600)
            return CircadianRhythm.Night(onset: onset, wake: wake, asleepHours: asleep)
        }
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}
