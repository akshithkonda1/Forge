import SwiftUI
import UIKit
import ForgeCore

@main
struct ForgeSwiftApp: App {
    @StateObject private var store = ForgePerf.measure("AppStoreInit", category: .launch) { AppStore() }

    // Exists so iOS has somewhere to hand a CloudKit share when a supporter
    // accepts a cycle invite; SwiftUI's App lifecycle exposes no other hook.
    @UIApplicationDelegateAdaptor(ForgeAppDelegate.self) private var appDelegate

    init() {
        // One launch interval for the synchronous start work; AppStore's
        // init carries its own span. Durations only — see ForgePerf.
        ForgePerf.measure("appInit", category: .launch) {
            SecureStoreMigration.run(from: .standard, to: KeychainStore())
            // Listens for watch workout state and mirrors it into a Live
            // Activity (lock screen + Dynamic Island). Owns WCSession on
            // the phone; one companion sync after activation.
            WorkoutActivityCoordinator.shared.activate()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(AriaPresence.shared)
                .environment(SleepWindDownPlayer.shared)
                .preferredColorScheme(.dark)
                .onAppear {
                    // WCSession companion sync is owned by
                    // WorkoutActivityCoordinator.activationDidCompleteWith.
                    // Do not retry on a 1.5 / 4 / 8s ladder from here.
                    Task {
                        HealthDeviceCatalogSync.shared.loadCached()
                        // HealthKit source enumeration waits on healthd. Do
                        // not pin a resume-into-prep launch behind that.
                        guard !store.needsForgePrep else { return }
                        let sources = await HealthKitManager.shared.knownHealthSources()
                        await HealthDeviceCatalogSync.shared.refresh(healthSources: sources)
                    }
                    Task {
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
                        guard !store.needsForgePrep else { return }
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
