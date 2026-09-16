import SwiftUI

struct SleepView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var hkService = HealthKitSleepService.shared
    @State private var selectedTab: SleepTab = SleepTab.suggested(
        hour: Calendar.current.component(.hour, from: Date())
    )
    @State private var showSleepPersonalization = false

    @ObservedObject private var alarmStore = ForgeAlarmStore.shared

    private var presence: SleepSurfacePresence { store.sleepSurface }

    private var tonightCoach: SleepBedtimeCoach {
        SleepBedtimeCoach.make(from: store.sleepData)
    }

    private var wakeCoach: SleepWakeCoach {
        SleepWakeCoach.make(
            alarms: alarmStore.alarms,
            sleepScore: store.sleepData.first?.score,
            lastNightHours: store.sleepData.first?.totalHours,
            smartWindowMinutes: alarmStore.next.map {
                hkService.adaptiveSmartWakeMinutes(base: $0.smartWakeWindow)
            }
        )
    }

    private var headerSubtitle: String {
        if selectedTab == .alarms { return wakeCoach.headline }
        return tonightCoach.phase == .dayplan
            ? "Energy first. Night second."
            : tonightCoach.headline
    }

    private func consumePendingSleepTab() {
        guard let leaf = store.pendingSleepTab else { return }
        switch leaf {
        case "alarms", "wake":
            selectedTab = .alarms
        case "night", "tonight", "wind-down", "winddown":
            selectedTab = .night
        default:
            break
        }
        store.pendingSleepTab = nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            SleepBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                SleepHeaderView(
                    selectedTab: selectedTab,
                    subtitle: headerSubtitle,
                    presence: presence,
                    onAskAria: {
                        store.openChat(
                            with: selectedTab == .alarms ? wakeCoach.ariaPrompt : tonightCoach.ariaPrompt,
                            voice: false
                        )
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
                        .environmentObject(store)
                        .tag(SleepTab.alarms)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selectedTab)
            }
        }
        .sheet(isPresented: $showSleepPersonalization) {
            SleepPersonalizationSheet()
                .environmentObject(hkService)
                .environmentObject(store)
        }
        .onAppear { consumePendingSleepTab() }
        .onChange(of: store.pendingSleepTab) { _, _ in consumePendingSleepTab() }
        .task {
            await hkService.refreshFromAppleHealth(into: store)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.background
            RadialGradient(
                colors: [Color(hex: "1A1440").opacity(0.62), .clear],
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 10,
                endRadius: 480
            )
            RadialGradient(
                colors: [Color.aurora.opacity(0.12), .clear],
                center: UnitPoint(x: 0.82, y: 0.16),
                startRadius: 8,
                endRadius: 280
            )
            .blur(radius: reduceMotion ? 0 : 18)
            RadialGradient(
                colors: [Color(hex: "A9D8FF").opacity(0.05), .clear],
                center: UnitPoint(x: 0.14, y: 0.32),
                startRadius: 8,
                endRadius: 240
            )
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.028), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
            .opacity(reduceMotion ? 0.35 : 0.55)
        }
    }
}

struct SleepHeaderView: View {
    let selectedTab: SleepTab
    var subtitle: String = "Energy first. Night second."
    var presence: SleepSurfacePresence
    let onAskAria: () -> Void
    let onPersonalize: () -> Void
    let onTabSelect: (SleepTab) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tabIcon: [SleepTab: String] {
        [.day: "chart.line.uptrend.xyaxis", .night: "moon.stars.fill", .alarms: "alarm.fill"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Sleep")
                            .font(FDS.TypeScale.pageTitle())
                            .foregroundColor(.textPrimary)
                        SleepStatusDot(kind: presence.liveDot)
                    }
                    Text(presence.statusCaption)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: subtitle)
                }
                Spacer()
                HStack(spacing: 8) {
                    ForgeIconButton(
                        systemImage: "slider.horizontal.3",
                        accent: .aurora,
                        accessibilityLabel: "Sleep preferences",
                        action: onPersonalize
                    )
                    Button(action: onAskAria) {
                        HStack(spacing: 6) {
                            ARIAIdentityMark(state: .idle, mood: .energized, size: 14, amplitude: 0.22)
                            Text("Ask ARIA")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(FDS.Gradient.ember)
                        .clipShape(Capsule())
                        .shadow(color: Color.ember.opacity(0.28), radius: 8, y: 3)
                    }
                    .accessibilityLabel("Ask ARIA about sleep")
                }
            }

            HStack(spacing: 6) {
                ForEach(SleepTab.allCases, id: \.self) { tab in
                    Button {
                        onTabSelect(tab)
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tabIcon[tab] ?? "circle")
                                .font(.system(size: 11, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium, design: .rounded))
                        }
                        .foregroundColor(selectedTab == tab ? .white : .textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            selectedTab == tab
                                ? AnyShapeStyle(FDS.Gradient.ember)
                                : AnyShapeStyle(Color.white.opacity(0.06))
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(
                                selectedTab == tab ? Color.white.opacity(0.0) : Color.white.opacity(0.10),
                                lineWidth: 1
                            )
                        )
                        .shadow(color: selectedTab == tab ? Color.ember.opacity(0.22) : .clear, radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 12)
    }
}
