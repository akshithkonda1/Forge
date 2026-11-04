// Tess equivalent — OnboardingGateTests was not on any branch or PR.
// Fails on main: skipPrepHold defaults to false even on the DEBUG simulator,
// and a leftover interviewComplete flag still gates prep without a session.
import XCTest
import ForgeCore
@testable import ForgeSwift

final class OnboardingGateTests: XCTestCase {

    private var previousFlag: Any?

    override func setUp() {
        super.setUp()
        previousFlag = UserDefaults.standard.object(forKey: AriaForgePrepHandoff.interviewCompleteKey)
        AriaForgePrepHandoff.clearInterviewComplete()
    }

    override func tearDown() {
        if let previousFlag {
            UserDefaults.standard.set(previousFlag, forKey: AriaForgePrepHandoff.interviewCompleteKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AriaForgePrepHandoff.interviewCompleteKey)
        }
        super.tearDown()
    }

    @MainActor
    func testPrepHoldIsOnForEveryBuild() {
        let coordinator = OnboardingCoordinator()
        XCTAssertFalse(
            coordinator.skipPrepHold,
            "Launch never skips the 45–55s hold. DEBUG Skip wait is explicit."
        )
    }

    func testFloorAndCapBeatTheWatchdog() {
        XCTAssertEqual(AriaForgePrep.floor, 45)
        XCTAssertEqual(AriaForgePrep.cap, 55)
        XCTAssertLessThan(AriaForgePrep.cap, AriaForgePrep.watchdog)
    }

    func testStaleInterviewFlagClearsWhenUnauthenticated() {
        AriaForgePrepHandoff.markInterviewComplete()
        XCTAssertTrue(AriaForgePrepHandoff.isInterviewComplete)
        AriaForgePrepHandoff.validateFlag(isOnboarded: false, isAuthenticated: false)
        XCTAssertFalse(AriaForgePrepHandoff.isInterviewComplete)
        XCTAssertFalse(
            AriaForgePrepHandoff.needsPrep(isOnboarded: false, isAuthenticated: false)
        )
    }

    func testValidResumeKeepsFlagUntilPrepFinishes() {
        AriaForgePrepHandoff.markInterviewComplete()
        AriaForgePrepHandoff.validateFlag(isOnboarded: false, isAuthenticated: true)
        XCTAssertTrue(AriaForgePrepHandoff.isInterviewComplete)
        XCTAssertTrue(AriaForgePrepHandoff.needsPrep(isOnboarded: false, isAuthenticated: true))
        XCTAssertFalse(AriaForgePrepHandoff.needsPrep(isOnboarded: true, isAuthenticated: true))
    }
}
