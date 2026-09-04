import XCTest
@testable import ForgeCore

/// What Forge claims is worth showing, and in what order.
///
/// The ordering is the contract, not the numbers: a live workout must outrank
/// a wind-down prompt, which must outrank an ambient glance. Get that wrong and
/// a running session slides down the Smart Stack while a "time to wind down"
/// card sits above it.
final class SmartStackRelevanceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 3_000_000)

    private func snapshot(
        workoutPhase: WorkoutLiveState.Phase? = nil,
        windDown: Date? = nil,
        practice: PracticeType? = nil
    ) -> WatchSnapshot {
        var snapshot = WatchSnapshot()
        if let workoutPhase {
            snapshot.activeWorkout = WorkoutLiveState(
                workoutType: .strength,
                phase: workoutPhase,
                startedAt: now,
                elapsedSeconds: 600
            )
        }
        snapshot.tonightWindDown = windDown
        snapshot.recommendedPractice = practice
        return snapshot
    }

    func testNoSnapshotClaimsNothing() {
        XCTAssertNil(SmartStackRelevance.score(for: nil, now: now))
    }

    func testALiveWorkoutOutranksEverythingElse() {
        let live = SmartStackRelevance.score(
            for: snapshot(workoutPhase: .active, windDown: now, practice: .focusReset),
            now: now
        )
        XCTAssertEqual(live?.score, SmartStackRelevance.liveSession)
        XCTAssertNil(live?.duration, "the app replaces this on every phase change")
    }

    func testEveryLivePhaseCounts() {
        // Resting and paused are still a session in progress; only .ended is not.
        for phase in [WorkoutLiveState.Phase.countdown, .active, .resting, .paused] {
            XCTAssertEqual(
                SmartStackRelevance.score(for: snapshot(workoutPhase: phase), now: now)?.score,
                SmartStackRelevance.liveSession,
                "\(phase) should still rank as a live session"
            )
        }
    }

    func testAnEndedWorkoutDoesNotHoldTheTopSlot() {
        let score = SmartStackRelevance.score(for: snapshot(workoutPhase: .ended), now: now)?.score
        XCTAssertEqual(score, SmartStackRelevance.ambient)
    }

    func testWindDownIsRelevantAroundItsWindow() {
        let soon = now.addingTimeInterval(30 * 60)
        let relevance = SmartStackRelevance.score(for: snapshot(windDown: soon), now: now)
        XCTAssertEqual(relevance?.score, SmartStackRelevance.flagged)
        XCTAssertEqual(relevance?.duration, SmartStackRelevance.windDownWindowMinutes * 60)
    }

    func testWindDownStaysRelevantJustAfterItOpens() {
        // The half hour after the window opened matters at least as much as
        // the half hour before it.
        let passed = now.addingTimeInterval(-30 * 60)
        XCTAssertEqual(
            SmartStackRelevance.score(for: snapshot(windDown: passed), now: now)?.score,
            SmartStackRelevance.flagged
        )
    }

    func testADistantWindDownIsNotUrgent() {
        let hours = now.addingTimeInterval(6 * 3600)
        XCTAssertEqual(
            SmartStackRelevance.score(for: snapshot(windDown: hours), now: now)?.score,
            SmartStackRelevance.ambient,
            "a bedtime six hours out is not a reason to take a Smart Stack slot"
        )
    }

    func testARecommendedResetRanksAboveAmbientAndBelowWindDown() {
        let reset = SmartStackRelevance.score(for: snapshot(practice: .focusReset), now: now)?.score
        XCTAssertNotNil(reset)
        XCTAssertGreaterThan(reset!, SmartStackRelevance.ambient)
        XCTAssertLessThan(reset!, SmartStackRelevance.flagged,
                          "a reset keeps; a bedtime does not")
    }

    func testAnEmptySnapshotIsStillWorthAGlance() {
        XCTAssertEqual(SmartStackRelevance.score(for: WatchSnapshot(), now: now)?.score,
                       SmartStackRelevance.ambient)
    }

    func testTheOrderingHoldsEndToEnd() {
        // The property that actually matters, asserted as one chain.
        let live = SmartStackRelevance.score(for: snapshot(workoutPhase: .active), now: now)!.score
        let bedtime = SmartStackRelevance.score(for: snapshot(windDown: now), now: now)!.score
        let reset = SmartStackRelevance.score(for: snapshot(practice: .boxBreathing), now: now)!.score
        let idle = SmartStackRelevance.score(for: WatchSnapshot(), now: now)!.score
        XCTAssertTrue(live > bedtime && bedtime > reset && reset > idle)
    }
}
