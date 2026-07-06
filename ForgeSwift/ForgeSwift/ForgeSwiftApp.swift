import SwiftUI

@main
struct ForgeSwiftApp: App {
    @StateObject private var store = AppStore()

    init() {
        // Listens for watch workout state and mirrors it into a Live
        // Activity (lock screen + Dynamic Island).
        WorkoutActivityCoordinator.shared.activate()
        // Mirrors the backend base URL + user id into the shared App
        // Group so the watch's deeper-coaching call reaches the same
        // backend as the phone.
        Task { @MainActor in WatchAriaConfigBridge.sync() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
