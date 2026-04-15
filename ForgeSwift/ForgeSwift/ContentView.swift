import SwiftUI

// MARK: - Root entry point (mirrors /src/app/page.tsx)

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if store.isOnboarded {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

// MARK: - Main Tab Container (mirrors page.tsx tab switcher)

struct MainTabView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content area — pad bottom so content doesn't hide behind nav
            Group {
                switch store.activeTab {
                case .home:     HomeView()
                case .chat:     ChatView()
                case .workout:  WorkoutView()
                case .lifestyle: LifestyleView()
                case .sleep:    SleepView()
                case .profile:  ProfileTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 80)          // room for bottom nav

            // Fixed bottom navigation
            BottomNavBar()
        }
        .background(Color.background.ignoresSafeArea())
    }
}

// MARK: - Bottom Navigation Bar (mirrors bottom-nav.tsx)

struct BottomNavBar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            // Divider line
            Rectangle()
                .fill(Color.borderColor)
                .frame(height: 1 / UIScreen.main.scale)

            HStack(spacing: 0) {
                ForEach(TabItem.allCases) { tab in
                    if tab == .workout {
                        WorkoutTabButton(tab: tab)
                    } else {
                        RegularTabButton(tab: tab)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 64)
            .background(
                Color(hex: "0A0A0A").opacity(0.9)
                    .background(.ultraThinMaterial.opacity(0.4))
            )
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
        }
        .background(Color.background)
    }
}

// Regular (non-center) tab button
struct RegularTabButton: View {
    let tab: TabItem
    @EnvironmentObject var store: AppStore

    var isActive: Bool { store.activeTab == tab }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                store.activeTab = tab
            }
        } label: {
            ZStack(alignment: .top) {
                VStack(spacing: 4) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundColor(isActive ? .ember : .textTertiary)
                        .animation(.easeInOut(duration: 0.2), value: isActive)
                    Text(tab.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isActive ? .ember : .textTertiary)
                        .animation(.easeInOut(duration: 0.2), value: isActive)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)

                // Active indicator — thin line at top
                if isActive {
                    Rectangle()
                        .fill(Color.ember)
                        .frame(width: 32, height: 2)
                        .cornerRadius(1)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// Workout center tab — elevated circle button (mirrors BottomNav.tsx workout case)
struct WorkoutTabButton: View {
    let tab: TabItem
    @EnvironmentObject var store: AppStore

    var isActive: Bool { store.activeTab == tab }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                store.activeTab = tab
            }
        } label: {
            VStack(spacing: 2) {
                Circle()
                    .fill(isActive ? Color.ember : Color.ember.opacity(0.85))
                    .frame(width: 56, height: 56)
                    .shadow(color: isActive ? Color.ember.opacity(0.4) : .clear, radius: 14)
                    .overlay(
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 23, weight: .medium))
                            .foregroundColor(.white)
                    )
                    .offset(y: -12)

                Text(tab.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isActive ? .ember : .textTertiary)
                    .offset(y: -6)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
