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
    @Namespace private var namespace
    @State private var previousTab: TabItem = .home
    @State private var dragOffset: CGFloat = 0
    /// Cycle Health is hosted on the shell so Profile/Settings deep links always work
    /// even when Home is not the active tab content.
    @State private var showCycleHealth = false
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
            .id(store.activeTab)

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
        .onAppear {
            if store.pendingCycleHealthOpen {
                presentCycleHealth()
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
        let tabs: [TabItem] = [.home, .workout, .chat, .lifestyle, .sleep, .progress, .profile]
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
    
    /// Home · Workout · Chat(ARIA) · Lifestyle · Sleep · Progress · Profile
    private let tabs: [TabItem] = [.home, .workout, .chat, .lifestyle, .sleep, .progress, .profile]
    
    @State private var isPressed = false
    @State private var pressedTab: TabItem?

    var body: some View {
        VStack(spacing: 0) {
            // Refined top edge with shimmer
            ZStack {
                // Base separator
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                
                // Shimmer highlight
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.15),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
                .blur(radius: 0.5)
            }

            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    if tab == .chat {
                        ARIATabButton(namespace: namespace)
                    } else {
                        RegularForgeTab(tab: tab, namespace: namespace)
                    }
                }
            }
            .frame(height: 62)
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .background(
                ZStack {
                    Color(hex: "060608").opacity(0.88)
                    LinearGradient.premiumChrome
                    Color.white.opacity(0.015)
                        .blendMode(.overlay)
                }
                .background(.ultraThinMaterial.opacity(0.45))
            )

            ZStack {
                Color(hex: "060608")
                Color.white.opacity(0.015)
            }
            .frame(height: safeAreaBottom)
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.02), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.6)
        }
        .shadow(color: .black.opacity(0.55), radius: 28, y: -10)
        .shadow(color: Color.ember.opacity(store.activeTab == .chat ? 0.14 : 0.04), radius: 24, y: -6)
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
            VStack(spacing: 6) {
                ZStack {
                    // Morphing active indicator
                    if isActive {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.ember.opacity(0.18),
                                        Color.ember.opacity(0.12)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 52, height: 32)
                            .overlay(
                                Capsule()
                                    .stroke(Color.ember.opacity(0.2), lineWidth: 0.5)
                            )
                            .shadow(color: Color.ember.opacity(0.3), radius: 8, y: 2)
                            .matchedGeometryEffect(id: "activeTab", in: namespace)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Icon with sophisticated animation
                    Image(systemName: isActive ? tab.systemImageFilled : tab.systemImage)
                        .font(.system(size: 17, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(
                            isActive ?
                            LinearGradient(
                                colors: [Color.ember, Color(hex: "FF5A00")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.white.opacity(0.45), Color.white.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(pressed ? 0.82 : (hovered ? 1.05 : 1.0))
                        .shadow(
                            color: isActive ? Color.ember.opacity(0.4) : .clear,
                            radius: 6,
                            y: 2
                        )
                }
                .frame(height: 32)

                // Compact labels — 7 tabs need tight typography that still reads.
                Text(tab.shortLabel)
                    .font(.system(size: 8.5, weight: isActive ? .bold : .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(
                        isActive ?
                        LinearGradient(
                            colors: [Color.ember, Color(hex: "FF5A00")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [Color.white.opacity(0.42), Color.white.opacity(0.30)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .tracking(isActive ? 0.25 : 0.1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
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
    @State private var orbPulse = false
    @State private var particlePhase: CGFloat = 0
    @State private var breathScale: CGFloat = 1.0

    private var isActive: Bool { store.activeTab == .chat }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                store.activeTab = .chat
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // EPIC particle rings when active
                    if isActive {
                        ForEach(0..<3) { index in
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: isVoiceMode ? 
                                        [
                                            Color(hex: "38BDF8").opacity(0.4),
                                            Color(hex: "0EA5E9").opacity(0.2),
                                            Color.clear
                                        ] :
                                        [
                                            Color.ember.opacity(0.4),
                                            Color(hex: "FF5A00").opacity(0.2),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 48 + CGFloat(index * 8), height: 48 + CGFloat(index * 8))
                                .scaleEffect(orbPulse ? 1.6 : 1.0)
                                .opacity(orbPulse ? 0.0 : (0.5 - Double(index) * 0.15))
                                .animation(
                                    .easeOut(duration: 2.0 + Double(index) * 0.3)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * 0.2),
                                    value: orbPulse
                                )
                        }
                    }
                    
                    // Premium orbital glow
                    if isActive {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: isVoiceMode ?
                                    [
                                        Color(hex: "38BDF8").opacity(0.3),
                                        Color(hex: "0EA5E9").opacity(0.15),
                                        Color.clear
                                    ] :
                                    [
                                        Color.ember.opacity(0.3),
                                        Color(hex: "FF5A00").opacity(0.15),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                            .blur(radius: 20)
                            .scaleEffect(breathScale)
                            .animation(
                                .easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                                value: breathScale
                            )
                    }

                    // Main orb with depth and dimension
                    ZStack {
                        // Shadow layer for depth
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 48, height: 48)
                            .blur(radius: 8)
                            .offset(y: 3)
                        
                        // Main gradient orb
                        Circle()
                            .fill(
                                AngularGradient(
                                    gradient: Gradient(colors: isVoiceMode ?
                                        [
                                            Color(hex: "38BDF8"),
                                            Color(hex: "0EA5E9"),
                                            Color(hex: "0284C7"),
                                            Color(hex: "0EA5E9"),
                                            Color(hex: "38BDF8")
                                        ] :
                                        [
                                            Color.ember,
                                            Color(hex: "FF5A00"),
                                            Color(hex: "E84000"),
                                            Color(hex: "FF5A00"),
                                            Color.ember
                                        ]
                                    ),
                                    center: .center,
                                    startAngle: .degrees(particlePhase),
                                    endAngle: .degrees(particlePhase + 360)
                                )
                            )
                            .frame(width: 48, height: 48)
                            .overlay(
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.white.opacity(0.3),
                                                Color.clear
                                            ],
                                            center: .topLeading,
                                            startRadius: 0,
                                            endRadius: 25
                                        )
                                    )
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.3),
                                                Color.clear
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(
                                color: isVoiceMode ?
                                    Color(hex: "38BDF8").opacity(isActive ? 0.7 : 0.3) :
                                    Color.ember.opacity(isActive ? 0.7 : 0.3),
                                radius: isActive ? 16 : 8,
                                y: 4
                            )
                        
                        // Icon with premium styling
                        Image(systemName: isVoiceMode ? "waveform" : "message.fill")
                            .font(.system(size: isVoiceMode ? 18 : 16, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.white,
                                        Color.white.opacity(0.9)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .scaleEffect(pressed ? 0.75 : 1.0)
                            .symbolEffect(.bounce, value: isVoiceMode)
                    }
                    .scaleEffect(pressed ? 0.88 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
                }
                .frame(height: 32)

                // Label with premium typography
                Text(isVoiceMode ? "Voice" : "ARIA")
                    .font(.system(size: 10, weight: isActive ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(
                        isVoiceMode ?
                        LinearGradient(
                            colors: [
                                Color(hex: "38BDF8"),
                                Color(hex: "0EA5E9")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        (isActive ?
                        LinearGradient(
                            colors: [Color.ember, Color(hex: "FF5A00")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    )
                    .tracking(0.6)
                    .shadow(
                        color: isVoiceMode ? 
                            Color(hex: "38BDF8").opacity(0.5) :
                            (isActive ? Color.ember.opacity(0.5) : .clear),
                        radius: 4,
                        y: 1
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .onLongPressGesture(minimumDuration: 0.6) {
            // Epic haptic sequence
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                generator.impactOccurred(intensity: 0.7)
            }
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                isVoiceMode.toggle()
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                store.activeTab = .chat
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                orbPulse = true
                breathScale = 1.08
            }
            // Smooth particle rotation
            withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                particlePhase = 360
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                orbPulse = false
                breathScale = 1.0
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    orbPulse = true
                    breathScale = 1.08
                }
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
