import XCTest
@testable import ForgeCore

/// Pause bookkeeping for a practice session.
///
/// This lived in MindfulnessSessionManager as two mutable fields updated from
/// five call sites with nothing checking any of them. The failure is quiet in
/// both directions: fold the running segment in twice and the user is credited
/// with practice they did not do; forget to fold it in and a session they
/// finished does not reach the 30-second bar that logs it to Health.
final class SessionClockTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testElapsedIsZeroBeforeAnythingStarts() {
        XCTAssertEqual(SessionClock().elapsed(at: t0), 0)
        XCTAssertFalse(SessionClock().isRunning)
    }

    func testRunningClockAccumulatesRealTime() {
        let clock = SessionClock.started(at: t0)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(30)), 30)
    }

    func testPausedClockStops() {
        let clock = SessionClock.started(at: t0).paused(at: t0.addingTimeInterval(30))
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(300)), 30,
                       "time while paused must not count")
    }

    func testResumeContinuesFromWhereItStopped() {
        let clock = SessionClock.started(at: t0)
            .paused(at: t0.addingTimeInterval(30))
            .resumed(at: t0.addingTimeInterval(300))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(310)), 40,
                       "30 practised, 270 paused, 10 more practised")
    }

    func testSeveralPausesCompose() {
        var clock = SessionClock.started(at: t0)
        clock = clock.paused(at: t0.addingTimeInterval(10))
        clock = clock.resumed(at: t0.addingTimeInterval(100))
        clock = clock.paused(at: t0.addingTimeInterval(120))
        clock = clock.resumed(at: t0.addingTimeInterval(200))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(205)), 35)
    }

    func testPausingTwiceDoesNotDoubleCount() {
        let once = SessionClock.started(at: t0).paused(at: t0.addingTimeInterval(30))
        let twice = once.paused(at: t0.addingTimeInterval(90))
        XCTAssertEqual(twice, once)
        XCTAssertEqual(twice.elapsed(at: t0.addingTimeInterval(90)), 30)
    }

    func testResumingARunningClockDoesNotDiscardTheSegmentInFlight() {
        let clock = SessionClock.started(at: t0)
        let again = clock.resumed(at: t0.addingTimeInterval(30))
        XCTAssertEqual(again, clock)
        XCTAssertEqual(again.elapsed(at: t0.addingTimeInterval(30)), 30)
    }

    func testBackwardsClockCannotSubtractPractisedTime() {
        // A clock adjustment mid-session must not hand back negative practice.
        let clock = SessionClock(accumulated: 60, segmentStartedAt: t0)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(-45)), 60)
    }

    func testStoppedBanksTheRunningSegment() {
        let clock = SessionClock.started(at: t0).stopped(at: t0.addingTimeInterval(42))
        XCTAssertEqual(clock.accumulated, 42)
        XCTAssertFalse(clock.isRunning)
    }

    func testCompletedCreditsThePlanNotTheTickThatNoticed() {
        // The runner wakes a little after the duration expires; the user gets
        // the session they planned, not 180.3 seconds of it.
        let clock = SessionClock.started(at: t0).completed(of: 180)
        XCTAssertEqual(clock.accumulated, 180)
        XCTAssertFalse(clock.isRunning)
    }

    func testRemainingAndCompletion() {
        let clock = SessionClock.started(at: t0)
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(60), of: 180), 120)
        XCTAssertFalse(clock.isComplete(at: t0.addingTimeInterval(179), of: 180))
        XCTAssertTrue(clock.isComplete(at: t0.addingTimeInterval(180), of: 180))
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(500), of: 180), 0,
                       "remaining never goes negative")
    }

    func testThirtySecondLoggingBarSurvivesAPause() {
        // endEarly credits anything >= 30s. A session practised for 20s, paused
        // for an hour, then practised 15s more is 35s of practice and counts.
        let clock = SessionClock.started(at: t0)
            .paused(at: t0.addingTimeInterval(20))
            .resumed(at: t0.addingTimeInterval(3600))
            .stopped(at: t0.addingTimeInterval(3615))
        XCTAssertEqual(clock.accumulated, 35)
        XCTAssertGreaterThanOrEqual(clock.accumulated, 30)
    }
}
