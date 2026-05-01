import SwiftUI

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if store.isOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
            
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
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Forge logo with glow
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.ember.opacity(glowIntensity * 0.4),
                                    Color.ember.opacity(glowIntensity * 0.2),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 30,
                                endRadius: 120
                            )
                        )
                        .frame(width: 240, height: 240)
                        .blur(radius: 30)
                    
                    // Main logo
                    Image(systemName: "flame.fill")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.ember, Color(hex: "FF3B00")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.ember.opacity(0.8), radius: 20, y: 10)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                
                Text("FORGE")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .tracking(4)
                    .foregroundColor(.white)
                    .opacity(logoOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 1.5).delay(0.2)) {
                glowIntensity = 1.0
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

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background with subtle gradient
            LinearGradient(
                colors: [
                    Color.background,
                    Color.background.opacity(0.95),
                    Color(hex: "0A0A0A")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Content with parallax effect
            Group {
                switch store.activeTab {
                case .home:      HomeView()
                case .chat:      ChatView()
                case .workout:   WorkoutView()
                case .lifestyle: LifestyleView()
                case .sleep:     SleepView()
                case .profile:   ProfileTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 82)
            .offset(y: dragOffset * 0.1) // Subtle parallax
            .transition(.asymmetric(
                insertion: .move(edge: tabTransitionEdge(from: previousTab, to: store.activeTab))
                    .combined(with: .opacity),
                removal: .move(edge: tabTransitionEdge(from: store.activeTab, to: previousTab))
                    .combined(with: .opacity)
            ))
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: store.activeTab)
            .id(store.activeTab)

            ForgeBottomNav(namespace: namespace, dragOffset: $dragOffset)
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: store.activeTab) { old, new in
            previousTab = old
        }
    }
    
    private func tabTransitionEdge(from: TabItem, to: TabItem) -> Edge {
        let tabs: [TabItem] = [.home, .workout, .chat, .sleep, .profile]
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
    
    private let tabs: [TabItem] = [.home, .workout, .chat, .sleep, .profile]
    
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
                    // Premium glass effect
                    Color(hex: "080808").opacity(0.85)
                    
                    // Subtle gradient overlay
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.white.opacity(0.01),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    // Noise texture simulation
                    Color.white.opacity(0.02)
                        .blendMode(.overlay)
                }
                .background(.ultraThinMaterial.opacity(0.3))
            )

            // Safe area extension
            ZStack {
                Color(hex: "080808")
                Color.white.opacity(0.01)
            }
            .frame(height: safeAreaBottom)
        }
        .shadow(color: .black.opacity(0.6), radius: 32, y: -8)
        .shadow(color: Color.ember.opacity(store.activeTab == .chat ? 0.1 : 0), radius: 20, y: -5)
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
                        .font(.system(size: 20, weight: isActive ? .semibold : .regular))
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

                // Label with refined typography
                Text(tab.label)
                    .font(.system(size: 10, weight: isActive ? .bold : .medium, design: .rounded))
                    .foregroundStyle(
                        isActive ?
                        LinearGradient(
                            colors: [Color.ember, Color(hex: "FF5A00")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .tracking(isActive ? 0.4 : 0.2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .contentShape(Rectangle())
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
