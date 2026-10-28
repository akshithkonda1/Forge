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
/// the extensions that also link ForgeCore. Call `start()` once from
/// `application(_:didFinishLaunchingWithOptions:)`; it returns at once and
/// does its file work on the ReliabilityLog actor, off the launch path.
@MainActor
enum ReliabilityMonitor {

    private static var started = false
    private static var observers: [NSObjectProtocol] = []

    static func start() {
        guard !started else { return }
        started = true

        let debugger = ReliabilityProcess.isDebuggerAttached
        let version = ReliabilityProcess.appVersion
        Task { await ReliabilityLog.shared.processLaunch() }
        ReliabilityMetricKit.start()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { await ReliabilityLog.shared.didBecomeActive(debugger: debugger, appVersion: version) }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ReliabilityMonitor.recordBackground() }
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
    private static func recordBackground() {
        let token = BackgroundSave()
        token.identifier = UIApplication.shared.beginBackgroundTask(withName: "forge.reliability.save") {
            MainActor.assumeIsolated { token.end() }
        }
        Task { @MainActor in
            await ReliabilityLog.shared.didEnterBackground()
            token.end()
        }
    }

    @MainActor
    private final class BackgroundSave {
        var identifier: UIBackgroundTaskIdentifier = .invalid

        func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
}
