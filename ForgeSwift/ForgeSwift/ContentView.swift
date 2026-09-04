import SwiftUI

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSplash = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                if !store.isAuthenticated {
                    AuthWelcomeView()
                } else if !store.isOnboarded {
                    OnboardingView()
                } else {
                    MainTabView()
                }
            }
            .animation(.easeInOut(duration: 0.35), value: store.isAuthenticated)
            .animation(.easeInOut(duration: 0.35), value: store.isOnboarded)

            // Epic splash screen
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
    @State private var logoScale: CGFloat = 0.4
    @State private var logoOpacity: Double = 0
    @State private var glowIntensity: Double = 0
    @State private var textOffset: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.ember.opacity(0.10 * glowIntensity),
                    Color(hex: "7B61FF").opacity(0.06 * glowIntensity),
                    Color.aurora.opacity(0.03 * glowIntensity),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                AuroraOrbView(state: .idle, amplitude: 0.34, mood: .energized, size: 132)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .shadow(color: Color.ember.opacity(0.35 * glowIntensity), radius: 48, y: 8)

                VStack(spacing: 10) {
                    Text("FORGE")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .tracking(8)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color.white.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text("ARIA · already listening")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(2.2)
                        .foregroundColor(.textTertiary)
                }
                .opacity(logoOpacity)
                .offset(y: textOffset)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Forge. Your body. Your coach.")
        .onAppear {
            let base: Animation = reduceMotion
                ? .easeOut(duration: 0.3)
                : .spring(response: 1.15, dampingFraction: 0.72)
            withAnimation(base) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation((reduceMotion ? .easeOut(duration: 0.3) : FDS.Spring.fluid).delay(0.18)) {
                textOffset = 0
            }
            withAnimation(.easeInOut(duration: 2.2).delay(0.25)) {
                glowIntensity = 1.0
            }
        }
    }
}

// MARK: - Main Tab Container

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var weeklyReview = WeeklyAriaReviewStore.shared
    @Namespace private var namespace
    /// Sole Cycle Health host. Home used to present a second cover on the same
    /// `pendingCycleHealthOpen` flag, which blanked or stuck the page.
    @State private var showCycleHealth = false
    @State private var showHydration = false
    @State private var cycleInitialPane: MenstrualHealthView.Pane = .me

    var body: some View {
        ZStack(alignment: .bottom) {
            // Premium ambient canvas
            ZStack {
                Color.background
                RadialGradient(
                    colors: [Color.ember.opacity(0.07), .clear],
                    center: UnitPoint(x: 0.2, y: 0.0),
                    startRadius: 10,
                    endRadius: 380
                )
                RadialGradient(
                    colors: [Color.steel.opacity(0.05), .clear],
                    center: UnitPoint(x: 0.95, y: 0.85),
                    startRadius: 8,
                    endRadius: 320
                )
            }
            .ignoresSafeArea()
            
            Group {
                switch store.activeTab {
                case .home:      HomeView()
                case .workout:   WorkoutView()
                case .chat:      ChatView()
                case .lifestyle: LifestyleView()
                case .sleep:     SleepView()
                case .progress:  ProgressPageView()
                case .profile:   ProfileTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.12), value: store.activeTab)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ForgeBottomNav(namespace: namespace)
            }
        }
        .onChange(of: store.pendingCycleHealthOpen) { _, open in
            guard open else { return }
            presentCycleHealth()
        }
        .onChange(of: store.pendingHydrationOpen) { _, open in
            guard open else { return }
            presentHydration()
        }
        .onAppear {
            if store.pendingCycleHealthOpen {
                presentCycleHealth()
            }
            if store.pendingHydrationOpen {
                presentHydration()
            }
        }
        .fullScreenCover(isPresented: $showCycleHealth) {
            NavigationStack {
                MenstrualHealthView(initialPane: cycleInitialPane)
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showCycleHealth = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .accessibilityLabel("Close Cycle Health")
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showHydration) {
            NavigationStack {
                HydrationView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showHydration = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .accessibilityLabel("Close Hydration")
                        }
                    }
            }
        }
        .sheet(isPresented: $weeklyReview.showSheet) {
            WeeklyAriaReviewSheet()
                .environmentObject(store)
        }
    }

    private func presentHydration() {
        showHydration = true
        store.pendingHydrationOpen = false
    }

    private func presentCycleHealth() {
        if store.pendingCyclePane == "partner" {
            cycleInitialPane = .partner
        } else {
            cycleInitialPane = .me
        }
        showCycleHealth = true
        store.pendingCycleHealthOpen = false
        store.pendingCyclePane = nil
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

    /// Home · Train · Life · ARIA (center) · Sleep · Stats · You
    private let tabs: [TabItem] = [.home, .workout, .lifestyle, .chat, .sleep, .progress, .profile]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                if tab == .chat {
                    ARIATabButton(namespace: namespace)
                        .frame(maxWidth: .infinity)
                } else {
                    RegularForgeTab(tab: tab, namespace: namespace)
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
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .padding(.horizontal, 4)
        .background {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 22,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 22,
                    style: .continuous
                )
                .fill(.ultraThinMaterial)
                UnevenRoundedRectangle(
                    topLeadingRadius: 22,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 22,
                    style: .continuous
                )
                .fill(Color.background.opacity(0.52))
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 0.5)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea(edges: .bottom)
        }
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
            FDS.selectionHaptic()
            withAnimation(FDS.Spring.snap) {
                store.activeTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .bottom) {
                    Image(systemName: isActive ? tab.systemImageFilled : tab.systemImage)
                        .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Color.ember : Color.white.opacity(0.38))
                        .shadow(color: isActive ? Color.ember.opacity(0.45) : .clear, radius: 6, y: 0)
                        .frame(height: 22)
                        .symbolRenderingMode(.hierarchical)
                    if isActive {
                        Capsule()
                            .fill(FDS.Gradient.ember)
                            .frame(width: 14, height: 2.5)
                            .offset(y: 4)
                            .matchedGeometryEffect(id: "tab-dot", in: namespace)
                    }
                }

                Text(tab.shortLabel)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium, design: .rounded))
                    .tracking(0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isActive ? Color.ember : Color.white.opacity(0.38))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
            .accessibilityLabel(tab.label)
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ARIA Center Tab

struct ARIATabButton: View {
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore

    private var isActive: Bool { store.activeTab == .chat }
    private var isVoiceMode: Bool { store.ariaVoiceMode }

    var body: some View {
        Button {
            FDS.haptic(.medium)
            withAnimation(FDS.Spring.snap) {
                store.activeTab = .chat
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    (isVoiceMode ? Color.steel : Color.ember).opacity(isActive ? 0.3 : 0.14),
                                    (isVoiceMode ? Color(hex: "00D2FF") : Color.ember).opacity(0.04),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 32
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: (isVoiceMode ? Color.steel : Color.ember).opacity(isActive ? 0.55 : 0.22), radius: 14, y: 4)
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    (isVoiceMode ? Color.steelLight : Color.emberLight).opacity(0.6),
                                    (isVoiceMode ? Color(hex: "00D2FF") : Color(hex: "FF2D55")).opacity(0.2),
                                    (isVoiceMode ? Color.steel : Color.ember).opacity(0.4),
                                    .clear
                                ],
                                center: .center
                            ),
                            lineWidth: 1.2
                        )
                        .frame(width: 56, height: 56)
                    ARIAIdentityMark(
                        state: isVoiceMode ? .listening : .idle,
                        mood: isVoiceMode ? .focused : .energized,
                        size: 44,
                        amplitude: isVoiceMode ? 0.4 : 0.2
                    )
                }

                Text(isVoiceMode ? "Voice" : "ARIA")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(0.3)
                    .foregroundStyle(isActive ? Color.ember : Color.white.opacity(0.5))
            }
            .frame(height: 48)
            .contentShape(Rectangle())
            .accessibilityLabel(isVoiceMode ? "ARIA Voice" : "ARIA")
            .accessibilityHint("Long-press to switch voice mode")
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.55) {
            FDS.haptic(.medium)
            withAnimation(FDS.Spring.snap) {
                store.ariaVoiceMode.toggle()
                store.activeTab = .chat
                store.ariaVoiceLaunch = store.ariaVoiceMode
            }
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
    /// Short labels for the 7-tab bar so nothing clips on small phones.
    var shortLabel: String {
        switch self {
        case .home: return "Home"
        case .workout: return "Train"
        case .chat: return "ARIA"
        case .lifestyle: return "Life"
        case .sleep: return "Sleep"
        case .progress: return "Stats"
        case .profile: return "You"
        }
    }

    var systemImageFilled: String {
        switch self {
        case .home:      return "house.fill"
        case .chat:      return "message.fill"
        case .workout:   return "dumbbell.fill"
        case .lifestyle: return "leaf.fill"
        case .sleep:     return "moon.fill"
        case .progress:  return "chart.line.uptrend.xyaxis"
        case .profile:   return "person.fill"
        }
    }
}
