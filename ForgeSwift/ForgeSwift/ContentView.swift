import SwiftUI

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSplash = true

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.6)) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - Splash Screen

struct ForgeSplashScreen: View {
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var glowIntensity: Double = 0
    @State private var ringPulse = false
    
    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            RadialGradient(
                colors: [Color.ember.opacity(0.16 * glowIntensity), Color.aurora.opacity(0.06 * glowIntensity), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 320
            )
            .ignoresSafeArea()
            
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.ember.opacity(0.2), lineWidth: 1)
                        .frame(width: ringPulse ? 168 : 140, height: ringPulse ? 168 : 140)
                        .opacity(ringPulse ? 0 : 0.8)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.ember.opacity(glowIntensity * 0.45),
                                    Color.ember.opacity(glowIntensity * 0.12),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 24,
                                endRadius: 130
                            )
                        )
                        .frame(width: 240, height: 240)
                        .blur(radius: 28)
                    
                    Image(systemName: "flame.fill")
                        .font(.system(size: 68, weight: .bold))
                        .foregroundStyle(FDS.Gradient.ember)
                        .shadow(color: Color.ember.opacity(0.75), radius: 22, y: 8)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                
                Text("FORGE")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color.white.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(logoOpacity)
                
                Text("ARIA · Intelligence Layer")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundColor(.textTertiary)
                    .opacity(logoOpacity * 0.9)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.62)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 1.4).delay(0.15)) {
                glowIntensity = 1.0
            }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                ringPulse = true
            }
        }
    }
}

// MARK: - Main Tab Container

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var weeklyReview = WeeklyAriaReviewStore.shared
    @Namespace private var namespace
    /// Cycle Health is hosted on the shell so Profile/Settings deep links always work
    /// even when Home is not the active tab content.
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

// MARK: - Bottom Navigation

struct ForgeBottomNav: View {
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

// MARK: - Regular Tab Button

struct RegularForgeTab: View {
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

// MARK: - ARIA Center Button (Chat + Voice toggle)

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
                        .fill((isVoiceMode ? Color.steel : Color.ember).opacity(0.18))
                        .frame(width: 52, height: 52)
                        .shadow(color: (isVoiceMode ? Color.steel : Color.ember).opacity(isActive ? 0.5 : 0.28), radius: 12, y: 4)
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    (isVoiceMode ? Color.steelLight : Color.emberLight).opacity(0.7),
                                    (isVoiceMode ? Color.steel : Color.ember).opacity(0.2)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.4
                        )
                        .frame(width: 52, height: 52)
                    ARIAIdentityMark(
                        state: isVoiceMode ? .listening : (isActive ? .idle : .idle),
                        mood: isVoiceMode ? .focused : .energized,
                        size: 42,
                        amplitude: isVoiceMode ? 0.4 : 0.18
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
}

// MARK: - TabItem extensions
// Requires TabItem enum to have cases: .home, .chat, .workout, .lifestyle, .sleep, .profile
// Each needs: label: String, systemImage: String, systemImageFilled: String

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
