import XCTest
@testable import ForgeSwift

/// The first tests in the app target.
///
/// `MenstrualCycleEngine` is 943 lines of clinical logic with no coverage at
/// all, and it decides things people act on — whether they are bleeding, when
/// they are fertile, when the next period lands. `buildPeriodEpisodes` sits
/// under most of it, and it is pure: day keys in, episodes out. There is no
/// reason it was untested except that the project had nowhere to put a test.
final class PeriodEpisodeTests: XCTestCase {

    private func log(_ day: Int, _ flow: MenstrualFlowLevel) -> CycleDayLog {
        CycleDayLog(dayKey: key(day), flow: flow)
    }

    /// Day keys inside one month, so arithmetic never crosses a boundary the
    /// test itself has to reason about.
    private func key(_ day: Int) -> String {
        String(format: "2026-03-%02d", day)
    }

    // MARK: - Clustering

    func testConsecutiveBleedingDaysAreOneEpisode() {
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: [
            log(3, .medium), log(4, .heavy), log(5, .medium), log(6, .light),
        ])

        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes[0].startDayKey, key(3))
        XCTAssertEqual(episodes[0].endDayKey, key(6))
        XCTAssertEqual(episodes[0].dayCount, 4)
        XCTAssertEqual(episodes[0].peakFlow, .heavy, "peak is the heaviest day, not the last")
    }

    /// A missed day mid-period is the normal case — you are bleeding, not doing
    /// data entry. Splitting on it would report two short periods and move the
    /// user through their phases twice.
    func testAOneDayGapDoesNotSplitAPeriod() {
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: [
            log(3, .medium), log(4, .heavy), /* 5 missed */ log(6, .light),
        ])

        XCTAssertEqual(episodes.count, 1, "a skipped log is absence of evidence, not evidence of an end")
        XCTAssertEqual(episodes[0].dayCount, 3)
    }

    func testAThreeDayGapStartsANewEpisode() {
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: [
            log(3, .medium), log(4, .medium),
            log(8, .medium), log(9, .medium),
        ])

        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(episodes[0].startDayKey, key(3))
        XCTAssertEqual(episodes[1].startDayKey, key(8))
    }

    func testEpisodesComeBackInChronologicalOrderRegardlessOfLogOrder() {
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: [
            log(20, .medium), log(21, .medium),
            log(3, .heavy), log(4, .medium),
        ])

        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(episodes[0].startDayKey, key(3),
                       "logs arrive in whatever order the store held them")
        XCTAssertEqual(episodes[1].startDayKey, key(20))
    }

    // MARK: - What counts as a period

    func testNoBleedingMeansNoEpisodes() {
        XCTAssertTrue(MenstrualCycleEngine.buildPeriodEpisodes(from: []).isEmpty)
        XCTAssertTrue(
            MenstrualCycleEngine.buildPeriodEpisodes(from: [log(3, .none), log(4, .none)]).isEmpty
        )
    }

    /// A single spotting day is not a period. Treating it as one restarts the
    /// cycle and throws off every prediction that follows.
    func testAnIsolatedSpottingDayDoesNotOpenAnEpisode() {
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: [log(11, .spotting)])
        XCTAssertTrue(episodes.isEmpty)
    }

    func testSpottingAdjacentToRealFlowIsPartOfThatEpisode() {
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: [
            log(3, .spotting), log(4, .medium), log(5, .light),
        ])

        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes[0].startDayKey, key(3), "the spotting day is the start, not discarded")
        XCTAssertEqual(episodes[0].peakFlow, .medium)
    }

    func testASingleRealFlowDayIsAnEpisode() {
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: [log(7, .medium)])
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes[0].dayCount, 1)
    }

    // MARK: - Shape of the result

    func testEveryEpisodeIsInternallyConsistent() {
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: [
            log(2, .light), log(3, .heavy), log(4, .medium),
            log(15, .medium), log(16, .light),
        ])

        for episode in episodes {
            XCTAssertFalse(episode.id.isEmpty)
            XCTAssertLessThanOrEqual(episode.startDayKey, episode.endDayKey)
            XCTAssertGreaterThan(episode.dayCount, 0)
            XCTAssertFalse(episode.isConfirmedComplete,
                           "an inferred end is not a confirmed one — the UI tells them apart")
        }
    }
}

// MARK: - Same-day HealthKit flow conflicts

final class HealthKitSameDayFlowTests: XCTestCase {
    private func date(_ hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 3
        comps.hour = hour
        return Calendar.current.date(from: comps)!
    }

    func testHeaviestFlowWinsEvenWhenALighterSampleIsLast() {
        let samples: [(flow: MenstrualFlowLevel, date: Date)] = [
            (.heavy, date(8)),
            (.light, date(18)),
        ]
        XCTAssertEqual(
            HealthKitSameDayFlow.resolve(samples)?.flow,
            .heavy,
            "last-processed must not beat a heavier earlier sample"
        )
    }

    func testEqualWeightPrefersTheNewestSample() {
        let older = date(8)
        let newer = date(18)
        let winner = HealthKitSameDayFlow.resolve([
            (.medium, newer),
            (.medium, older),
        ])
        XCTAssertEqual(winner?.flow, .medium)
        XCTAssertEqual(winner?.date, newer)
    }

    func testSpottingLosesToMediumOnTheSameDay() {
        XCTAssertEqual(
            HealthKitSameDayFlow.resolve([
                (.spotting, date(20)),
                (.medium, date(7)),
            ])?.flow,
            .medium
        )
    }
}

// MARK: - BBT shift calendar consecutiveness

final class BBTShiftCalendarTests: XCTestCase {
    private func key(_ day: Int) -> String {
        String(format: "2026-03-%02d", day)
    }

    private func flow(_ day: Int, _ level: MenstrualFlowLevel) -> CycleDayLog {
        CycleDayLog(dayKey: key(day), flow: level)
    }

    private func bbt(_ day: Int, _ temp: Double) -> CycleDayLog {
        CycleDayLog(dayKey: key(day), bbtCelsius: temp)
    }

    private func evaluate(logs: [CycleDayLog], asOfDay: Int) -> MenstrualCycleSnapshot {
        var settings = MenstrualTrackingSettings.default
        settings.enabled = true
        return MenstrualCycleEngine.evaluate(
            logs: logs,
            settings: settings,
            asOf: CycleDayKey.date(from: key(asOfDay))!
        )
    }

    private func periodPlusCover() -> [CycleDayLog] {
        [
            flow(1, .heavy), flow(2, .medium), flow(3, .medium), flow(4, .light),
            bbt(6, 36.20), bbt(7, 36.18), bbt(8, 36.22),
            bbt(9, 36.19), bbt(10, 36.21), bbt(11, 36.20),
        ]
    }

    func testConsecutiveRiseTriggersBBTShift() {
        var logs = periodPlusCover()
        logs += [bbt(12, 36.45), bbt(13, 36.48), bbt(14, 36.50)]
        let snap = evaluate(logs: logs, asOfDay: 16)
        XCTAssertEqual(snap.ovulationMethod, "bbt_shift")
        XCTAssertEqual(
            MenstrualCycleEngine.detectBBTShift(cycleLogs: logs, start: key(1)),
            11
        )
    }

    func testGappedRiseDoesNotTriggerFalseShift() {
        var logs = periodPlusCover()
        logs += [bbt(20, 36.45), bbt(21, 36.48), bbt(22, 36.50)]
        let snap = evaluate(logs: logs, asOfDay: 23)
        XCTAssertNotEqual(
            snap.ovulationMethod,
            "bbt_shift",
            "six low then a multi-day hole then three high is not a biphasic shift"
        )
        XCTAssertNil(MenstrualCycleEngine.detectBBTShift(cycleLogs: logs, start: key(1)))
    }

    func testSingleSkippedDayStillCountsAsConsecutive() {
        var logs = periodPlusCover()
        logs += [bbt(13, 36.45), bbt(14, 36.48), bbt(15, 36.50)]
        XCTAssertNotNil(
            MenstrualCycleEngine.detectBBTShift(cycleLogs: logs, start: key(1)),
            "a one-day gap is allowed"
        )
    }
}

// MARK: - Dead 28-day phase fallback

final class CyclePhaseFallbackTests: XCTestCase {
    func testLongCycleDayTwelveIsFollicularNotCookieCutterFertile() {
        var settings = MenstrualTrackingSettings.default
        settings.enabled = true
        settings.averageCycleOverride = 35
        settings.typicalLutealDays = 14
        let logs = [
            CycleDayLog(dayKey: "2026-03-01", flow: .heavy),
            CycleDayLog(dayKey: "2026-03-02", flow: .medium),
            CycleDayLog(dayKey: "2026-03-03", flow: .light),
        ]
        let snap = MenstrualCycleEngine.evaluate(
            logs: logs,
            settings: settings,
            asOf: CycleDayKey.date(from: "2026-03-12")!
        )
        XCTAssertEqual(snap.dayInCycle, 12)
        XCTAssertEqual(snap.ovulationDayInCycle, 21, "35 − 14 luteal")
        XCTAssertEqual(
            snap.phase,
            .follicular,
            "day 12 of a 35-day cycle is pre-fertile; the old ≤16 fertile cookie-cutter must stay gone"
        )
    }
}

// MARK: - Personalized luteal coaching ranges

final class CyclePhaseCoachingDirectiveTests: XCTestCase {
    func testDefaultLutealKeepsFourteenDaySplit() {
        let text = CyclePhaseCoachingDirective.directive(
            for: .luteal,
            domain: .workout,
            lutealDays: 14
        )
        XCTAssertTrue(text.contains("days 1–7 post-ovulation"))
        XCTAssertTrue(text.contains("days 8–14"))
    }

    func testShorterLutealDerivesEarlyAndLateFromLength() {
        let text = CyclePhaseCoachingDirective.directive(
            for: .luteal,
            domain: .workout,
            lutealDays: 10
        )
        XCTAssertTrue(text.contains("days 1–5 post-ovulation"))
        XCTAssertTrue(text.contains("days 6–10"))
        XCTAssertFalse(text.contains("days 8–14"))
    }

    func testCoachingWordingStaysTheSameBeyondTheDayRange() {
        let fourteen = CyclePhaseCoachingDirective.directive(
            for: .luteal, domain: .workout, lutealDays: 14
        )
        let twelve = CyclePhaseCoachingDirective.directive(
            for: .luteal, domain: .workout, lutealDays: 12
        )
        let strippedFourteen = fourteen
            .replacingOccurrences(of: "days 1–7 post-ovulation", with: "RANGE")
            .replacingOccurrences(of: "days 8–14", with: "RANGE")
        let strippedTwelve = twelve
            .replacingOccurrences(of: "days 1–6 post-ovulation", with: "RANGE")
            .replacingOccurrences(of: "days 7–12", with: "RANGE")
        XCTAssertEqual(strippedFourteen, strippedTwelve)
    }

    func testLutealHalvesClampToBiologyBounds() {
        XCTAssertEqual(CyclePhaseCoachingDirective.lutealHalves(lutealDays: 8).lateEnd, 10)
        XCTAssertEqual(CyclePhaseCoachingDirective.lutealHalves(lutealDays: 20).lateEnd, 16)
    }
}

// MARK: - Privacy opt-in copy

final class CyclePrivacyLowPriorityTests: XCTestCase {
    func testPolicyMentionsAriaOptInAndPerPersonSupporters() {
        XCTAssertTrue(CyclePrivacy.policy.contains("share with ARIA"))
        XCTAssertTrue(CyclePrivacy.policy.contains("one person at a time"))
        XCTAssertTrue(CyclePrivacy.policy.contains("ciphertext"))
        XCTAssertTrue(CyclePrivacy.ariaShareLine.lowercased().contains("off until"))
        XCTAssertTrue(CyclePrivacy.bullets.contains { $0.text.contains("share with ARIA") })
    }
}
