import SwiftUI
import UIKit

@main
struct ForgeSwiftApp: App {
    @StateObject private var store = AppStore()

    // Exists so iOS has somewhere to hand a CloudKit share when a supporter
    // accepts a cycle invite; SwiftUI's App lifecycle exposes no other hook.
    @UIApplicationDelegateAdaptor(ForgeAppDelegate.self) private var appDelegate

    init() {
        // Listens for watch workout state and mirrors it into a Live
        // Activity (lock screen + Dynamic Island). Also owns WCSession
        // on the phone so companion config can flow to ForgeWatch.
        // Owns WCSession on the phone; pushes companion config in activationDidCompleteWith
        // once the session is actually active. The onAppear sync below is the UI-ready pass.
        WorkoutActivityCoordinator.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Re-sync when UI is up (WCSession may not be activated in init).
                    let firstName = store.userProfile.name
                        .split(separator: " ").first.map(String.init)
                    WatchAriaConfigBridge.sync(firstName: firstName)
                    // Dual-sim / companion launches: watch often boots a few seconds
                    // after the phone. Retry so ARIA URL + name land after WCSession
                    // becomes reachable (App Groups are unreliable in Simulator).
                    for delay in [1.5, 4.0, 8.0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            WatchAriaConfigBridge.sync(firstName: firstName)
                        }
                    }
                }
                .onChange(of: store.userProfile.name) { _, name in
                    WatchAriaConfigBridge.sync(
                        firstName: name.split(separator: " ").first.map(String.init)
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    WatchAriaConfigBridge.sync(
                        firstName: store.userProfile.name
                            .split(separator: " ").first.map(String.init)
                    )
                    Task { await store.flushPendingWidgetWater(); store.publishHomeWidgets() }
                    WeeklyAriaReviewStore.shared.refreshDue()
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
        }
    }
}
