import SwiftUI

@main
struct ForgeApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var hkService = HealthKitSleepService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(hkService)
        }
    }
}