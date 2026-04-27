import SwiftUI

@main
struct ForgeApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if store.isOnboarded {
                    MainTabView()
                } else {
                    OnboardingFlow()
                }
            }
            .environment(store)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store

        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch store.activeTab {
                case .home: HomeView()
                case .chat: ChatView()
                case .workout: WorkoutView()
                case .sleep: SleepView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom bottom nav
            ForgeTabBar(activeTab: $store.activeTab)
        }
        .background(Color.forgeBackground)
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Custom Tab Bar

struct ForgeTabBar: View {
    @Binding var activeTab: AppStore.Tab

    private let tabs: [(tab: AppStore.Tab, icon: String, label: String)] = [
        (.home, "house.fill", "Home"),
        (.chat, "message.fill", "Chat"),
        (.workout, "dumbbell.fill", "Workout"),
        (.sleep, "moon.fill", "Sleep"),
        (.profile, "person.fill", "Profile"),
    ]

    var body: some View {
        HStack {
            ForEach(tabs, id: \.tab) { item in
                if item.tab == .workout {
                    // Elevated center button
                    Button {
                        activeTab = item.tab
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(activeTab == item.tab ? Color.ember : Color.ember.opacity(0.8))
                                    .frame(width: 56, height: 56)
                                    .shadow(color: activeTab == item.tab ? .ember.opacity(0.4) : .clear, radius: 12)

                                Image(systemName: item.icon)
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                            }
                            .offset(y: -12)

                            Text(item.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(activeTab == item.tab ? .ember : .textTertiary)
                                .offset(y: -10)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        activeTab = item.tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .font(.system(size: 20))
                                .foregroundColor(activeTab == item.tab ? .ember : .textTertiary)

                            Text(item.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(activeTab == item.tab ? .ember : .textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            Color.forgeBackground.opacity(0.8)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.forgeBorder),
            alignment: .top
        )
    }
}
