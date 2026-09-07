import XCTest
@testable import ForgeSwift

final class AriaForgePrepTests: XCTestCase {

    func testFloorIsFortyFiveSecondsAndCapIsThreeMinutes() {
        XCTAssertEqual(AriaForgePrep.floor, 45)
        XCTAssertEqual(AriaForgePrep.cap, 180)
    }

    func testEmptyLoadStaysAtTheFloor() {
        XCTAssertEqual(AriaForgePrep.duration(for: .empty), AriaForgePrep.floor)
    }

    func testHealthHistoryAndCloudStretchTowardTheCap() {
        let light = AriaForgePrep.Load.estimated(
            healthConnected: true,
            cycleTracking: false,
            remoteEligible: false
        )
        let heavy = AriaForgePrep.Load(
            healthConnected: true,
            sleepNights: 30,
            workoutDays: 30,
            cycleTracking: true,
            remoteEligible: true,
            clinicalLikely: true,
            chatHistoryLikely: true
        )
        let empty = AriaForgePrep.duration(for: .empty)
        let lightDuration = AriaForgePrep.duration(for: light)
        let heavyDuration = AriaForgePrep.duration(for: heavy)
        XCTAssertGreaterThan(lightDuration, empty)
        XCTAssertGreaterThan(heavyDuration, lightDuration)
        XCTAssertLessThanOrEqual(heavyDuration, AriaForgePrep.cap)
        XCTAssertGreaterThanOrEqual(empty, AriaForgePrep.floor)
        XCTAssertEqual(heavyDuration, AriaForgePrep.cap)
    }

    func testDurationNeverShrinksWhenCountsArrive() {
        let estimated = AriaForgePrep.Load.estimated(
            healthConnected: true,
            cycleTracking: true,
            remoteEligible: true
        )
        let current = AriaForgePrep.duration(for: estimated)
        let thinner = AriaForgePrep.Load.empty
        XCTAssertEqual(
            AriaForgePrep.revisedDuration(current: current, measured: thinner),
            current
        )
        let heavier = AriaForgePrep.Load(
            healthConnected: true,
            sleepNights: 30,
            workoutDays: 28,
            cycleTracking: true,
            remoteEligible: true,
            clinicalLikely: true,
            chatHistoryLikely: true
        )
        XCTAssertGreaterThanOrEqual(
            AriaForgePrep.revisedDuration(current: current, measured: heavier),
            current
        )
    }

    func testStagesWalkTheHoldWithoutAPercentHUD() {
        let duration: TimeInterval = 90
        XCTAssertEqual(AriaForgePrep.stage(at: 0, duration: duration), .profile)
        XCTAssertEqual(AriaForgePrep.stage(at: 20, duration: duration), .health)
        XCTAssertEqual(AriaForgePrep.stage(at: 40, duration: duration), .history)
        XCTAssertEqual(AriaForgePrep.stage(at: 60, duration: duration), .session)
        XCTAssertEqual(AriaForgePrep.stage(at: 80, duration: duration), .devices)
        XCTAssertEqual(AriaForgePrep.stage(at: 90, duration: duration), .ready)
        XCTAssertEqual(AriaForgePrep.Stage.profile.eyebrow, "Prepping Forge")
        XCTAssertFalse(AriaForgePrep.Stage.profile.headline.contains("%"))
        XCTAssertFalse(AriaForgePrep.Stage.health.detail(healthConnected: true).localizedCaseInsensitiveContains("loading 47"))
        XCTAssertFalse(AriaForgePrep.allowsSpeech)
    }

    func testShouldFinishHoldsUntilFloorEvenWhenWorkIsDone() {
        XCTAssertFalse(
            AriaForgePrep.shouldFinish(
                elapsed: 10,
                duration: 45,
                workFinished: true,
                skipHold: false
            )
        )
        XCTAssertTrue(
            AriaForgePrep.shouldFinish(
                elapsed: 45,
                duration: 45,
                workFinished: true,
                skipHold: false
            )
        )
    }

    func testShouldFinishWaitsForWorkUntilTheCap() {
        XCTAssertFalse(
            AriaForgePrep.shouldFinish(
                elapsed: 90,
                duration: 90,
                workFinished: false,
                skipHold: false
            )
        )
        XCTAssertTrue(
            AriaForgePrep.shouldFinish(
                elapsed: 180,
                duration: 90,
                workFinished: false,
                skipHold: false
            )
        )
    }

    func testSkipHoldFinishesAsSoonAsWorkIsDone() {
        XCTAssertFalse(
            AriaForgePrep.shouldFinish(
                elapsed: 1,
                duration: 45,
                workFinished: false,
                skipHold: true
            )
        )
        XCTAssertTrue(
            AriaForgePrep.shouldFinish(
                elapsed: 1,
                duration: 45,
                workFinished: true,
                skipHold: true
            )
        )
    }

    @MainActor
    func testInstantClockHoldsToTheFloorWithoutWallClockSleep() async {
        let clock = AriaForgePrepInstantClock()
        var lastStage = AriaForgePrep.Stage.profile
        var lastProgress = 0.0
        var ticks = 0

        await AriaForgePrep.runSequence(
            initialLoad: .empty,
            clock: clock,
            shouldSkipHold: { false },
            measuredLoad: { .empty },
            onTick: { stage, progress in
                lastStage = stage
                lastProgress = progress
                ticks += 1
            },
            work: { }
        )

        XCTAssertGreaterThanOrEqual(clock.elapsed, AriaForgePrep.floor)
        XCTAssertLessThan(clock.elapsed, AriaForgePrep.floor + AriaForgePrep.tick * 2)
        XCTAssertEqual(lastStage, .ready)
        XCTAssertEqual(lastProgress, 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(ticks, 10)
        XCTAssertLessThan(ticks, 400, "Instant clock must not spin on wall time")
    }

    @MainActor
    func testSkipHoldDoesNotWaitOutTheFloor() async {
        let clock = AriaForgePrepInstantClock()
        await AriaForgePrep.runSequence(
            initialLoad: .empty,
            clock: clock,
            shouldSkipHold: { true },
            measuredLoad: { .empty },
            onTick: { _, _ in },
            work: { }
        )
        XCTAssertLessThan(clock.elapsed, 5)
    }

    func testInterviewCompleteSurvivesAKillUntilOnboarded() {
        let key = AriaForgePrepHandoff.interviewCompleteKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        AriaForgePrepHandoff.clearInterviewComplete()
        XCTAssertFalse(AriaForgePrepHandoff.needsPrep(isOnboarded: false))
        XCTAssertFalse(AriaForgePrepHandoff.needsPrep(isOnboarded: true))

        AriaForgePrepHandoff.markInterviewComplete()
        XCTAssertTrue(AriaForgePrepHandoff.needsPrep(isOnboarded: false))
        XCTAssertFalse(
            AriaForgePrepHandoff.needsPrep(isOnboarded: true),
            "Returning users who already finished onboarding skip prep"
        )

        AriaForgePrepHandoff.clearInterviewComplete()
        XCTAssertFalse(AriaForgePrepHandoff.needsPrep(isOnboarded: false))
    }
}
