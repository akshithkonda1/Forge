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
    @State private var previousTab: TabItem = .home
    @State private var dragOffset: CGFloat = 0
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
            .padding(.bottom, 88)
            .offset(y: dragOffset * 0.08)
            .transition(.asymmetric(
                insertion: .move(edge: tabTransitionEdge(from: previousTab, to: store.activeTab))
                    .combined(with: .opacity),
                removal: .move(edge: tabTransitionEdge(from: store.activeTab, to: previousTab))
                    .combined(with: .opacity)
            ))
            .animation(FDS.Spring.page, value: store.activeTab)

            ForgeBottomNav(namespace: namespace, dragOffset: $dragOffset)
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: store.activeTab) { old, new in
            previousTab = old
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
    
    private func tabTransitionEdge(from: TabItem, to: TabItem) -> Edge {
        // ARIA is the true center tab (index 3 of 7).
        let tabs: [TabItem] = [.home, .workout, .lifestyle, .chat, .sleep, .progress, .profile]
        guard let fromIndex = tabs.firstIndex(of: from),
              let toIndex = tabs.firstIndex(of: to) else {
            return .trailing
        }
        return toIndex > fromIndex ? .trailing : .leading
    }
}

// MARK: - Bottom Navigation

struct ForgeBottomNav: View {
    @EnvironmentObject var store: AppStore
    var namespace: Namespace.ID
    @Binding var dragOffset: CGFloat
    
    /// Home · Train · Life · ARIA (center) · Sleep · Stats · You
    private let tabs: [TabItem] = [.home, .workout, .lifestyle, .chat, .sleep, .progress, .profile]
    
    @State private var isPressed = false
    @State private var pressedTab: TabItem?

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 10)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)

                    HStack(spacing: 0) {
                        ForEach(tabs, id: \.self) { tab in
                            if tab == .chat {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                            } else {
                                RegularForgeTab(tab: tab, namespace: namespace)
                            }
                        }
                    }
                    .frame(height: 56)
                    .padding(.horizontal, 4)
                    .background(Color.background.opacity(0.94))
                    .background(.ultraThinMaterial.opacity(0.35))

                    Color.background
                        .frame(height: safeAreaBottom)
                }

                ARIATabButton(namespace: namespace)
                    .offset(y: -10 - safeAreaBottom / 2)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 16, y: -4)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    dragOffset = gesture.translation.height
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        dragOffset = 0
                    }
                }
        )
    }

    private var safeAreaBottom: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom) ?? 0
    }
}

// MARK: - Regular Tab Button

struct RegularForgeTab: View {
    let tab: TabItem
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore
    @State private var pressed = false
    @State private var hovered = false

    private var isActive: Bool { store.activeTab == tab }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                store.activeTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isActive ? tab.systemImageFilled : tab.systemImage)
                    .font(.system(size: 17, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .ember : .white.opacity(0.38))
                    .frame(height: 24)
                    .scaleEffect(pressed ? 0.9 : 1.0)

                Text(tab.shortLabel)
                    .font(.system(size: 9, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundColor(isActive ? .ember : .white.opacity(0.38))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(Rectangle())
            .accessibilityLabel(tab.label)
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.93 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }
                .onEnded { _ in
                    pressed = false
                }
        )
    }
}

// MARK: - ARIA Center Button (Chat + Voice toggle)

struct ARIATabButton: View {
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore
    @State private var isVoiceMode = false
    @State private var pressed = false

    private var isActive: Bool { store.activeTab == .chat }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) {
                store.activeTab = .chat
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isVoiceMode ? Color(hex: "0EA5E9") : Color.ember)
                        .frame(width: 48, height: 48)
                    Image(systemName: isVoiceMode ? "waveform" : "message.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
                .scaleEffect(pressed ? 0.94 : 1.0)

                Text(isVoiceMode ? "Voice" : "ARIA")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isActive ? .ember : .white.opacity(0.45))
            }
            .frame(width: 64, height: 64)
            .contentShape(Rectangle())
            .accessibilityLabel(isVoiceMode ? "ARIA Voice" : "ARIA")
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.55) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) {
                isVoiceMode.toggle()
                store.activeTab = .chat
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
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
