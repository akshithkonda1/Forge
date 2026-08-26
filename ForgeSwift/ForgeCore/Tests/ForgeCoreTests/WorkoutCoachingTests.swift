import XCTest
@testable import ForgeCore

/// Zone-boundary coaching: when a cue fires, and what it says.
///
/// Extracted from WorkoutSessionManager.maybeCoach. The throttle is the part
/// with a physical consequence — without it, anyone training on a zone boundary
/// gets a haptic on every sample.
final class WorkoutCoachingTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func zone(_ n: Int) -> ForgeHRZone {
        ForgeHRZones.zone(for: [0: 100, 1: 100, 2: 120, 3: 140, 4: 155, 5: 175][n] ?? 100)
    }

    func testNoCueWithoutAZoneChange() {
        let decision = WorkoutCoaching.cue(
            zone: zone(3), previousZone: 3, target: 3,
            lastCueAt: .distantPast, now: t0
        )
        XCTAssertNil(decision, "the same zone is not news")
    }

    func testFirstZoneReadingCues() {
        let decision = WorkoutCoaching.cue(
            zone: zone(3), previousZone: nil, target: 3,
            lastCueAt: .distantPast, now: t0
        )
        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.firedAt, t0)
    }

    func testThrottleSuppressesARapidSecondCue() {
        let decision = WorkoutCoaching.cue(
            zone: zone(4), previousZone: 3, target: 3,
            lastCueAt: t0, now: t0.addingTimeInterval(10)
        )
        XCTAssertNil(decision, "a boundary flicker must not buzz the wrist repeatedly")
    }

    func testThrottleReleasesAfterTheWindow() {
        let decision = WorkoutCoaching.cue(
            zone: zone(4), previousZone: 3, target: 3,
            lastCueAt: t0, now: t0.addingTimeInterval(WorkoutCoaching.throttle + 1)
        )
        XCTAssertNotNil(decision)
    }

    func testWellAboveTargetSuggestsEasingWithoutInstructing() {
        let cue = WorkoutCoaching.cue(
            zone: zone(5), previousZone: 3, target: 3,
            lastCueAt: .distantPast, now: t0
        )?.cue
        XCTAssertEqual(cue?.contains("easing off"), true)
        XCTAssertEqual(cue?.contains("Your call"), true, "reports, never commands")
    }

    func testWellBelowTargetOffersHeadroom() {
        let cue = WorkoutCoaching.cue(
            zone: zone(1), previousZone: 3, target: 4,
            lastCueAt: .distantPast, now: t0
        )?.cue
        XCTAssertEqual(cue?.contains("Plenty in reserve"), true)
        XCTAssertEqual(cue?.contains("No rush"), true)
    }

    func testMobilityAndYogaAreNeverToldToGoHarder() {
        let cue = WorkoutCoaching.cue(
            zone: zone(1), previousZone: 3, target: 4,
            lastCueAt: .distantPast, now: t0, allowsBuildingUp: false
        )?.cue
        XCTAssertEqual(cue?.contains("Plenty in reserve"), false,
                       "a restorative session is not an effort to escalate")
    }

    func testOneZoneOffTargetIsStillJustTheZoneLine() {
        // Adjacent to target is normal drift, not a deviation worth naming.
        let cue = WorkoutCoaching.cue(
            zone: zone(4), previousZone: 2, target: 3,
            lastCueAt: .distantPast, now: t0
        )?.cue
        XCTAssertEqual(cue, zone(4).coachingLine)
    }

    func testFiredAtIsTheInstantToCarryForward() {
        let now = t0.addingTimeInterval(500)
        let decision = WorkoutCoaching.cue(
            zone: zone(2), previousZone: 1, target: 3,
            lastCueAt: t0, now: now
        )
        XCTAssertEqual(decision?.firedAt, now,
                       "the manager stores this as lastCueAt; a wrong value breaks the throttle")
    }
}
