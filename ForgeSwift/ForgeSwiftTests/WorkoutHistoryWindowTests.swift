import XCTest
@testable import ForgeSwift

final class WorkoutHistoryWindowTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 15, minute: 30))!
    }

    private func session(id: String, date: String) -> WorkoutHistory {
        WorkoutHistory(
            id: id,
            date: date,
            name: "Session",
            type: .strength,
            duration: 40,
            volume: 0,
            intensity: .moderate
        )
    }

    func testISO8601DefaultFormatterDropsHealthKitDayDates() {
        // The bug: AriaContextStore used ISO8601DateFormatter() which only
        // parses internet datetimes, so HealthKit `yyyy-MM-dd` history
        // vanished from workoutsCompleted30d.
        XCTAssertNil(ISO8601DateFormatter().date(from: "2026-09-20"))
        XCTAssertEqual(
            calendar.component(.day, from: WorkoutHistoryWindow.parseDate("2026-09-20", calendar: calendar)!),
            20
        )
    }

    func testThirtyDayWindowIsInclusiveCalendarDaysNotExclusiveCutoff() {
        let history = [
            session(id: "today", date: "2026-09-29"),
            session(id: "day29", date: "2026-08-31"),
            session(id: "day30", date: "2026-08-30"),
            session(id: "iso", date: "2026-09-10T18:15:00Z"),
        ]

        // Old filter: cutoff = now - 30 days (Aug 30 15:30) and `date > cutoff`.
        // A HealthKit day date of Aug 30 never parsed; Aug 31 00:00 local is
        // inside a true 30-day calendar window (today + previous 29 days).
        XCTAssertEqual(
            WorkoutHistoryWindow.completedCount(
                in: history,
                days: 30,
                now: now,
                calendar: calendar
            ),
            3
        )
        XCTAssertEqual(
            WorkoutHistoryWindow.parseDate("2026-08-31", calendar: calendar),
            calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!)
        )
    }

    func testWorkoutFinishUsesSessionClockNotArrivalTime() {
        let started = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 7, minute: 0))!
        let arrival = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 9, minute: 12))!
        let finished = WorkoutSessionStamp.finishedAt(
            startedAt: started,
            elapsedSeconds: 48 * 60,
            now: arrival
        )
        XCTAssertEqual(finished, started.addingTimeInterval(48 * 60))
        XCTAssertNotEqual(finished, arrival)
        XCTAssertEqual(
            WorkoutSessionStamp.finishedAt(startedAt: nil, elapsedSeconds: 10, now: arrival),
            arrival
        )
    }
}
