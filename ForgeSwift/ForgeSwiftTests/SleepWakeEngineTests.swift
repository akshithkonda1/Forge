import XCTest
@testable import ForgeSwift
import ForgeCore
import UserNotifications

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
        XCTAssertTrue(SleepWakeEngine.isWakeNotification(SleepWakeEngine.failsafeNotificationId(for: id)))
        XCTAssertFalse(SleepWakeEngine.isWakeNotification("forge.weekly.aria"))
        XCTAssertTrue(SleepWakeEngine.canSnooze(count: 0))
        XCTAssertTrue(SleepWakeEngine.canSnooze(count: 1))
        XCTAssertFalse(SleepWakeEngine.canSnooze(count: 2))
        XCTAssertFalse(
            SleepAlarmScheduleMath.isStandingWakeNotification(
                SleepWakeEngine.failsafeNotificationId(for: id)
            )
        )
        XCTAssertFalse(
            SleepAlarmScheduleMath.isStandingWakeNotification(
                SleepWakeEngine.snoozeNotificationId(for: id)
            )
        )
        XCTAssertTrue(
            SleepAlarmScheduleMath.isStandingWakeNotification(
                SleepWakeEngine.hardNotificationId(for: id) + ".2"
            )
        )
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

    func testCoachUsesExplicitAdaptiveWindow() {
        var alarm = weekdayAlarm(hour: 7, minute: 0)
        alarm.isSmartWake = true
        alarm.smartWakeWindow = 15
        let coach = SleepWakeCoach.make(
            alarms: [alarm],
            now: date(2026, 9, 3, 10, 0),
            calendar: calendar,
            smartWindowMinutes: 45
        )
        XCTAssertEqual(calendar.component(.hour, from: coach.smartFire!), 6)
        XCTAssertEqual(calendar.component(.minute, from: coach.smartFire!), 15)
    }

    @MainActor
    func testComputeSmartAlarmWindowDelegatesToCoreMath() {
        let minutes = HealthKitSleepService.shared.computeSmartAlarmWindow(
            baseWindow: 30,
            recentScore: 60,
            debt: 0,
            chronotype: .bear,
            struggleAverageSnoozes: 0
        )
        XCTAssertEqual(minutes, 45)
        let lion = HealthKitSleepService.shared.computeSmartAlarmWindow(
            baseWindow: 30,
            recentScore: 90,
            debt: 0,
            chronotype: .lion,
            struggleAverageSnoozes: 0
        )
        XCTAssertEqual(lion, 15)
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
        dsp.reset(rampSeconds: 1, sound: .gentleRise)
        XCTAssertLessThan(abs(dsp.nextSample()), 0.01)
    }

    func testBackupToneIsLouderAndDistinctFromPickerSounds() {
        XCTAssertNotEqual(
            SleepWakeEscalation.backupFrequencies.0,
            AlarmSoundOption.gentleRise.wakeFrequencies.0
        )
        XCTAssertNotEqual(
            SleepWakeEscalation.backupFrequencies.0,
            AlarmSoundOption.tibetanBell.wakeFrequencies.0
        )
        var dsp = WakeToneDSP()
        dsp.reset(rampSeconds: 60, sound: .gentleRise)
        let quiet = abs(dsp.nextSample())
        dsp.escalateToBackup()
        var peak: Float = 0
        for _ in 0..<2_048 {
            peak = max(peak, abs(dsp.nextSample()))
        }
        XCTAssertGreaterThan(peak, quiet)
        XCTAssertGreaterThan(peak, 0.2)
        XCTAssertLessThanOrEqual(peak, 1)
    }

    func testHeavySleeperEscalationSkipsThePoliteClimb() {
        XCTAssertEqual(
            SleepWakeEscalation.ramp(gradualVolume: true, struggling: true, selected: .gradual),
            .instant
        )
        XCTAssertEqual(
            SleepWakeEscalation.ramp(gradualVolume: true, struggling: false, selected: .gentle),
            .gentle
        )
        XCTAssertEqual(
            SleepWakeEscalation.stage(elapsed: 0, rampSeconds: 60, struggling: false),
            .primary
        )
        XCTAssertEqual(
            SleepWakeEscalation.stage(elapsed: 20, rampSeconds: 15, struggling: false),
            .backup
        )
        XCTAssertEqual(
            SleepWakeEscalation.stage(elapsed: 8, rampSeconds: 60, struggling: true),
            .backup
        )
        XCTAssertEqual(
            SleepWakeEscalation.stage(elapsed: 20, rampSeconds: 60, struggling: true),
            .insistent
        )
        XCTAssertNil(SleepWakeEscalation.hapticCadenceSeconds(stage: .primary, faulted: false))
        XCTAssertEqual(SleepWakeEscalation.hapticCadenceSeconds(stage: .primary, faulted: true), 0.9)
        XCTAssertEqual(SleepWakeEscalation.hapticCadenceSeconds(stage: .insistent, faulted: false), 1.0)
    }

    func testDeliveryFailClosesWhenNotificationsCannotWake() {
        XCTAssertEqual(
            SleepAlarmScheduleMath.delivery(
                authorization: .denied,
                timeSensitive: .enabled,
                expected: 5,
                pending: 0,
                addFailures: 0,
                authError: nil
            ),
            .notificationsOff
        )
        XCTAssertEqual(
            SleepAlarmScheduleMath.delivery(
                authorization: .provisional,
                timeSensitive: .enabled,
                expected: 5,
                pending: 5,
                addFailures: 0,
                authError: nil
            ),
            .quietDelivery
        )
        XCTAssertTrue(
            SleepAlarmScheduleMath.delivery(
                authorization: .authorized,
                timeSensitive: .enabled,
                expected: 7,
                pending: 2,
                addFailures: 0,
                authError: nil
            ).isFailClosed
        )
        let armed = SleepAlarmScheduleMath.delivery(
            authorization: .authorized,
            timeSensitive: .enabled,
            expected: 7,
            pending: 7,
            addFailures: 0,
            authError: nil
        )
        XCTAssertEqual(armed, .armed(pending: 7, timeSensitive: true))
        XCTAssertFalse(armed.isFailClosed)
        let focus = SleepAlarmScheduleMath.delivery(
            authorization: .authorized,
            timeSensitive: .disabled,
            expected: 7,
            pending: 7,
            addFailures: 0,
            authError: nil
        )
        XCTAssertEqual(focus, .armed(pending: 7, timeSensitive: false))
        XCTAssertTrue(focus.needsAttention)
        XCTAssertFalse(focus.isFailClosed)
    }

    func testExpectedPendingCountCountsHardAndSmartWeekdays() {
        var weekdays = weekdayAlarm(hour: 7, minute: 0)
        weekdays.isSmartWake = false
        XCTAssertEqual(SleepAlarmScheduleMath.expectedPendingCount(in: [weekdays]), 5)
        weekdays.isSmartWake = true
        XCTAssertEqual(SleepAlarmScheduleMath.expectedPendingCount(in: [weekdays]), 10)
        weekdays.isEnabled = false
        XCTAssertEqual(SleepAlarmScheduleMath.expectedPendingCount(in: [weekdays]), 0)
        var everyday = weekdayAlarm(hour: 8, minute: 0)
        everyday.days = []
        everyday.isSmartWake = false
        XCTAssertEqual(SleepAlarmScheduleMath.expectedPendingCount(in: [everyday]), 7)
    }

    func testWakeUsesPublicAPIsAlreadyInTheForgeTree() {
        XCTAssertFalse(SleepAlarmAppleAPI.authorizationOptions.contains(.criticalAlert))
        XCTAssertTrue(SleepAlarmAppleAPI.authorizationOptions.contains(.alert))
        XCTAssertTrue(SleepAlarmAppleAPI.authorizationOptions.contains(.sound))
        XCTAssertTrue(SleepAlarmAppleAPI.authorizationOptions.contains(.badge))
        XCTAssertEqual(SleepAlarmAppleAPI.interruptionLevel, .timeSensitive)
        XCTAssertEqual(SleepAlarmAppleAPI.failsafePingSeconds, 60)
        XCTAssertEqual(SleepAlarmAppleAPI.playbackSession, .alarm)
        XCTAssertEqual(SleepAlarmAppleAPI.backgroundAudioMode, "audio")

        let info = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ForgeSwift/Info-Add.plist")
        let text = (try? String(contentsOf: info, encoding: .utf8)) ?? ""
        XCTAssertTrue(text.contains("<string>audio</string>"), "Wake tone needs UIBackgroundModes audio")
        XCTAssertFalse(text.contains("critical-alerts"))
        let entitlements = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ForgeSwift/ForgeSwift.entitlements")
        let entitlementText = (try? String(contentsOf: entitlements, encoding: .utf8)) ?? ""
        XCTAssertFalse(entitlementText.contains("alarmkit"))
        XCTAssertFalse(entitlementText.contains("critical-alerts"))
        XCTAssertTrue(entitlementText.contains("healthkit"))
    }

    func testReliabilityCopyStaysLifestyleNotClinical() {
        let lines = [
            SleepAlarmDelivery.notificationsOff.headline,
            SleepAlarmDelivery.notificationsOff.cue,
            SleepAlarmDelivery.quietDelivery.headline,
            SleepWakeAudioFault.sessionDropped.coachLine,
            SleepWakeAudioFault.sessionActivateFailed.coachLine,
            SleepAlarmDelivery.armed(pending: 5, timeSensitive: true).cue
        ]
        for line in lines {
            let lower = line.lowercased()
            XCTAssertFalse(lower.contains("insomnia"), line)
            XCTAssertFalse(lower.contains("treat"), line)
            XCTAssertFalse(lower.contains("diagnos"), line)
            XCTAssertFalse(lower.contains("medical"), line)
            XCTAssertFalse(lower.contains("disorder"), line)
        }
    }

    func testAlarmSoundsHaveDistinctWakeFrequencies() {
        XCTAssertNotEqual(
            AlarmSoundOption.gentleRise.wakeFrequencies.0,
            AlarmSoundOption.tibetanBell.wakeFrequencies.0
        )
        var dsp = WakeToneDSP()
        dsp.reset(rampSeconds: 0.01, sound: .oceanWaves)
        var last: Float = 0
        for _ in 0..<400 { last = dsp.nextSample() }
        XCTAssertLessThanOrEqual(abs(last), 1)
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
