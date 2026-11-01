// Tess equivalent — OnboardingGateTests was not on any branch or PR.
// Fails on main: skipPrepHold defaults to false even on the DEBUG simulator,
// and a leftover interviewComplete flag still gates prep without a session.
import XCTest
import UserNotifications
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

    #if DEBUG
    @MainActor
    func testDebugSimulatorSkipsPrepHold() {
        let coordinator = OnboardingCoordinator()
        XCTAssertEqual(
            coordinator.skipPrepHold,
            TestReadyLaunchPolicy.isRunningOnSimulator,
            "DEBUG simulator must skip the 45s–180s hold; real devices keep it"
        )
    }
    #endif

    func testFloorCapAndLeftoverWatchdog() {
        XCTAssertEqual(AriaForgePrep.floor, 45)
        XCTAssertEqual(AriaForgePrep.cap, 180)
        XCTAssertEqual(AriaForgePrep.leftoverWatchdog, 50)
        XCTAssertLessThan(AriaForgePrep.leftoverWatchdog, 60)
    }

    func testLaunchAsksForNotificationsAfterFirstFrameNotDuringIt() {
        XCTAssertEqual(
            ForgeNotificationScheduler.authorizationIntent(
                status: .notDetermined,
                promptIfUndetermined: false
            ),
            .skipPrompt,
            "first-frame path must not present the permission sheet"
        )
        XCTAssertEqual(
            ForgeNotificationScheduler.authorizationIntent(
                status: .notDetermined,
                promptIfUndetermined: true
            ),
            .prompt,
            "after the first frame, real devices and Simulator both ask"
        )
        XCTAssertEqual(
            ForgeNotificationScheduler.authorizationIntent(
                status: .authorized,
                promptIfUndetermined: false
            ),
            .alreadyGranted
        )
        XCTAssertEqual(
            ForgeNotificationScheduler.authorizationIntent(
                status: .denied,
                promptIfUndetermined: true
            ),
            .denied
        )
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
