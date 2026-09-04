import XCTest
@testable import ForgeSwift

final class SleepWakeEngineTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testDisabledAlarmNeverFires() {
        var alarm = weekdayAlarm(hour: 7, minute: 0)
        alarm.isEnabled = false
        XCTAssertNil(SleepWakeEngine.nextHardFire(alarm: alarm, now: date(2026, 9, 3, 6, 0), calendar: calendar))
    }

    func testEmptyDaysMeansEveryDay() {
        var alarm = weekdayAlarm(hour: 8, minute: 0)
        alarm.days = []
        let thursday = date(2026, 9, 3, 9, 0) // Thursday
        let fire = SleepWakeEngine.nextHardFire(alarm: alarm, now: thursday, calendar: calendar)
        XCTAssertEqual(calendar.component(.weekday, from: fire!), 6) // Friday
        XCTAssertEqual(calendar.component(.hour, from: fire!), 8)
    }

    func testWeekdayAlarmSkipsWeekend() {
        let alarm = weekdayAlarm(hour: 7, minute: 0)
        let saturday = date(2026, 9, 5, 10, 0)
        let fire = SleepWakeEngine.nextHardFire(alarm: alarm, now: saturday, calendar: calendar)!
        XCTAssertEqual(calendar.component(.weekday, from: fire), 2) // Monday
        XCTAssertEqual(calendar.component(.hour, from: fire), 7)
        XCTAssertEqual(calendar.component(.day, from: fire), 7)
    }

    func testNextAlarmPicksTheSoonestEnabled() {
        let late = weekdayAlarm(hour: 8, minute: 0)
        var early = weekdayAlarm(hour: 6, minute: 30)
        early.id = UUID()
        var off = weekdayAlarm(hour: 6, minute: 0)
        off.id = UUID()
        off.isEnabled = false
        let now = date(2026, 9, 3, 5, 0)
        let next = SleepWakeEngine.nextAlarm(in: [late, early, off], now: now, calendar: calendar)
        XCTAssertEqual(next?.id, early.id)
    }

    func testSmartWakeLeadAndMidnightWrap() {
        let hard = date(2026, 9, 4, 0, 15)
        let smart = SleepWakeEngine.smartWakeFire(hard: hard, windowMinutes: 30)
        XCTAssertEqual(calendar.component(.hour, from: smart), 23)
        XCTAssertEqual(calendar.component(.minute, from: smart), 45)
        XCTAssertEqual(calendar.component(.day, from: smart), 3)

        let clock = SleepWakeEngine.repeatingSmartClock(
            weekday: 5, // Thursday 00:15 → Wednesday 23:45
            hour: 0,
            minute: 15,
            windowMinutes: 30,
            now: date(2026, 9, 3, 12, 0),
            calendar: calendar
        )
        XCTAssertEqual(clock.weekday, 4)
        XCTAssertEqual(clock.hour, 23)
        XCTAssertEqual(clock.minute, 45)
    }

    func testSameDaySmartClockDoesNotChangeWeekday() {
        let clock = SleepWakeEngine.repeatingSmartClock(
            weekday: 2,
            hour: 7,
            minute: 0,
            windowMinutes: 30,
            now: date(2026, 9, 7, 12, 0), // Monday
            calendar: calendar
        )
        XCTAssertEqual(clock.weekday, 2)
        XCTAssertEqual(clock.hour, 6)
        XCTAssertEqual(clock.minute, 30)
    }

    func testNotificationIdsStayInWakeNamespace() {
        let id = UUID()
        XCTAssertTrue(SleepWakeEngine.isWakeNotification(SleepWakeEngine.hardNotificationId(for: id)))
        XCTAssertTrue(SleepWakeEngine.isWakeNotification(SleepWakeEngine.smartNotificationId(for: id)))
        XCTAssertTrue(SleepWakeEngine.isWakeNotification(SleepWakeEngine.snoozeNotificationId(for: id)))
        XCTAssertFalse(SleepWakeEngine.isWakeNotification("forge.weekly.aria"))
        XCTAssertTrue(SleepWakeEngine.canSnooze(count: 0))
        XCTAssertTrue(SleepWakeEngine.canSnooze(count: 1))
        XCTAssertFalse(SleepWakeEngine.canSnooze(count: 2))
    }

    func testCoachPhasesAndMissingSleepCopy() {
        let alarm = weekdayAlarm(hour: 7, minute: 0)
        let waiting = SleepWakeCoach.make(
            alarms: [alarm],
            now: date(2026, 9, 3, 10, 0),
            calendar: calendar
        )
        XCTAssertEqual(waiting.phase, .waiting)
        XCTAssertEqual(calendar.component(.hour, from: waiting.hardFire!), 7)

        let approaching = SleepWakeCoach.make(
            alarms: [alarm],
            now: date(2026, 9, 4, 6, 0),
            calendar: calendar
        )
        XCTAssertEqual(approaching.phase, .approaching)
        XCTAssertEqual(approaching.minutesUntilHard, 60)

        let window = SleepWakeCoach.make(
            alarms: [alarm],
            now: date(2026, 9, 4, 6, 40),
            calendar: calendar
        )
        XCTAssertEqual(window.phase, .windowOpen)

        let due = SleepWakeCoach.make(
            alarms: [alarm],
            now: date(2026, 9, 4, 7, 0),
            calendar: calendar
        )
        XCTAssertEqual(due.phase, .due)
        XCTAssertTrue(due.ariaPrompt.localizedCaseInsensitiveContains("unavailable"))
    }

    func testMorningPromptUsesScoreWhenPresent() {
        let prompt = SleepWakeCoach.morningPrompt(sleepScore: 82, lastNightHours: 7.4)
        XCTAssertTrue(prompt.contains("82"))
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("unavailable"))
    }

    func testCountdownLabel() {
        let now = date(2026, 9, 3, 6, 0)
        XCTAssertEqual(
            SleepWakeEngine.countdownLabel(until: date(2026, 9, 3, 6, 20), now: now),
            "in 20 min"
        )
        XCTAssertEqual(
            SleepWakeEngine.countdownLabel(until: date(2026, 9, 3, 8, 15), now: now),
            "in 2h 15m"
        )
    }

    func testSoundLibraryHasNamedBedsNotJustBrown() {
        XCTAssertEqual(SleepSoundKind.allCases.count, 16)
        XCTAssertEqual(
            Set(SleepSoundKind.tonightPicks),
            [.cafe, .brown, .white, .lofi]
        )
        XCTAssertEqual(SleepSoundKind.cafe.displayName, "Café")
        XCTAssertEqual(SleepSoundKind.white.displayName, "White Noise")
        XCTAssertEqual(SleepSoundKind.lofi.displayName, "Lo-Fi Beats")
        XCTAssertEqual(SleepSoundKind.brown.category, .noise)
        XCTAssertEqual(SleepSoundKind.cafe.category, .ambient)
        XCTAssertEqual(SleepSoundKind.lofi.category, .focus)
        XCTAssertEqual(SleepSoundKind.rain.category, .nature)
        for kind in SleepSoundKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty, kind.rawValue)
            XCTAssertFalse(kind.blurb.isEmpty, kind.rawValue)
            XCTAssertFalse(kind.icon.isEmpty, kind.rawValue)
        }
        XCTAssertEqual(allSleepSounds.count, SleepSoundKind.allCases.count)
        XCTAssertEqual(Set(SleepSoundKind.allCases.map(\.category)), Set(SleepSoundCategory.allCases))
        XCTAssertEqual(SleepSoundKind.storageKey, "forge.sleep.sound.kind.v1")
    }

    func testSoundscapeSamplesStayInUnitRange() {
        for kind in SleepSoundKind.allCases {
            var dsp = SoundscapeDSP()
            dsp.reset(kind: kind)
            for _ in 0..<2_048 {
                let sample = dsp.nextSample()
                XCTAssertGreaterThanOrEqual(sample, -1, kind.rawValue)
                XCTAssertLessThanOrEqual(sample, 1, kind.rawValue)
            }
        }
    }

    func testSoundscapeIsDeterministicForAKind() {
        var a = SoundscapeDSP()
        a.reset(kind: .lofi)
        var b = SoundscapeDSP()
        b.reset(kind: .lofi)
        let left = (0..<256).map { _ in a.nextSample() }
        let right = (0..<256).map { _ in b.nextSample() }
        XCTAssertEqual(left, right)
    }

    func testRendererMatchesDirectDSP() {
        var dsp = SoundscapeDSP()
        dsp.reset(kind: .brown)
        let renderer = SoundscapeRenderer()
        renderer.reset(kind: .brown)
        var buffer = [Float](repeating: 0, count: 128)
        buffer.withUnsafeMutableBufferPointer { ptr in
            renderer.render(into: ptr.baseAddress!, frames: 128)
        }
        let expected = (0..<128).map { _ in dsp.nextSample() }
        XCTAssertEqual(buffer, expected)
    }

    func testWakeToneRampsFromSilence() {
        var dsp = WakeToneDSP()
        dsp.reset(rampSeconds: 1)
        XCTAssertLessThan(abs(dsp.nextSample()), 0.01)
    }

    func testPersistedKindRoundTripsThroughStorageKey() {
        let previous = UserDefaults.standard.string(forKey: SleepSoundKind.storageKey)
        SleepSoundKind.cafe.persist()
        XCTAssertEqual(SleepSoundKind.stored, .cafe)
        if let previous {
            UserDefaults.standard.set(previous, forKey: SleepSoundKind.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: SleepSoundKind.storageKey)
        }
    }

    private func weekdayAlarm(hour: Int, minute: Int) -> ForgeAlarm {
        ForgeAlarm(
            label: "Weekdays",
            time: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour, minute: minute))!,
            days: [2, 3, 4, 5, 6],
            isEnabled: true
        )
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}
