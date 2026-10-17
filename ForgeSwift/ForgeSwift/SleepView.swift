import SwiftUI
import ForgeCore

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

    /// Nil when the newest stored night is older than yesterday.
    private var lastNight: SleepData? { SleepData.lastNight(in: store.sleepData) }

    private var tonightCoach: SleepBedtimeCoach {
        SleepBedtimeCoach.make(from: store.sleepData, lowEnergyDay: store.readiness.overall < 60)
    }

    private var wakeCoach: SleepWakeCoach {
        SleepWakeCoach.make(
            alarms: alarmStore.alarms,
            sleepScore: lastNight?.score,
            lastNightHours: lastNight?.totalHours,
            smartWindowMinutes: alarmStore.next.map {
                hkService.adaptiveSmartWakeMinutes(base: $0.smartWakeWindow, depth: alarmStore.sleeperDepth)
            }
        )
    }

    private var headerSubtitle: String {
        if selectedTab == .alarms {
            if alarmStore.delivery.needsAttention {
                return alarmStore.delivery.headline
            }
            return wakeCoach.headline
        }
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
            let recentScore = lastNight?.score
            _ = hkService.computeAdaptiveSunrise(
                debt: debt,
                recentScore: recentScore,
                profile: hkService.userProfile
            )
        }
    }
}

/// Flat night field. Sleep's identity comes from its data (stages, timing),
/// not from a violet wash.
struct SleepBackground: View {
    var body: some View {
        Color.background
    }
}

struct SleepHeaderView: View {
    let selectedTab: SleepTab
    var subtitle: String = "Energy first. Night second."
    var presence: SleepSurfacePresence
    let onAskAria: () -> Void
    let onPersonalize: () -> Void
    let onTabSelect: (SleepTab) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let tabIcon: [SleepTab: String] = [
        .day: "chart.line.uptrend.xyaxis",
        .night: "moon.stars.fill",
        .alarms: "alarm.fill"
    ]

    private var tabOptions: [ForgeSegmentOption<SleepTab>] {
        SleepTab.allCases.map { tab in
            ForgeSegmentOption(value: tab, title: tab.title, icon: Self.tabIcon[tab])
        }
    }

    private var tabSelection: Binding<SleepTab> {
        Binding(
            get: { selectedTab },
            set: { onTabSelect($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            ForgePageHeader(title: "Sleep", subtitle: subtitle, accent: .steel) {
                askAriaButton
                ForgeIconButton(
                    systemImage: "slider.horizontal.3",
                    accessibilityLabel: "Sleep preferences",
                    tinted: false,
                    action: onPersonalize
                )
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Text(presence.statusCaption)
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundColor(.textTertiary)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }
            ForgeSegmentedControl(
                tabOptions,
                selection: tabSelection,
                accent: .steel,
                bleed: 0,
                animatesSelection: false
            )
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.bottom, FDS.Spacing.md)
    }

    private var askAriaButton: some View {
        Button {
            onAskAria()
        } label: {
            ARIAIdentityMark(state: .idle, mood: .energized, size: 28, amplitude: 0.22)
                .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: ForgeUX.stroke))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask ARIA about sleep")
    }
}
