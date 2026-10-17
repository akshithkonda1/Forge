import XCTest
@testable import ForgeCore

final class ForgeTutorialTests: XCTestCase {

    func testBeatListIsFourActLearnByDoing() {
        XCTAssertEqual(ForgeTutorial.Beat.teachingOrder.map(\.rawValue), [
            "welcome", "seeHistory", "personalIndex", "askAria", "mosaicWin", "done",
        ])
        XCTAssertTrue(ForgeTutorial.Beat.personalIndex.isOptional)
        XCTAssertFalse(ForgeTutorial.Beat.askAria.isOptional)
        XCTAssertFalse(ForgeTutorial.Beat.mosaicWin.isOptional)
        for beat in ForgeTutorial.Beat.teachingOrder where beat != .done {
            XCTAssertFalse(beat.prompt.lowercased().contains("national"))
            XCTAssertFalse(beat.prompt.lowercased().contains("average"))
            XCTAssertFalse(beat.prompt.lowercased().contains("percentile"))
            XCTAssertFalse(ForgeHealthPotential.tutorialLeadsWithBMI(beat.prompt))
        }
    }

    func testHappyPathAdvancesOneGesturePerBeat() {
        var state = ForgeTutorial.start(hasRealMosaicData: true)
        XCTAssertFalse(state.usingDemoMosaic)
        XCTAssertEqual(state.beat, .welcome)

        state = apply(state, .acknowledge, 2.4).state
        XCTAssertEqual(state.beat, .seeHistory)

        state = apply(state, .openedProgress, 2.5).state
        XCTAssertEqual(state.beat, .personalIndex)

        state = apply(state, .focusedTile, 3.0).state
        XCTAssertEqual(state.beat, .askAria)

        state = apply(state, .askedAria, 2.2).state
        XCTAssertEqual(state.beat, .mosaicWin)

        let last = apply(state, .expandedTile, 2.0)
        XCTAssertEqual(last.state.beat, .done)
        XCTAssertTrue(last.rewarded)
        XCTAssertTrue(last.state.isComplete)
    }

    func testNailingAStepSkipsTheNextOptionalBeat() {
        var state = ForgeTutorial.start(hasRealMosaicData: true)
        state = apply(state, .acknowledge, 0.4).state
        let outcome = apply(state, .openedProgress, 0.5)
        XCTAssertTrue(outcome.rewarded)
        // Nailed seeHistory → skip optional personalIndex.
        XCTAssertEqual(outcome.state.beat, .askAria)
        XCTAssertEqual(outcome.state.nailStreak, 2)
    }

    func testJumpingAheadSkipsIntermediateBeats() {
        var state = ForgeTutorial.start(hasRealMosaicData: true)
        let outcome = apply(state, .askedAria, 0.8)
        XCTAssertTrue(outcome.skippedAhead)
        XCTAssertTrue(outcome.rewarded)
        XCTAssertEqual(outcome.state.beat, .mosaicWin)
    }

    func testHesitateRehintsWithoutAdvancing() {
        var state = ForgeTutorial.start(hasRealMosaicData: true)
        state = apply(state, .acknowledge, 2.0).state
        let outcome = apply(state, .hesitated, ForgeTutorial.hesitateSeconds)
        XCTAssertTrue(outcome.rehint)
        XCTAssertFalse(outcome.rewarded)
        XCTAssertEqual(outcome.state.beat, .seeHistory)
        XCTAssertEqual(outcome.state.hesitateStreak, 1)
        XCTAssertEqual(outcome.state.nailStreak, 0)
    }

    func testSkipNeverBlocksAndCompletesFromAnyBeat() {
        let mid = ForgeTutorial.State(beat: .personalIndex)
        let outcome = ForgeTutorial.apply(state: mid, gesture: .skip, latency: 0)
        XCTAssertEqual(outcome.state.beat, .done)
        XCTAssertFalse(outcome.rewarded)
        XCTAssertTrue(outcome.state.isComplete)
    }

    func testUnknownOrEarlierGesturesDoNotBlock() {
        var state = ForgeTutorial.State(beat: .askAria)
        var outcome = apply(state, .acknowledge, 0.2)
        XCTAssertEqual(outcome.state.beat, .askAria)
        XCTAssertFalse(outcome.rewarded)

        state = ForgeTutorial.State(beat: .mosaicWin)
        outcome = apply(state, .openedProgress, 0.2)
        XCTAssertEqual(outcome.state.beat, .mosaicWin)
    }

    func testDemoMosaicIsTheFallbackWhenHealthIsEmpty() {
        let empty = StatsMosaic.snapshot(StatsMosaic.Input())
        XCTAssertFalse(ForgeTutorial.hasRealMosaicData(empty))
        let started = ForgeTutorial.start(hasRealMosaicData: false)
        XCTAssertTrue(started.usingDemoMosaic)
        let demo = ForgeTutorial.mosaic(for: started, live: empty)
        XCTAssertGreaterThan(demo.dayPercent, 0)
        XCTAssertTrue(demo.tiles.contains { $0.track == .sleep && $0.source == .health })
        XCTAssertTrue(demo.tiles.contains { $0.track == .habits && $0.source == .empty })
        XCTAssertFalse(StatsMosaic.containsBannedMedical(demo.mosaicLine))
        XCTAssertFalse(demo.mosaicLine.lowercased().contains("recovery"))
    }

    func testCopyNeverDiagnosesRanksOrSaysRecovery() {
        for beat in ForgeTutorial.Beat.allCases {
            XCTAssertFalse(beat.prompt.lowercased().contains("recovery"), beat.rawValue)
            XCTAssertFalse(beat.prompt.lowercased().contains("diagnos"), beat.rawValue)
            XCTAssertFalse(beat.prompt.lowercased().contains("don't worry"), beat.rawValue)
            XCTAssertFalse(ForgeHealthPotential.containsBanned(beat.prompt), beat.rawValue)
        }
    }

    private func apply(
        _ state: ForgeTutorial.State,
        _ gesture: ForgeTutorial.Gesture,
        _ latency: Double
    ) -> ForgeTutorial.Outcome {
        ForgeTutorial.apply(state: state, gesture: gesture, latency: latency)
    }
}
