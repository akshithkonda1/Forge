import SwiftUI

@main
struct ForgeSwiftApp: App {
    @StateObject private var store = AppStore()

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
