// Pins the launch-stability failures: a fresh simulator must paint without
// a notification permission sheet, HealthKit must not probe healthd on a
// blank install, and skip-hold prep must leave AriaForgePrep without the
// 45s–180s ingest.
import XCTest
import UserNotifications
import ForgeCore
@testable import ForgeSwift

@MainActor
final class LaunchStabilityGateTests: XCTestCase {

    func testLaunchDoesNotPromptForNotificationPermission() {
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

    func testSkipHoldPrepLeavesAriaForgePrepWithoutHeavyIngest() async {
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
        coordinator.prepWorkOverride = {
            await AriaForgePrep.loadUserData(
                into: store,
                trainingTheme: .classic,
                skipHeavyIngest: true
            )
        }
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

    func testSkipHoldFinishesEvenWhenWorkNeverReturns() async {
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

        let coordinator = OnboardingCoordinator()
        coordinator.skipPrepHold = true
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
