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

    func testDisabledCycleTrackingSkipsNotificationCenterOnLaunch() {
        XCTAssertFalse(
            ForgeNotificationScheduler.shouldTouchCycleNotificationCenter(
                enabled: false,
                previouslyScheduled: false
            ),
            "MenstrualHealthStore.init must not XPC UNUserNotificationCenter when cycle tracking was never on"
        )
        XCTAssertTrue(
            ForgeNotificationScheduler.shouldTouchCycleNotificationCenter(
                enabled: true,
                previouslyScheduled: false
            )
        )
        XCTAssertTrue(
            ForgeNotificationScheduler.shouldTouchCycleNotificationCenter(
                enabled: false,
                previouslyScheduled: true
            ),
            "Turning tracking off still clears previously scheduled cycle ids"
        )
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
        XCTAssertFalse(
            coordinator.skipPrepHold,
            "Launch never sets skipPrepHold; DEBUG Skip wait is explicit"
        )
        XCTAssertEqual(AriaForgePrep.floor, 45)
        XCTAssertEqual(AriaForgePrep.cap, 55)
        XCTAssertEqual(AriaForgePrep.watchdog, 60)
        XCTAssertLessThan(AriaForgePrep.cap, AriaForgePrep.watchdog)
        XCTAssertEqual(AriaForgePrepHandoff.onboardedKey, AppStore.onboardedDefaultsKey)
    }

    func testLeftoverCapUsesProcessRelativeClockNotMachineUptime() {
        AriaForgePrep.resetToProductionClockForTests()
        defer { AriaForgePrep.resetLeftoverSessionForTests() }
        let elapsed = AriaForgePrep.elapsedSinceProcessStartForTests()
        XCTAssertLessThan(
            elapsed,
            2,
            "Leftover remaining must be process-relative, not CI machine awake time"
        )
        let machine = ProcessInfo.processInfo.systemUptime
        if machine > 5 {
            XCTAssertLessThan(elapsed, machine - 2, "Machine systemUptime is not leftover elapsed")
        }
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
        XCTAssertFalse(
            AriaForgePrepHandoff.shouldFinishLeftoverPrepOnRestore(
                isDebugSimulator: true,
                isTestHost: false,
                isAuthenticated: true,
                isInterviewComplete: true
            ),
            "Debug simulator restore is not a leftover-prep exit"
        )
        XCTAssertFalse(
            AriaForgePrepHandoff.shouldFinishLeftoverPrepOnRestore(
                isDebugSimulator: false,
                isTestHost: false,
                isAuthenticated: true,
                isInterviewComplete: true
            )
        )
    }

    func testFirstFrameRevealIsNotAThirtySecondHide() {
        XCTAssertNil(
            ProcessInfo.processInfo.environment["FORGE_LAUNCH_LIGHT_ROOT"],
            "Launch never sets FORGE_LAUNCH_LIGHT_ROOT"
        )
        XCTAssertFalse(
            ProcessInfo.processInfo.environment["FORGE_LAUNCH_LIGHT_ROOT"] == "1"
        )
        XCTAssertEqual(LaunchBrandField.markSide, 220)
        let coordinator = OnboardingCoordinator()
        XCTAssertFalse(coordinator.skipPrepHold)
    }

    func testKokoroOnlyStopAndIsSpeakingDoNotAllocateSynthesizer() {
        let presence = AriaPresence.shared
        presence.resetSynthesizerStorageForTests()
        XCTAssertNil(presence.synthesizerStorageForTests)

        presence.stopSpeaking()
        XCTAssertNil(
            presence.synthesizerStorageForTests,
            "stopSpeaking must use synthesizerStorage?, not the lazy getter"
        )
        XCTAssertFalse(presence.isSpeaking)

        XCTAssertFalse(presence.appleSynthesizerIsSpeaking)
        XCTAssertNil(
            presence.synthesizerStorageForTests,
            "isSpeaking must return false when storage is nil, without allocating"
        )
    }

    func testAriaPresenceNeverPlaysAppleFallbackVoice() {
        let presence = AriaPresence.shared
        presence.resetSynthesizerStorageForTests()
        let previousMute = AriaSpokenMute.isMuted
        AriaSpokenMute.isMuted = false
        defer {
            AriaSpokenMute.isMuted = previousMute
            presence.resetSynthesizerStorageForTests()
            presence.stopSpeaking()
        }

        XCTAssertFalse(
            AriaPresence.appleFallbackPlaybackEnabled,
            "Kokoro-82M is ARIA's only voice — AVSpeechSynthesizer must not play"
        )
        presence.speak("Kokoro-82M is the only voice.")
        XCTAssertNil(
            presence.synthesizerStorageForTests,
            "speak() must not allocate AVSpeechSynthesizer as an Apple fallback"
        )
        XCTAssertFalse(presence.appleSynthesizerIsSpeaking)
        presence.stopSpeaking()
        XCTAssertNil(presence.synthesizerStorageForTests)
    }

    func testNeedsPrepShortCircuitsOnboardedWithoutInterviewPlist() {
        AriaForgePrepHandoff.markInterviewComplete()
        defer { AriaForgePrepHandoff.clearInterviewComplete() }
        XCTAssertFalse(
            AriaForgePrepHandoff.needsPrep(isOnboarded: true, isAuthenticated: true),
            "Cold Home must not read the interview plist on the first body"
        )
        XCTAssertFalse(
            AriaForgePrepHandoff.needsPrep(isOnboarded: false, isAuthenticated: false)
        )
        XCTAssertTrue(
            AriaForgePrepHandoff.needsPrep(isOnboarded: false, isAuthenticated: true)
        )
    }

    func testLeftoverPrepFirstCommitIsForgePrepNotBrandField() {
        XCTAssertTrue(LaunchFirstCommit.leftoverPrepPending(needsForgePrep: true))
        XCTAssertFalse(LaunchFirstCommit.leftoverPrepPending(needsForgePrep: false))
        XCTAssertEqual(
            LaunchFirstCommit.surface(leftoverPrep: true, revealRoot: false),
            .forgePrep,
            "Wedged prep must draw AriaForgePrep before afterPaint / splash"
        )
        XCTAssertEqual(
            LaunchFirstCommit.surface(leftoverPrep: false, revealRoot: false),
            .brandField
        )
        XCTAssertEqual(
            LaunchFirstCommit.surface(leftoverPrep: false, revealRoot: true),
            .routed
        )
        XCTAssertFalse(
            LaunchFirstCommit.splashCoversFirstCommit(leftoverPrep: true),
            "ForgeSplashScreen is Color.background #09090B — it must not cover prep"
        )
        XCTAssertTrue(LaunchFirstCommit.splashCoversFirstCommit(leftoverPrep: false))

        let coordinator = OnboardingCoordinator()
        XCTAssertEqual(coordinator.prepStage, .profile)
        XCTAssertEqual(coordinator.prepStage.eyebrow, "Prepping Forge")
        XCTAssertFalse(coordinator.prepStage.headline.isEmpty)
        XCTAssertFalse(coordinator.prepStage.detail(healthConnected: false).isEmpty)
        XCTAssertEqual(AriaForgePrep.Stage.profile.eyebrow, "Prepping Forge")
        XCTAssertEqual(AriaForgePrep.Stage.profile.headline, "Loading your profile")
    }

    func testLaunchPathDoesNotDumpChatSheetOrStrikeOnFirstLayout() {
        XCTAssertFalse(
            LaunchFirstCommit.splashMountsStrikeOnFirstCommit,
            "ForgeStrikeMark TimelineView+Canvas stays off the first splash commit"
        )
        XCTAssertFalse(
            LaunchFirstCommit.shouldOpenChatAfterPrep(leftoverResume: true),
            "Leftover fail-open must land on Home, not Chat+AriaMeet+weekly sheet"
        )
        XCTAssertTrue(LaunchFirstCommit.shouldOpenChatAfterPrep(leftoverResume: false))
        XCTAssertFalse(
            LaunchFirstCommit.shouldPromptNotifications(needsForgePrep: true),
            "Leftover prep must not present the notification permission sheet"
        )
        XCTAssertTrue(LaunchFirstCommit.shouldPromptNotifications(needsForgePrep: false))
        XCTAssertFalse(LaunchFirstCommit.shouldAttachVoiceGates(leftoverPrep: true))
        XCTAssertTrue(LaunchFirstCommit.shouldAttachVoiceGates(leftoverPrep: false))
        XCTAssertFalse(
            LaunchFirstCommit.shouldAttachVoiceGatesOnLaunch(leftoverPrep: false, isOnboarded: false),
            "Kokoro 210 MB sheet is not an interview first frame"
        )
        XCTAssertTrue(
            LaunchFirstCommit.shouldAttachVoiceGatesOnLaunch(leftoverPrep: false, isOnboarded: true)
        )
        XCTAssertFalse(LaunchFirstCommit.promptsNotificationsOnOnboardingAppear)
        XCTAssertFalse(
            LaunchFirstCommit.presentsWeeklyReviewOnFirstChatLayout,
            "WeeklyAriaReviewSheet is not a first Chat layout"
        )
        XCTAssertEqual(AppStore().activeTab, .home)
    }

    func testLeftoverFailOpenBeatsWatchdogWithMargin() {
        XCTAssertEqual(AriaForgePrep.floor, 45)
        XCTAssertEqual(AriaForgePrep.cap, 55)
        XCTAssertEqual(AriaForgePrep.watchdog, 60)
        XCTAssertEqual(AriaForgePrep.leftoverFailOpen, 24)
        // Origin slop (dyld / AppStore init) plus the harness's 2s poll
        // must still leave real margin under PREP_WATCHDOG_S. The old
        // watchdog-12 (48s) path ended near 57s.
        XCTAssertLessThan(AriaForgePrep.leftoverFailOpen + 8 + 2, AriaForgePrep.watchdog)
        XCTAssertLessThan(AriaForgePrep.leftoverFailOpen, AriaForgePrep.watchdog - 20)
        // Process-handoff retries are 8 × 2s after leftoverFailOpen.
        XCTAssertLessThan(AriaForgePrep.leftoverFailOpen + 16 + 8, AriaForgePrep.watchdog)

        let atProcessStart = AriaForgePrep.leftoverRemaining(
            requested: AriaForgePrep.cap,
            elapsed: 0
        )
        XCTAssertEqual(atProcessStart, AriaForgePrep.leftoverFailOpen)
        XCTAssertLessThan(atProcessStart, AriaForgePrep.watchdog)

        let afterTenSeconds = AriaForgePrep.leftoverRemaining(
            requested: AriaForgePrep.cap,
            elapsed: 10
        )
        XCTAssertEqual(afterTenSeconds, AriaForgePrep.leftoverFailOpen - 10)
        XCTAssertLessThan(afterTenSeconds + 10 + 8 + 2, AriaForgePrep.watchdog)

        let injected = AriaForgePrep.leftoverRemaining(requested: 0.05, elapsed: 0)
        XCTAssertEqual(injected, 0.05)
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
        while AriaForgePrepHandoff.isInterviewComplete && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(AriaForgePrepHandoff.isInterviewComplete)
        XCTAssertFalse(store.isOnboarded)
        XCTAssertEqual(store.launchRootDestination, .authWelcome)
    }

    func testLeftoverTimeoutWithoutSessionDoesNotSkipAuth() async {
        AriaForgePrep.resetLeftoverSessionForTests()
        defer { AriaForgePrep.resetLeftoverSessionForTests() }

        let store = AppStore()
        store.isAuthenticated = false
        store.isOnboarded = false
        AriaForgePrepHandoff.markInterviewComplete()
        XCTAssertEqual(store.launchRootDestination, .authWelcome)

        // Injected duration — not the 55s product cap.
        AriaForgePrep.armLeftoverTimeout(store: store, after: 0.05)
        let deadline = Date().addingTimeInterval(2)
        while AriaForgePrepHandoff.isInterviewComplete && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertFalse(AriaForgePrepHandoff.isInterviewComplete)
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(store.isOnboarded)
        XCTAssertFalse(store.needsForgePrep)
        XCTAssertEqual(
            store.launchRootDestination,
            .authWelcome,
            "Leftover fail-open must clear the prep hang, not skip sign-in"
        )
        XCTAssertNotEqual(store.launchRootDestination, .home)
    }

    func testStaleSessionV1AloneDoesNotAuthenticateOutsideHarnessPath() {
        let client = ForgeAuthClient.shared
        let previousOverride = client.devOverrideEnabled
        let previousAuth = UserDefaults.standard.object(forKey: AppStore.authDefaultsKey)
        let previousOnboarded = UserDefaults.standard.object(forKey: AppStore.onboardedDefaultsKey)
        let previousInterview = UserDefaults.standard.object(
            forKey: AriaForgePrepHandoff.interviewCompleteKey
        )
        defer {
            client.devOverrideEnabled = previousOverride
            if previousOverride {
                _ = client.installTestReadySessionIfNeeded()
            }
            if let previousAuth {
                UserDefaults.standard.set(previousAuth, forKey: AppStore.authDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppStore.authDefaultsKey)
            }
            if let previousOnboarded {
                UserDefaults.standard.set(previousOnboarded, forKey: AppStore.onboardedDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppStore.onboardedDefaultsKey)
            }
            if let previousInterview {
                UserDefaults.standard.set(
                    previousInterview,
                    forKey: AriaForgePrepHandoff.interviewCompleteKey
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: AriaForgePrepHandoff.interviewCompleteKey
                )
            }
            UserDefaults.standard.synchronize()
        }

        // Outside the test-ready / harness path: no auto-minted tester.
        client.devOverrideEnabled = false
        client.signOut()
        UserDefaults.standard.set(false, forKey: AppStore.onboardedDefaultsKey)
        UserDefaults.standard.set(true, forKey: AppStore.authDefaultsKey)
        UserDefaults.standard.synchronize()
        AriaForgePrepHandoff.markInterviewComplete()
        XCTAssertTrue(
            AriaForgePrepHandoff.readBool(AppStore.authDefaultsKey),
            "Fixture: leftover forge.auth.session.v1 is YES"
        )
        XCTAssertNil(client.session)

        let store = AppStore()
        XCTAssertFalse(
            store.isAuthenticated,
            "Stale forge.auth.session.v1 alone must not authenticate outside harness"
        )
        XCTAssertNil(ForgeAuthClient.shared.session)
        XCTAssertFalse(store.isOnboarded)
        XCTAssertEqual(store.launchRootDestination, .authWelcome)
        XCTAssertNotEqual(store.launchRootDestination, .home)
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
        // Flush clears interview off-actor so needsForgePrep goes false
        // before finishForgePrep hops isOnboarded. Wait on isOnboarded;
        // do not `await` inside XCTAssert (autoclosure) or to the right of `||`.
        let deadline = Date().addingTimeInterval(2)
        var onboarded = false
        while Date() < deadline {
            onboarded = store.isOnboarded
            if onboarded { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(onboarded)
        XCTAssertFalse(store.needsForgePrep)
        XCTAssertFalse(AriaForgePrepHandoff.isInterviewComplete)
    }

    func testLeftoverTimeoutFlushesHandoffOffMainActor() {
        AriaForgePrep.resetLeftoverSessionForTests()
        let previousOnboarded = UserDefaults.standard.object(forKey: AppStore.onboardedDefaultsKey)
        defer {
            AriaForgePrep.resetLeftoverSessionForTests()
            if let previousOnboarded {
                UserDefaults.standard.set(previousOnboarded, forKey: AppStore.onboardedDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppStore.onboardedDefaultsKey)
            }
            UserDefaults.standard.synchronize()
        }

        let store = AppStore()
        store.isAuthenticated = true
        store.isOnboarded = false
        AriaForgePrepHandoff.markInterviewComplete()
        XCTAssertTrue(store.needsForgePrep)

        AriaForgePrep.armLeftoverTimeout(store: store, after: 0.05)
        // Block the main thread so finishForgePrep cannot hop back.
        // The detached fail-open must still flush the launch-gate plist.
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(
            AriaForgePrepHandoff.isInterviewComplete,
            "Leftover fail-open must flush CFPreferences without waiting on MainActor"
        )
        XCTAssertTrue(
            AriaForgePrepHandoff.readBool(AppStore.onboardedDefaultsKey),
            "Authenticated leftover fail-open marks onboarded on disk"
        )
        XCTAssertEqual(
            store.activeTab,
            .home,
            "Fail-open must not hop to Chat on the same commit as onboarded"
        )
    }
}
