import SwiftUI

struct SleepView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var hkService = HealthKitSleepService.shared
    @State private var selectedTab: SleepTab = .day
    @State private var showAIChat = false
    @State private var showSleepPersonalization = false

    var body: some View {
        ZStack(alignment: .top) {
            SleepBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                SleepHeaderView(
                    selectedTab: selectedTab,
                    onAskAria: { showAIChat = true },
                    onPersonalize: { showSleepPersonalization = true },
                    onTabSelect: { selectedTab = $0 }
                )

                TabView(selection: $selectedTab) {
                    SleepDayTab()
                        .environmentObject(hkService)
                        .tag(SleepTab.day)

                    SleepNightTab(
                        showPersonalization: $showSleepPersonalization
                    )
                    .environmentObject(hkService)
                    .tag(SleepTab.night)

                    AlarmTab()
                        .environmentObject(hkService)
                        .tag(SleepTab.alarms)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.22), value: selectedTab)
            }
        }
        .sheet(isPresented: $showAIChat) {
            AISleepChatView()
                .environmentObject(store)
                .environmentObject(hkService)
        }
        .sheet(isPresented: $showSleepPersonalization) {
            SleepPersonalizationSheet()
                .environmentObject(hkService)
                .environmentObject(store)
        }
        .task {
            if await hkService.requestAuthorization() {
                let hkSleep = await hkService.fetchRecentSleepData(days: 14)
                store.mergeSleepDataLocally(hkSleep)
            }
            let debt = hkService.computeSleepDebt(from: store.sleepData)
            let recentScore = store.sleepData.first?.score
            _ = hkService.computeAdaptiveSunrise(
                debt: debt,
                recentScore: recentScore,
                profile: hkService.userProfile
            )
        }
    }
}

struct SleepBackground: View {
    var body: some View {
        ZStack {
            Color.background
            RadialGradient(
                colors: [Color(hex: "1A1440").opacity(0.55), .clear],
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 10,
                endRadius: 460
            )
            RadialGradient(
                colors: [Color.aurora.opacity(0.10), .clear],
                center: UnitPoint(x: 0.82, y: 0.18),
                startRadius: 8,
                endRadius: 260
            )
            RadialGradient(
                colors: [Color.ember.opacity(0.06), .clear],
                center: UnitPoint(x: 0.12, y: 0.28),
                startRadius: 8,
                endRadius: 240
            )
        }
    }
}

struct SleepHeaderView: View {
    let selectedTab: SleepTab
    let onAskAria: () -> Void
    let onPersonalize: () -> Void
    let onTabSelect: (SleepTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sleep")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("Energy first. Night second.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Button(action: onPersonalize) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Sleep preferences")
                Button(action: onAskAria) {
                    Text("Ask ARIA")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Ask ARIA about sleep")
            }

            HStack(spacing: 0) {
                ForEach(SleepTab.allCases, id: \.self) { tab in
                    Button {
                        onTabSelect(tab)
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.title)
                                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                                .foregroundColor(selectedTab == tab ? .textPrimary : .textTertiary)
                            Rectangle()
                                .fill(selectedTab == tab ? Color.textPrimary : Color.clear)
                                .frame(height: 1.5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 8)
    }
}
