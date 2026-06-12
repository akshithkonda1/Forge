import SwiftUI

@main
struct ForgeSwiftApp: App {
    @StateObject private var store = AppStore()

    init() {
        ForgePhoneWatchConnectivity.shared.activate()
        ForgeNotificationCoordinator.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "forge", url.host == "device-connected" else { return }
                    Task {
                        await store.refreshConnections()
                        await store.loadDashboardFromAPI()
                    }
                }
        }
    }
}
