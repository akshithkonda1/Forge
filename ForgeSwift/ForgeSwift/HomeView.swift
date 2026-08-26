import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var showHeaderBlur = false
    @State private var showTrend = false
    @State private var proactiveInsight: String?
    /// Cycle Health is opened only from Home (full-screen cover), not a bottom tab.
    @State private var showCycleHealth = false
    @State private var cycleInitialPane: MenstrualHealthView.Pane? = nil

    private var primaryAction: HomePrimaryAction {
        HomePrimaryAction.resolve(store: store)
    }

    /// Cycle entry lives on Home for everyone who may track self or support someone.
    private var showsCycleEntry: Bool {
        true
    }

    var body: some View {
        ZStack(alignment: .top) {
            HomeAuroraBackground(readinessScore: store.readiness.overall)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: HomeMetrics.sectionGap) {
                        HomeHeaderView()
                            .padding(.top, 12)

                        HomeTodayHero(action: primaryAction)

                        if !store.quietMode,
                           let insight = proactiveInsight,
                           AriaContextStore.shared.shouldBeProactive() {
                            ProactiveCardView(
                                insight: insight,
                                relationshipLevel: AriaContextStore.shared.context.relationshipLevel,
                                onTap: {
                                    store.openChat(with: "Tell me more about: \(insight)", voice: false)
                                }
                            )
                        }

                        if !store.quietMode {
                            HomeARIABriefingCard()
                        }

                        // Rooms stay — they feed ARIA. They are not the first decision.
                        if !MenstrualHealthStore.shared.consentedPeople.isEmpty {
                            HomeSupportPulseCard {
                                FDS.haptic(.light)
                                cycleInitialPane = .partner
                                showCycleHealth = true
                            }
                        }

                        if showsCycleEntry {
                            HomeCycleModule {
                                FDS.haptic(.light)
                                cycleInitialPane = .me
                                showCycleHealth = true
                            }
                        }

                        HomeLifestylePreviewCard()
                        HomeWidgetBoard()
                        HomeAgendaCard()
                        HomeWinCard()
                        HomeDayPreviewStrip()
                        StreakCalendarSection()
                        HomeTrendSection(isExpanded: $showTrend)
                            .padding(.bottom, HomeMetrics.scrollBottomClearance)
                }
                .padding(.horizontal, HomeMetrics.inset)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: geo.frame(in: .named("home-scroll")).minY
                        )
                    }
                }
            }
            .coordinateSpace(name: "home-scroll")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                // Starts at 0 and goes negative. Wait until the greeting has
                // actually left before pinning a compact bar over it.
                let pinned = value < -88
                if pinned != showHeaderBlur {
                    withAnimation(.easeInOut(duration: 0.2)) { showHeaderBlur = pinned }
                }
            }
            .refreshable { await refreshData() }

            if showHeaderBlur {
                HomeScrollMiniHeader()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

        }
        .animation(.easeInOut(duration: 0.22), value: showHeaderBlur)
        .task {
            await store.refreshDailyData()
            proactiveInsight = await AriaService.shared.fetchProactiveMessage(store: store)
            MenstrualHealthStore.shared.refresh(from: store)
        }
        .fullScreenCover(isPresented: $showCycleHealth) {
            NavigationStack {
                MenstrualHealthView(initialPane: cycleInitialPane)
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showCycleHealth = false
                                cycleInitialPane = nil
                            }
                            .foregroundStyle(Color.ember)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: store.pendingCycleHealthOpen) { _, open in
            guard open else { return }
            if store.pendingCyclePane == "partner" {
                cycleInitialPane = .partner
            } else {
                cycleInitialPane = .me
            }
            showCycleHealth = true
            store.pendingCycleHealthOpen = false
            store.pendingCyclePane = nil
        }
        .onAppear {
            if store.pendingCycleHealthOpen {
                if store.pendingCyclePane == "partner" {
                    cycleInitialPane = .partner
                }
                showCycleHealth = true
                store.pendingCycleHealthOpen = false
                store.pendingCyclePane = nil
            }
        }
    }

    @MainActor
    private func refreshData() async {
        FDS.haptic(.light)
        await store.refreshDailyData()
        proactiveInsight = await AriaService.shared.fetchProactiveMessage(store: store)
        FDS.notificationHaptic(.success)
    }
}

struct HomeHeaderView: View {
    @EnvironmentObject var store: AppStore

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning" }
        if h < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    private var firstName: String {
        store.userProfile.name.components(separatedBy: " ").first ?? ""
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(dateString)
                    .forgeSectionLabel()

                Text(greeting + (firstName.isEmpty ? "" : ", \(firstName)"))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                HomeDataStatusPill(
                    isLive: store.healthKitLive,
                    updatedAt: store.lastMetricsRefresh
                )
            }

            Spacer(minLength: 12)

            Button {
                FDS.haptic(.light)
                store.setQuietMode(!store.quietMode)
            } label: {
                Image(systemName: store.quietMode ? "moon.fill" : "moon")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(store.quietMode ? Color.steel : Color.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.quietMode ? "Quiet mode on" : "Quiet mode off")

            Button {
                store.activeTab = .profile
            } label: {
                ProfileAvatarView(
                    fileName: store.userProfile.avatarFileName,
                    initials: String(firstName.prefix(1)).uppercased(),
                    size: 40,
                    showsRing: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .homeEntrance(delay: 0.05)
    }
}

private struct HomeDataStatusPill: View {
    @EnvironmentObject private var store: AppStore
    let isLive: Bool
    let updatedAt: Date?
    @State private var reconnecting = false

    var body: some View {
        Button {
            guard !isLive else { return }
            reconnecting = true
            Task {
                await store.reconnectHealthKit()
                reconnecting = false
                FDS.notificationHaptic(store.healthKitLive ? .success : .warning)
            }
        } label: {
            HStack(spacing: 5) {
                if reconnecting {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle()
                        .fill(isLive ? Color.vitality : Color.warning)
                        .frame(width: 5, height: 5)
                        .shadow(color: isLive ? Color.vitality.opacity(0.8) : .clear, radius: 3)
                }
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isLive ? Color.vitality : .warning)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLive || reconnecting)
        .accessibilityLabel(statusText)
        .accessibilityHint(isLive ? "" : "Double tap to reconnect Apple Health")
    }

    private var statusText: String {
        if reconnecting { return "Reconnecting…" }
        if isLive {
            if let updatedAt {
                let mins = max(0, Int(Date().timeIntervalSince(updatedAt) / 60))
                if mins < 1 { return "Apple Health live · just now" }
                if mins < 60 { return "Apple Health live · \(mins)m ago" }
            }
            return "Apple Health live"
        }
        return "Apple Health offline · tap to reconnect"
    }
}

private struct HomeScrollMiniHeader: View {
    @EnvironmentObject var store: AppStore

    private var firstName: String {
        store.userProfile.name.components(separatedBy: " ").first ?? "Forge"
    }

    var body: some View {
        HStack(spacing: 12) {
            ReadinessRingView(score: store.readiness.overall, size: 26, strokeWidth: 3, showLabel: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(firstName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(store.todayWorkout?.name ?? homeStatusLine(store: store))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.startLifeShapedSession()
            } label: {
                Text(store.isWorkoutActive ? "Continue" : "Start")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(store.readiness.overall < 55 ? Color.steel : Color.ember)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, HomeMetrics.inset)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background {
            Color.background.opacity(0.94)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }
}
