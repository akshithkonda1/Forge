import SwiftUI

@main
struct ForgeSwiftApp: App {
    @UIApplicationDelegateAdaptor(ForgeAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ForgePhoneWatchConnectivity.shared.activate()
        ForgeNotificationCoordinator.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onAppear {
                    ForgeNotificationCoordinator.shared.onBriefNotificationTapped = { _ in
                        store.activeTab = .chat
                    }
                    if store.briefNotificationsEnabled {
                        ForgeNotificationCoordinator.shared.registerForRemotePushIfNeeded()
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "forge", url.host == "device-connected" else { return }
                    Task {
                        await store.refreshConnections()
                        await store.loadDashboardFromAPI()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, store.isOnboarded else { return }
                    Task {
                        await store.refreshProactiveBriefs(scheduleNotifications: store.briefNotificationsEnabled)
                    }
                }
        }
    }
}
