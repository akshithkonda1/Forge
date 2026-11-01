// Pins the shared launch-stability contract from #506: leftover AriaForgePrep
// times out before PREP_WATCHDOG_S, and the notification sheet waits until
// after the first frame. No Simulator-only skip flags.
import XCTest
import UserNotifications
import ForgeCore
@testable import ForgeSwift

@MainActor
final class LaunchStabilityGateTests: XCTestCase {

    func testLaunchDoesNotPromptForNotificationPermissionOnFirstFrame() {
        XCTAssertEqual(
            ForgeNotificationScheduler.authorizationIntent(
                status: .notDetermined,
                promptIfUndetermined: false
            ),
            .skipPrompt
        )
        XCTAssertEqual(
            ForgeNotificationScheduler.authorizationIntent(
                status: .notDetermined,
                promptIfUndetermined: true
            ),
            .prompt
        )
    }

    func testLeftoverWatchdogIsUnderTheLaunchPrepWatchdog() {
        XCTAssertEqual(AriaForgePrep.floor, 45)
        XCTAssertEqual(AriaForgePrep.leftoverWatchdog, 50)
        XCTAssertLessThan(AriaForgePrep.leftoverWatchdog, 60)
        XCTAssertTrue(
            AriaForgePrep.shouldFinish(
                elapsed: 50,
                duration: 180,
                workFinished: false,
                skipHold: false
            )
        )
    }

    func testSkipHoldPrepLeavesAriaForgePrepWhenWorkIsEmpty() async {
        let previousFlag = UserDefaults.standard.object(
            forKey: AriaForgePrepHandoff.interviewCompleteKey
        )
        let previousOnboarded = UserDefaults.standard.object(forKey: AppStore.onboardedDefaultsKey)
        defer {
            if let previousFlag {
                UserDefaults.standard.set(previousFlag, forKey: AriaForgePrepHandoff.interviewCompleteKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AriaForgePrepHandoff.interviewCompleteKey)
            }
            if let previousOnboarded {
                UserDefaults.standard.set(previousOnboarded, forKey: AppStore.onboardedDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppStore.onboardedDefaultsKey)
            }
        }

        let store = AppStore()
        store.isAuthenticated = true
        store.isOnboarded = false
        AriaForgePrepHandoff.markInterviewComplete()
        XCTAssertTrue(store.needsForgePrep)

        let coordinator = OnboardingCoordinator()
        coordinator.prepClock = AriaForgePrepInstantClock()
        coordinator.skipPrepHold = true
        coordinator.prepWorkOverride = { }
        coordinator.resumePrep(in: store)
        let deadline = Date().addingTimeInterval(2)
        while coordinator.isPrepping && Date() < deadline {
            await Task.yield()
        }
        XCTAssertFalse(coordinator.isPrepping)
        XCTAssertTrue(store.isOnboarded)
        XCTAssertFalse(AriaForgePrepHandoff.isInterviewComplete)
        XCTAssertFalse(store.needsForgePrep)
    }
}
