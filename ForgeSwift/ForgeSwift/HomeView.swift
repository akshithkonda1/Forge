import SwiftUI
import Charts

// ╔════════════════════════════════════════════════════════════════════╗
// ║  FORGE HOME — Control Center + Day Preview                         ║
// ║  Status · Next action · ARIA briefing · Telemetry · Week rhythm  ║
// ╚════════════════════════════════════════════════════════════════════╝

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var primaryAction: HomePrimaryAction {
        HomePrimaryAction.resolve(store: store)
    }

    var body: some View {
        ZStack(alignment: .top) {
            CinematicHomeBackground(readinessScore: store.readiness.overall)
                .ignoresSafeArea()

            if !reduceMotion {
                ReadinessParticleOverlay(readinessScore: store.readiness.overall)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            ScrollView(showsIndicators: false) {
                ZStack(alignment: .top) {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .global).minY)
                    }
                    .frame(height: 0)

                    VStack(spacing: 0) {
                        // 1. Header
                        HomeHeaderView()
                            .padding(.top, 64)
                            .padding(.horizontal, FDS.Spacing.lg)
                            .padding(.bottom, 20)

                        // 2. Hero readiness control
                        HomeHeroReadinessCard(onCelebrate: triggerCelebration)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)

                        // 3. Primary control
                        HomePrimaryCTA(action: primaryAction)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)

                        // 4. ARIA briefing
                        if let insight = proactiveInsight,
                           AriaContextStore.shared.shouldBeProactive() {
                            ProactiveCardView(
                                insight: insight,
                                relationshipLevel: AriaContextStore.shared.context.relationshipLevel,
                                onTap: {
                                    store.openChat(with: "Tell me more about: \(insight)", voice: false)
                                }
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }

                        HomeARIABriefingCard()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)

                        // 5. Day preview telemetry
                        HomeDayPreviewStrip()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)

                        // 6. Week rhythm
                        StreakCalendarSection()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)

                        // 7. Optional trend
                        HomeTrendSection(isExpanded: $showTrend)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 140)
                    }
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
        }
    }

    private func triggerCelebration() {
        celebrationKey += 1
        withAnimation(FDS.Spring.hero) { showCelebration = true }
        FDS.notificationHaptic(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(FDS.Spring.standard) { showCelebration = false }
        }
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
    @State private var appeared = false

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
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -12)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true }
        }
    }
}

private struct HomeDataStatusPill: View {
    let isLive: Bool
    let updatedAt: Date?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isLive ? Color(hex: "22C55E") : Color.textMuted)
                .frame(width: 5, height: 5)
                .shadow(color: isLive ? Color(hex: "22C55E").opacity(0.8) : .clear, radius: 3)
            Text(statusText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isLive ? Color(hex: "22C55E") : .textMuted)
        }
        .accessibilityLabel(statusText)
    }

    private var statusText: String {
        if isLive {
            if let updatedAt {
                let mins = max(0, Int(Date().timeIntervalSince(updatedAt) / 60))
                if mins < 1 { return "HealthKit live · just now" }
                if mins < 60 { return "HealthKit live · \(mins)m ago" }
            }
            return "HealthKit live"
        }
        return "HealthKit offline"
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
        .padding(.horizontal, 16)
        .padding(.top, 54)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.borderColor.opacity(0.5)).frame(height: 0.5)
        }
    }
}

// ============================================================
// MARK: - Hero readiness
// ============================================================

private struct HomeHeroReadinessCard: View {
    @EnvironmentObject var store: AppStore
    var onCelebrate: () -> Void = {}
    @State private var appeared = false
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("READINESS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(2)
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

                VStack(spacing: 8) {
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
                }
                .padding(.top, 12)
            }
        }
        .padding(22)
        .background(
            ZStack {
                Color.surface
                RadialGradient(
                    colors: [readinessColor(store.readiness.overall).opacity(0.1), .clear],
                    center: .center,
                    startRadius: 40,
                    endRadius: 220
                )
            }
        )
        .cornerRadius(FDS.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.xl)
                .stroke(readinessColor(store.readiness.overall).opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.12)) { appeared = true } }
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
                .background(
                    action.isRecovery
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color.steel, Color.steel.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(FDS.Gradient.ember)
                )
                .cornerRadius(FDS.Radius.lg)
                .shadow(
                    color: (action.isRecovery ? Color.steel : Color.ember).opacity(pressed ? 0.2 : 0.45),
                    radius: pressed ? 6 : 18,
                    y: pressed ? 2 : 8
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

            // Secondary control
            Button {
                FDS.haptic(.light)
                store.openChat(with: "What should I focus on today?", voice: false)
            } label: {
                Text("Ask ARIA instead")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
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
    @State private var appeared = false
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
                    .cornerRadius(FDS.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: FDS.Radius.md)
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
                briefingChip(icon: "sparkles", label: "Ask anything") {
                    store.openChat(with: "What should I know right now?", voice: false)
                }
                Spacer()
                briefingChip(icon: "calendar", label: "Plan week") {
                    store.openChat(with: "Help me plan this week around recovery and training.", voice: false)
                }
            }
        }
        .padding(18)
        .background(
            ZStack {
                Color.surface
                LinearGradient(
                    colors: [Color.ember.opacity(0.06), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .cornerRadius(FDS.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.xl)
                .stroke(
                    LinearGradient(
                        colors: [Color.ember.opacity(0.35), Color.ember.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.ember.opacity(0.1), radius: 20, y: 8)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.18)) { appeared = true }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                pulseRing = true
            }
            startTypewriterIfNeeded()
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
        let name = store.userProfile.name.components(separatedBy: " ").first ?? ""
        let h = Calendar.current.component(.hour, from: Date())
        let time = h < 12 ? "Morning" : h < 17 ? "Afternoon" : "Evening"
        let score = store.readiness.overall
        let hrv = store.dailyMetrics.hrv
        let deep = store.dailyMetrics.deepSleep
        let deepStr = deep >= 60 ? "\(deep / 60)h \(deep % 60)m" : "\(deep)m"
        let ctx = AriaContextStore.shared.context
        let guidanceOnly = ctx.constraints.contains { $0.contains("guidance_only") }

        var parts: [String] = []
        parts.append(name.isEmpty ? "\(time)." : "\(time), \(name).")

        if score >= 85 {
            parts.append("You're in a high-readiness window at \(score).")
        } else if score >= 70 {
            parts.append("Readiness is solid at \(score) — good day to train with intent.")
        } else if score >= 55 {
            parts.append("Readiness sits at \(score). Keep quality high and volume honest.")
        } else {
            parts.append("Readiness is \(score). Today is for protection, not punishment.")
        }

        if store.readiness.sleepQuality >= 80 {
            parts.append("Deep sleep looked solid (\(deepStr)).")
        } else if store.readiness.sleepQuality < 60 {
            parts.append("Deep sleep was only \(deepStr) — recovery may lag.")
        }

        if hrv > 0 {
            if hrv >= 50 {
                parts.append("HRV holding strong at \(hrv)ms.")
            } else if hrv < 40 {
                parts.append("HRV is low at \(hrv)ms — nervous system wants ease.")
            }
        }

        if let workout = store.todayWorkout {
            if score >= 70 {
                parts.append("Primary control: \(workout.name).")
            } else {
                parts.append("If you move, bias light around \(workout.name) — or swap for recovery.")
            }
        } else {
            parts.append("No plan locked yet — I can build one from your signals.")
        }

        if guidanceOnly {
            parts.append("Reminder: guidance and structure only — I'm your lifestyle coach, not a clinician.")
        }

        if let goal = store.userProfile.fitnessGoals.first {
            parts.append("Still aligned to \(goal.label.lowercased()).")
        }

        return parts.joined(separator: " ")
    }
}

// ============================================================
// MARK: - Day preview strip (truthful telemetry)
// ============================================================

private struct HomeDayPreviewStrip: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("DAY PREVIEW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .tracking(2)
                Spacer()
                Button("Sleep") { store.activeTab = .sleep }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ember)
            }

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
                        iconColor: Color(hex: "22C55E"),
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
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.28)) { appeared = true } }
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
        .background(Color.surface)
        .cornerRadius(FDS.Radius.lg)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
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
    @State private var appeared = false

    /// Real-ish series from sleep scores when available; otherwise empty.
    private var trendData: [(day: String, score: Int)] {
        let cal = Calendar.current
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
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(2)
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
                            y: .value("Score", appeared ? point.score : 0)
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
                            y: .value("Score", appeared ? point.score : 0)
                        )
                        .foregroundStyle(readinessColor(point.score))
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Day", point.day),
                            y: .value("Score", appeared ? point.score : 0)
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
        .padding(18)
        .background(Color.surface)
        .cornerRadius(FDS.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.xl)
                .stroke(Color.borderColor, lineWidth: 0.5)
        )
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.35)) { appeared = true }
        }
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
        .background(Color.surfaceElevated)
        .cornerRadius(12)
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
    @State private var appeared = false

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
                        .scaleEffect(appeared ? 1 : 0.7)
                        .opacity(appeared ? 1 : 0)
                        .animation(FDS.Spring.hero.delay(0.08 + Double(i) * 0.05), value: appeared)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .background(Color.surface)
        .cornerRadius(FDS.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.xl)
                .stroke(Color.ember.opacity(0.12), lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.32)) { appeared = true } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.currentStreak) day streak this week")
    }
}

// ============================================================
// MARK: - Cinematic background + particles + celebration
// ============================================================

struct CinematicHomeBackground: View {
    let readinessScore: Int
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var primaryColor: Color { readinessColor(readinessScore) }

    var body: some View {
        ZStack {
            Color(hex: "080808")
            if reduceMotion {
                primaryColor.opacity(0.06)
            } else {
                LinearGradient(
                    colors: [
                        Color(hex: "080808"),
                        primaryColor.opacity(phase ? 0.09 : 0.04),
                        Color(hex: "080808"),
                        Color.ember.opacity(phase ? 0.03 : 0.01)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [primaryColor.opacity(0.12), .clear],
                    center: UnitPoint(x: 0.3, y: 0.2),
                    startRadius: 20,
                    endRadius: 420
                )
                .blur(radius: 40)
            }
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.35)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
        .animation(.easeInOut(duration: 1.6), value: readinessScore)
    }
}

private struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var speed: Double
    var opacity: Double
}

struct ReadinessParticleOverlay: View {
    let readinessScore: Int
    @State private var particles: [Particle] = []
    @State private var globalT: Double = 0

    /// Fewer particles when readiness is mid/low — motion serves state.
    private var particleCount: Int {
        switch readinessScore {
        case 85...: return 28
        case 70..<85: return 18
        case 55..<70: return 10
        default: return 6
        }
    }

    private var accentColor: Color { readinessColor(readinessScore) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for p in particles {
                    let y = (p.y + CGFloat(t * p.speed).truncatingRemainder(dividingBy: size.height + 40))
                        .truncatingRemainder(dividingBy: size.height + 40) - 20
                    let rect = CGRect(x: p.x, y: y, width: p.size, height: p.size)
                    ctx.opacity = p.opacity
                    ctx.fill(Path(ellipseIn: rect), with: .color(accentColor))
                }
            }
        }
        .onAppear { rebuildParticles() }
        .onChange(of: readinessScore) { _, _ in rebuildParticles() }
    }

    private func rebuildParticles() {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        particles = (0..<particleCount).map { _ in
            Particle(
                x: .random(in: 0...w),
                y: .random(in: 0...h),
                size: .random(in: 1.2...2.8),
                speed: .random(in: 6...16),
                opacity: .random(in: 0.08...0.28)
            )
        }
    }
}

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
            .cornerRadius(24)
        }
        .onAppear {
            let colors: [Color] = [.ember, Color(hex: "22C55E"), .steel, Color(hex: "F59E0B")]
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
                            colors: [Color(hex: "FF4C00"), Color(hex: "FF2200")],
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
    case 85...: return Color(hex: "22C55E")
    case 70..<85: return Color.ember
    case 50..<70: return Color.steel
    default: return Color(hex: "EF4444")
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
