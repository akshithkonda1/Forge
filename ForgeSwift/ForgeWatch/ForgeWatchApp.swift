import SwiftUI

@main
struct ForgeWatchApp: App {
    @StateObject private var workout = ForgeWatchWorkoutSessionManager.shared
    @StateObject private var connectivity = ForgeWatchConnectivityManager.shared

    init() {
        ForgeWatchConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ForgeWatchContentView()
                .environmentObject(workout)
                .environmentObject(connectivity)
        }
    }
}