import SwiftUI
import UIKit

@main
struct ForgeSwiftApp: App {
    @StateObject private var store = AppStore()

    init() {
        // Listens for watch workout state and mirrors it into a Live
        // Activity (lock screen + Dynamic Island). Also owns WCSession
        // on the phone so companion config can flow to ForgeWatch.
        WorkoutActivityCoordinator.shared.activate()
        // Base URL + user id (name synced again in onAppear once store is live).
        Task { @MainActor in WatchAriaConfigBridge.sync() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Re-sync when UI is up (WCSession may not be activated in init).
                    WatchAriaConfigBridge.sync(
                        firstName: store.userProfile.name
                            .split(separator: " ").first.map(String.init)
                    )
                    // Best-effort: if a watch is already reachable, nudge it again
                    // after a short delay so dual-sim launches still get config.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        WatchAriaConfigBridge.sync(
                            firstName: store.userProfile.name
                                .split(separator: " ").first.map(String.init)
                        )
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
