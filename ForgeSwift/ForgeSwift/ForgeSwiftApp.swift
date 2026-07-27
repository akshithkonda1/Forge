import SwiftUI
import UIKit

@main
struct ForgeSwiftApp: App {
    @StateObject private var store = AppStore()

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
                }
        }
    }
}
