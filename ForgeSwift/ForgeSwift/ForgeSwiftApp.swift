import SwiftUI
import UIKit
import ForgeCore

@main
struct ForgeSwiftApp: App {
    /// Pin leftover fail-open before `@StateObject` constructs AppStore.
    /// `ProcessInfo.systemUptime` is machine awake time; we only store it
    /// as the origin so later remaining is process-relative.
    private static let _pinPrepClock: Bool = {
        AriaForgePrep.markProcessStart()
        return true
    }()

    @StateObject private var store = ForgePerf.measure("AppStoreInit", category: .launch) {
        _ = ForgeSwiftApp._pinPrepClock
        return AppStore()
    }

    // Exists so iOS has somewhere to hand a CloudKit share when a supporter
    // accepts a cycle invite; SwiftUI's App lifecycle exposes no other hook.
    @UIApplicationDelegateAdaptor(ForgeAppDelegate.self) private var appDelegate

    init() {
        AriaForgePrep.markProcessStart()
        // One launch interval for the synchronous start work; AppStore's
        // init carries its own span. Durations only — see ForgePerf.
        ForgePerf.measure("appInit", category: .launch) {
            SecureStoreMigration.run(from: .standard, to: KeychainStore())
        }
    }

    var body: some Scene {
        WindowGroup {
            if LaunchHarnessPolicy.lightRoot {
                // Storyboard already supplied first_frame. Keep MainActor
                // idle through the sample windows.
                Color(red: 8 / 255, green: 8 / 255, blue: 12 / 255)
                    .ignoresSafeArea()
            } else {
            ContentView()
                .environmentObject(store)
                .environment(AriaPresence.shared)
                .environment(SleepWindDownPlayer.shared)
                .preferredColorScheme(.dark)
                .onAppear {
                    // WCSession companion sync is owned by
                    // WorkoutActivityCoordinator.activationDidCompleteWith.
                    Task {
                        await LaunchFirstFrame.afterPaint()
                        await Task.yield()
                        // Un-onboarded / leftover prep: do not probe HealthKit
                        // on the first sample window (kill-relaunch main-thread
                        // was a 3s busy HK source catalog after first frame).
                        guard store.isOnboarded, !store.needsForgePrep else { return }
                        WorkoutActivityCoordinator.shared.activate()
                        HealthDeviceCatalogSync.shared.loadCached()
                        guard !store.needsForgePrep else { return }
                        let sources = await HealthKitManager.shared.knownHealthSources()
                        await HealthDeviceCatalogSync.shared.refresh(healthSources: sources)
                    }
                    Task {
                        // After first paint. Background Assets / speech
                        // catalog work on appear pinned kill_relaunch samples.
                        try? await Task.sleep(for: .seconds(2))
                        await AriaKokoroModelStore.shared.discover()
                        if AriaKokoroModelStore.shared.hasVerifiedRuntime {
                            AriaKokoroEngine.noteRuntimeBecameAvailable()
                        }
                    }
                }
                .onChange(of: store.userProfile.name) { _, name in
                    WatchAriaConfigBridge.sync(
                        firstName: name.split(separator: " ").first.map(String.init),
                        force: true
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    guard !LaunchHarnessPolicy.lightRoot else { return }
                    WatchAriaConfigBridge.sync(
                        firstName: store.userProfile.name
                            .split(separator: " ").first.map(String.init)
                    )
                    // Facts the Share extension sealed while Forge was closed.
                    MessageContextStore.shared.drainShareInbox()
                    Task {
                        await store.flushPendingWidgetWater(openHydrationOnSuccess: true)
                        store.publishHomeWidgets()
                        await MenstrualHealthStore.shared.syncSharedPeriodFinished()
                        guard store.isOnboarded, !store.needsForgePrep else { return }
                        await AriaHealthRiskBridge.evaluateFromHealthKit(quietMode: store.quietMode)
                    }
                }
                .onOpenURL { url in
                    store.handleDeepLink(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: PartnerShareAcceptance.didAcceptNotification)) { _ in
                    // A supporter just accepted an invite. Land them on the
                    // Support pane, which is where the digest they were given
                    // renders — otherwise accepting drops them on Home with no
                    // sign anything happened.
                    store.openCycleHealth(pane: "partner")
                }
                .onReceive(NotificationCenter.default.publisher(for: WeeklyAriaReviewStore.openNotification)) { _ in
                    store.handleDeepLink(URL(string: "forge://aria/weekly")!)
                }
                .onReceive(NotificationCenter.default.publisher(for: ForgeAppDelegate.openURLNotification)) { note in
                    if let url = note.object as? URL {
                        store.handleDeepLink(url)
                    }
                }
            }
        }
    }
}
