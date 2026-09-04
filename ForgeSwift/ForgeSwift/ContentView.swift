import SwiftUI

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSplash = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                if store.isOnboarded {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .animation(FDS.adaptiveAnimation(FDS.Spring.standard), value: store.isOnboarded)

            if showSplash {
                ForgeSplashScreen()
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .onAppear {
            let delay: TimeInterval = reduceMotion ? 0.6 : 1.4
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(FDS.adaptiveAnimation(.easeOut(duration: 0.5))) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - Splash Screen

struct ForgeSplashScreen: View {
    @State private var logoScale: CGFloat = 0.88
    @State private var logoOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SplashMeshBackground()
                .ignoresSafeArea()

            VStack(spacing: FDS.Spacing.xl) {
                ForgeMark(size: 72, glow: !reduceMotion)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                VStack(spacing: FDS.Spacing.sm) {
                    Text("FORGE")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(Color.textPrimary)

                    Text("Your body. Your coach.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.textSecondary)
                }
                .opacity(taglineOpacity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Forge. Your body. Your coach.")
        .onAppear {
            let spring = FDS.adaptiveAnimation(FDS.Spring.hero)
            withAnimation(spring) {
                logoScale = 1
                logoOpacity = 1
            }
            withAnimation(spring.delay(reduceMotion ? 0 : 0.35)) {
                taglineOpacity = 1
            }
        }
    }
}

private struct SplashMeshBackground: View {
    var body: some View {
        ZStack {
            Color.background

            RadialGradient(
                colors: [
                    Color.ember.opacity(0.22),
                    Color.ember.opacity(0.06),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 320
            )

            LinearGradient(
                colors: [
                    Color(hex: "0D0D0D").opacity(0),
                    Color.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct ForgeMark: View {
    var size: CGFloat = 48
    var glow: Bool = true

    var body: some View {
        ZStack {
            if glow {
                Circle()
                    .fill(Color.ember.opacity(0.25))
                    .frame(width: size * 2.2, height: size * 2.2)
                    .blur(radius: size * 0.35)
            }

            Image(systemName: "flame.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(FDS.Gradient.emberDeep)
                .shadow(color: Color.ember.opacity(0.45), radius: size * 0.18, y: size * 0.08)
        }
    }
}

// MARK: - Main Tab Container

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @Namespace private var tabNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var swipeOffset: CGFloat = 0
    @State private var swipeDirection: Edge = .trailing

    private let navTabs: [TabItem] = [.home, .workout, .chat, .sleep, .profile]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.background.ignoresSafeArea()

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: swipeOffset)
                .padding(.bottom, store.isWorkoutActive ? 0 : ForgeTabBarMetrics.contentInset)
                .simultaneousGesture(tabSwipeGesture)

            if !store.isWorkoutActive {
                ForgeTabBar(
                    namespace: tabNamespace,
                    tabs: navTabs,
                    readinessScore: store.readiness.overall
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(FDS.adaptiveAnimation(FDS.Spring.page), value: store.isWorkoutActive)
        .ignoresSafeArea(edges: .bottom)
    }

    private var tabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard !store.isWorkoutActive else { return }
                guard isHorizontalSwipe(value) else { return }

                let resistance: CGFloat = 0.35
                swipeOffset = value.translation.width * resistance
            }
            .onEnded { value in
                guard !store.isWorkoutActive else { return }
                defer {
                    withAnimation(FDS.adaptiveAnimation(FDS.Spring.page)) {
                        swipeOffset = 0
                    }
                }
                guard isHorizontalSwipe(value) else { return }

                let threshold: CGFloat = 72
                if value.translation.width <= -threshold {
                    moveTab(by: 1)
                } else if value.translation.width >= threshold {
                    moveTab(by: -1)
                }
            }
    }

    private func isHorizontalSwipe(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > abs(value.translation.height) * 1.35
    }

    private func moveTab(by offset: Int) {
        guard let currentIndex = navTabs.firstIndex(of: store.activeTab) else { return }
        let nextIndex = currentIndex + offset
        guard navTabs.indices.contains(nextIndex) else { return }

        swipeDirection = offset > 0 ? .trailing : .leading
        FDS.selectionHaptic()
        withAnimation(FDS.adaptiveAnimation(FDS.Spring.page)) {
            store.activeTab = navTabs[nextIndex]
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        let content = Group {
            switch store.activeTab {
            case .home:      HomeView()
            case .chat:      ChatView()
            case .workout:   WorkoutView()
            case .lifestyle: LifestyleView()
            case .sleep:     SleepView()
            case .profile:   ProfileTabView()
            }
        }

        if reduceMotion {
            content
                .id(store.activeTab)
        } else {
            content
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .move(edge: swipeDirection))
                            .combined(with: .scale(scale: 0.985)),
                        removal: .opacity
                            .combined(with: .move(edge: swipeDirection == .trailing ? .leading : .trailing))
                    )
                )
                .animation(FDS.Spring.page, value: store.activeTab)
                .id(store.activeTab)
        }
    }
}

// MARK: - Tab Bar Metrics

private enum ForgeTabBarMetrics {
    static let barHeight: CGFloat = 64
    static let horizontalInset: CGFloat = 20
    static let bottomPadding: CGFloat = 8
    static let contentInset: CGFloat = 96

    static var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0
    }
}

// MARK: - Floating Tab Bar

struct ForgeTabBar: View {
    @EnvironmentObject var store: AppStore
    var namespace: Namespace.ID
    let tabs: [TabItem]
    let readinessScore: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var readinessTint: Color { readinessColor(for: readinessScore) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if !reduceMotion {
                    ReadinessTabBarGlow(tint: readinessTint)
                        .allowsHitTesting(false)
                }

                HStack(spacing: 0) {
                    ForEach(tabs, id: \.self) { tab in
                        if tab == .chat {
                            ARIATabButton(namespace: namespace)
                        } else {
                            ForgeTabItem(tab: tab, namespace: namespace)
                        }
                    }
                }
                .padding(.horizontal, FDS.Spacing.sm)
                .frame(height: ForgeTabBarMetrics.barHeight)
                .background(tabBarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.xl + 4, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    readinessTint.opacity(0.28),
                                    Color.white.opacity(0.08),
                                    readinessTint.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xl + 4, style: .continuous))
                .shadow(color: readinessTint.opacity(0.22), radius: 18, y: 6)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            }
            .padding(.horizontal, ForgeTabBarMetrics.horizontalInset)
            .padding(.bottom, ForgeTabBarMetrics.bottomPadding)
            .animation(FDS.adaptiveAnimation(.easeInOut(duration: 0.8)), value: readinessScore)

            Color.clear
                .frame(height: ForgeTabBarMetrics.safeAreaBottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation. Readiness \(readinessScore), \(readinessLabel(for: readinessScore)).")
    }

    private var tabBarBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: FDS.Radius.xl + 4, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: FDS.Radius.xl + 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            readinessTint.opacity(0.10),
                            Color.white.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

private struct ReadinessTabBarGlow: View {
    let tint: Color

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(0.34),
                            tint.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 140
                    )
                )
                .frame(height: ForgeTabBarMetrics.barHeight + 28)
                .blur(radius: 22)

            Capsule(style: .continuous)
                .fill(tint.opacity(0.08))
                .frame(height: ForgeTabBarMetrics.barHeight + 6)
                .blur(radius: 10)
        }
        .padding(.horizontal, ForgeTabBarMetrics.horizontalInset - 6)
    }
}

// MARK: - Tab Item Button

struct ForgeTabItem: View {
    let tab: TabItem
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore

    private var isActive: Bool { store.activeTab == tab }

    var body: some View {
        Button {
            selectTab()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if isActive {
                        Capsule()
                            .fill(Color.ember.opacity(0.14))
                            .frame(width: 52, height: 30)
                            .overlay(
                                Capsule()
                                    .stroke(Color.ember.opacity(0.22), lineWidth: 0.5)
                            )
                            .matchedGeometryEffect(id: "forgeActiveTab", in: namespace)
                    }

                    Image(systemName: isActive ? tab.systemImageFilled : tab.systemImageOutline)
                        .font(.system(size: 19, weight: isActive ? .semibold : .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isActive ? Color.ember : Color.textTertiary)
                }
                .frame(height: 30)

                Text(tab.navLabel)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isActive ? Color.ember : Color.textMuted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: ForgeTabBarMetrics.barHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ForgeTabButtonStyle())
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    private func selectTab() {
        guard store.activeTab != tab else { return }
        FDS.selectionHaptic()
        withAnimation(FDS.adaptiveAnimation(FDS.Spring.standard)) {
            store.activeTab = tab
        }
    }
}

// MARK: - ARIA Center Tab

struct ARIATabButton: View {
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private var isActive: Bool { store.activeTab == .chat }
    private var isVoiceMode: Bool { store.ariaVoiceMode }

    var body: some View {
        Button {
            openARIA()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if isActive && !reduceMotion {
                        Circle()
                            .stroke(
                                (isVoiceMode ? Color.steel : Color.ember).opacity(0.35),
                                lineWidth: 1.5
                            )
                            .frame(width: 54, height: 54)
                            .scaleEffect(breathe ? 1.12 : 1)
                            .opacity(breathe ? 0 : 0.8)
                            .animation(
                                FDS.adaptiveAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)),
                                value: breathe
                            )
                    }

                    ariaOrb
                        .offset(y: -6)
                }
                .frame(height: 30)

                Text(isVoiceMode ? "Voice" : "ARIA")
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isActive ? (isVoiceMode ? Color.steel : Color.ember) : Color.textMuted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: ForgeTabBarMetrics.barHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ForgeTabButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55)
                .onEnded { _ in toggleVoiceMode() }
        )
        .accessibilityLabel(isVoiceMode ? "ARIA voice mode" : "ARIA coach")
        .accessibilityHint("Double tap to open. Long press to switch between chat and voice.")
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .onAppear {
            if isActive { breathe = true }
        }
        .onChange(of: isActive) { _, active in
            breathe = active && !reduceMotion
        }
    }

    private var ariaOrb: some View {
        ZStack {
            Circle()
                .fill(
                    isVoiceMode
                        ? LinearGradient(colors: [Color.steel, Color.steelDark], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : FDS.Gradient.emberDeep
                )
                .frame(width: 46, height: 46)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(
                    color: (isVoiceMode ? Color.steel : Color.ember).opacity(isActive ? 0.55 : 0.25),
                    radius: isActive ? 14 : 8,
                    y: 4
                )

            Image(systemName: isVoiceMode ? "waveform" : "sparkles")
                .font(.system(size: isVoiceMode ? 17 : 16, weight: .bold))
                .foregroundStyle(Color.white)
                .symbolEffect(.bounce, value: isVoiceMode)
        }
        .scaleEffect(isActive ? 1 : 0.92)
        .animation(FDS.adaptiveAnimation(FDS.Spring.standard), value: isActive)
        .animation(FDS.adaptiveAnimation(FDS.Spring.standard), value: isVoiceMode)
    }

    private func openARIA() {
        FDS.haptic(.medium)
        withAnimation(FDS.adaptiveAnimation(FDS.Spring.standard)) {
            store.activeTab = .chat
        }
    }

    private func toggleVoiceMode() {
        FDS.notificationHaptic(.success)
        withAnimation(FDS.adaptiveAnimation(FDS.Spring.standard)) {
            store.ariaVoiceMode.toggle()
            store.activeTab = .chat
        }
    }
}

// MARK: - Tab Button Style

private struct ForgeTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(FDS.Spring.snap, value: configuration.isPressed)
    }
}

// MARK: - TabItem Presentation

extension TabItem {
    var navLabel: String {
        switch self {
        case .home:      return "Today"
        case .workout:   return "Train"
        case .chat:      return "ARIA"
        case .sleep:     return "Rest"
        case .profile:   return "You"
        case .lifestyle: return "Life"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .home:      return "Today, home dashboard"
        case .workout:   return "Train, workouts"
        case .chat:      return "ARIA coach"
        case .sleep:     return "Rest, sleep tracking"
        case .profile:   return "You, profile and settings"
        case .lifestyle: return "Life, lifestyle"
        }
    }

    var systemImageOutline: String {
        switch self {
        case .home:      return "house"
        case .chat:      return "message"
        case .workout:   return "dumbbell"
        case .lifestyle: return "leaf"
        case .sleep:     return "moon"
        case .profile:   return "person"
        }
    }

    var systemImageFilled: String {
        switch self {
        case .home:      return "house.fill"
        case .chat:      return "message.fill"
        case .workout:   return "dumbbell.fill"
        case .lifestyle: return "leaf.fill"
        case .sleep:     return "moon.fill"
        case .profile:   return "person.fill"
        }
    }
}
