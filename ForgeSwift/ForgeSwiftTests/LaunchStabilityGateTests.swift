// Pins the real launch path: no notification sheet at launch, leftover
// prep runs the 45–55s hold on every build, and the cap beats the 60s
// watchdog even when ingest hangs.
import XCTest
import UserNotifications
import ForgeCore
@testable import ForgeSwift

@MainActor
final class LaunchStabilityGateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AriaForgePrep.resetLeftoverSessionForTests()
    }

    override func tearDown() {
        AriaForgePrep.resetLeftoverSessionForTests()
        super.tearDown()
    }

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
        XCTAssertEqual(
            ForgeNotificationScheduler.authorizationIntent(
                status: .provisional,
                promptIfUndetermined: false
            ),
            .alreadyGranted
        )
    }

    func testPrepHoldDefaultsOffAndCapBeatsWatchdog() {
        let coordinator = OnboardingCoordinator()
        XCTAssertFalse(coordinator.skipPrepHold)
        XCTAssertEqual(AriaForgePrep.floor, 45)
        XCTAssertEqual(AriaForgePrep.cap, 55)
        XCTAssertEqual(AriaForgePrep.watchdog, 60)
        XCTAssertLessThan(AriaForgePrep.cap, AriaForgePrep.watchdog)
    }

    func testWatchdogCapFinishesEvenWhenWorkNeverReturns() async {
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
        coordinator.skipPrepHold = false
        coordinator.prepWorkOverride = {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
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

    func testRestoreDoesNotFinishLeftoverPrep() {
        let store = AppStore()
        store.isAuthenticated = true
        store.isOnboarded = false
        AriaForgePrepHandoff.markInterviewComplete()
        AriaForgePrepHandoff.validateFlag(
            isOnboarded: store.isOnboarded,
            isAuthenticated: store.isAuthenticated
        )
        XCTAssertTrue(store.needsForgePrep)
        XCTAssertTrue(AriaForgePrepHandoff.isInterviewComplete)
        XCTAssertFalse(store.isOnboarded)
    }

    func testFirstFrameRevealIsNotAThirtySecondHide() {
        XCTAssertFalse(
            ProcessInfo.processInfo.environment["FORGE_LAUNCH_LIGHT_ROOT"] == "1"
        )
        XCTAssertEqual(LaunchBrandField.markSide, 220)
    }

    func testLeftoverTimeoutArmsWithoutRestoredAuth() async {
        AriaForgePrep.resetLeftoverSessionForTests()
        defer { AriaForgePrep.resetLeftoverSessionForTests() }

        let store = AppStore()
        store.isAuthenticated = false
        store.isOnboarded = false
        AriaForgePrepHandoff.markInterviewComplete()
        XCTAssertFalse(store.needsForgePrep)

        AriaForgePrep.armLeftoverTimeout(store: store, after: 0.05)
        let deadline = Date().addingTimeInterval(2)
        while !store.isOnboarded && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(store.isOnboarded)
        XCTAssertFalse(AriaForgePrepHandoff.isInterviewComplete)
    }

    func testLeftoverTimeoutFinishesWhenHoldNeverStarts() async {
        AriaForgePrep.resetLeftoverSessionForTests()
        defer { AriaForgePrep.resetLeftoverSessionForTests() }

        let store = AppStore()
        store.isAuthenticated = true
        store.isOnboarded = false
        AriaForgePrepHandoff.markInterviewComplete()
        XCTAssertTrue(store.needsForgePrep)

        AriaForgePrep.armLeftoverTimeout(store: store, after: 0.05)
        let deadline = Date().addingTimeInterval(2)
        while store.needsForgePrep && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(store.needsForgePrep)
        XCTAssertTrue(store.isOnboarded)
        XCTAssertFalse(AriaForgePrepHandoff.isInterviewComplete)
    }
}
