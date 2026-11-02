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

// MARK: - evaluate() math

final class MenstrualCycleEngineEvaluateTests: XCTestCase {

    private func settings(
        cycle: Int? = 28,
        period: Int? = 5,
        luteal: Int = 14,
        hormonal: Bool = false,
        condition: CycleCondition = .none
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

    private func noon(_ key: String) -> Date {
        guard let date = CycleDayKey.date(from: key) else {
            XCTFail("invalid day key \(key)")
            return Date()
        }
        return date
    }

    private func bleed(start: String, days: Int, flow: MenstrualFlowLevel = .medium) -> [CycleDayLog] {
        (0..<days).compactMap { offset in
            guard let key = CycleDayKey.addDays(start, offset) else { return nil }
            return CycleDayLog(dayKey: key, flow: flow, source: "manual")
        }
    }

    private func log(
        _ key: String,
        flow: MenstrualFlowLevel = .none,
        bbt: Double? = nil,
        opk: OvulationTestResult? = nil,
        mucus: CervicalMucusQuality? = nil
    ) -> CycleDayLog {
        CycleDayLog(
            dayKey: key,
            flow: flow,
            bbtCelsius: bbt,
            ovulationTest: opk,
            mucus: mucus,
            source: "manual"
        )
    }

    func testEvaluateReportsCycleDayFromFixedPeriodStart() {
        let snap = MenstrualCycleEngine.evaluate(
            logs: bleed(start: "2026-03-01", days: 5),
            settings: settings(),
            asOf: noon("2026-03-10")
        )
        XCTAssertEqual(snap.dayInCycle, 10)
        XCTAssertEqual(snap.lastPeriodStartDayKey, "2026-03-01")
        XCTAssertEqual(snap.asOfDayKey, "2026-03-10")
        XCTAssertEqual(snap.cyclesObserved, 0)
    }

    func testPhaseBoundariesForCommonCycleLengths() {
        let cases: [(cycle: Int, ovu: Int, asOf: String, phase: MenstrualPhase)] = [
            (21, 7, "2026-03-03", .menstruation),
            (21, 7, "2026-03-07", .ovulation),
            (21, 7, "2026-03-12", .luteal),
            (28, 14, "2026-03-03", .menstruation),
            (28, 14, "2026-03-08", .follicular),
            (28, 14, "2026-03-10", .fertileWindow),
            (28, 14, "2026-03-14", .ovulation),
            (28, 14, "2026-03-18", .luteal),
            (35, 21, "2026-03-16", .fertileWindow),
            (35, 21, "2026-03-21", .ovulation),
            (35, 21, "2026-03-26", .luteal),
            (45, 31, "2026-03-26", .fertileWindow),
            (45, 31, "2026-03-31", .ovulation),
            (45, 31, "2026-04-04", .luteal),
        ]
        for item in cases {
            let snap = MenstrualCycleEngine.evaluate(
                logs: bleed(start: "2026-03-01", days: 5),
                settings: settings(cycle: item.cycle),
                asOf: noon(item.asOf)
            )
            XCTAssertEqual(snap.phase, item.phase, "cycle \(item.cycle) on \(item.asOf)")
            XCTAssertEqual(snap.ovulationDayInCycle, item.ovu, "ovu for \(item.cycle)")
            XCTAssertEqual(snap.ovulationMethod, "calendar_minus_luteal")
        }
    }

    func testLHSurgeUsesFirstPositiveOfLatestRun() {
        var logs = bleed(start: "2026-03-01", days: 5)
        logs += [
            log("2026-03-12", opk: .positive),
            log("2026-03-13", opk: .lhSurge),
            log("2026-03-14", opk: .positive),
        ]
        let snap = MenstrualCycleEngine.evaluate(
            logs: logs,
            settings: settings(),
            asOf: noon("2026-03-16")
        )
        XCTAssertEqual(snap.ovulationMethod, "lh_surge")
        XCTAssertEqual(snap.ovulationDayInCycle, 13,
                       "first positive is March 12 (day 12); ovulation is the next day, not the last positive")
        XCTAssertNotEqual(snap.ovulationDayInCycle, 15)
    }

    func testBBTShiftRequiresCalendarConsecutiveDays() {
        var consecutive = bleed(start: "2026-03-01", days: 5)
        for day in 6...11 {
            consecutive.append(log(String(format: "2026-03-%02d", day), bbt: 36.20))
        }
        for day in 12...14 {
            consecutive.append(log(String(format: "2026-03-%02d", day), bbt: 36.55))
        }
        let shifted = MenstrualCycleEngine.evaluate(
            logs: consecutive,
            settings: settings(),
            asOf: noon("2026-03-16")
        )
        XCTAssertEqual(shifted.ovulationMethod, "bbt_shift")
        XCTAssertEqual(shifted.ovulationDayInCycle, 11)

        var gapped = bleed(start: "2026-03-01", days: 5)
        for day in [6, 7, 8, 9, 10, 11] {
            gapped.append(log(String(format: "2026-03-%02d", day), bbt: 36.20))
        }
        for day in [15, 16, 17] {
            gapped.append(log(String(format: "2026-03-%02d", day), bbt: 36.55))
        }
        let noShift = MenstrualCycleEngine.evaluate(
            logs: gapped,
            settings: settings(),
            asOf: noon("2026-03-18")
        )
        XCTAssertEqual(noShift.ovulationMethod, "calendar_minus_luteal",
                       "a 3-day gap between coverline and rise must not invent a BBT shift")
    }

    func testMucusAndPopulationFallbackMethods() {
        var mucusLogs = bleed(start: "2026-03-01", days: 5)
        mucusLogs.append(log("2026-03-13", mucus: .eggWhite))
        let mucus = MenstrualCycleEngine.evaluate(
            logs: mucusLogs,
            settings: settings(),
            asOf: noon("2026-03-15")
        )
        XCTAssertEqual(mucus.ovulationMethod, "peak_mucus")
        XCTAssertEqual(mucus.ovulationDayInCycle, 13)

        let empty = MenstrualCycleEngine.evaluate(
            logs: [],
            settings: settings(),
            asOf: noon("2026-03-10")
        )
        XCTAssertEqual(empty.ovulationMethod, "population_fallback")
        XCTAssertNil(empty.dayInCycle)
        XCTAssertNil(empty.nextPeriod)
    }

    func testNextPeriodWindowAndEnsemble() {
        let logs = bleed(start: "2026-01-04", days: 5)
            + bleed(start: "2026-02-01", days: 5)
            + bleed(start: "2026-03-01", days: 5)
        let snap = MenstrualCycleEngine.evaluate(
            logs: logs,
            settings: settings(cycle: 28),
            asOf: noon("2026-03-10")
        )
        XCTAssertEqual(snap.cyclesObserved, 2)
        XCTAssertEqual(snap.nextPeriod?.medianDayKey, "2026-03-29")
        XCTAssertEqual(snap.nextPeriod?.earliestDayKey, "2026-03-28")
        XCTAssertEqual(snap.nextPeriod?.latestDayKey, "2026-03-30")
        XCTAssertTrue(snap.predictionMethodSummary.contains("recency-weighted median"))
        XCTAssertTrue(snap.predictionMethodSummary.contains("last cycle"))
    }

    func testPerimenopauseSuppressesFertileLabels() {
        let snap = MenstrualCycleEngine.evaluate(
            logs: bleed(start: "2026-03-01", days: 5),
            settings: settings(condition: .perimenopause),
            asOf: noon("2026-03-14")
        )
        XCTAssertNil(snap.ovulationDayInCycle)
        XCTAssertNil(snap.fertileStartDayInCycle)
        XCTAssertNil(snap.fertileEndDayInCycle)
        XCTAssertNil(snap.fertileScore)
        XCTAssertNotEqual(snap.phase, .ovulation)
        XCTAssertNotEqual(snap.phase, .fertileWindow)
        XCTAssertNotEqual(snap.stage, .fertile)
        XCTAssertNotEqual(snap.stage, .ovulation)
    }

    func testHormonalBirthControlSimplifiesPhase() {
        let snap = MenstrualCycleEngine.evaluate(
            logs: bleed(start: "2026-03-01", days: 5),
            settings: settings(hormonal: true),
            asOf: noon("2026-03-14")
        )
        XCTAssertEqual(snap.phase, .follicular)
        XCTAssertNotEqual(snap.phase, .ovulation)
        XCTAssertTrue(snap.insights.contains { $0.localizedCaseInsensitiveContains("hormonal contraception") })
    }

    func testIrregularFlagAndFirstCycle() {
        let irregularLogs = bleed(start: "2025-11-01", days: 5)
            + bleed(start: "2025-11-22", days: 5)
            + bleed(start: "2025-12-27", days: 5)
            + bleed(start: "2026-02-10", days: 5)
        let irregular = MenstrualCycleEngine.evaluate(
            logs: irregularLogs,
            settings: settings(cycle: nil),
            asOf: noon("2026-02-20")
        )
        XCTAssertTrue(irregular.irregularityFlag)
        XCTAssertGreaterThanOrEqual(irregular.cyclesObserved, 3)

        let first = MenstrualCycleEngine.evaluate(
            logs: bleed(start: "2026-03-01", days: 5),
            settings: settings(),
            asOf: noon("2026-03-08")
        )
        XCTAssertEqual(first.cyclesObserved, 0)
        XCTAssertEqual(first.dataQuality, "partial")
        XCTAssertEqual(first.ovulationMethod, "calendar_minus_luteal")
        XCTAssertFalse(first.irregularityFlag)
    }

    func testDSTAndLeapDayKeys() {
        XCTAssertEqual(CycleDayKey.addDays("2026-03-08", 1), "2026-03-09")
        XCTAssertEqual(CycleDayKey.daysBetween("2026-03-08", "2026-03-09"), 1)
        XCTAssertEqual(CycleDayKey.addDays("2026-11-01", 1), "2026-11-02")
        XCTAssertEqual(CycleDayKey.addDays("2024-02-28", 1), "2024-02-29")
        XCTAssertEqual(CycleDayKey.addDays("2024-02-29", 1), "2024-03-01")
        XCTAssertEqual(CycleDayKey.daysBetween("2024-02-28", "2024-03-01"), 2)
        XCTAssertNil(CycleDayKey.date(from: "2026-02-31"))
        XCTAssertNil(CycleDayKey.date(from: "not-a-date"))

        let leapStart = bleed(start: "2024-02-25", days: 5)
        let snap = MenstrualCycleEngine.evaluate(
            logs: leapStart,
            settings: settings(),
            asOf: noon("2024-03-01")
        )
        XCTAssertEqual(snap.dayInCycle, 6)
        XCTAssertEqual(snap.lastPeriodStartDayKey, "2024-02-25")
    }

    func testInsightsNeverSayRecovery() {
        let snap = MenstrualCycleEngine.evaluate(
            logs: bleed(start: "2026-03-01", days: 5),
            settings: settings(condition: .endometriosis),
            asOf: noon("2026-03-20"),
            recentHRV: 40,
            baselineHRV: 55
        )
        XCTAssertFalse(MenstrualCycleEngine.disclaimer.localizedCaseInsensitiveContains("recovery"))
        XCTAssertFalse(snap.readinessNote.localizedCaseInsensitiveContains("recovery"))
        for line in snap.insights {
            XCTAssertFalse(line.localizedCaseInsensitiveContains("recovery"), line)
        }
        XCTAssertFalse(MenstrualPhase.luteal.trainingBias.localizedCaseInsensitiveContains("recovery"))
    }
}
