import SwiftUI
import Charts

// ╔════════════════════════════════════════════════════════════════════╗
// ║  FORGE HOME — Control Center + Day Preview                         ║
// ║  Status · Next action · ARIA briefing · Telemetry · Week rhythm  ║
// ╚════════════════════════════════════════════════════════════════════╝

// MARK: - Home metrics

/// One rhythm for the whole Home surface. Every section reads its inset, gap,
/// padding and radius from here instead of hand-picking a number.
///
/// Before this existed the page carried four corner radii (22/18/14/12, plus 24
/// on the celebration banner) in two curve styles, card padding of 16/18/22 with
/// no rule, and thirteen separate per-child bottom paddings.
enum HomeMetrics {
    /// Horizontal inset for every section. The header used `FDS.Spacing.lg`
    /// while the other eleven used a literal `16` — the same number, two spellings.
    static let inset: CGFloat = FDS.Spacing.lg
    /// Vertical gap between sections, applied once by the VStack.
    static let sectionGap: CGFloat = 16
    /// Interior padding for every card.
    static let cardPadding: CGFloat = 18
    /// Radius for elements *inside* a card. Cards themselves use the
    /// `forgeGlassCard` default (`FDS.Radius.xl`).
    static let innerRadius: CGFloat = FDS.Radius.md
    /// Clearance past the tab bar and floating orb at the end of the scroll.
    static let scrollBottomClearance: CGFloat = 140
    /// How far a section rises as it fades in.
    static let entranceRise: CGFloat = 12
}

// MARK: - Section entrance

/// `MainTabView` sets `.id(store.activeTab)` (ContentView.swift), so `HomeView`
/// is destroyed and rebuilt on every tab switch. Without a gate the entire
/// entrance cascade replayed each time you came back to Home. This survives the
/// rebuild and resets on process launch, so the choreography plays once per
/// launch and later visits render immediately.
private final class HomeEntranceSession: @unchecked Sendable {
    static let shared = HomeEntranceSession()
    private(set) var hasPlayed = false
    private var scheduled = false
    private init() {}

    /// Called by every section on first appear. Sections all appear within the
    /// same runloop turn, so the flag must not flip until the longest stagger
    /// has finished — otherwise later sections would snap in mid-cascade.
    func markPlayed() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { self.hasPlayed = true }
    }
}

/// One entrance rule for every Home section, replacing nine hand-rolled variants
/// whose offsets ran −12/12/14/18/20/none. The header used to be the only
/// section that slid *down* while everything else rose.
private struct HomeEntrance: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : HomeMetrics.entranceRise)
            .onAppear {
                guard !HomeEntranceSession.shared.hasPlayed else {
                    appeared = true
                    return
                }
                withAnimation(FDS.Spring.hero.delay(delay)) { appeared = true }
                HomeEntranceSession.shared.markPlayed()
            }
    }
}

extension View {
    /// `delay` encodes the section's position down the page.
    func homeEntrance(delay: Double) -> some View {
        modifier(HomeEntrance(delay: delay))
    }
}

// MARK: - Scroll Offset

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Primary action engine

@MainActor
enum HomePrimaryAction: Equatable {
    case startWorkout(id: String, name: String)
    case continueWorkout
    case recoveryDay(reason: String)
    case buildPlan

    static func resolve(store: AppStore) -> HomePrimaryAction {
        if store.isWorkoutActive { return .continueWorkout }

        let score = store.readiness.overall
        let guidanceOnly = AriaContextStore.shared.context.constraints
            .contains { $0.contains("guidance_only") }

        if score < 55 {
            let reason = guidanceOnly
                ? "Recovery-first day — structure and rest over intensity."
                : "Readiness is low. Protect recovery and go light."
            return .recoveryDay(reason: reason)
        }

        if let plan = store.todayWorkout {
            if score < 70 {
                return .recoveryDay(reason: "You're at \(score)%. Consider mobility or a lighter take on \(plan.name).")
            }
            return .startWorkout(id: plan.id, name: plan.name)
        }

        return .buildPlan
    }

    var title: String {
        switch self {
        case .startWorkout(_, let name): return "Start \(name)"
        case .continueWorkout:           return "Continue session"
        case .recoveryDay:               return "Start recovery session"
        case .buildPlan:                 return "Build today's plan with ARIA"
        }
    }

    var subtitle: String? {
        switch self {
        case .startWorkout:              return "Primary control · ready when you are"
        case .continueWorkout:           return "Pick up where you left off"
        case .recoveryDay(let reason):   return reason
        case .buildPlan:                 return "ARIA will shape a session from your readiness"
        }
    }

    var icon: String {
        switch self {
        case .startWorkout:    return "play.fill"
        case .continueWorkout: return "arrow.clockwise"
        case .recoveryDay:     return "leaf.fill"
        case .buildPlan:       return "sparkles"
        }
    }

    var isRecovery: Bool {
        if case .recoveryDay = self { return true }
        return false
    }
}

// MARK: - Root Home View

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var showHeaderBlur = false
    @State private var showCelebration = false
    @State private var celebrationKey = 0
    @State private var showTrend = false
    @State private var proactiveInsight: String?
    /// Cycle Health is opened only from Home (full-screen cover), not a bottom tab.
    @State private var showCycleHealth = false
    @State private var cycleInitialPane: MenstrualHealthView.Pane? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                ZStack(alignment: .top) {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .global).minY)
                    }
                    .frame(height: 0)

                    // One gap and one inset for the whole page, applied here rather
                    // than as thirteen per-child bottom paddings.
                    VStack(spacing: HomeMetrics.sectionGap) {
                        // 1. Header
                        HomeHeaderView()
                            .padding(.top, 64)

                        // 2. Hero readiness control
                        HomeHeroReadinessCard(onCelebrate: triggerCelebration)

                        // 3. Dual primary controls (train + lifestyle)
                        HomePrimaryCTA(action: primaryAction)

                        // 3b. User-pinned widgets (also addable on the iOS Home Screen)
                        HomeWidgetBoard()

                        // 4. Today's agenda
                        HomeAgendaCard()

                        // 5. Win of the day
                        HomeWinCard()

                        // 6. Support pulse (partner cycle)
                        if !MenstrualHealthStore.shared.consentedPeople.isEmpty {
                            HomeSupportPulseCard {
                                FDS.haptic(.light)
                                cycleInitialPane = .partner
                                showCycleHealth = true
                            }
                        }

                        // 7. ARIA briefing (suppressed in quiet mode for proactive card)
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

                        // 8. Lifestyle preview (full surface is its own tab)
                        HomeLifestylePreviewCard()

                        // 9. Cycle Health — entry only from Home (not bottom tabs)
                        if showsCycleEntry {
                            HomeCycleModule {
                                FDS.haptic(.light)
                                cycleInitialPane = .me
                                showCycleHealth = true
                            }
                        }

                        // 10. Day preview telemetry
                        HomeDayPreviewStrip()

                        // 11. Week rhythm
                        StreakCalendarSection()

                        // 12. Optional trend
                        HomeTrendSection(isExpanded: $showTrend)
                            .padding(.bottom, HomeMetrics.scrollBottomClearance)
                    }
                    .padding(.horizontal, HomeMetrics.inset)
                }
            }
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                withAnimation(.easeInOut(duration: 0.18)) {
                    showHeaderBlur = value < 48
                }
            }
            .refreshable { await refreshData() }

            if showHeaderBlur {
                HomeScrollMiniHeader()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if showCelebration && !reduceMotion {
                CelebrationOverlay(key: celebrationKey, onDismiss: {
                    withAnimation(FDS.Spring.standard) { showCelebration = false }
                })
                .ignoresSafeArea()
                .zIndex(100)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VoiceQuickLaunchOrb()
                        .padding(.trailing, 24)
                        .padding(.bottom, 108)
                }
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.22), value: showHeaderBlur)
        .onChange(of: store.readiness.overall) { old, new in
            if new >= 85 && old < 85 { triggerCelebration() }
        }
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

    private func triggerCelebration() {
        celebrationKey += 1
        withAnimation(FDS.Spring.hero) { showCelebration = true }
        FDS.notificationHaptic(.success)
        // Dismissal is owned by the overlay's own timer, which calls back through
        // `onDismiss`. This used to schedule a competing 4.5s timer against the
        // overlay's 3.8s one, so the teardown animation ran twice.
    }

    @MainActor
    private func refreshData() async {
        FDS.haptic(.light)
        await store.refreshDailyData()
        proactiveInsight = await AriaService.shared.fetchProactiveMessage(store: store)
        FDS.notificationHaptic(.success)
        if store.readiness.overall >= 85 { triggerCelebration() }
    }
}

// ============================================================
// MARK: - Header
// ============================================================

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
            VStack(alignment: .leading, spacing: 6) {
                Text(dateString.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .tracking(1.8)

                Text(greeting + (firstName.isEmpty ? "" : ", \(firstName)"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                HomeDataStatusPill(
                    isLive: store.healthKitLive,
                    updatedAt: store.lastMetricsRefresh
                )
            }

            Spacer()

            Button {
                FDS.haptic(.light)
                store.setQuietMode(!store.quietMode)
            } label: {
                Image(systemName: store.quietMode ? "moon.fill" : "moon")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(store.quietMode ? .steel : .textTertiary)
                    .frame(width: 40, height: 40)
                    .background(Color.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.borderColor, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.quietMode ? "Quiet mode on" : "Quiet mode off")
            .padding(.trailing, 8)

            Button {
                store.activeTab = .profile
            } label: {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.surface)
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Color.borderColor, lineWidth: 0.5))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 19))
                                .foregroundColor(.ember)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                    if store.currentStreak > 0 {
                        ZStack {
                            Circle().fill(Color.ember).frame(width: 22, height: 22)
                                .shadow(color: Color.ember.opacity(0.5), radius: 6)
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                        }
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("\(store.currentStreak) day streak")
                    }
                }
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
        .accessibilityHint(isLive ? "" : "Double tap to reconnect HealthKit")
    }

    private var statusText: String {
        if reconnecting { return "Reconnecting…" }
        if isLive {
            if let updatedAt {
                let mins = max(0, Int(Date().timeIntervalSince(updatedAt) / 60))
                if mins < 1 { return "HealthKit live · just now" }
                if mins < 60 { return "HealthKit live · \(mins)m ago" }
            }
            return "HealthKit live"
        }
        return "HealthKit offline · tap to reconnect"
    }
}

// ============================================================
// MARK: - Scroll mini header
// ============================================================

private struct HomeScrollMiniHeader: View {
    @EnvironmentObject var store: AppStore

    private var firstName: String {
        store.userProfile.name.components(separatedBy: " ").first ?? "Forge"
    }

    var body: some View {
        HStack(spacing: 12) {
            ReadinessRingView(score: store.readiness.overall, size: 28, strokeWidth: 3, showLabel: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(firstName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("\(store.readiness.overall) · \(homeStatusLine(store: store))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if store.currentStreak > 0 {
                Label("\(store.currentStreak)", systemImage: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.ember)
            }
        }
        .padding(.horizontal, HomeMetrics.inset)
        .padding(.top, 54)
        .padding(.bottom, 12)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient.premiumChrome.opacity(0.5)
            }
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.02)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.5)
        }
    }
}

// ============================================================
// MARK: - Hero readiness
// ============================================================

private struct HomeHeroReadinessCard: View {
    @EnvironmentObject var store: AppStore
    var onCelebrate: () -> Void = {}
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("READINESS")
                        .forgeSectionLabel()
                    Text(homeStatusLine(store: store))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(readinessColor(store.readiness.overall))
                }
                Spacer()
                Button {
                    FDS.haptic(.light)
                    withAnimation(FDS.Spring.standard) { showDetails.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showDetails ? "Less" : "Details")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(showDetails ? 180 : 0))
                    }
                    .foregroundColor(.ember)
                }
            }
            .padding(.bottom, 20)

            ReadinessRingView(score: store.readiness.overall, size: 176, strokeWidth: 14)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Readiness \(store.readiness.overall) out of 100, \(readinessLabel(store.readiness.overall))")
                .onTapGesture {
                    if store.readiness.overall >= 85 { onCelebrate() }
                }

            Text("\(store.readiness.overall) · \(homeStatusLine(store: store))")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, showDetails ? 16 : 0)

            if showDetails {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    BreakdownCardView(label: "Sleep", value: store.readiness.sleepQuality, inverted: false, index: 0)
                    BreakdownCardView(label: "Recovery", value: store.readiness.recoveryScore, inverted: false, index: 1)
                    BreakdownCardView(label: "Stress", value: store.readiness.stressLevel, inverted: true, index: 2)
                    BreakdownCardView(label: "Energy", value: store.readiness.energyBank, inverted: false, index: 3)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))

                VStack(alignment: .leading, spacing: 8) {
                    Text("WHY THIS SCORE")
                        .forgeSectionLabel()
                        .padding(.top, 4)
                    Text(readinessWhyCopy(store: store))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ReadinessInsightRow(
                        icon: "moon.stars.fill",
                        title: "Deep Sleep",
                        value: "\(store.dailyMetrics.deepSleep / 60)h \(store.dailyMetrics.deepSleep % 60)m",
                        color: .steel
                    )
                    ReadinessInsightRow(
                        icon: "waveform.path.ecg.rectangle.fill",
                        title: "HRV",
                        value: "\(store.dailyMetrics.hrv)ms",
                        color: .danger
                    )

                    Button {
                        FDS.haptic(.light)
                        store.openChat(
                            with: "Explain my readiness score of \(store.readiness.overall). Sleep \(store.readiness.sleepQuality), recovery \(store.readiness.recoveryScore), stress \(store.readiness.stressLevel), energy \(store.readiness.energyBank).",
                            voice: false
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Explain my readiness")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.ember)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.ember.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.top, 12)
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: readinessColor(store.readiness.overall))
        .homeEntrance(delay: 0.12)
    }
}

// ============================================================
// MARK: - Primary CTA
// ============================================================

private struct HomePrimaryCTA: View {
    @EnvironmentObject var store: AppStore
    let action: HomePrimaryAction
    @State private var pressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                FDS.haptic(.medium)
                perform()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: action.icon)
                        .font(.system(size: 16, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.system(size: 17, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if let subtitle = action.subtitle {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    ZStack {
                        if action.isRecovery {
                            FDS.Gradient.steel
                        } else {
                            FDS.Gradient.ember
                        }
                        LinearGradient.premiumChrome
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(
                    color: (action.isRecovery ? Color.steel : Color.ember).opacity(pressed ? 0.22 : 0.5),
                    radius: pressed ? 8 : 22,
                    y: pressed ? 3 : 10
                )
            }
            .buttonStyle(.plain)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(FDS.Spring.snap, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
            .accessibilityLabel(action.title)
            .accessibilityHint(action.subtitle ?? "Double tap to activate")

            // Dual secondary row: ARIA + Lifestyle
            HStack(spacing: 10) {
                Button {
                    FDS.haptic(.light)
                    store.openChat(with: "What should I focus on today?", voice: false)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Ask ARIA")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                            .stroke(Color.borderColor, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    FDS.haptic(.light)
                    store.activeTab = .lifestyle
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Lifestyle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(Color.vitality)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.vitality.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                            .stroke(Color.vitality.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func perform() {
        switch action {
        case .startWorkout, .continueWorkout:
            if !store.isWorkoutActive { store.startWorkout() }
            store.activeTab = .workout
        case .recoveryDay:
            store.openChat(
                with: "I'm at \(store.readiness.overall)% readiness. Build me a recovery-focused session — guidance only if needed.",
                voice: false
            )
        case .buildPlan:
            store.openChat(
                with: "Build today's training plan from my readiness, goals, and recovery.",
                voice: false
            )
        }
    }
}

// ============================================================
// MARK: - ARIA briefing
// ============================================================

struct HomeARIABriefingCard: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedText = ""
    @State private var isTyping = false
    @State private var pulseRing = false

    private var fullBriefing: String {
        HomeARIABriefingBuilder.build(store: store)
    }

    private var typewriterKey: String {
        let day = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let band = store.readiness.overall / 10
        return "home.aria.typewriter.\(Int(day)).\(band)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.ember.opacity(0.22))
                        .frame(width: 48, height: 48)
                        .blur(radius: 8)
                        .scaleEffect(pulseRing ? 1.35 : 1)
                        .opacity(pulseRing ? 0 : 0.7)
                    Circle()
                        .fill(FDS.Gradient.ember)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text("A")
                                .font(.system(size: 18, weight: .black))
                                .foregroundColor(.white)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("ARIA")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.ember)
                            .tracking(1.4)
                        Text("Briefing")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textMuted)
                    }
                    Text("Daily command · Forge")
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }

                Spacer()

                Button {
                    FDS.haptic(.medium)
                    store.openChat(with: fullBriefing, voice: true)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.ember.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.ember)
                    }
                    .overlay(Circle().stroke(Color.ember.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Talk to ARIA")
            }
            .padding(.bottom, 14)

            Button {
                FDS.haptic(.light)
                store.openChat(with: "Continue from today's briefing.", voice: false)
            } label: {
                Text(displayedText.isEmpty && !isTyping ? fullBriefing : displayedText)
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                            .stroke(Color.ember.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ARIA briefing: \(fullBriefing)")
            .padding(.bottom, 14)

            HStack(spacing: 0) {
                briefingChip(icon: "message.fill", label: "Reply") {
                    store.openChat(with: "Let's talk about my day.", voice: false)
                }
                Spacer()
                briefingChip(icon: themedPlanIcon, label: themedPlanLabel) {
                    store.openChat(with: themedPlanPrompt, voice: false)
                }
                Spacer()
                briefingChip(icon: "calendar", label: "Plan week") {
                    store.openChat(with: "Help me plan this week around recovery and training.", voice: false)
                }
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: .ember)
        .homeEntrance(delay: 0.18)
        .onAppear {
            // The avatar halo was the one continuous loop on Home that ignored
            // Reduce Motion, while the typewriter beside it already honoured it.
            if !reduceMotion {
                withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                    pulseRing = true
                }
            }
            startTypewriterIfNeeded()
        }
    }

    private var themedPlanLabel: String {
        switch store.userProfile.trainingTheme {
        case .soloLeveling: return "Daily quest"
        case .classic: return "Today's plan"
        default: return store.userProfile.trainingTheme.label
        }
    }

    private var themedPlanIcon: String {
        store.userProfile.trainingTheme == .classic ? "sparkles" : store.userProfile.trainingTheme.icon
    }

    private var themedPlanPrompt: String {
        let theme = store.userProfile.trainingTheme
        switch theme {
        case .soloLeveling:
            return "Build today's Solo Leveling daily quest based on my readiness."
        case .classic:
            return "What should I train today based on my readiness?"
        default:
            return "Build a \(theme.label) training plan for me based on my readiness."
        }
    }

    private func briefingChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            FDS.haptic(.light)
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(label == "Reply" ? .ember : .textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func startTypewriterIfNeeded() {
        let defaults = UserDefaults.standard
        let already = defaults.string(forKey: "home.aria.lastTypewriterKey") == typewriterKey
        let text = fullBriefing

        if already || UIAccessibility.isReduceMotionEnabled {
            displayedText = text
            isTyping = false
            return
        }

        defaults.set(typewriterKey, forKey: "home.aria.lastTypewriterKey")
        displayedText = ""
        isTyping = true
        var idx = 0
        func next() {
            guard idx < text.count else {
                isTyping = false
                return
            }
            let i = text.index(text.startIndex, offsetBy: idx)
            displayedText.append(text[i])
            idx += 1
            let delay: Double = text[i] == " " ? 0.035 : (text[i] == "." ? 0.14 : 0.02)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { next() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { next() }
    }
}

@MainActor
enum HomeARIABriefingBuilder {
    static func build(store: AppStore) -> String {
        let deep = store.dailyMetrics.deepSleep
        let deepStr = deep >= 60 ? "\(deep / 60)h \(deep % 60)m" : "\(deep)m"
        let context = store.makeTrainerContext()
        let theme = store.userProfile.trainingTheme

        let facts = AriaSpeechFacts(
            sessionTitle: store.todayWorkout?.name,
            themeLabel: theme.label
        )

        // Seed a few factual beats; voice engine varies delivery.
        let voiceCore = AriaVoiceEngine.speak(
            intent: .briefing,
            context: context,
            facts: facts,
            themeOverride: theme
        )

        // Candidates are ranked by how much they matter today, then the top two
        // are taken. Previously they were gated and shuffled by the readiness
        // score itself (`score % 3 == 0`, RNG seeded on `score &* 17`), which had
        // two bad consequences: whether ARIA mentioned your partner depended on
        // an unrelated number, and a genuinely urgent beat ("HRV is low at 38ms")
        // could lose a coin flip to filler ("Still aligned to strength"). It also
        // reshuffled the whole briefing whenever readiness moved a single point.
        var beats: [BriefingBeat] = []

        // --- Recovery signals. A deficit outranks a confirmation: being told
        //     something is wrong is more actionable than being told it is fine.
        if store.readiness.sleepQuality < 60 {
            beats.append(.init(text: "Deep sleep was only \(deepStr) — recovery may lag.", priority: .urgent))
        } else if store.readiness.sleepQuality >= 80 {
            beats.append(.init(text: "Deep sleep looked solid (\(deepStr)).", priority: .confirming))
        }
        if store.dailyMetrics.hrv > 0 {
            if store.dailyMetrics.hrv < 40 {
                beats.append(.init(text: "HRV is low at \(store.dailyMetrics.hrv)ms.", priority: .urgent))
            } else if store.dailyMetrics.hrv >= 50 {
                beats.append(.init(text: "HRV holding at \(store.dailyMetrics.hrv)ms.", priority: .confirming))
            }
        }

        // --- Blocks today's action, so it ranks above passive observations.
        if store.todayWorkout == nil {
            if theme == .soloLeveling {
                beats.append(.init(text: "No quest locked — ask for today's daily quest.", priority: .blocking))
            } else if theme != .classic {
                beats.append(.init(text: "No plan locked — I can build a \(theme.label) session.", priority: .blocking))
            }
        }

        // --- Support context. The phase-specific line is time-sensitive and
        //     genuinely actionable; the generic nudge is not, so it sits low
        //     rather than being gated on `score % 3`.
        let cycleStore = MenstrualHealthStore.shared
        if let person = cycleStore.mostTimelyPerson {
            let who = person.displayName
            let phase = cycleStore.personSnapshots[person.id]?.phase ?? cycleStore.partnerSnapshot.phase
            let extra = cycleStore.consentedPeople.count > 1
                ? " · \(cycleStore.consentedPeople.count) people"
                : ""
            if phase == .menstruation || phase == .luteal {
                beats.append(.init(
                    text: person.role == .child
                        ? "\(who) may need the soft parent playbook today."
                        : "Keep \(who) in mind — \(phase.shortLabel.lowercased()) energy.",
                    priority: .timely))
            } else {
                beats.append(.init(text: "You're also looking out for \(who)\(extra). Ask me anytime.", priority: .ambient))
            }
        } else if store.userProfile.gender == .male {
            beats.append(.init(text: "Partner or daughter to support? I can learn that context.", priority: .ambient))
        }

        if let emotion = AriaContextStore.shared.context.lifestyleTags.first(where: { $0.hasPrefix("emotion:") && !$0.contains("about_other") }) {
            let raw = emotion.replacingOccurrences(of: "emotion:", with: "")
            if let need = AriaEmotionalNeed(rawValue: raw), need != .crisis {
                beats.append(.init(text: "Still holding space for \(need.label.lowercased()) if you need it.", priority: .timely))
            }
        }

        // --- Pure reassurance, carrying no new information. Kept so a quiet day
        //     still reads warm, but it can only appear when nothing outranks it.
        if let goal = store.userProfile.fitnessGoals.first {
            beats.append(.init(text: "Still aligned to \(goal.label.lowercased()).", priority: .filler))
        }

        // Rank, then break ties on a seed that is stable for the whole day, so
        // repeated glances at Home read consistently instead of reshuffling.
        let daySeed = UInt64(abs(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970.rounded())) &+ 1
        var rng = AriaSeededRNG(seed: daySeed)
        let jittered = beats.map { (beat: $0, tie: rng.int(in: 0..<1000)) }
        let chosen = jittered
            .sorted { ($0.beat.priority.rawValue, $0.tie) > ($1.beat.priority.rawValue, $1.tie) }
            .prefix(2)
            .map { $0.beat.text }

        return ([voiceCore] + chosen).joined(separator: " ")
    }

    /// One candidate line, ranked by how much it matters today.
    private struct BriefingBeat {
        let text: String
        let priority: Priority

        /// Higher wins. The ordering encodes an editorial stance: a deficit you
        /// can act on beats a confirmation that things are fine, and anything
        /// concrete beats reassurance.
        enum Priority: Int {
            case filler     = 10   // true but carries no information
            case ambient    = 20   // a standing offer, not tied to today
            case confirming = 40   // a metric that looks good
            case timely     = 60   // relevant specifically today
            case blocking   = 80   // stops the user acting until resolved
            case urgent     = 100  // a deficit worth changing the plan over
        }
    }
}

// ============================================================
// MARK: - Cycle Health entry (Home-only surface)
// ============================================================

/// Primary entry into Cycle Health. Not a bottom tab — opens full-screen from Home.
struct HomeCycleModule: View {
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    @EnvironmentObject private var store: AppStore
    var onOpen: () -> Void

    private var preferPartner: Bool {
        store.userProfile.gender == .male && !cycleStore.settings.enabled
    }

    private var phase: MenstrualPhase {
        if preferPartner || (!cycleStore.consentedPeople.isEmpty && !cycleStore.settings.enabled) {
            if let person = cycleStore.mostTimelyPerson,
               let snap = cycleStore.personSnapshots[person.id] {
                return snap.phase
            }
            return cycleStore.partnerSnapshot.phase
        }
        return cycleStore.snapshot.phase
    }

    private var accent: Color { Color(hex: phase.accentHex) }

    private var title: String {
        if cycleStore.settings.enabled, let day = cycleStore.snapshot.dayInCycle {
            return "\(cycleStore.snapshot.phase.label) · Day \(day)"
        }
        if cycleStore.consentedPeople.count > 1 {
            return "Supporting \(cycleStore.consentedPeople.count) people"
        }
        if let person = cycleStore.selectedPerson ?? cycleStore.consentedPeople.first,
           person.settings.enabled, person.settings.consentAcknowledged {
            let name = person.displayName
            if let day = (cycleStore.personSnapshots[person.id] ?? cycleStore.partnerSnapshot).dayInCycle {
                return "\(name) · Day \(day)"
            }
            return "Supporting \(name)"
        }
        return "Cycle Health"
    }

    private var subtitle: String {
        if cycleStore.settings.enabled {
            return cycleStore.snapshot.trainingNote
        }
        if !cycleStore.consentedPeople.isEmpty {
            if cycleStore.consentedPeople.count > 1 {
                return cycleStore.consentedPeople.map { $0.role.shortLabel }.joined(separator: " · ")
            }
            return "Family support · open to log or ask ARIA"
        }
        return "Track your cycle or support someone you love"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("CYCLE")
                        .forgeSectionLabel()
                    Spacer()
                    Text("Open")
                        .font(FDS.TypeScale.label(12))
                        .foregroundStyle(accent)
                }

                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(accent.opacity(0.22), lineWidth: 6)
                            .frame(width: 56, height: 56)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                        Image(systemName: phase.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(FDS.TypeScale.title(17))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(FDS.TypeScale.body(12))
                            .foregroundColor(.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }

                // Mini chips
                HStack(spacing: 8) {
                    if cycleStore.settings.enabled {
                        miniChip("\(Int(cycleStore.snapshot.confidence * 100))% conf", accent)
                        if let next = cycleStore.snapshot.nextPeriod {
                            miniChip("Next \(shortDate(next.medianDayKey))", Color.alert)
                        }
                    } else if !cycleStore.consentedPeople.isEmpty {
                        ForEach(cycleStore.consentedPeople.prefix(3)) { person in
                            miniChip(person.role.shortLabel, Color.indigo)
                        }
                        if let snap = cycleStore.mostTimelyPerson.flatMap({ cycleStore.personSnapshots[$0.id] }) {
                            miniChip(snap.phase.shortLabel, accent)
                        }
                    } else {
                        miniChip("My cycle", Color.alert)
                        miniChip("Support", Color.indigo)
                    }
                    miniChip("Private", Color.vitality)
                    Spacer()
                }

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.vitality)
                    Text(CyclePrivacy.shortPromise)
                        .font(FDS.TypeScale.body(11))
                        .foregroundColor(.textTertiary)
                        .lineLimit(2)
                }
            }
            .padding(HomeMetrics.cardPadding)
            .forgeGlassCard(accent: accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cycle Health, \(title). \(CyclePrivacy.shortPromise)")
        .accessibilityHint("Opens private cycle tracking from Home")
    }

    private var progress: CGFloat {
        let snap: MenstrualCycleSnapshot = {
            if preferPartner || !cycleStore.settings.enabled {
                if let person = cycleStore.mostTimelyPerson,
                   let s = cycleStore.personSnapshots[person.id] {
                    return s
                }
                return cycleStore.partnerSnapshot
            }
            return cycleStore.snapshot
        }()
        guard let day = snap.dayInCycle else { return 0.12 }
        let len = max(21, min(45, snap.cycleLengthMedian))
        return min(0.95, CGFloat(day) / CGFloat(len))
    }

    private func miniChip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(FDS.TypeScale.micro(10))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func shortDate(_ key: String) -> String {
        guard let d = CycleDayKey.date(from: key) else { return key }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

// ============================================================
// MARK: - Readiness why copy
// ============================================================

@MainActor
private func readinessWhyCopy(store: AppStore) -> String {
    var bits: [String] = []
    let r = store.readiness
    if r.sleepQuality < 55 {
        bits.append("Sleep quality is dragging the score")
    } else if r.sleepQuality >= 80 {
        bits.append("Sleep looks supportive")
    }
    if r.recoveryScore < 55 {
        bits.append("recovery markers are soft")
    } else if r.recoveryScore >= 80 {
        bits.append("recovery is solid")
    }
    if r.stressLevel >= 65 {
        bits.append("stress is elevated")
    }
    if r.energyBank < 50 {
        bits.append("energy bank is low")
    }
    let cycle = MenstrualHealthStore.shared
    if cycle.settings.enabled, cycle.settings.shareWithAria, cycle.snapshot.recommendRecoveryBias {
        bits.append("cycle phase suggests a recovery bias")
    }
    if bits.isEmpty {
        return "Balanced drivers across sleep, recovery, stress, and energy. Readiness is a composite — not a single sensor."
    }
    let joined = bits.joined(separator: "; ")
    return joined.prefix(1).uppercased() + joined.dropFirst() + "."
}

// ============================================================
// MARK: - Win of the day
// ============================================================

private struct HomeWinCard: View {
    @EnvironmentObject var store: AppStore

    private var title: String {
        if store.isWorkoutActive { return "Session in progress" }
        if store.currentStreak >= 7 { return "\(store.currentStreak)-day streak" }
        if store.currentStreak > 0 { return "Streak: \(store.currentStreak) days" }
        return "Forge day zero energy"
    }

    private var subtitle: String {
        if store.isWorkoutActive { return "Finish strong — then log recovery." }
        if store.currentStreak >= 3 { return "Consistency is compounding. Protect sleep tonight." }
        return "Complete today’s plan to light the streak."
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.ember.opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color.ember)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("WIN")
                    .forgeSectionLabel()
                    .foregroundStyle(Color.ember)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: .ember)
    }
}

// ============================================================
// MARK: - Support pulse
// ============================================================

private struct HomeSupportPulseCard: View {
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    var onOpen: () -> Void

    /// One accent for the whole card. The icon used to take the live phase colour
    /// while the card border was hardcoded indigo, so the two fought each other.
    private var pulsePerson: SupportedPerson? { cycleStore.mostTimelyPerson }
    private var pulseSnapshot: MenstrualCycleSnapshot {
        if let id = pulsePerson?.id { return cycleStore.personSnapshots[id] ?? cycleStore.partnerSnapshot }
        return cycleStore.partnerSnapshot
    }
    private var accent: Color { Color(hex: pulseSnapshot.phase.accentHex) }
    private var pulseBriefLine: String {
        if let id = pulsePerson?.id, let brief = cycleStore.personBriefs[id] {
            return brief.headline
        }
        if cycleStore.consentedPeople.count > 1 {
            let others = cycleStore.consentedPeople
                .filter { $0.id != pulsePerson?.id }
                .prefix(2)
                .map(\.displayName)
            if !others.isEmpty {
                return "Also \(others.joined(separator: ", "))"
            }
        }
        return cycleStore.partnerSupportBrief?.headline ?? "Open cycle support"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: pulseSnapshot.phase.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.15))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(cycleStore.consentedPeople.count > 1 ? "SUPPORTING \(cycleStore.consentedPeople.count)" : "SUPPORTING")
                        .forgeSectionLabel()
                    Text("\(pulsePerson?.displayName ?? cycleStore.partnerSettings.displayName) · \(pulseSnapshot.phase.shortLabel)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(pulseBriefLine)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
            }
            .padding(HomeMetrics.cardPadding)
            .forgeGlassCard(accent: accent)
        }
        .buttonStyle(.plain)
    }
}

// ============================================================
// MARK: - Agenda (today's command list)
// ============================================================

private struct HomeAgendaCard: View {
    @EnvironmentObject var store: AppStore

    private var items: [(icon: String, title: String, sub: String, color: Color, action: () -> Void)] {
        var rows: [(icon: String, title: String, sub: String, color: Color, action: () -> Void)] = []

        if store.isWorkoutActive {
            rows.append((
                "figure.strengthtraining.traditional",
                "Continue session",
                store.todayWorkout?.name ?? "Active workout",
                .ember,
                { store.activeTab = .workout }
            ))
        } else if let plan = store.todayWorkout {
            rows.append((
                "dumbbell.fill",
                plan.name,
                "\(plan.duration) min · \(plan.intensity.label)",
                .ember,
                { store.activeTab = .workout }
            ))
        } else {
            rows.append((
                "sparkles",
                "Build today's plan",
                "ARIA will shape a session from readiness",
                .ember,
                { store.openChat(with: "Build today's training plan from my readiness.", voice: false) }
            ))
        }

        let sleepHours = store.dailyMetrics.totalSleep > 0
            ? Double(store.dailyMetrics.totalSleep) / 60.0
            : store.sleepData.first?.totalHours
        if let h = sleepHours, h > 0 {
            rows.append((
                "moon.zzz.fill",
                String(format: "Sleep · %.1fh", h),
                store.readiness.overall < 60 ? "Protect recovery tonight" : "Review wind-down",
                .steel,
                { store.activeTab = .sleep }
            ))
        } else {
            rows.append((
                "moon.zzz.fill",
                "Log or sync sleep",
                "HealthKit sleep improves readiness",
                .steel,
                { store.activeTab = .sleep }
            ))
        }

        rows.append((
            "leaf.fill",
            "Lifestyle check-in",
            "Protein · water · meals",
            Color.vitality,
            { store.activeTab = .lifestyle }
        ))

        if MenstrualHealthStore.shared.settings.enabled {
            let snap = MenstrualHealthStore.shared.snapshot
            rows.append((
                snap.phase.icon,
                "Cycle · \(snap.phase.shortLabel)",
                snap.dayInCycle.map { "Day \($0)" } ?? snap.phase.label,
                Color(hex: snap.phase.accentHex),
                {
                    store.openChat(
                        with: "I'm in \(snap.phase.label)"
                            + (snap.dayInCycle.map { " (day \($0))" } ?? "")
                            + ". How should I train and recover?",
                        voice: false
                    )
                }
            ))
        }

        return rows
    }

    var body: some View {
        // `items` is a computed property that rebuilds the whole row array; it was
        // being evaluated twice per render, once for the count and once for the
        // ForEach. Bind it once.
        let rows = items
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TODAY'S AGENDA")
                    .forgeSectionLabel()
                Spacer()
                Text("\(rows.count) items")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMuted)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                Button {
                    FDS.haptic(.light)
                    item.action()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(item.color.opacity(0.16))
                                .frame(width: 36, height: 36)
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(item.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text(item.sub)
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textMuted)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: .ember.opacity(0.5))
        .homeEntrance(delay: 0.16)
    }
}

// ============================================================
// MARK: - Lifestyle preview (Home control center)
// ============================================================

private struct HomeLifestylePreviewCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Button {
            FDS.haptic(.light)
            store.activeTab = .lifestyle
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("LIFESTYLE")
                        .forgeSectionLabel()
                    Spacer()
                    Text("Open")
                        .font(FDS.TypeScale.label(12))
                        .foregroundStyle(Color.vitality)
                }

                HStack(spacing: 10) {
                    lifestyleChip(
                        icon: "figure.walk",
                        value: store.dailyMetrics.steps > 0 ? store.dailyMetrics.steps.formatted() : "—",
                        label: "Steps",
                        color: Color.vitality
                    )
                    lifestyleChip(
                        icon: "flame.fill",
                        value: store.dailyMetrics.activeCalories > 0 ? "\(store.dailyMetrics.activeCalories)" : "—",
                        label: "Active",
                        color: .ember
                    )
                    lifestyleChip(
                        icon: "heart.fill",
                        value: store.dailyMetrics.hrv > 0 ? "\(store.dailyMetrics.hrv)" : "—",
                        label: "HRV",
                        color: .danger
                    )
                    lifestyleChip(
                        icon: "drop.fill",
                        value: {
                            let glasses = HealthKitManager.shared.todayStats?.water ?? 0
                            return glasses > 0 ? String(format: "%.1f", glasses) : "—"
                        }(),
                        label: "Water",
                        color: Color(hex: "4A9EFF")
                    )
                }

                HStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.amber)
                    Text("Nutrition · hydration · wellbeing — tap water for the full page")
                        .font(FDS.TypeScale.body(12))
                        .foregroundColor(.textTertiary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
            }
            .padding(HomeMetrics.cardPadding)
            .forgeGlassCard(accent: Color.vitality)
        }
        .buttonStyle(.plain)
        .homeEntrance(delay: 0.22)
        .accessibilityLabel("Lifestyle preview")
        .accessibilityHint("Opens the Lifestyle tab")
    }

    private func lifestyleChip(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surfaceElevated.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
    }
}

// ============================================================
// MARK: - Day preview strip (truthful telemetry)
// ============================================================

private struct HomeDayPreviewStrip: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("DAY PREVIEW")
                    .forgeSectionLabel()
                Spacer()
                Button("Sleep") { store.activeTab = .sleep }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ember)
            }

            // The tiles bleed to the screen edge instead of stopping at the page
            // inset, so the row reads as scrollable rather than clipped. The
            // negative outer inset is paid back as leading content padding, which
            // keeps the first tile aligned with the header above it.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    HomeMetricTile(
                        icon: "moon.zzz.fill",
                        iconColor: .steel,
                        value: sleepValue,
                        label: "Sleep"
                    )
                    HomeMetricTile(
                        icon: "waveform.path.ecg",
                        iconColor: .danger,
                        value: store.dailyMetrics.hrv > 0 ? "\(store.dailyMetrics.hrv)ms" : "—",
                        label: "HRV"
                    )
                    HomeMetricTile(
                        icon: "figure.walk",
                        iconColor: Color.vitality,
                        value: store.dailyMetrics.steps > 0 ? store.dailyMetrics.steps.formatted() : "—",
                        label: "Steps"
                    )
                    HomeMetricTile(
                        icon: "flame.fill",
                        iconColor: .ember,
                        value: store.dailyMetrics.activeCalories > 0 ? "\(store.dailyMetrics.activeCalories)" : "—",
                        label: "Active Cal"
                    )
                }
                .padding(.horizontal, HomeMetrics.inset)
            }
            .padding(.horizontal, -HomeMetrics.inset)
        }
        .homeEntrance(delay: 0.28)
    }

    private var sleepValue: String {
        let total = store.dailyMetrics.totalSleep
        if total <= 0 {
            if let last = store.sleepData.first {
                return String(format: "%.1fh", last.totalHours)
            }
            return "—"
        }
        let hours = Double(total) / 60.0
        return String(format: "%.1fh", hours)
    }
}

private struct HomeMetricTile: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.16)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(iconColor)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)
        }
        .padding(14)
        .frame(width: 118, alignment: .leading)
        .forgeGlassCard(cornerRadius: HomeMetrics.innerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// ============================================================
// MARK: - Trend (collapsible, real data only)
// ============================================================

private struct HomeTrendSection: View {
    @EnvironmentObject var store: AppStore
    @Binding var isExpanded: Bool
    /// Drives the chart grow-from-zero only; the card enters via `.homeEntrance`.
    @State private var chartGrown = false

    /// Real-ish series from sleep scores when available; otherwise empty.
    private var trendData: [(day: String, score: Int)] {
        _ = Calendar.current
        let f = DateFormatter()
        f.dateFormat = "EEE"
        let sleeps = store.sleepData.prefix(7)
        guard sleeps.count >= 3 else { return [] }

        return sleeps.reversed().enumerated().map { _, sleep in
            let label: String = {
                if let date = ISO8601DateFormatter().date(from: sleep.date)
                    ?? DateFormatter.cachedYMD.date(from: sleep.date) {
                    return f.string(from: date)
                }
                return f.string(from: Date())
            }()
            // Map sleep score into readiness-like 0–100 band
            let score = min(100, max(30, sleep.score))
            return (label, score)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                FDS.haptic(.light)
                withAnimation(FDS.Spring.standard) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("7-DAY SIGNAL")
                        .forgeSectionLabel()
                    Spacer()
                    if trendData.isEmpty {
                        Text("Not enough data")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textMuted)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.ember)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(trendData.isEmpty)

            if isExpanded, !trendData.isEmpty {
                Chart {
                    ForEach(Array(trendData.enumerated()), id: \.offset) { i, point in
                        AreaMark(
                            x: .value("Day", point.day),
                            y: .value("Score", chartGrown ? point.score : 0)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [readinessColor(point.score).opacity(0.28), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Day", point.day),
                            y: .value("Score", chartGrown ? point.score : 0)
                        )
                        .foregroundStyle(readinessColor(point.score))
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Day", point.day),
                            y: .value("Score", chartGrown ? point.score : 0)
                        )
                        .foregroundStyle(readinessColor(point.score))
                        .symbolSize(i == trendData.count - 1 ? 56 : 28)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(Color.textMuted)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 88)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard()
        .onAppear {
            guard !chartGrown else { return }
            withAnimation(FDS.Spring.hero.delay(0.45)) { chartGrown = true }
        }
        .homeEntrance(delay: 0.35)
    }
}

private extension DateFormatter {
    static let cachedYMD: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// ============================================================
// MARK: - Breakdown + insight rows (kept)
// ============================================================

struct BreakdownCardView: View {
    let label: String
    let value: Int
    let inverted: Bool
    let index: Int
    @State private var appeared = false

    private var display: Int { inverted ? 100 - value : value }
    private var dot: Color { readinessColor(display) }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                Text("\(display)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            Spacer()
        }
        .padding(12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .fill(Color.surfaceElevated.opacity(0.9))
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(Color.borderHairline, lineWidth: 1)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.05 * Double(index))) { appeared = true }
        }
    }
}

struct ReadinessInsightRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.system(size: 15)).foregroundColor(color)
            }
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
        }
        .padding(.vertical, 4)
    }
}

// ============================================================
// MARK: - Readiness Ring
// ============================================================

struct ReadinessRingView: View {
    let score: Int
    let size: CGFloat
    let strokeWidth: CGFloat
    var showLabel: Bool = true

    @State private var progress: CGFloat = 0
    @State private var glowPulse = false
    @State private var outerPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { readinessColor(score) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size, height: size)

            if !reduceMotion {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: strokeWidth + 14, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 18)
                    .scaleEffect(outerPulse ? 1.02 : 0.99)
            }

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: strokeWidth + 6, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .blur(radius: 8)
                .opacity(glowPulse ? 0.55 : 0.85)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.6), color, color.opacity(0.85)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.5), radius: 14)

            if progress > 0.02 {
                Circle()
                    .fill(color)
                    .frame(width: strokeWidth * 0.85, height: strokeWidth * 0.85)
                    .shadow(color: color, radius: 6)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(-90 + Double(progress) * 360))
            }

            if showLabel {
                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: size * 0.24, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.textPrimary, color], startPoint: .top, endPoint: .bottom)
                        )
                        .contentTransition(.numericText())
                    Text(readinessLabel(score).uppercased())
                        .font(.system(size: size * 0.07, weight: .black))
                        .foregroundColor(color)
                        .tracking(1.6)
                    Text("Readiness")
                        .font(.system(size: size * 0.055, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            let anim = reduceMotion
                ? Animation.easeOut(duration: 0.2)
                : Animation.spring(response: 1.5, dampingFraction: 0.7).delay(0.35)
            withAnimation(anim) { progress = CGFloat(score) / 100 }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) { glowPulse = true }
                withAnimation(.easeInOut(duration: 3.1).repeatForever(autoreverses: true)) { outerPulse = true }
            }
        }
        .onChange(of: score) { _, new in
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) {
                progress = CGFloat(new) / 100
            }
        }
    }
}

// ============================================================
// MARK: - Streak calendar
// ============================================================

struct StreakCalendarSection: View {
    @EnvironmentObject var store: AppStore
    /// Drives only the per-cell stagger; the card's own entrance is handled by
    /// `.homeEntrance`, so the two no longer share a flag.
    @State private var cellsAppeared = false

    private var weekDays: [(label: String, hasWorkout: Bool, isToday: Bool)] {
        let cal = Calendar.current
        let today = Date()
        return (0..<7).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let f = DateFormatter()
            f.dateFormat = "EEE"
            let label = f.string(from: date)
            let isToday = offset == 0
            let hasWorkout = store.workoutHistory.contains { history in
                if let historyDate = ISO8601DateFormatter().date(from: history.date) {
                    return cal.isDate(historyDate, inSameDayAs: date)
                }
                if let historyDate = DateFormatter.cachedYMD.date(from: history.date) {
                    return cal.isDate(historyDate, inSameDayAs: date)
                }
                return false
            }
            return (label, hasWorkout, isToday)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.ember)
                    Text("\(store.currentStreak)-DAY STREAK")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.ember)
                        .tracking(2)
                }
                Spacer()
                Text("This week")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMuted)
            }

            HStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { i, day in
                    VStack(spacing: 8) {
                        Text(day.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(day.isToday ? .ember : .textMuted)
                        ZStack {
                            Circle()
                                .fill(day.hasWorkout ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                                .frame(width: 34, height: 34)
                            if day.hasWorkout {
                                Circle().stroke(Color.ember.opacity(0.4), lineWidth: 1).frame(width: 34, height: 34)
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.ember)
                            } else if day.isToday {
                                Circle().stroke(Color.ember.opacity(0.6), lineWidth: 1.5).frame(width: 34, height: 34)
                                Circle().fill(Color.ember).frame(width: 6, height: 6)
                            } else {
                                Circle().fill(Color.white.opacity(0.08)).frame(width: 8, height: 8)
                            }
                        }
                        .scaleEffect(cellsAppeared ? 1 : 0.7)
                        .opacity(cellsAppeared ? 1 : 0)
                        .animation(FDS.Spring.hero.delay(0.08 + Double(i) * 0.05), value: cellsAppeared)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: .ember)
        // Card fade and per-cell stagger used to run off the same `appeared`
        // flag, so the 0.08–0.38 cell cascade raced the card's own 0.32 fade.
        // The card now enters via the shared modifier and `cellsAppeared` drives
        // only the cells, so the two are independent by construction.
        .onAppear {
            guard !cellsAppeared else { return }
            cellsAppeared = true
        }
        .homeEntrance(delay: 0.32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.currentStreak) day streak this week")
    }
}

// ============================================================
// MARK: - Celebration
// ============================================================

struct CelebrationOverlay: View {
    let key: Int
    let onDismiss: () -> Void
    @State private var particles: [ConfettiParticle] = []
    @State private var bannerScale: CGFloat = 0.6
    @State private var revealed = false

    private struct ConfettiParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var color: Color
        var rotation: Double
        var size: CGFloat
    }

    var body: some View {
        ZStack {
            Color.black.opacity(revealed ? 0.35 : 0).ignoresSafeArea()
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    for p in particles {
                        var tctx = ctx
                        tctx.opacity = 0.9
                        tctx.translateBy(x: p.x, y: p.y + CGFloat((t * 40).truncatingRemainder(dividingBy: Double(size.height))))
                        tctx.rotate(by: .degrees(p.rotation + t * 40))
                        tctx.fill(
                            Path(CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size * 0.6)),
                            with: .color(p.color)
                        )
                    }
                }
            }

            VStack(spacing: 10) {
                Text("Peak readiness")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.white)
                Text("You're in the window. Use it well.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .scaleEffect(bannerScale)
            .padding(28)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous))
        }
        .onAppear {
            let colors: [Color] = [.ember, Color.vitality, .steel, Color.warning]
            let w = UIScreen.main.bounds.width
            particles = (0..<40).map { _ in
                ConfettiParticle(
                    x: .random(in: 0...w),
                    y: .random(in: -40...120),
                    color: colors.randomElement()!,
                    rotation: .random(in: 0...360),
                    size: .random(in: 6...12)
                )
            }
            withAnimation(FDS.Spring.hero) {
                revealed = true
                bannerScale = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) { onDismiss() }
        }
        .id(key)
    }
}

// ============================================================
// MARK: - Voice orb
// ============================================================

struct VoiceQuickLaunchOrb: View {
    @EnvironmentObject var store: AppStore
    @State private var pulse = false
    @State private var outerPulse = false
    @State private var pressed = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            FDS.haptic(.heavy)
            store.openChat(with: "Voice check-in — what should I do next?", voice: true)
        } label: {
            ZStack {
                if !reduceMotion {
                    Circle()
                        .fill(Color.ember.opacity(0.15))
                        .frame(width: 80, height: 80)
                        .scaleEffect(outerPulse ? 1.35 : 1.0)
                        .opacity(outerPulse ? 0 : 0.8)
                    Circle()
                        .fill(Color.ember.opacity(0.25))
                        .frame(width: 62, height: 62)
                        .blur(radius: 12)
                        .scaleEffect(pulse ? 1.1 : 0.95)
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.ember, Color.emberDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: Color.ember.opacity(0.55), radius: 16, y: 8)

                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            .scaleEffect(pressed ? 0.92 : (appeared ? 1.0 : 0.6))
            .opacity(appeared ? 1 : 0)
            .animation(FDS.Spring.snap, value: pressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Talk to ARIA")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .onAppear {
            withAnimation(FDS.Spring.floaty.delay(0.7)) { appeared = true }
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { outerPulse = true }
            withAnimation(.easeInOut(duration: FDS.Duration.breathe).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// ============================================================
// MARK: - Helpers
// ============================================================

private func readinessColor(_ score: Int) -> Color {
    switch score {
    case 85...: return Color.vitality
    case 70..<85: return Color.ember
    case 50..<70: return Color.steel
    default: return Color.alert
    }
}

private func readinessLabel(_ score: Int) -> String {
    switch score {
    case 85...: return "Peak"
    case 70..<85: return "Good"
    case 50..<70: return "Fair"
    default: return "Low"
    }
}

@MainActor
private func homeStatusLine(store: AppStore) -> String {
    let score = store.readiness.overall
    switch score {
    case 85...: return "Primed to perform"
    case 70..<85: return "Recovered enough to train"
    case 55..<70: return "Train smart, not maximal"
    default: return "Protect recovery today"
    }
}
