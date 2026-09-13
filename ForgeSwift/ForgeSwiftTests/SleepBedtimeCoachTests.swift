import XCTest
@testable import ForgeSwift
import ForgeCore

final class SleepBedtimeCoachTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testSuggestedTabOpensTonightInTheEvening() {
        XCTAssertEqual(SleepTab.suggested(hour: 21), .night)
        XCTAssertEqual(SleepTab.suggested(hour: 2), .night)
        XCTAssertEqual(SleepTab.suggested(hour: 7), .alarms)
        XCTAssertEqual(SleepTab.suggested(hour: 10), .day)
        XCTAssertEqual(SleepTab.night.title, "Tonight")
        XCTAssertEqual(SleepTab.alarms.title, "Wake")
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

    func testCorrectionOverridesPredictorBedtimeAndSurvivesAdvancing() {
        let now = date(2026, 9, 13, 16, 0)
        let correction = ScheduleCorrectionStep(
            recommendedWakeHour: 7.75,
            recommendedOnsetHour: 23.0,
            shiftMinutesTonight: -15,
            remainingGapMinutes: 105,
            nightsRemainingEstimate: 8,
            reachedTarget: false,
            currentWakeHour: 8.0,
            confidence: 0.9,
            targetWakeHour: 6.0
        )
        let coach = SleepBedtimeCoach.make(
            onsets: [],
            sleepMinutes: [],
            fallbackOnsetHour: 22.5,
            now: now,
            calendar: calendar,
            correction: correction
        )
        XCTAssertEqual(calendar.component(.hour, from: coach.bedtime), 23)
        XCTAssertEqual(calendar.component(.minute, from: coach.bedtime), 0)
        XCTAssertTrue(coach.cue.contains("earlier"), coach.cue)
        let later = coach.advancing(now: date(2026, 9, 13, 21, 0))
        XCTAssertEqual(later.bedtime, coach.bedtime)
        XCTAssertTrue(later.cue.contains("earlier"), later.cue)
    }

    func testMakeFromHistoryUsesSavedGoal() {
        let suite = "forge.coach.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let nights: [SleepData] = (0..<7).map { offset in
            let wake = date(2026, 9, 13 - offset, 8, 0)
            return SleepData(
                date: String(format: "2026-09-%02d", 13 - offset),
                totalHours: 8,
                deepMinutes: 90,
                remMinutes: 90,
                lightMinutes: 240,
                awakeMinutes: 20,
                score: 80,
                onset: wake.addingTimeInterval(-8 * 3600),
                wake: wake
            )
        }
        ScheduleGoalStore.save(
            ScheduleGoal(
                targetWakeHour: 6.0,
                cutoverStart: date(2026, 9, 1, 0, 0)
            ),
            defaults: defaults
        )
        let coach = SleepBedtimeCoach.make(
            from: nights,
            now: date(2026, 9, 13, 16, 0),
            calendar: calendar,
            defaults: defaults
        )
        XCTAssertTrue(coach.cue.contains("earlier") || coach.cue.contains("Shifting"), coach.cue)
        XCTAssertFalse(coach.scheduleNote.isEmpty)
    }

    func testDayEmptyCopyIsHonestWhenHealthIsConnected() {
        let connected = HealthKitSleepService.dayEmptyCopy(healthConnected: true)
        XCTAssertEqual(connected.title, "No scored night yet")
        XCTAssertTrue(connected.message.localizedCaseInsensitiveContains("in-bed"))
        XCTAssertFalse(connected.message.localizedCaseInsensitiveContains("reconnect"))
        XCTAssertEqual(connected.cta, "Refresh from Apple Health")

        let disconnected = HealthKitSleepService.dayEmptyCopy(healthConnected: false)
        XCTAssertEqual(disconnected.title, "Connect Apple Health to unlock sleep")
        XCTAssertEqual(disconnected.cta, "Reconnect Apple Health")
    }

    func testInBedWindowIsHoursNotAScore() {
        let start = Date(timeIntervalSince1970: 0)
        let window = InBedWindow(start: start, end: start.addingTimeInterval(7.5 * 3600))
        XCTAssertEqual(window.hours, 7.5, accuracy: 0.01)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}
