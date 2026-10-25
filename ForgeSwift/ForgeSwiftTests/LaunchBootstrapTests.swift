// Tess equivalent — LaunchBootstrapTests was not on any branch or PR.
// Pins that a kill mid-prep resumes into a visible prep state, never a
// blank root, and that the interviewComplete flag is the resume signal.
import XCTest
import ForgeCore
@testable import ForgeSwift

@MainActor
final class LaunchBootstrapTests: XCTestCase {

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

    func testKillDuringPrepResumesIntoVisiblePrepNotBlank() {
        let store = AppStore()
        store.isAuthenticated = true
        store.isOnboarded = false
        AriaForgePrepHandoff.markInterviewComplete()

        XCTAssertTrue(store.needsForgePrep)

        let coordinator = OnboardingCoordinator()
        coordinator.prepClock = AriaForgePrepInstantClock()
        coordinator.skipPrepHold = true
        coordinator.prepWorkOverride = { }
        XCTAssertFalse(coordinator.prepStage.eyebrow.isEmpty)
        XCTAssertFalse(coordinator.prepStage.headline.isEmpty)
        XCTAssertFalse(coordinator.prepStage.detail(healthConnected: false).isEmpty)

        coordinator.resumePrep(in: store)
        XCTAssertTrue(coordinator.isPrepping)
        XCTAssertFalse(coordinator.prepStage.headline.isEmpty)
        XCTAssertEqual(coordinator.prepStage.eyebrow, "Prepping Forge")
    }

    func testUnauthenticatedLeftoverFlagDoesNotForcePrep() {
        let store = AppStore()
        store.isAuthenticated = false
        store.isOnboarded = false
        AriaForgePrepHandoff.markInterviewComplete()
        AriaForgePrepHandoff.validateFlag(
            isOnboarded: store.isOnboarded,
            isAuthenticated: store.isAuthenticated
        )
        XCTAssertFalse(store.needsForgePrep)
        XCTAssertFalse(AriaForgePrepHandoff.isInterviewComplete)
    }

    func testDeviceHoldPolicyUnchanged() {
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
        XCTAssertTrue(
            AriaForgePrep.shouldFinish(
                elapsed: 180,
                duration: 90,
                workFinished: false,
                skipHold: false
            )
        )
    }
}
