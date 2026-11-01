import Foundation
import ForgeCore

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
    static let tick: TimeInterval = 0.25

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
        cap: TimeInterval = cap
    ) -> Bool {
        if elapsed >= cap { return true }
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

    static var isInterviewComplete: Bool {
        UserDefaults.standard.bool(forKey: interviewCompleteKey)
    }

    static func markInterviewComplete() {
        UserDefaults.standard.set(true, forKey: interviewCompleteKey)
        UserDefaults.standard.synchronize()
    }

    static func clearInterviewComplete() {
        UserDefaults.standard.removeObject(forKey: interviewCompleteKey)
        UserDefaults.standard.synchronize()
    }

    /// Interview finished, shell not open yet — resume prep after a kill.
    /// A leftover flag with no signed-in session is stale and is not a prep gate.
    static func needsPrep(isOnboarded: Bool, isAuthenticated: Bool = true) -> Bool {
        isInterviewComplete && !isOnboarded && isAuthenticated
    }

    /// Drop a leftover `interviewComplete` flag that cannot resume a real prep.
    /// A valid resume still runs the 45–55s hold on every build.
    static func validateFlag(isOnboarded: Bool, isAuthenticated: Bool) {
        if isOnboarded || !isAuthenticated {
            clearInterviewComplete()
        }
    }
}

extension AriaForgePrep {
    /// One leftover-prep session per process. The timeout is wall-clock
    /// from this arm — not from when OnboardingView happens to appear —
    /// so a late root still leaves AriaForgePrep before `watchdog`.
    @MainActor
    private static var leftoverTimeoutArmed = false
    @MainActor
    private static var leftoverTimeoutTask: Task<Void, Never>?
    @MainActor
    private static var leftoverIngestTask: Task<Void, Never>?

    @MainActor
    static func resetLeftoverSessionForTests() {
        leftoverTimeoutArmed = false
        leftoverTimeoutTask?.cancel()
        leftoverTimeoutTask = nil
        leftoverIngestTask?.cancel()
        leftoverIngestTask = nil
    }

    /// Fail-open: if the hold or ingest is still pending at `cap`, open
    /// the shell and flush the handoff the launch gate reads.
    @MainActor
    static func armLeftoverTimeout(
        store: AppStore,
        after seconds: TimeInterval = cap
    ) {
        guard store.needsForgePrep, !leftoverTimeoutArmed else { return }
        leftoverTimeoutArmed = true
        leftoverTimeoutTask = Task { [weak store] in
            let ns = UInt64((max(0, seconds) * 1_000_000_000).rounded())
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let store, store.needsForgePrep else { return }
                store.finishForgePrep()
            }
        }
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
        leftoverIngestTask = Task { @MainActor in
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

        await store.syncChatHistoryFromCloud()
        WatchAriaConfigBridge.sync(
            firstName: store.userProfile.name.split(separator: " ").first.map(String.init)
        )
        let sources = await HealthKitManager.shared.knownHealthSources()
        await HealthDeviceCatalogSync.shared.refresh(healthSources: sources)
        await store.resyncNotifications()
        AriaContextStore.shared.addInsight("Onboarding interview complete.")
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

@MainActor
private final class RunState {
    var workFinished = false
    var duration: TimeInterval

    init(duration: TimeInterval) {
        self.duration = duration
    }
}
