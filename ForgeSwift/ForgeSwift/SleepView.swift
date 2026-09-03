import SwiftUI

struct SleepView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var hkService = HealthKitSleepService.shared
    @State private var selectedTab: SleepTab = SleepTab.suggested(
        hour: Calendar.current.component(.hour, from: Date())
    )
    @State private var showSleepPersonalization = false

    private var tonightCoach: SleepBedtimeCoach {
        let nights = store.sleepData.prefix(14)
        let schedule = EnergySchedule.make(from: store.sleepData)
        return SleepBedtimeCoach.make(
            onsets: nights.compactMap(\.onset),
            sleepMinutes: nights.map { $0.totalHours * 60 },
            needMinutes: (schedule?.needHours ?? 8) * 60,
            fallbackOnsetHour: schedule?.phase.onsetHour
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            SleepBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                SleepHeaderView(
                    selectedTab: selectedTab,
                    subtitle: tonightCoach.phase == .dayplan
                        ? "Energy first. Night second."
                        : tonightCoach.headline,
                    onAskAria: {
                        store.openChat(with: tonightCoach.ariaPrompt, voice: false)
                    },
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
    var subtitle: String = "Energy first. Night second."
    let onAskAria: () -> Void
    let onPersonalize: () -> Void
    let onTabSelect: (SleepTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sleep")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
                Button(action: onPersonalize) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                }
                .accessibilityLabel("Sleep preferences")
                Button(action: onAskAria) {
                    Text("Ask ARIA")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
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
                                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium, design: .rounded))
                                .foregroundColor(selectedTab == tab ? .textPrimary : .textTertiary)
                            Capsule()
                                .fill(selectedTab == tab ? AnyShapeStyle(FDS.Gradient.ember) : AnyShapeStyle(Color.clear))
                                .frame(width: selectedTab == tab ? 28 : 0, height: 2.5)
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
