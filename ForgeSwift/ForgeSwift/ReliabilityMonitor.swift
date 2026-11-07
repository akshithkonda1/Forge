import Foundation
import UIKit
import ForgeCore

/// Starts the two first-party sources the Reliability screen reads:
/// MetricKit (ForgeCore's `ReliabilityMetricKit`) and foreground sessions
/// for the crash-free session rate.
///
/// A session opens when Forge becomes active and goes quiet when it enters
/// the background. On the next launch, ReliabilityLog closes a session that
/// was still on screen as abnormal (crash, watchdog, foreground memory kill)
/// and one that was in the background as clean (iOS reclaiming a suspended
/// app is not something a person sees). Sessions started under Xcode's
/// debugger are recorded but never counted.
///
/// Lives in the app target because `UIApplication.shared` is unavailable to
/// the extensions that also link ForgeCore. Call `scheduleStart()` from
/// `application(_:didFinishLaunchingWithOptions:)`; it returns at once.
/// Sysctl, MetricKit subscribe, and ledger I/O run off the launch main
/// thread so first_frame / kill_relaunch samples are not billed for
/// reliability telemetry.
enum ReliabilityMonitor {

    private static let gate = NSLock()
    private static var started = false

    /// Kick the work off the launch path. Safe to call more than once.
    static func scheduleStart() {
        Task.detached(priority: .utility) {
            await startOffMain()
        }
    }

    /// Back-compat for callers that still say `start()`. Does not run on
    /// the calling thread.
    static func start() {
        scheduleStart()
    }

    private static func startOffMain() async {
        gate.lock()
        if started {
            gate.unlock()
            return
        }
        started = true
        gate.unlock()

        let debugger = ReliabilityProcess.isDebuggerAttached
        let version = ReliabilityProcess.appVersion
        await ReliabilityLog.shared.processLaunch()
        ReliabilityMetricKit.start()

        await MainActor.run {
            ReliabilityLifecycle.installObservers(debugger: debugger, version: version)
        }
    }
}

@MainActor
private enum ReliabilityLifecycle {
    private static var observers: [NSObjectProtocol] = []

    static func installObservers(debugger: Bool, version: String?) {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { await ReliabilityLog.shared.didBecomeActive(debugger: debugger, appVersion: version) }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ReliabilityLifecycle.recordBackground() }
        })
        observers.append(center.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            Task { await ReliabilityLog.shared.willTerminate() }
        })
    }

    /// Ask iOS for a few seconds so the "went to background" write lands
    /// before the process is suspended; otherwise a later kill while
    /// suspended would read as a crash on the next launch.
    static func recordBackground() {
        let token = BackgroundSave()
        token.identifier = UIApplication.shared.beginBackgroundTask(withName: "forge.reliability.save") {
            MainActor.assumeIsolated { token.end() }
        }
        Task { @MainActor in
            await ReliabilityLog.shared.didEnterBackground()
            token.end()
        }
    }

    private final class BackgroundSave {
        var identifier: UIBackgroundTaskIdentifier = .invalid

        func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
}
