import XCTest
@testable import ForgeCore

final class ForgeTutorialTests: XCTestCase {

    func testBeatListWalksEverySurface() {
        XCTAssertEqual(ForgeTutorial.Beat.teachingOrder.map(\.rawValue), [
            "welcome", "home", "sleep", "seeHistory", "personalIndex", "train",
            "askAria", "hobbyFit", "lifestyle", "trainingModel", "settings",
            "watchWidgets", "mosaicWin", "done",
        ])
        XCTAssertTrue(ForgeTutorial.Beat.personalIndex.isOptional)
        XCTAssertTrue(ForgeTutorial.Beat.watchWidgets.isOptional)
        XCTAssertFalse(ForgeTutorial.Beat.askAria.isOptional)
        for beat in ForgeTutorial.Beat.teachingOrder where beat != .done {
            XCTAssertFalse(beat.prompt.lowercased().contains("national"))
            XCTAssertFalse(beat.prompt.lowercased().contains("buy"))
            XCTAssertFalse(beat.prompt.lowercased().contains("upgrade"))
        }
    }

    func testOpeningBranchesOnExperience() {
        XCTAssertEqual(ForgeTutorial.Opening.resolve(experience: "beginner", goals: []), .beginner)
        XCTAssertEqual(
            ForgeTutorial.Opening.resolve(experience: "elite", goals: ["competition"]),
            .competitor
        )
        XCTAssertEqual(ForgeTutorial.Opening.resolve(experience: "intermediate", goals: []), .everyday)
        XCTAssertEqual(
            ForgeTutorial.Opening.resolve(experience: "intermediate", goals: ["athletic-performance"]),
            .competitor
        )
        XCTAssertEqual(
            ForgeTutorial.Opening.resolve(experience: "intermediate", goals: ["PR"]),
            .competitor
        )
        XCTAssertTrue(ForgeTutorial.Opening.beginner.welcome.lowercased().contains("no jargon"))
        XCTAssertTrue(ForgeTutorial.Opening.competitor.welcome.lowercased().contains("load"))
        XCTAssertFalse(ForgeTutorial.Opening.beginner.welcome.lowercased().contains("recovery"))
        XCTAssertGreaterThan(
            ForgeTutorial.Opening.beginner.hesitateSeconds,
            ForgeTutorial.Opening.competitor.hesitateSeconds
        )
        let beginnerHome = ForgeTutorial.Beat.home.prompt(opening: .beginner)
        let competitorHome = ForgeTutorial.Beat.home.prompt(opening: .competitor)
        XCTAssertNotEqual(beginnerHome, competitorHome)
        XCTAssertTrue(beginnerHome.lowercased().contains("glance"))
        XCTAssertTrue(competitorHome.lowercased().contains("load"))
        XCTAssertFalse(beginnerHome.lowercased().contains("recovery"))
        XCTAssertEqual(ForgeTutorial.hesitateSeconds(for: .everyday), 6.0, accuracy: 0.01)
    }

    func testHappyPathAdvancesOneGesturePerBeat() {
        var state = ForgeTutorial.start(hasRealMosaicData: true, experience: "beginner")
        XCTAssertEqual(state.opening, .beginner)
        XCTAssertEqual(state.beat, .welcome)

        state = apply(state, .acknowledge, 2.4).state
        XCTAssertEqual(state.beat, .home)
        state = apply(state, .acknowledge, 2.0).state
        XCTAssertEqual(state.beat, .sleep)
        state = apply(state, .openedSleep, 2.0).state
        XCTAssertEqual(state.beat, .seeHistory)
        state = apply(state, .openedProgress, 2.5).state
        XCTAssertEqual(state.beat, .personalIndex)
        state = apply(state, .focusedTile, 3.0).state
        XCTAssertEqual(state.beat, .train)
        state = apply(state, .openedTrain, 2.0).state
        XCTAssertEqual(state.beat, .askAria)
        state = apply(state, .askedAria, 2.2).state
        XCTAssertEqual(state.beat, .hobbyFit)
        state = apply(state, .openedHobbyFit, 2.0).state
        XCTAssertEqual(state.beat, .lifestyle)
        state = apply(state, .openedLifestyle, 2.0).state
        XCTAssertEqual(state.beat, .trainingModel)
        state = apply(state, .openedTrainingModel, 2.0).state
        XCTAssertEqual(state.beat, .settings)
        state = apply(state, .openedSettings, 2.0).state
        XCTAssertEqual(state.beat, .watchWidgets)
        state = apply(state, .acknowledge, 2.0).state
        XCTAssertEqual(state.beat, .mosaicWin)
        let last = apply(state, .expandedTile, 2.0)
        XCTAssertEqual(last.state.beat, .done)
        XCTAssertTrue(last.state.isComplete)
    }

    func testNailingAStepSkipsTheNextOptionalBeat() {
        var state = ForgeTutorial.start(hasRealMosaicData: true)
        state = apply(state, .acknowledge, 0.4).state
        state = apply(state, .acknowledge, 0.4).state
        state = apply(state, .openedSleep, 0.4).state
        let outcome = apply(state, .openedProgress, 0.5)
        XCTAssertEqual(outcome.state.beat, .train)
    }

    func testSkipNeverBlocksAndCompletesFromAnyBeat() {
        let mid = ForgeTutorial.State(beat: .train)
        let outcome = ForgeTutorial.apply(state: mid, gesture: .skip, latency: 0)
        XCTAssertEqual(outcome.state.beat, .done)
        XCTAssertTrue(outcome.state.isComplete)
    }

    func testCopyNeverDiagnosesRanksOrSaysRecovery() {
        for opening in ForgeTutorial.Opening.allCases {
            for beat in ForgeTutorial.Beat.allCases {
                let line = beat.prompt(opening: opening)
                XCTAssertFalse(line.lowercased().contains("recovery"), "\(opening.rawValue).\(beat.rawValue)")
                XCTAssertFalse(line.lowercased().contains("diagnos"), "\(opening.rawValue).\(beat.rawValue)")
                XCTAssertFalse(ForgeHealthPotential.containsBanned(line), "\(opening.rawValue).\(beat.rawValue)")
            }
        }
        XCTAssertTrue(ForgeTutorial.pausedLine.lowercased().contains("taking a break"))
    }

    func testDemoMosaicIsTheFallbackWhenHealthIsEmpty() {
        let empty = StatsMosaic.snapshot(StatsMosaic.Input())
        XCTAssertFalse(ForgeTutorial.hasRealMosaicData(empty))
        let started = ForgeTutorial.start(hasRealMosaicData: false)
        XCTAssertTrue(started.usingDemoMosaic)
        let demo = ForgeTutorial.mosaic(for: started, live: empty)
        XCTAssertGreaterThan(demo.dayPercent, 0)
        XCTAssertFalse(demo.mosaicLine.lowercased().contains("recovery"))
    }

    private func apply(
        _ state: ForgeTutorial.State,
        _ gesture: ForgeTutorial.Gesture,
        _ latency: Double
    ) -> ForgeTutorial.Outcome {
        ForgeTutorial.apply(state: state, gesture: gesture, latency: latency)
    }
}
