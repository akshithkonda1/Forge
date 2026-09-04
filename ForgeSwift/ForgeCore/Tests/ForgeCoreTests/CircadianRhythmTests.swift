import XCTest
@testable import ForgeCore

/// The failure mode of this engine is not a crash — it is confidently telling
/// someone their afternoon slump is at 4am, or that they are eleven hours in
/// debt when they slept fine. Every test here is aimed at a wrong answer that
/// would look plausible on screen.
final class CircadianRhythmTests: XCTestCase {

    // MARK: - Helpers

    /// Pinned to UTC. These fixtures sit in March, and in a DST-observing zone
    /// the spring-forward night makes 02:00 a time that does not exist —
    /// Foundation quietly resolves it to 03:00 and the phase estimate shifts by
    /// an hour for reasons no assertion would explain.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    /// A night that starts the evening of `day` and ends the following morning.
    private func night(day: Int,
                       onsetHour: Int,
                       onsetMinute: Int = 0,
                       wakeHour: Int,
                       wakeMinute: Int = 0,
                       asleepHours: Double? = nil) -> CircadianRhythm.Night {
        // Onset at or after 20:00 belongs to the evening of `day`; anything
        // earlier on the clock is already past midnight.
        let onset = date(day: onsetHour >= 12 ? day : day + 1, hour: onsetHour, minute: onsetMinute)
        let wake = date(day: day + 1, hour: wakeHour, minute: wakeMinute)
        let inBed = wake.timeIntervalSince(onset) / 3600
        return CircadianRhythm.Night(onset: onset,
                                     wake: wake,
                                     asleepHours: asleepHours ?? inBed)
    }

    /// Fourteen identical nights — the regular sleeper the model is easiest to
    /// reason about, used as the baseline for most assertions.
    private func regularNights(onsetHour: Int = 23,
                               wakeHour: Int = 7,
                               asleepHours: Double = 7.5) -> [CircadianRhythm.Night] {
        (1...14).map { night(day: $0, onsetHour: onsetHour, wakeHour: wakeHour, asleepHours: asleepHours) }
    }

    // MARK: - Clock arithmetic

    func testNormalizedHourWrapsNegatives() {
        XCTAssertEqual(CircadianRhythm.normalizedHour(-1.5), 22.5, accuracy: 0.0001)
        XCTAssertEqual(CircadianRhythm.normalizedHour(25), 1, accuracy: 0.0001)
        XCTAssertEqual(CircadianRhythm.normalizedHour(-26), 22, accuracy: 0.0001)
        XCTAssertEqual(CircadianRhythm.normalizedHour(0), 0, accuracy: 0.0001)
    }

    /// The bug this whole approach exists to avoid: 23:30 and 00:30 average to
    /// midnight, but arithmetic on 23.5 and 0.5 gives noon — twelve hours wrong,
    /// and wrong in the direction that inverts the entire day.
    func testCircularMeanCrossesMidnight() {
        let mean = CircadianRhythm.circularMean([23.5, 0.5])
        XCTAssertEqual(min(mean, 24 - mean), 0, accuracy: 0.01,
                       "23:30 and 00:30 must average to midnight, not noon")
    }

    func testCircularMeanMatchesArithmeticMeanAwayFromMidnight() {
        XCTAssertEqual(CircadianRhythm.circularMean([6, 7, 8]), 7, accuracy: 0.01)
        XCTAssertEqual(CircadianRhythm.circularMean([7, 7, 7]), 7, accuracy: 0.01)
    }

    func testCircularSpreadIsZeroForIdenticalTimesAndGrowsWithScatter() {
        XCTAssertEqual(CircadianRhythm.circularSpread([7, 7, 7, 7]), 0, accuracy: 0.01)

        let tight = CircadianRhythm.circularSpread([6.5, 7, 7.5])
        let loose = CircadianRhythm.circularSpread([4, 7, 11])
        XCTAssertLessThan(tight, loose)
        XCTAssertGreaterThan(tight, 0)
    }

    /// Spread must not blow up merely because the times straddle midnight.
    func testCircularSpreadHandlesMidnightStraddle() {
        let straddling = CircadianRhythm.circularSpread([23.5, 0, 0.5])
        let equivalent = CircadianRhythm.circularSpread([11.5, 12, 12.5])
        XCTAssertEqual(straddling, equivalent, accuracy: 0.01)
    }

    // MARK: - Sleep need

    func testSleepNeedFallsBackToDefaultBelowFiveNights() {
        let sparse = (1...4).map { night(day: $0, onsetHour: 23, wakeHour: 7, asleepHours: 5.0) }
        XCTAssertEqual(CircadianRhythm.sleepNeedHours(from: sparse),
                       CircadianRhythm.defaultSleepNeedHours,
                       "four nights of 5h must not be read as a 6.5h need")
    }

    func testSleepNeedIsClampedToPhysiologicalRange() {
        let marathon = regularNights(asleepHours: 13)
        XCTAssertEqual(CircadianRhythm.sleepNeedHours(from: marathon),
                       CircadianRhythm.maxSleepNeedHours,
                       "a fortnight of 13h nights is a sensor or an illness, not a need")

        let deprived = regularNights(asleepHours: 4)
        XCTAssertEqual(CircadianRhythm.sleepNeedHours(from: deprived),
                       CircadianRhythm.minSleepNeedHours,
                       "chronic deprivation must not be mistaken for a low need")
    }

    /// The reason a percentile is used rather than a mean: someone whose
    /// weeknights are short but whose weekends are not needs the weekend number.
    func testSleepNeedUsesUpperTailNotTheMean() {
        var nights = (1...10).map { night(day: $0, onsetHour: 23, wakeHour: 7, asleepHours: 6.0) }
        nights += (11...14).map { night(day: $0, onsetHour: 23, wakeHour: 7, asleepHours: 8.6) }

        let need = CircadianRhythm.sleepNeedHours(from: nights)
        let mean = nights.map(\.asleepHours).reduce(0, +) / Double(nights.count)
        XCTAssertGreaterThan(need, mean, "the mean of a deprived person is their deprivation")
        XCTAssertEqual(need, 8.6, accuracy: 0.01)
    }

    func testSleepNeedIgnoresNapSizedFragments() {
        var nights = regularNights(asleepHours: 8.0)
        nights.append(night(day: 20, onsetHour: 23, wakeHour: 7, asleepHours: 0.4))
        XCTAssertEqual(CircadianRhythm.sleepNeedHours(from: nights), 8.0, accuracy: 0.01)
    }

    // MARK: - Sleep debt

    func testDebtCountsOnlyShortfalls() {
        let nights = [
            night(day: 1, onsetHour: 23, wakeHour: 7, asleepHours: 6.0),   // 2h short
            night(day: 2, onsetHour: 23, wakeHour: 7, asleepHours: 7.5),   // 0.5h short
            night(day: 3, onsetHour: 23, wakeHour: 7, asleepHours: 8.0),   // even
        ]
        XCTAssertEqual(CircadianRhythm.sleepDebtHours(nights: nights, need: 8.0), 2.5, accuracy: 0.01)
    }

    /// A debt figure you can pay forward invites exactly the behaviour it exists
    /// to discourage: a long lie-in does not buy a licence for Monday.
    func testSurplusSleepDoesNotBankCredit() {
        let nights = [
            night(day: 1, onsetHour: 22, wakeHour: 10, asleepHours: 11.0),  // 3h over
            night(day: 2, onsetHour: 23, wakeHour: 7, asleepHours: 6.0),    // 2h short
        ]
        XCTAssertEqual(CircadianRhythm.sleepDebtHours(nights: nights, need: 8.0), 2.0, accuracy: 0.01,
                       "the surplus night must not cancel the short one")
    }

    func testDebtWindowDropsOlderNights() {
        // Twenty short nights, but only the last fourteen should count.
        let nights = (1...20).map { night(day: $0, onsetHour: 23, wakeHour: 7, asleepHours: 7.0) }
        XCTAssertEqual(CircadianRhythm.sleepDebtHours(nights: nights, need: 8.0), 14.0, accuracy: 0.01)
    }

    func testDebtIsZeroWithoutNights() {
        XCTAssertEqual(CircadianRhythm.sleepDebtHours(nights: [], need: 8.0), 0)
    }

    // MARK: - Phase

    func testPhaseIsNilWithoutNights() {
        XCTAssertNil(CircadianRhythm.phase(from: [], calendar: calendar))
    }

    func testPhaseRecoversHabitualWakeAndOnset() {
        let phase = CircadianRhythm.phase(from: regularNights(onsetHour: 23, wakeHour: 7),
                                          calendar: calendar)!
        XCTAssertEqual(phase.wakeHour, 7, accuracy: 0.05)
        XCTAssertEqual(phase.onsetHour, 23, accuracy: 0.05)
        XCTAssertGreaterThan(phase.confidence, 0.95, "identical nights are maximally confident")
    }

    func testPhaseHandlesPostMidnightOnsets() {
        // Bed at 00:30, up at 08:30 — onset is on the far side of midnight.
        let nights = (1...14).map {
            night(day: $0, onsetHour: 0, onsetMinute: 30, wakeHour: 8, wakeMinute: 30)
        }
        let phase = CircadianRhythm.phase(from: nights, calendar: calendar)!
        XCTAssertEqual(phase.onsetHour, 0.5, accuracy: 0.05,
                       "a 00:30 bedtime is 00:30, not 12:30")
        XCTAssertEqual(phase.wakeHour, 8.5, accuracy: 0.05)
    }

    func testCircularSpreadDoesNotInvertAcrossMidnight() {
        // 23:30 and 00:30 are an hour apart. Arithmetic on 23.5 and 0.5
        // pretends they are half a day apart.
        let spread = CircadianRhythm.circularSpread([23.5, 0.5])
        XCTAssertEqual(spread, 0.5, accuracy: 0.05)
        XCTAssertLessThan(spread, 2)
    }

    /// A rotating-shift worker has no stable phase. Saying so is the correct
    /// output; drawing them a confident curve is not.
    func testErraticScheduleReportsLowConfidence() {
        let steady = CircadianRhythm.phase(from: regularNights(), calendar: calendar)!
        let scattered = (1...14).map { day -> CircadianRhythm.Night in
            let wake = [4, 7, 11, 15, 9, 6, 13][day % 7]
            return night(day: day, onsetHour: 22, wakeHour: wake, asleepHours: 7)
        }
        let shift = CircadianRhythm.phase(from: scattered, calendar: calendar)!
        XCTAssertLessThan(shift.confidence, steady.confidence)
        XCTAssertLessThan(shift.confidence, 0.5)
    }

    func testPhaseUsesOnlyTheRecentWindow() {
        // Thirty nights: the first sixteen on an old schedule, the last fourteen
        // on a new one. Only the new schedule should show up.
        var nights = (1...16).map { night(day: $0, onsetHour: 2, wakeHour: 10) }
        nights += (17...30).map { night(day: $0, onsetHour: 22, wakeHour: 6) }

        let phase = CircadianRhythm.phase(from: nights, calendar: calendar)!
        XCTAssertEqual(phase.wakeHour, 6, accuracy: 0.05, "a schedule change should take effect")
    }

    // MARK: - Hours awake

    func testHoursAwakeCountsFromWakeAndDecaysOvernight() {
        let phase = CircadianRhythm.Phase(wakeHour: 7, onsetHour: 23, confidence: 1)

        XCTAssertEqual(CircadianRhythm.hoursAwake(atHour: 7, phase: phase), 0, accuracy: 0.01)
        XCTAssertEqual(CircadianRhythm.hoursAwake(atHour: 15, phase: phase), 8, accuracy: 0.01)
        XCTAssertEqual(CircadianRhythm.hoursAwake(atHour: 23, phase: phase), 16, accuracy: 0.01)

        // Asleep: pressure is being paid down, so the figure falls rather than
        // climbing past sixteen all night.
        let earlyNight = CircadianRhythm.hoursAwake(atHour: 1, phase: phase)
        let lateNight = CircadianRhythm.hoursAwake(atHour: 5, phase: phase)
        XCTAssertLessThan(earlyNight, 16)
        XCTAssertLessThan(lateNight, earlyNight)
        XCTAssertGreaterThanOrEqual(lateNight, 0)
    }

    // MARK: - The curve

    /// RISE's signature claim, and the one most likely to be quietly wrong: the
    /// mid-afternoon slump has to actually exist in the numbers, not just in a
    /// label pinned to the chart.
    func testAfternoonDipIsRealAndSitsBetweenTwoPeaks() {
        let phase = CircadianRhythm.Phase(wakeHour: 7, onsetHour: 23, confidence: 1)
        let waking = CircadianRhythm.curve(phase: phase, samplesPerHour: 12)
            .filter { $0.hour >= 7 && $0.hour <= 23 }

        // Morning crest, the trough after it, then the evening crest.
        let dip = waking.filter { $0.hour >= 12 && $0.hour <= 16 }.min { $0.energy < $1.energy }!
        let morning = waking.filter { $0.hour < dip.hour }.max { $0.energy < $1.energy }!
        let evening = waking.filter { $0.hour > dip.hour }.max { $0.energy < $1.energy }!

        XCTAssertLessThan(dip.energy, morning.energy, "no dip after the morning peak")
        XCTAssertLessThan(dip.energy, evening.energy, "no recovery into the evening")
        XCTAssertGreaterThan(dip.hour, 12.5)
        XCTAssertLessThan(dip.hour, 15.5)
        XCTAssertGreaterThan(evening.hour, 16, "the second wind belongs in the evening")
    }

    /// The dip is anchored to wake, not to a wall-clock hour. Someone up at 5am
    /// slumps before lunch, and telling them 3pm would be worse than saying
    /// nothing.
    func testDipTracksWakeTimeForEarlyRiserAndNightOwl() {
        // The first local minimum of the waking day: a sample lower than the one
        // before it and no higher than the one after.
        //
        // Deliberately not a global minimum over the morning — that finds
        // wake-up, which is lower than the dip and is not a dip. A slump is a
        // fall between two rises, so the test looks for exactly that shape.
        func dipClockHour(wake: Double, onset: Double) -> Double? {
            let phase = CircadianRhythm.Phase(wakeHour: wake, onsetHour: onset, confidence: 1)
            let day = CircadianRhythm.curve(phase: phase, samplesPerHour: 12)
                .map { (offset: CircadianRhythm.normalizedHour($0.hour - wake),
                        hour: $0.hour,
                        energy: $0.energy) }
                .sorted { $0.offset < $1.offset }

            for index in 1..<(day.count - 1) {
                let sample = day[index]
                guard sample.offset > 2, sample.offset < 12 else { continue }
                if sample.energy < day[index - 1].energy, sample.energy <= day[index + 1].energy {
                    return sample.hour
                }
            }
            return nil
        }

        guard let lark = dipClockHour(wake: 5, onset: 21),
              let owl = dipClockHour(wake: 10, onset: 2) else {
            return XCTFail("no slump between the morning and evening crests")
        }

        XCTAssertEqual(CircadianRhythm.normalizedHour(lark - 5),
                       CircadianRhythm.dipHoursAfterWake, accuracy: 0.75)
        XCTAssertEqual(CircadianRhythm.normalizedHour(owl - 10),
                       CircadianRhythm.dipHoursAfterWake, accuracy: 0.75)
        XCTAssertNotEqual(lark, owl, "the dip is not a fixed clock hour")
    }

    /// Overnight, `hoursAwake` is a decaying residue rather than elapsed time,
    /// and it sweeps back down through the dip's centre in the small hours.
    /// Anchoring the dip to it would carve a second slump into the middle of the
    /// night, in the exact stretch the UI presents as restorative.
    func testNoPhantomDipDuringTheSleepWindow() {
        let phase = CircadianRhythm.Phase(wakeHour: 7, onsetHour: 23, confidence: 1)

        // Bed at 23:00 means pressure decays from 16h, passing back down through
        // 7.5 about 3h10m later. Anchored to `hoursAwake`, the dip's centre would
        // land there — roughly 02:10 — instead of at the circadian nadir, which
        // for a 07:00 riser is 05:00.
        let overnight = CircadianRhythm.curve(phase: phase, samplesPerHour: 12)
            .filter { $0.hour >= 23 || $0.hour <= 5 }
        let deepest = overnight.min { $0.energy < $1.energy }!

        XCTAssertGreaterThan(deepest.hour, 3.0,
                             "the night's low point is at \(deepest.hour):00, near where a "
                             + "pressure-anchored dip would sit rather than at the nadir")
        XCTAssertLessThanOrEqual(deepest.hour, 5.0)
    }

    func testEnergyStaysInUnitRange() {
        for wake in stride(from: 4.0, through: 11.0, by: 0.5) {
            let phase = CircadianRhythm.Phase(wakeHour: wake,
                                              onsetHour: CircadianRhythm.normalizedHour(wake + 16),
                                              confidence: 1)
            for debt in [0.0, 5.0, 20.0, 100.0] {
                for sample in CircadianRhythm.curve(phase: phase, sleepDebtHours: debt) {
                    XCTAssertGreaterThanOrEqual(sample.energy, 0)
                    XCTAssertLessThanOrEqual(sample.energy, 1)
                }
            }
        }
    }

    /// Debt lowers the whole day rather than rearranging it — which is what
    /// being tired actually feels like. If debt moved the peaks, the schedule
    /// would reshuffle itself every morning for no reason the user could see.
    func testDebtLowersTheCurveWithoutMovingItsPeaks() {
        let phase = CircadianRhythm.Phase(wakeHour: 7, onsetHour: 23, confidence: 1)
        let rested = CircadianRhythm.curve(phase: phase, sleepDebtHours: 0, samplesPerHour: 12)
        let tired = CircadianRhythm.curve(phase: phase, sleepDebtHours: 12, samplesPerHour: 12)

        XCTAssertEqual(rested.count, tired.count)
        for (a, b) in zip(rested, tired) where a.energy > 0.25 {
            XCTAssertLessThan(b.energy, a.energy, "debt must cost something at \(a.hour):00")
        }

        let restedPeak = rested.max { $0.energy < $1.energy }!.hour
        let tiredPeak = tired.max { $0.energy < $1.energy }!.hour
        XCTAssertEqual(restedPeak, tiredPeak, accuracy: 0.25, "debt moved the day's peak")
    }

    func testCurveCoversTheDayAtTheRequestedResolution() {
        let phase = CircadianRhythm.Phase(wakeHour: 7, onsetHour: 23, confidence: 1)
        XCTAssertEqual(CircadianRhythm.curve(phase: phase, samplesPerHour: 4).count, 96)
        XCTAssertEqual(CircadianRhythm.curve(phase: phase, samplesPerHour: 1).count, 24)
        // A nonsense resolution must not divide by zero or hang.
        XCTAssertEqual(CircadianRhythm.curve(phase: phase, samplesPerHour: 0).count, 24)
    }

    // MARK: - Windows

    func testWindowOffsetsHoldForEarlyRiserAndNightOwl() {
        let lark = CircadianRhythm.Phase(wakeHour: 5, onsetHour: 21, confidence: 1)
        let owl = CircadianRhythm.Phase(wakeHour: 10, onsetHour: 2, confidence: 1)

        for (offset, expected) in [(0.5, CircadianRhythm.Window.grogginess),
                                   (3.0, .morningPeak),
                                   (7.5, .afternoonDip),
                                   (11.5, .eveningPeak),
                                   (17.0, .sleep)] {
            XCTAssertEqual(CircadianRhythm.window(atHour: CircadianRhythm.normalizedHour(5 + offset), phase: lark),
                           expected, "lark, \(offset)h after wake")
            XCTAssertEqual(CircadianRhythm.window(atHour: CircadianRhythm.normalizedHour(10 + offset), phase: owl),
                           expected, "owl, \(offset)h after wake")
        }
    }

    func testMelatoninWindowLeadsSleepOnset() {
        let phase = CircadianRhythm.Phase(wakeHour: 7, onsetHour: 23, confidence: 1)
        // Onset is 23:00, so melatonin rises from about 21:00.
        XCTAssertEqual(CircadianRhythm.window(atHour: 21.5, phase: phase), .melatoninWindow)
        XCTAssertEqual(CircadianRhythm.window(atHour: 22.9, phase: phase), .melatoninWindow)
        XCTAssertEqual(CircadianRhythm.window(atHour: 20.5, phase: phase), .windingDown)
        XCTAssertEqual(CircadianRhythm.window(atHour: 23.5, phase: phase), .sleep)
    }

    /// Every hour of the day has to land somewhere, for every plausible phase.
    /// A gap here is a blank hero card at some specific time of day for some
    /// specific user, which is the hardest kind of bug to hear about.
    func testEveryHourResolvesForEveryPhase() {
        for wake in stride(from: 0.0, to: 24.0, by: 0.5) {
            let phase = CircadianRhythm.Phase(wakeHour: wake,
                                              onsetHour: CircadianRhythm.normalizedHour(wake + 16),
                                              confidence: 1)
            for hour in stride(from: 0.0, to: 24.0, by: 0.25) {
                let window = CircadianRhythm.window(atHour: hour, phase: phase)
                XCTAssertTrue(CircadianRhythm.Window.allCases.contains(window))
            }
        }
    }

    func testNextWindowIsAheadAndDifferent() {
        let phase = CircadianRhythm.Phase(wakeHour: 7, onsetHour: 23, confidence: 1)
        for hour in stride(from: 0.0, to: 24.0, by: 0.5) {
            let current = CircadianRhythm.window(atHour: hour, phase: phase)
            guard let next = CircadianRhythm.nextWindow(afterHour: hour, phase: phase) else {
                XCTFail("no next window from \(hour):00")
                continue
            }
            XCTAssertNotEqual(next.window, current)
            XCTAssertGreaterThan(next.startsInHours, 0)
            XCTAssertLessThanOrEqual(next.startsInHours, 24)
        }
    }

    func testGrogginessFollowsSleepAndIsShortLived() {
        let phase = CircadianRhythm.Phase(wakeHour: 7, onsetHour: 23, confidence: 1)
        XCTAssertEqual(CircadianRhythm.window(atHour: 6.9, phase: phase), .sleep)
        XCTAssertEqual(CircadianRhythm.window(atHour: 7.0, phase: phase), .grogginess)
        XCTAssertEqual(CircadianRhythm.window(atHour: 7.9, phase: phase), .grogginess)
        XCTAssertNotEqual(CircadianRhythm.window(atHour: 8.1, phase: phase), .grogginess,
                          "sleep inertia does not last an hour and a half")
    }

    func testEveryWindowHasCopy() {
        for window in CircadianRhythm.Window.allCases {
            XCTAssertFalse(window.title.isEmpty)
            XCTAssertFalse(window.guidance.isEmpty)
        }
    }

    // MARK: - End to end

    /// The path the app actually takes: HealthKit nights in, a schedule out.
    func testTypicalSleeperProducesACoherentSchedule() {
        let nights = regularNights(onsetHour: 23, wakeHour: 7, asleepHours: 7.0)
        let need = CircadianRhythm.sleepNeedHours(from: nights)
        let debt = CircadianRhythm.sleepDebtHours(nights: nights, need: need)
        let phase = CircadianRhythm.phase(from: nights, calendar: calendar)!

        XCTAssertEqual(need, 7.0, accuracy: 0.01)
        XCTAssertEqual(debt, 0, accuracy: 0.01, "sleeping to your own estimated need is not a debt")

        XCTAssertEqual(CircadianRhythm.window(atHour: 9, phase: phase), .morningPeak)
        XCTAssertEqual(CircadianRhythm.window(atHour: 14.5, phase: phase), .afternoonDip)
        XCTAssertEqual(CircadianRhythm.window(atHour: 3, phase: phase), .sleep)
    }

    /// Someone whose nights are long enough to reveal their need, but who is
    /// missing sleep against it, should see a debt and a depressed curve.
    func testUnderSleptWeekShowsDebtAndCosts() {
        var nights = (1...4).map { night(day: $0, onsetHour: 22, wakeHour: 7, asleepHours: 8.5) }
        nights += (5...14).map { night(day: $0, onsetHour: 1, wakeHour: 7, asleepHours: 5.5) }

        let need = CircadianRhythm.sleepNeedHours(from: nights)
        let debt = CircadianRhythm.sleepDebtHours(nights: nights, need: need)
        XCTAssertEqual(need, 8.5, accuracy: 0.01)
        XCTAssertGreaterThan(debt, 20)

        let phase = CircadianRhythm.phase(from: nights, calendar: calendar)!
        let tired = CircadianRhythm.energy(atHour: 15, phase: phase,
                                           hoursAwake: CircadianRhythm.hoursAwake(atHour: 15, phase: phase),
                                           sleepDebtHours: debt, sleepNeedHours: need)
        let rested = CircadianRhythm.energy(atHour: 15, phase: phase,
                                            hoursAwake: CircadianRhythm.hoursAwake(atHour: 15, phase: phase),
                                            sleepDebtHours: 0, sleepNeedHours: need)
        XCTAssertLessThan(tired, rested)
    }
}
