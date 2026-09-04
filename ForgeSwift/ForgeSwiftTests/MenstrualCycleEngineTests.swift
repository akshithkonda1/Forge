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
