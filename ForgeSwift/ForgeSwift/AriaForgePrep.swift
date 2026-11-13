import Foundation
import ForgeCore

/// Module load, before `AppStore.init`. Leftover fail-open is counted from
/// here so a true-cold dyld still leaves AriaForgePrep before `watchdog`.
let forgeProcessStart = Date()

/// Console-style first boot after the ARIA interview: load this person's
/// profile, Health, history, plan, Watch, and reminders before the shell
/// opens. Duration is 45–55 seconds from how much data there is. The cap
/// is the product timeout: prep always finishes or fails open before
/// `PREP_WATCHDOG_S` (60s) on every build — device, simulator, Debug,
/// Release.
enum AriaForgePrep: Sendable {
    static let floor: TimeInterval = 45
    /// Leave the console before the launch-stability watchdog (60s).
    static let cap: TimeInterval = 55
    /// Same number as `ForgeSwift/Scripts/launch-gate/thresholds.env`.
    static let watchdog: TimeInterval = 60
    /// Leftover / wedge fail-open from process start. The 45–55s hold still
    /// runs when ingest finishes; this deadline shows the shell with partial
    /// data if the hold never starts or ingest hangs. `watchdog - 12` (48s)
    /// plus dyld / AppStore-init origin slop and the harness's 2s poll landed
    /// at ~57s against a 60s gate — not real margin. Does not change
    /// `floor`, `cap`, or `watchdog`.
    static let leftoverFailOpen: TimeInterval = 24
    static let tick: TimeInterval = 0.25
    /// Shared leftover-prep timeout from #506. The visual hold still uses
    /// `floor`…`cap`, but a hung HealthKit / notification await must not keep
    /// `interviewComplete` set past the launch-stability `PREP_WATCHDOG_S=60`.
    static let leftoverWatchdog: TimeInterval = 50

    /// Prep copy is on-screen only. Spoken ARIA during this sequence is a fail
    /// (same bar as reading the UI aloud).
    static let allowsSpeech = false

    struct Load: Equatable, Sendable {
        var healthConnected: Bool
        var sleepNights: Int
        var workoutDays: Int
        var cycleTracking: Bool
        var remoteEligible: Bool
        var clinicalLikely: Bool
        var chatHistoryLikely: Bool

        static let empty = Load(
            healthConnected: false,
            sleepNights: 0,
            workoutDays: 0,
            cycleTracking: false,
            remoteEligible: false,
            clinicalLikely: false,
            chatHistoryLikely: false
        )

        /// First guess at interview-end, before HealthKit returns counts.
        static func estimated(
            healthConnected: Bool,
            cycleTracking: Bool,
            remoteEligible: Bool
        ) -> Load {
            Load(
                healthConnected: healthConnected,
                sleepNights: healthConnected ? 12 : 0,
                workoutDays: healthConnected ? 8 : 0,
                cycleTracking: cycleTracking,
                remoteEligible: remoteEligible,
                clinicalLikely: healthConnected,
                chatHistoryLikely: remoteEligible
            )
        }
    }

    enum Stage: Int, CaseIterable, Sendable {
        case profile
        case health
        case history
        case session
        case devices
        case ready

        var eyebrow: String { "Prepping Forge" }

        var headline: String {
            switch self {
            case .profile: return "Loading your profile"
            case .health: return "Pulling Apple Health"
            case .history: return "Reading nights and sessions"
            case .session: return "Building today's session"
            case .devices: return "Syncing Watch and reminders"
            case .ready: return "Forge is ready"
            }
        }

        func detail(healthConnected: Bool) -> String {
            switch self {
            case .profile:
                return "Name, goals, and how you like to be coached."
            case .health:
                return healthConnected
                    ? "Sleep, heart, and the last month of movement."
                    : "Setting the floor without Apple Health — you can connect later."
            case .history:
                return "Profiles first. Then the history ARIA coaches from."
            case .session:
                return "From this morning's signals, not a catalog default."
            case .devices:
                return "So ARIA is the same person on every screen."
            case .ready:
                return "ARIA already knows the day."
            }
        }

        func footer(progress: Double) -> String {
            if self == .ready || progress >= 0.9 {
                return "ARIA already knows the day."
            }
            if progress >= 0.55 {
                return "Almost there."
            }
            return "This can take a minute."
        }
    }

    /// 45s with nothing to ingest. Scales toward the 55s cap as Health
    /// history, cycle, clinical records, and cloud chat show up. Never
    /// below floor, never above cap.
    static func duration(for load: Load) -> TimeInterval {
        var extra: TimeInterval = 0
        if load.healthConnected { extra += 25 }
        extra += min(35, TimeInterval(max(0, load.sleepNights)) * 1.2)
        extra += min(25, TimeInterval(max(0, load.workoutDays)) * 0.85)
        if load.cycleTracking { extra += 15 }
        if load.remoteEligible { extra += 20 }
        if load.clinicalLikely { extra += 12 }
        if load.chatHistoryLikely { extra += 10 }
        if load.healthConnected { extra += 8 }
        return min(cap, max(floor, floor + extra))
    }

    /// Duration only grows once real counts land — the bar never jumps backward.
    static func revisedDuration(current: TimeInterval, measured: Load) -> TimeInterval {
        max(current, duration(for: measured))
    }

    static func stage(at elapsed: TimeInterval, duration: TimeInterval) -> Stage {
        let t = duration > 0 ? min(1, max(0, elapsed / duration)) : 1
        switch t {
        case ..<0.16: return .profile
        case ..<0.34: return .health
        case ..<0.54: return .history
        case ..<0.74: return .session
        case ..<0.90: return .devices
        default: return .ready
        }
    }

    static func progress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, elapsed / duration))
    }

    /// Hold until the floor (console boot) even if loads finish early.
    /// If loads run long, wait for them until the cap, then open the
    /// shell and let remaining work finish in the background. The cap
    /// is the graceful timeout — every build leaves AriaForgePrep before
    /// the 60s watchdog.
    static func shouldFinish(
        elapsed: TimeInterval,
        duration: TimeInterval,
        workFinished: Bool,
        skipHold: Bool,
        cap: TimeInterval = cap,
        leftoverWatchdog watchdog: TimeInterval = AriaForgePrep.leftoverWatchdog
    ) -> Bool {
        if elapsed >= cap { return true }
        if elapsed >= watchdog { return true }
        if skipHold { return workFinished }
        return workFinished && elapsed >= duration
    }
}

// MARK: - Clock (tests inject an instant clock so they never sleep 45s)

@MainActor
protocol AriaForgePrepClock: AnyObject {
    func now() -> Date
    func sleep(_ duration: TimeInterval) async
}

@MainActor
final class AriaForgePrepSystemClock: AriaForgePrepClock {
    func now() -> Date { Date() }

    func sleep(_ duration: TimeInterval) async {
        guard duration > 0 else { return }
        let ns = UInt64((duration * 1_000_000_000).rounded())
        try? await Task.sleep(nanoseconds: ns)
    }
}

/// Advances virtual time immediately and yields so parallel MainActor work
/// can run. XCTest uses this instead of wall-clock 45s–3min.
@MainActor
final class AriaForgePrepInstantClock: AriaForgePrepClock {
    private(set) var elapsed: TimeInterval = 0

    func now() -> Date { Date(timeIntervalSinceReferenceDate: elapsed) }

    func sleep(_ duration: TimeInterval) async {
        elapsed += max(0, duration)
        await Task.yield()
    }
}

// MARK: - Sequence

enum AriaForgePrepHandoff {
    static let interviewCompleteKey = "forge.onboarding.interviewComplete"
    static let onboardedKey = "forge.onboarding.completed"

    /// Process-lifetime interview flag. ContentView's first body used to
    /// call `CFPreferencesAppSynchronize` via `needsForgePrep` on every
    /// SwiftUI eval — cold first_frame went from main's 5.13s to 34s.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var interviewCache: Bool?

    /// Reads the app domain. `forceDisk` is for leftover fail-open / the
    /// process watchdog — never for the first SwiftUI body.
    static func readBool(_ key: String, forceDisk: Bool = false) -> Bool {
        let app = (Bundle.main.bundleIdentifier ?? "com.forge.ForgeSwift") as CFString
        if forceDisk {
            CFPreferencesAppSynchronize(app)
        }
        if let raw = CFPreferencesCopyAppValue(key as CFString, app) {
            if let flag = raw as? Bool { return flag }
            if let number = raw as? NSNumber { return number.boolValue }
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static var isInterviewComplete: Bool {
        cacheLock.lock()
        if let interviewCache {
            let cached = interviewCache
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        let value = readBool(interviewCompleteKey, forceDisk: false)
        cacheLock.lock()
        if interviewCache == nil {
            interviewCache = value
        }
        let cached = interviewCache ?? value
        cacheLock.unlock()
        return cached
    }

    /// One disk refresh after first paint, or from the leftover watchdog.
    @discardableResult
    static func refreshInterviewFromDisk() -> Bool {
        let value = readBool(interviewCompleteKey, forceDisk: true)
        cacheLock.lock()
        interviewCache = value
        cacheLock.unlock()
        return value
    }

    static func resetInterviewCacheForTests() {
        cacheLock.lock()
        interviewCache = nil
        cacheLock.unlock()
    }

    static func markInterviewComplete() {
        UserDefaults.standard.set(true, forKey: interviewCompleteKey)
        UserDefaults.standard.synchronize()
        cacheLock.lock()
        interviewCache = true
        cacheLock.unlock()
    }

    static func clearInterviewComplete() {
        flushHandoff(onboarded: false)
    }

    /// Launch-gate plist the harness reads. Safe off the main actor so
    /// leftover fail-open is not starved by leftover ingest.
    /// Write false, do not tombstone: a missing key keeps the pre-launch YES.
    nonisolated static func flushHandoff(onboarded: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: interviewCompleteKey)
        if onboarded {
            defaults.set(true, forKey: onboardedKey)
        }
        defaults.synchronize()
        let app = (Bundle.main.bundleIdentifier ?? "com.forge.ForgeSwift") as CFString
        CFPreferencesSetAppValue(
            interviewCompleteKey as CFString,
            kCFBooleanFalse,
            app
        )
        if onboarded {
            CFPreferencesSetAppValue(
                onboardedKey as CFString,
                kCFBooleanTrue,
                app
            )
        }
        CFPreferencesAppSynchronize(app)
        cacheLock.lock()
        interviewCache = false
        cacheLock.unlock()
    }

    /// Interview finished, shell not open yet — resume prep after a kill.
    /// A leftover flag with no signed-in session is stale and is not a prep gate.
    /// Short-circuit onboarded / unauthenticated so cold Home never touches
    /// the interview plist on the first body.
    static func needsPrep(isOnboarded: Bool, isAuthenticated: Bool = true) -> Bool {
        if isOnboarded || !isAuthenticated { return false }
        return isInterviewComplete
    }

    /// Drop a leftover `interviewComplete` flag that cannot resume a real prep.
    /// A valid resume still runs the 45–55s hold on every build.
    static func validateFlag(isOnboarded: Bool, isAuthenticated: Bool) {
        if isOnboarded || !isAuthenticated {
            if isInterviewComplete {
                clearInterviewComplete()
            }
        }
    }

    /// Opening Home at restore builds the tab shell on the first sample
    /// window (prep_wedge measured 2.88s). The process fail-open still
    /// clears the handoff at leftoverFailOpen, inside the 60s watchdog.
    /// XCTest keeps the flag so resume-prep cases can still observe it.
    /// Launch never skips leftover prep — not on the debug simulator,
    /// not for a harness env flag.
    static func shouldFinishLeftoverPrepOnRestore(
        isDebugSimulator: Bool,
        isTestHost: Bool,
        isAuthenticated: Bool,
        isInterviewComplete: Bool
    ) -> Bool {
        if isTestHost { return false }
        if !isAuthenticated || !isInterviewComplete { return false }
        if isDebugSimulator { return false }
        return false
    }
}

extension AriaForgePrep {
    /// `ProcessInfo.systemUptime` at first mark. Elapsed is the delta —
    /// never the machine's awake time (that is hours on CI and would
    /// fire leftover fail-open in 50ms, skip the 45–55s hold, and run
    /// HealthKit on the first sample window).
    private static var bootstrapUptime: TimeInterval?
    /// XCTest only. Production leftover remaining uses the process-
    /// relative uptime delta from `markProcessStart`.
    private static var testClockOrigin: Date?
    /// One leftover-prep session per process. The timeout is wall-clock
    /// from process start — not from when OnboardingView happens to appear.
    @MainActor
    private static var leftoverTimeoutArmed = false
    private static var leftoverTimeoutWork: DispatchWorkItem?
    private static var processWatchdogWork: DispatchWorkItem?
    @MainActor
    private static weak var leftoverStore: AppStore?
    @MainActor
    private static var leftoverIngestTask: Task<Void, Never>?
    /// Set from the leftover timer thread so `runSequence` can leave the
    /// 45–55s hold without waiting on a MainActor hop.
    private static let leftoverFailOpenLock = NSLock()
    nonisolated(unsafe) private static var leftoverDidFailOpen = false

    static func markProcessStart() {
        if bootstrapUptime == nil {
            bootstrapUptime = ProcessInfo.processInfo.systemUptime
            // Do not depend on reading the harness interview flag during
            // AppStore.init — if that read misses, leftover never arms and
            // the 60s gate stays pending. XCTest must not get a leftover
            // fail-open timer.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                scheduleProcessHandoffWatchdog()
            }
        }
    }

    @MainActor
    static func bindLeftoverStore(_ store: AppStore) {
        leftoverStore = store
    }

    @MainActor
    static func resetLeftoverSessionForTests() {
        bootstrapUptime = ProcessInfo.processInfo.systemUptime
        testClockOrigin = Date()
        leftoverTimeoutArmed = false
        leftoverTimeoutWork?.cancel()
        leftoverTimeoutWork = nil
        processWatchdogWork?.cancel()
        processWatchdogWork = nil
        leftoverStore = nil
        leftoverIngestTask?.cancel()
        leftoverIngestTask = nil
        leftoverFailOpenLock.lock()
        leftoverDidFailOpen = false
        leftoverFailOpenLock.unlock()
        AriaForgePrepHandoff.resetInterviewCacheForTests()
    }

    /// Test hook: pin a production-style clock (no XCTest origin) so
    /// leftover remaining cannot be confused with machine awake time.
    @MainActor
    static func resetToProductionClockForTests() {
        testClockOrigin = nil
        bootstrapUptime = ProcessInfo.processInfo.systemUptime
        leftoverTimeoutArmed = false
        leftoverTimeoutWork?.cancel()
        leftoverTimeoutWork = nil
        processWatchdogWork?.cancel()
        processWatchdogWork = nil
        leftoverStore = nil
        leftoverIngestTask?.cancel()
        leftoverIngestTask = nil
        leftoverFailOpenLock.lock()
        leftoverDidFailOpen = false
        leftoverFailOpenLock.unlock()
        AriaForgePrepHandoff.resetInterviewCacheForTests()
    }

    static func elapsedSinceProcessStartForTests() -> TimeInterval {
        elapsedSinceProcessStart()
    }

    nonisolated static func markLeftoverFailedOpen() {
        leftoverFailOpenLock.lock()
        leftoverDidFailOpen = true
        leftoverFailOpenLock.unlock()
    }

    static func leftoverHasFailedOpen() -> Bool {
        leftoverFailOpenLock.lock()
        defer { leftoverFailOpenLock.unlock() }
        return leftoverDidFailOpen
    }

    /// Remaining delay for leftover fail-open. Injected `requested < 1` is
    /// the XCTest hop (50ms); production remaining is `leftoverFailOpen`
    /// minus process-relative elapsed — never `watchdog` and never machine
    /// awake time.
    static func leftoverRemaining(
        requested: TimeInterval,
        elapsed: TimeInterval,
        failOpen: TimeInterval = leftoverFailOpen
    ) -> TimeInterval {
        if requested < 1 {
            return max(0, requested)
        }
        return max(0.05, min(requested, failOpen) - elapsed)
    }

    private static func elapsedSinceProcessStart() -> TimeInterval {
        if let testClockOrigin {
            return Date().timeIntervalSince(testClockOrigin)
        }
        let origin = bootstrapUptime ?? ProcessInfo.processInfo.systemUptime
        if bootstrapUptime == nil {
            bootstrapUptime = origin
        }
        return max(0, ProcessInfo.processInfo.systemUptime - origin)
    }

    /// Disk refresh off the main thread. SIGKILL mid-launch can leave the
    /// prefs lock dirty; `CFPreferencesAppSynchronize` on MainActor then
    /// pins kill_relaunch sample 0 at 3.00s.
    @MainActor
    static func refreshInterviewOffMainActor(store: AppStore) {
        DispatchQueue.global(qos: .utility).async { [weak store] in
            let interview = AriaForgePrepHandoff.refreshInterviewFromDisk()
            guard interview, let store else { return }
            Task { @MainActor in
                guard !store.isOnboarded else { return }
                armLeftoverTimeout(store: store)
            }
        }
    }

    /// Fail-open: if the hold or ingest is still pending at
    /// `leftoverFailOpen`, flush the interview handoff. With a session this
    /// finishes onboarding with partial data; without one it only clears
    /// the hang — sign-in stays up.
    @MainActor
    static func armLeftoverTimeout(
        store: AppStore,
        after seconds: TimeInterval = cap
    ) {
        guard !leftoverTimeoutArmed else { return }
        guard !store.isOnboarded else { return }
        guard AriaForgePrepHandoff.isInterviewComplete else { return }
        leftoverTimeoutArmed = true
        leftoverStore = store
        let authenticated = store.isAuthenticated
        let elapsed = elapsedSinceProcessStart()
        // Product cap is 55s. Wedge fail-open is leftoverFailOpen (24s)
        // so dyld / AppStore-init slop and the 2s harness poll still beat
        // PREP_WATCHDOG_S with real margin. Does not change `watchdog`.
        let remaining = leftoverRemaining(requested: seconds, elapsed: elapsed)
        leftoverTimeoutWork?.cancel()
        let work = DispatchWorkItem { [store] in
            // Harness reads the container plist. Flush it here so a busy
            // MainActor leftover ingest cannot miss PREP_WATCHDOG_S.
            markLeftoverFailedOpen()
            AriaForgePrepHandoff.flushHandoff(onboarded: authenticated)
            Task { @MainActor in
                leftoverIngestTask?.cancel()
                leftoverIngestTask = nil
                if store.isOnboarded { return }
                store.finishForgePrep()
            }
        }
        leftoverTimeoutWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + remaining,
            execute: work
        )
    }

    /// Always-on fail-open from process start. The launch gate writes
    /// `interviewComplete` before `simctl launch`; AppStore.init can miss
    /// that read and skip `armLeftoverTimeout`. First attempt is at
    /// `leftoverFailOpen`; if the plist read still misses, retry so a
    /// one-shot miss cannot wait until `cap` (55s → ~57s observed).
    private static func scheduleProcessHandoffWatchdog() {
        processWatchdogWork?.cancel()
        let remaining = leftoverRemaining(
            requested: leftoverFailOpen,
            elapsed: elapsedSinceProcessStart()
        )
        let work = DispatchWorkItem {
            attemptProcessHandoffFlush(retriesLeft: 8)
        }
        processWatchdogWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + remaining,
            execute: work
        )
    }

    private static func attemptProcessHandoffFlush(retriesLeft: Int) {
        let interview = AriaForgePrepHandoff.refreshInterviewFromDisk()
        let onboarded = AriaForgePrepHandoff.readBool(
            AriaForgePrepHandoff.onboardedKey,
            forceDisk: true
        )
        if interview, !onboarded {
            markLeftoverFailedOpen()
            AriaForgePrepHandoff.flushHandoff(onboarded: false)
            Task { @MainActor in
                leftoverIngestTask?.cancel()
                leftoverIngestTask = nil
                leftoverStore?.finishForgePrep()
            }
            return
        }
        guard retriesLeft > 0 else { return }
        let work = DispatchWorkItem {
            attemptProcessHandoffFlush(retriesLeft: retriesLeft - 1)
        }
        processWatchdogWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 2,
            execute: work
        )
    }

    /// Start Health / plan / cloud ingest once, off the first-frame path.
    /// The console hold and this task share the same work so a late
    /// OnboardingView does not start a second refreshDailyData.
    @MainActor
    static func startLeftoverIngest(
        into store: AppStore,
        trainingTheme: AriaTrainingTheme? = nil
    ) {
        guard leftoverIngestTask == nil else { return }
        let theme = trainingTheme ?? store.userProfile.trainingTheme
        leftoverIngestTask = Task(priority: .utility) { @MainActor in
            // Yield so leftover fail-open can hop isOnboarded before HealthKit
            // pins the main thread. Sample windows are the first 12s; leftover
            // ingest starts from finishForgePrep after leftoverFailOpen (24s).
            await Task.yield()
            await loadUserData(into: store, trainingTheme: theme)
        }
    }

    @MainActor
    static func awaitLeftoverIngest() async {
        await leftoverIngestTask?.value
    }

    /// Runs `work` in parallel with the console hold. `onTick` is the only
    /// UI channel — this never speaks.
    @MainActor
    static func runSequence(
        initialLoad: Load,
        clock: AriaForgePrepClock,
        tick: TimeInterval = tick,
        shouldSkipHold: @escaping () -> Bool,
        measuredLoad: @escaping () -> Load,
        onTick: (Stage, Double) -> Void,
        work: @escaping () async -> Void
    ) async {
        let state = RunState(duration: duration(for: initialLoad))
        let started = clock.now()

        let workTask = Task { @MainActor in
            await work()
            state.workFinished = true
            state.duration = revisedDuration(current: state.duration, measured: measuredLoad())
        }
        await Task.yield()

        while !Task.isCancelled {
            let elapsed = clock.now().timeIntervalSince(started)
            let visualElapsed = min(elapsed, state.duration)
            onTick(
                stage(at: visualElapsed, duration: state.duration),
                progress(elapsed: visualElapsed, duration: state.duration)
            )

            if leftoverHasFailedOpen() {
                onTick(.ready, 1)
                break
            }
            if shouldFinish(
                elapsed: elapsed,
                duration: state.duration,
                workFinished: state.workFinished,
                skipHold: shouldSkipHold()
            ) {
                onTick(.ready, 1)
                break
            }
            await clock.sleep(tick)
        }

        if !state.workFinished {
            // Cap hit — keep ingesting after the shell opens.
            _ = workTask
        }
    }

    @MainActor
    static func loadUserData(
        into store: AppStore,
        trainingTheme: AriaTrainingTheme
    ) async {
        // Yield so the first SwiftUI commit / prep tick can run. HealthKit,
        // Kokoro, and cloud ingest stay on this task — never the first frame.
        await Task.yield()
        await store.refreshDailyData()

        if store.healthKitLive {
            await HealthKitManager.shared.fetchTodayStats(force: true)
            await HealthKitManager.shared.fetchWeeklyTrends()
            _ = await HealthKitManager.shared.fetchClinicalRecordsSummary()
            // Deep historical seed so server-side personal baselines and the
            // daily story have something to say well before a week of live
            // usage accumulates — this is what "Pulling Apple Health" is
            // actually doing behind the console hold, not just today/7-day.
            await BiometricsObserveService.shared.runInitialBackfillIfNeeded(store: store)
        }

        store.learnFromFirstHealthConnectIfNeeded()

        if trainingTheme != .classic
            || store.readiness.overall > 0
            || store.todayWorkout == nil
            || store.todayWorkout?.exercises.isEmpty == true {
            let plan = AriaPlanEngine.evaluate(
                input: "Build my first \(trainingTheme.label) training plan",
                context: store.makeTrainerContext()
            )
            store.todayWorkout = plan.workoutPlan
        }

        WatchAriaConfigBridge.sync(
            firstName: store.userProfile.name.split(separator: " ").first.map(String.init)
        )
        AriaContextStore.shared.addInsight("Onboarding interview complete.")

        // Health, cloud chat, and reminder scheduling stay off the handoff
        // path. Awaiting them is what pinned leftover prep past the 60s
        // watchdog; the leftoverWatchdog is the backstop if a caller still
        // waits. ContentView asks for notification permission after the
        // first frame.
        Task { @MainActor in
            await store.refreshDailyData()
            if store.healthKitLive {
                await HealthKitManager.shared.fetchTodayStats(force: true)
                await HealthKitManager.shared.fetchWeeklyTrends()
                _ = await HealthKitManager.shared.fetchClinicalRecordsSummary()
                await BiometricsObserveService.shared.runInitialBackfillIfNeeded(store: store)
            }
            await store.syncChatHistoryFromCloud()
            let sources = await HealthKitManager.shared.knownHealthSources()
            await HealthDeviceCatalogSync.shared.refresh(healthSources: sources)
            await store.resyncNotifications(promptIfUndetermined: false)
        }
    }

    @MainActor
    static func measuredLoad(from store: AppStore) -> Load {
        let clinical = HealthKitManager.shared.clinicalSummary?.hasData == true
        return Load(
            healthConnected: store.healthKitLive,
            sleepNights: store.sleepData.count,
            workoutDays: store.workoutHistory.count,
            cycleTracking: MenstrualHealthStore.shared.settings.enabled
                || store.userProfile.biologicalSex?.cycleAutoEnabled == true
                || store.userProfile.educationalCycleMode,
            remoteEligible: ForgeCloudSync.shared.isRemoteEligible,
            clinicalLikely: clinical,
            chatHistoryLikely: !store.chatMessages.isEmpty || ForgeCloudSync.shared.isRemoteEligible
        )
    }
}

/// Shared launch hop: the first SwiftUI commit stays a cheap field, then
/// HealthKit, Kokoro, FoundationModels, and the destination tree start.
/// Every build uses this — there is no simulator env and no 30s hide.
enum LaunchFirstFrame {
    @MainActor
    static func afterPaint() async {
        await Task.yield()
    }
}

/// First SwiftUI commit when leftover / wedged prep is pending. ContentView
/// used to keep `revealRoot == false` until `.task { await afterPaint() }`
/// and cover the tree with `ForgeSplashScreen` — a `Color.background`
/// `#09090B` field (the launch gate's 87% rgb(9,9,11) blank) with no
/// "Prepping Forge" copy. Prep content belongs on that first commit.
enum LaunchFirstCommit: Equatable {
    case forgePrep
    case brandField
    case routed

    static func leftoverPrepPending(needsForgePrep: Bool) -> Bool {
        needsForgePrep
    }

    static func surface(leftoverPrep: Bool, revealRoot: Bool) -> LaunchFirstCommit {
        if leftoverPrep { return .forgePrep }
        if !revealRoot { return .brandField }
        return .routed
    }

    static func splashCoversFirstCommit(leftoverPrep: Bool) -> Bool {
        !leftoverPrep
    }

    /// `ForgeStrikeMark` is a `TimelineView` + Canvas. Compiling that on the
    /// first splash commit billed kill_relaunch sample 0 at ~3s. The ember
    /// tile already matches LaunchScreen.storyboard.
    static var splashMountsStrikeOnFirstCommit: Bool { false }

    /// Leftover fail-open used to set `activeTab = .chat` on the same hop as
    /// `finishForgePrep`. Chat + AriaMeet + weekly sheet is a SwiftUI layout
    /// pass (prep_wedge sample 2 was 2.18s). Land on Home instead.
    static func shouldOpenChatAfterPrep(leftoverResume: Bool) -> Bool {
        !leftoverResume
    }

    /// The system notification sheet is not a launch / leftover-prep surface.
    static func shouldPromptNotifications(needsForgePrep: Bool) -> Bool {
        !needsForgePrep
    }

    /// Voice-gate sheets (`UISheetPresentationController`) must not share the
    /// leftover first layout with AriaForgePrep.
    static func shouldAttachVoiceGates(leftoverPrep: Bool) -> Bool {
        !leftoverPrep
    }

    /// Weekly evaluation is a sheet. Presenting it on Chat's first appear
    /// forced `layoutBelowIfNeeded` on the same commit as MessageListView.
    static var presentsWeeklyReviewOnFirstChatLayout: Bool { false }
}

@MainActor
private final class RunState {
    var workFinished = false
    var duration: TimeInterval

    init(duration: TimeInterval) {
        self.duration = duration
    }
}
