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

// MARK: - evaluate() coverage (cycle day, phases, ovulation, predictions)

final class MenstrualCycleEngineEvaluateTests: XCTestCase {

    private func settings(
        cycle: Int? = 28,
        period: Int? = 5,
        hormonal: Bool = false,
        condition: CycleCondition = .none,
        luteal: Int = 14
    ) -> MenstrualTrackingSettings {
        var s = MenstrualTrackingSettings.default
        s.enabled = true
        s.averageCycleOverride = cycle
        s.averagePeriodOverride = period
        s.typicalLutealDays = luteal
        s.usesHormonalContraception = hormonal
        s.condition = condition
        return s
    }

    private func date(_ key: String) -> Date {
        CycleDayKey.date(from: key)!
    }

    private func evaluate(
        _ logs: [CycleDayLog],
        asOf: String,
        settings: MenstrualTrackingSettings? = nil
    ) -> MenstrualCycleSnapshot {
        MenstrualCycleEngine.evaluate(
            logs: logs,
            settings: settings ?? self.settings(),
            asOf: date(asOf)
        )
    }

    private func bleed(start: String, days: Int = 5) -> [CycleDayLog] {
        (0..<days).compactMap { offset in
            CycleDayKey.addDays(start, offset).map {
                CycleDayLog(dayKey: $0, flow: .medium)
            }
        }
    }

    // MARK: Cycle day

    func testEvaluateCycleDayIsOneBasedFromLastPeriodStart() {
        let snap = evaluate(bleed(start: "2026-03-01"), asOf: "2026-03-10")
        XCTAssertEqual(snap.dayInCycle, 10)
        XCTAssertEqual(snap.lastPeriodStartDayKey, "2026-03-01")
        XCTAssertEqual(snap.asOfDayKey, "2026-03-10")
    }

    func testEvaluateFirstCycleWithNoHistoryUsesPopulationFallback() {
        let snap = evaluate([], asOf: "2026-03-10")
        XCTAssertNil(snap.dayInCycle)
        XCTAssertNil(snap.lastPeriodStartDayKey)
        XCTAssertEqual(snap.ovulationMethod, "population_fallback")
        XCTAssertEqual(snap.ovulationDayInCycle, 14, "28 − 14 luteal")
        XCTAssertEqual(snap.dataQuality, "no_data")
        XCTAssertEqual(snap.phase, .unknown)
        XCTAssertNil(snap.nextPeriod)
    }

    func testEvaluateFirstLoggedPeriodHasNoCycleLengthsYet() {
        let snap = evaluate(bleed(start: "2026-03-01"), asOf: "2026-03-10")
        XCTAssertEqual(snap.cyclesObserved, 0)
        XCTAssertEqual(snap.dataQuality, "partial")
        XCTAssertEqual(snap.ovulationMethod, "calendar_minus_luteal")
        XCTAssertNotNil(snap.nextPeriod, "a single start is enough to project the next period")
    }

    // MARK: Phase boundaries

    func testPhaseBoundariesFor21DayCycle() {
        // calendar_minus_luteal: max(10, min(21-14, 21-10)) = 10
        let logs = bleed(start: "2026-03-01")
        let s = settings(cycle: 21)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-03", settings: s).phase, .menstruation)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-10", settings: s).phase, .ovulation)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-10", settings: s).ovulationDayInCycle, 10)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-08", settings: s).phase, .fertileWindow)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-13", settings: s).phase, .luteal)
    }

    func testPhaseBoundariesFor28DayCycle() {
        // calendar_minus_luteal: 14
        let logs = bleed(start: "2026-03-01")
        let s = settings(cycle: 28)
        let snap = evaluate(logs, asOf: "2026-03-14", settings: s)
        XCTAssertEqual(snap.ovulationDayInCycle, 14)
        XCTAssertEqual(snap.fertileStartDayInCycle, 9)
        XCTAssertEqual(snap.fertileEndDayInCycle, 15)
        XCTAssertEqual(snap.phase, .ovulation)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-03", settings: s).phase, .menstruation)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-07", settings: s).phase, .follicular)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-12", settings: s).phase, .fertileWindow)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-20", settings: s).phase, .luteal)
    }

    func testPhaseBoundariesFor35DayCycle() {
        // calendar_minus_luteal: max(10, min(35-14, 35-10)) = 21
        let logs = bleed(start: "2026-03-01")
        let s = settings(cycle: 35)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-21", settings: s).ovulationDayInCycle, 21)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-21", settings: s).phase, .ovulation)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-10", settings: s).phase, .follicular)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-18", settings: s).phase, .fertileWindow)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-28", settings: s).phase, .luteal)
    }

    func testPhaseBoundariesFor45DayCycle() {
        // calendar_minus_luteal: max(10, min(45-14, 45-10)) = 31
        let logs = bleed(start: "2026-03-01")
        let s = settings(cycle: 45)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-31", settings: s).ovulationDayInCycle, 31)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-31", settings: s).phase, .ovulation)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-20", settings: s).phase, .follicular)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-28", settings: s).phase, .fertileWindow)
        XCTAssertEqual(evaluate(logs, asOf: "2026-04-04", settings: s).phase, .luteal)
    }

    // MARK: Ovulation methods

    func testLHSurgeUsesFirstPositiveOfLatestConsecutiveRun() {
        var logs = bleed(start: "2026-03-01")
        logs.append(CycleDayLog(dayKey: "2026-03-08", ovulationTest: .positive))
        logs.append(CycleDayLog(dayKey: "2026-03-12", ovulationTest: .lhSurge))
        logs.append(CycleDayLog(dayKey: "2026-03-13", ovulationTest: .lhSurge))
        logs.append(CycleDayLog(dayKey: "2026-03-14", ovulationTest: .positive))

        let first = MenstrualCycleEngine.firstPositiveOfLatestLHRun(
            in: logs, periodStart: "2026-03-01", asOfDayKey: "2026-03-20"
        )
        XCTAssertEqual(first?.dayKey, "2026-03-12", "isolated March 8 is a prior run")

        let snap = evaluate(logs, asOf: "2026-03-20")
        XCTAssertEqual(snap.ovulationMethod, "lh_surge")
        // daysBetween(Mar 1, Mar 12) = 11; day-in-cycle = 13 (11 + 2)
        XCTAssertEqual(snap.ovulationDayInCycle, 13)
        XCTAssertNotEqual(snap.ovulationDayInCycle, 15, "last positive (Mar 14) must not push ovulation later")
    }

    func testBBTShiftEstimatesOvulationTheDayBeforeTheRise() {
        var logs = bleed(start: "2026-03-01")
        for day in 1...9 {
            let key = String(format: "2026-03-%02d", day)
            let temp = day <= 6 ? 36.40 : 36.55
            if let idx = logs.firstIndex(where: { $0.dayKey == key }) {
                logs[idx].bbtCelsius = temp
            } else {
                logs.append(CycleDayLog(dayKey: key, bbtCelsius: temp))
            }
        }
        let snap = evaluate(logs, asOf: "2026-03-15")
        XCTAssertEqual(snap.ovulationMethod, "bbt_shift")
        XCTAssertEqual(snap.ovulationDayInCycle, 6)
    }

    func testPeakMucusEstimatesOvulation() {
        var logs = bleed(start: "2026-03-01")
        logs.append(CycleDayLog(dayKey: "2026-03-13", mucus: .eggWhite))
        let snap = evaluate(logs, asOf: "2026-03-16")
        XCTAssertEqual(snap.ovulationMethod, "peak_mucus")
        // daysBetween(Mar 1, Mar 13) = 12; code uses day + 1 → 13
        XCTAssertEqual(snap.ovulationDayInCycle, 13)
    }

    func testCalendarMinusLutealAndPopulationFallbackMethods() {
        let calendar = evaluate(bleed(start: "2026-03-01"), asOf: "2026-03-16", settings: settings(cycle: 28))
        XCTAssertEqual(calendar.ovulationMethod, "calendar_minus_luteal")
        XCTAssertEqual(calendar.ovulationDayInCycle, 14)

        let population = evaluate([], asOf: "2026-03-16", settings: settings(cycle: 28))
        XCTAssertEqual(population.ovulationMethod, "population_fallback")
        XCTAssertEqual(population.ovulationDayInCycle, 14)
    }

    // MARK: Next period + ensemble

    func testNextPeriodPredictionWindowContainsTheMedian() {
        let snap = evaluate(bleed(start: "2026-03-01"), asOf: "2026-03-10", settings: settings(cycle: 28))
        let next = snap.nextPeriod
        XCTAssertEqual(next?.medianDayKey, "2026-03-29")
        XCTAssertEqual(next?.earliestDayKey, "2026-03-28")
        XCTAssertEqual(next?.latestDayKey, "2026-03-30")
        XCTAssertLessThanOrEqual(next!.earliestDayKey, next!.medianDayKey)
        XCTAssertLessThanOrEqual(next!.medianDayKey, next!.latestDayKey)
    }

    func testEnsembleBlendMentionsRecencyLastAndRobustMedian() {
        // 28-day starts: Jan 1, Jan 29, Feb 26, Mar 26
        let logs = bleed(start: "2026-01-01")
            + bleed(start: "2026-01-29")
            + bleed(start: "2026-02-26")
            + bleed(start: "2026-03-26")
        let snap = evaluate(logs, asOf: "2026-04-05")
        XCTAssertEqual(snap.cyclesObserved, 3)
        XCTAssertTrue(snap.predictionMethodSummary.contains("recency-weighted median"))
        XCTAssertTrue(snap.predictionMethodSummary.contains("last cycle"))
        XCTAssertTrue(snap.predictionMethodSummary.contains("robust median"))
        XCTAssertEqual(snap.nextPeriod?.medianDayKey, "2026-04-23")
    }

    // MARK: Condition branches

    func testPerimenopauseSuppressesFertileAndOvulationLabels() {
        let logs = bleed(start: "2026-03-01")
        let s = settings(condition: .perimenopause)
        let mid = evaluate(logs, asOf: "2026-03-14", settings: s)
        XCTAssertNil(mid.ovulationDayInCycle)
        XCTAssertNil(mid.ovulationMethod)
        XCTAssertNil(mid.fertileStartDayInCycle)
        XCTAssertNil(mid.fertileEndDayInCycle)
        XCTAssertNil(mid.fertileScore)
        XCTAssertNotEqual(mid.phase, .ovulation)
        XCTAssertNotEqual(mid.phase, .fertileWindow)
        XCTAssertTrue([MenstrualPhase.follicular, .luteal, .menstruation].contains(mid.phase))

        let late = evaluate(logs, asOf: "2026-03-20", settings: s)
        XCTAssertEqual(late.phase, .luteal)
    }

    func testHormonalBirthControlSimplifiesPhaseToBleedVersusNot() {
        let logs = bleed(start: "2026-03-01")
        let s = settings(hormonal: true)
        XCTAssertEqual(evaluate(logs, asOf: "2026-03-03", settings: s).phase, .menstruation)
        let after = evaluate(logs, asOf: "2026-03-14", settings: s)
        XCTAssertEqual(after.phase, .follicular)
        XCTAssertNil(after.fertileScore)
        XCTAssertTrue(after.insights.contains { $0.contains("Hormonal contraception") })
    }

    func testIrregularCycleFlagFiresOnWideInterStartRange() {
        let logs = bleed(start: "2026-01-01")
            + bleed(start: "2026-01-21") // 20
            + bleed(start: "2026-02-22") // 32
            + bleed(start: "2026-04-07") // 44
        let snap = evaluate(logs, asOf: "2026-04-15")
        XCTAssertEqual(snap.cyclesObserved, 3)
        XCTAssertTrue(snap.irregularityFlag)
    }

    func testRegularCyclesDoNotRaiseTheIrregularFlag() {
        let logs = bleed(start: "2026-01-01")
            + bleed(start: "2026-01-29")
            + bleed(start: "2026-02-26")
            + bleed(start: "2026-03-26")
        let snap = evaluate(logs, asOf: "2026-04-05")
        XCTAssertFalse(snap.irregularityFlag)
    }

    // MARK: DST + leap day keys

    func testDayKeysSurviveUSSpringForward() {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        defer { NSTimeZone.default = previous }

        // 2026-03-08 is the US spring-forward (02:00 → 03:00).
        XCTAssertEqual(CycleDayKey.addDays("2026-03-07", 1), "2026-03-08")
        XCTAssertEqual(CycleDayKey.addDays("2026-03-08", 1), "2026-03-09")
        XCTAssertEqual(CycleDayKey.daysBetween("2026-03-07", "2026-03-09"), 2)
        XCTAssertEqual(CycleDayKey.key(for: CycleDayKey.date(from: "2026-03-08")!), "2026-03-08")
    }

    func testDayKeysSurviveLeapDay() {
        XCTAssertEqual(CycleDayKey.addDays("2024-02-28", 1), "2024-02-29")
        XCTAssertEqual(CycleDayKey.addDays("2024-02-29", 1), "2024-03-01")
        XCTAssertEqual(CycleDayKey.daysBetween("2024-02-28", "2024-03-01"), 2)
        XCTAssertNotNil(CycleDayKey.date(from: "2024-02-29"))
        XCTAssertNil(CycleDayKey.date(from: "2025-02-29"), "non-leap Feb 29 must not roll over")
    }
}
