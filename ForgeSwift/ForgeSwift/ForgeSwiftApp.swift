import SwiftUI

@main
struct ForgeSwiftApp: App {
    @StateObject private var store = AppStore()

    init() {
        // Listens for watch workout state and mirrors it into a Live
        // Activity (lock screen + Dynamic Island).
        WorkoutActivityCoordinator.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
