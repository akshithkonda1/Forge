import SwiftUI

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
                }
                .onChange(of: store.userProfile.name) { _, name in
                    WatchAriaConfigBridge.sync(
                        firstName: name.split(separator: " ").first.map(String.init)
                    )
                }
        }
    }
}
