import XCTest
@testable import ForgeSwift

final class SleepBedtimeCoachTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testSuggestedTabOpensTonightInTheEvening() {
        XCTAssertEqual(SleepTab.suggested(hour: 21), .night)
        XCTAssertEqual(SleepTab.suggested(hour: 2), .night)
        XCTAssertEqual(SleepTab.suggested(hour: 10), .day)
        XCTAssertEqual(SleepTab.night.title, "Tonight")
    }

    func testFallbackBedtimeUsesOnsetHour() {
        let now = date(2026, 9, 3, 16, 0)
        let coach = SleepBedtimeCoach.make(
            onsets: [],
            sleepMinutes: [],
            fallbackOnsetHour: 22.5,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(coach.phase, .dayplan)
        XCTAssertEqual(calendar.component(.hour, from: coach.bedtime), 22)
        XCTAssertEqual(calendar.component(.minute, from: coach.bedtime), 30)
        XCTAssertEqual(coach.minutesUntilWindDown, 370) // 16:00 → 22:10
    }

    func testWindDownPhaseWhenInsideTheLeadWindow() {
        let now = date(2026, 9, 3, 22, 15)
        let coach = SleepBedtimeCoach.make(
            onsets: [],
            sleepMinutes: [],
            fallbackOnsetHour: 22.5,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(coach.phase, .windDown)
        XCTAssertTrue(coach.headline.localizedCaseInsensitiveContains("winding"))
    }

    func testLightsOutAndOverdue() {
        let lights = SleepBedtimeCoach.make(
            onsets: [],
            sleepMinutes: [],
            fallbackOnsetHour: 22.5,
            now: date(2026, 9, 3, 22, 35),
            calendar: calendar
        )
        XCTAssertEqual(lights.phase, .lightsOut)
        XCTAssertEqual(lights.countdownLabel, "now")

        let late = SleepBedtimeCoach.make(
            onsets: [],
            sleepMinutes: [],
            fallbackOnsetHour: 22.5,
            now: date(2026, 9, 3, 23, 30),
            calendar: calendar
        )
        XCTAssertEqual(late.phase, .overdue)
        XCTAssertTrue(late.ariaPrompt.localizedCaseInsensitiveContains("sleep"))
    }

    func testPredictorOnsetsBeatTheFallbackHour() {
        let now = date(2026, 9, 3, 21, 20)
        let onsets = (0..<5).compactMap { offset -> Date? in
            calendar.date(byAdding: .day, value: -offset, to: date(2026, 9, 3, 23, 0))
        }
        let coach = SleepBedtimeCoach.make(
            onsets: onsets,
            sleepMinutes: Array(repeating: 8 * 60, count: 5),
            needMinutes: 8 * 60,
            fallbackOnsetHour: 21.0,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(calendar.component(.hour, from: coach.bedtime), 23)
        XCTAssertEqual(coach.phase, .approaching, "21:20 is inside 90 minutes of a 22:40 wind-down")
    }

    func testAdvancingKeepsTheSameBedtime() {
        let now = date(2026, 9, 3, 16, 0)
        let coach = SleepBedtimeCoach.make(
            onsets: [],
            sleepMinutes: [],
            fallbackOnsetHour: 22.5,
            now: now,
            calendar: calendar
        )
        let later = coach.advancing(now: date(2026, 9, 3, 22, 40))
        XCTAssertEqual(later.bedtime, coach.bedtime)
        XCTAssertEqual(later.phase, .lightsOut)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}
