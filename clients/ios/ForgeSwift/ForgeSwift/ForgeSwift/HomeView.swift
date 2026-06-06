import SwiftUI
import Charts

// ╔════════════════════════════════════════════════════════════════════╗
// ║  FORGE HOME VIEW — Apple Design Award Caliber                      ║
// ║  Cinematic mesh · Particle overlay · Confetti burst                ║
// ║  ReadinessTrendChart · StreakCalendar · VoiceOrb                   ║
// ║  Double-glow ring · Dynamic insights · Full FDS integration        ║
// ╚════════════════════════════════════════════════════════════════════╝

// MARK: - Scroll Offset

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Root Home View

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var scrollOffset:    CGFloat = 0
    @State private var showHeaderBlur:  Bool    = false
    @State private var showCelebration: Bool    = false
    @State private var celebrationKey:  Int     = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            // ── Layer 0: Cinematic background ──────────────────────
            CinematicHomeBackground(readinessScore: store.readiness.overall)
                .ignoresSafeArea()

            // ── Layer 1: Particle system (readiness-reactive) ──────
            if !reduceMotion {
                ReadinessParticleOverlay(readinessScore: store.readiness.overall)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // ── Layer 2: Main scroll content ───────────────────────
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .top) {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .global).minY)
                    }
                    .frame(height: 0)

                    VStack(spacing: 0) {
                        HomeHeaderView()
                            .padding(.top, 64)
                            .padding(.horizontal, FDS.Spacing.lg)
                            .padding(.bottom, 24)

                        ARIAGreetingCard()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)

                        ReadinessSectionView(onCelebrate: triggerCelebration)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)

                        ReadinessTrendSection()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)

                        StreakCalendarSection()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)

                        if let workout = store.todayWorkout {
                            TodayPlanCardView(workout: workout)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 20)
                        }

                        QuickStatsView()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)

                        InsightsSectionView()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)

                        RecentActivityView()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 140)
                    }
                }
            }
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                withAnimation(.easeInOut(duration: 0.18)) {
                    showHeaderBlur = value < 40
                }
            }
            .refreshable { await refreshData() }

            // ── Layer 3: Frosted scroll header ─────────────────────
            if showHeaderBlur {
                FloatingStatusBar()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── Layer 4: Confetti celebration ──────────────────────
            if showCelebration && !reduceMotion {
                CelebrationOverlay(key: celebrationKey, onDismiss: {
                    withAnimation(FDS.Spring.standard) { showCelebration = false }
                })
                .ignoresSafeArea()
                .zIndex(100)
            }

            // ── Layer 5: Voice Quick Launch Orb ────────────────────
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
    func refreshData() async {
        FDS.haptic(.light)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await store.refreshDailyData()
        FDS.notificationHaptic(.success)
        if store.readiness.overall >= 85 { triggerCelebration() }
    }
}

// ============================================================
// MARK: - Cinematic Home Background
// ============================================================

struct CinematicHomeBackground: View {
    let readinessScore: Int
    @State private var phase:     Bool    = false
    @State private var meshPhase: Double  = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var primaryColor: Color {
        switch readinessScore {
        case 85...:  return Color(hex: "22C55E")
        case 70..<85: return Color.ember
        case 50..<70: return Color.steel
        default:      return Color(hex: "4B5563")
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "080808")

            if reduceMotion {
                primaryColor.opacity(0.06).ignoresSafeArea()
            } else {
                // Breathing primary gradient
                LinearGradient(
                    colors: [
                        Color(hex: "080808"),
                        primaryColor.opacity(phase ? 0.09 : 0.04),
                        Color(hex: "080808"),
                        Color.ember.opacity(phase ? 0.03 : 0.01),
                    ],
                    startPoint: phase ? .topLeading : .bottomLeading,
                    endPoint:   phase ? .bottomTrailing : .topTrailing
                )
                .opacity(0.9)

                // Animated blob mesh
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        let w = size.width; let h = size.height
                        let blobs: [(CGPoint, Color, CGFloat, Double)] = [
                            (CGPoint(x: w*(0.15 + 0.10*sin(t*0.17)), y: h*(0.20 + 0.08*cos(t*0.13))),
                             primaryColor, 280, 0.26),
                            (CGPoint(x: w*(0.80 + 0.09*cos(t*0.15)), y: h*(0.15 + 0.12*sin(t*0.11))),
                             Color.steel, 240, 0.18),
                            (CGPoint(x: w*(0.50 + 0.14*sin(t*0.12+1.0)), y: h*(0.70 + 0.07*cos(t*0.19))),
                             primaryColor, 200, 0.16),
                            (CGPoint(x: w*(0.10 + 0.08*cos(t*0.24)), y: h*(0.80 + 0.06*sin(t*0.14))),
                             Color.steel, 180, 0.14),
                        ]
                        for (center, color, r, opacity) in blobs {
                            let rect = CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2)
                            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                                Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
                                center: center, startRadius: 0, endRadius: r
                            ))
                        }
                    }
                }
                .blur(radius: 50)

                // Screen-blend aurora layer
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        let w = size.width; let h = size.height
                        let bands: [(CGFloat, Color, CGFloat)] = [
                            (h*(0.28 + 0.05*sin(t*0.09)), primaryColor, h*0.16),
                            (h*(0.55 + 0.07*cos(t*0.07)), Color.steel,  h*0.12),
                        ]
                        for (y, color, bH) in bands {
                            let rect = CGRect(x: 0, y: y-bH/2, width: w, height: bH)
                            ctx.fill(Path(rect), with: .linearGradient(
                                Gradient(colors: [color.opacity(0), color.opacity(0.14), color.opacity(0)]),
                                startPoint: CGPoint(x: 0, y: y-bH/2), endPoint: CGPoint(x: 0, y: y+bH/2)
                            ))
                        }
                    }
                }
                .blendMode(.screen)
                .opacity(0.5)
            }

            // Always-present vignette
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.5)],
                center: .center, startRadius: 80, endRadius: 380
            )
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { phase = true }
        }
        .animation(.easeInOut(duration: 1.8), value: readinessScore)
    }
}

// ============================================================
// MARK: - Particle Overlay (readiness-reactive)
// ============================================================

private struct Particle: Identifiable {
    let id:           Int
    var x:            CGFloat
    var y:            CGFloat
    let size:         CGFloat
    let speed:        Double
    let opacity:      Double
    let color:        Bool      // true = accent, false = neutral
    let phaseOffset:  Double
}

struct ReadinessParticleOverlay: View {
    let readinessScore: Int
    @State private var particles: [Particle] = []
    @State private var globalT: Double = 0

    private var particleCount: Int {
        switch readinessScore {
        case 85...:  return 28
        case 70..<85: return 16
        case 50..<70: return 8
        default:      return 4
        }
    }

    private var accentColor: Color {
        switch readinessScore {
        case 85...:  return Color(hex: "22C55E")
        case 70..<85: return Color.ember
        default:      return Color.steel
        }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    for p in particles {
                        let drift = CGFloat(sin(t * p.speed + p.phaseOffset) * 18)
                        let rise  = CGFloat(t * p.speed * 22).truncatingRemainder(dividingBy: size.height + 40)
                        let px    = p.x + drift
                        let py    = size.height - rise - p.y
                        let fade  = min(1.0, min(py / 60, (size.height - py) / 60))
                        let color = p.color ? accentColor : Color.white
                        let rect  = CGRect(x: px - p.size/2, y: py - p.size/2, width: p.size, height: p.size)
                        ctx.fill(
                            Path(ellipseIn: rect),
                            with: .color(color.opacity(p.opacity * fade * 0.6))
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .onAppear {
                particles = (0..<particleCount).map { i in
                    Particle(
                        id: i,
                        x: .random(in: 0...geo.size.width),
                        y: .random(in: 0...geo.size.height),
                        size: .random(in: 1.2...3.8),
                        speed: .random(in: 0.18...0.42),
                        opacity: .random(in: 0.25...0.7),
                        color: i % 3 == 0,
                        phaseOffset: .random(in: 0...(.pi * 2))
                    )
                }
            }
        }
    }
}

// ============================================================
// MARK: - Celebration Confetti
// ============================================================

struct CelebrationOverlay: View {
    @EnvironmentObject var store: AppStore
    let key:       Int
    let onDismiss: () -> Void
    @State private var particles: [ConfettiParticle] = []
    @State private var revealed = false
    @State private var bannerScale: CGFloat = 0.6

    private struct ConfettiParticle: Identifiable {
        let id: Int
        let x: CGFloat; let size: CGFloat
        let color: Color; let rotation: Double
        let speed: Double; let drift: Double
    }

    private let confettiColors: [Color] = [
        .ember, Color(hex: "22C55E"), Color.steel,
        Color(hex: "F59E0B"), Color(hex: "A855F7"), .white
    ]

    var body: some View {
        ZStack {
            // Confetti canvas
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0/60.0)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        for p in particles {
                            let elapsed = t.truncatingRemainder(dividingBy: 4.0)
                            let progress = elapsed / 4.0
                            let y = -30 + (size.height + 60) * CGFloat(progress) * CGFloat(p.speed)
                            let x = p.x + CGFloat(sin(t * p.drift + Double(p.id)) * 28)
                            let rot = t * p.rotation
                            let fade = min(1.0, min(progress * 4, (1.0 - progress) * 4))

                            ctx.translateBy(x: x, y: y)
                            ctx.rotate(by: .radians(rot))
                            let rect = CGRect(x: -p.size/2, y: -p.size/2, width: p.size, height: p.size)
                            ctx.fill(Path(rect), with: .color(p.color.opacity(fade * 0.9)))
                            ctx.rotate(by: .radians(-rot))
                            ctx.translateBy(x: -x, y: -y)
                        }
                    }
                }
                .onAppear {
                    particles = (0..<60).map { i in
                        ConfettiParticle(
                            id: i,
                            x: .random(in: 0...geo.size.width),
                            size: .random(in: 5...12),
                            color: confettiColors[i % confettiColors.count],
                            rotation: .random(in: 1.5...4.0),
                            speed: .random(in: 0.5...1.0),
                            drift: .random(in: 0.5...2.0)
                        )
                    }
                }
            }

            // Peak Performance Banner
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "22C55E").opacity(0.2))
                            .frame(width: 90, height: 90)
                            .blur(radius: 20)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .shadow(color: Color(hex: "FFD700").opacity(0.6), radius: 20)
                    }

                    VStack(spacing: 8) {
                        Text("PEAK PERFORMANCE")
                            .font(.system(size: 13, weight: .black))
                            .tracking(3.5)
                            .foregroundColor(Color(hex: "22C55E"))

                        Text("Readiness Score \(store.readiness.overall)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(LinearGradient(
                                colors: [.white, Color(hex: "22C55E")],
                                startPoint: .top, endPoint: .bottom
                            ))

                        Text("You're in the zone. Go crush it.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }

                    Button(action: onDismiss) {
                        Text("Let's Go →")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(FDS.Gradient.ember)
                            .cornerRadius(FDS.Radius.pill)
                            .shadow(color: Color.ember.opacity(0.45), radius: 14, y: 6)
                    }
                }
                .padding(32)
                .background(
                    ZStack {
                        Color.surface.opacity(0.95)
                        LinearGradient(
                            colors: [Color(hex: "22C55E").opacity(0.08), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                )
                .cornerRadius(FDS.Radius.xl)
                .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xl)
                    .stroke(Color(hex: "22C55E").opacity(0.3), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.3), radius: 40, y: 20)
                .padding(.horizontal, 24)
                .scaleEffect(bannerScale)
                .opacity(revealed ? 1 : 0)

                Spacer()
            }
        }
        .background(Color.black.opacity(revealed ? 0.55 : 0).ignoresSafeArea())
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.2)) {
                revealed = true
                bannerScale = 1.0
            }
        }
        .onTapGesture { onDismiss() }
        .id(key)
    }

}

// ============================================================
// MARK: - Floating Status Bar
// ============================================================

struct FloatingStatusBar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(readinessColor(store.readiness.overall))
                .frame(width: 8, height: 8)
                .shadow(color: readinessColor(store.readiness.overall).opacity(0.7), radius: 5)

            Text("Readiness")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)

            Text("\(store.readiness.overall)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(readinessColor(store.readiness.overall))

            Spacer()

            Text("FORGE")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(.ember)
                .tracking(2.5)
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.horizontal, 16).padding(.top, 52)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
    }
}

// ============================================================
// MARK: - Home Header
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
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateString.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .tracking(1.8)
                Text(greeting + (store.userProfile.name.isEmpty ? "" : ", \(store.userProfile.name.components(separatedBy: " ").first ?? "")"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.textPrimary)
                // Live HealthKit label
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: "22C55E")).frame(width: 5, height: 5)
                        .shadow(color: Color(hex: "22C55E").opacity(0.8), radius: 3)
                    Text("Live from HealthKit")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "22C55E"))
                }
            }

            Spacer()

            // Profile button with streak badge
            Button(action: { store.activeTab = .profile }) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.surface)
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Color.borderColor, lineWidth: 0.5))
                        .overlay(Image(systemName: "person.fill")
                            .font(.system(size: 19)).foregroundColor(.ember))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                    if store.currentStreak > 0 {
                        ZStack {
                            Circle().fill(Color.ember).frame(width: 22, height: 22)
                                .shadow(color: Color.ember.opacity(0.5), radius: 6)
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11)).foregroundColor(.white)
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -14)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true }
        }
    }
}

// ============================================================
// MARK: - ARIA Greeting Card
// ============================================================

struct ARIAGreetingCard: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared      = false
    @State private var displayedText = ""
    @State private var isTyping      = false
    @State private var pulseRing     = false
    @State private var glowBeat      = false

    private var fullGreeting: String {
        let h    = Calendar.current.component(.hour, from: Date())
        let time = h < 12 ? "Morning" : h < 17 ? "Afternoon" : "Evening"
        let deep = store.dailyMetrics.deepSleep
        let deepStr = deep >= 60 ? "\(deep/60)hr \(deep%60)m" : "\(deep)m"
        let sq   = store.readiness.sleepQuality
        let hrv  = store.dailyMetrics.hrv
        let overall = store.readiness.overall

        var parts: [String] = ["\(time), \(store.userProfile.name.components(separatedBy: " ").first ?? "")."]

        if sq >= 80 {
            parts.append("Deep sleep was solid — \(deepStr) of quality rest.")
        } else if sq >= 60 {
            parts.append("\(deepStr) of deep sleep. Decent, but room to improve.")
        } else {
            parts.append("Only \(deepStr) of deep sleep. Recovery may lag today.")
        }

        if hrv >= 50 {
            parts.append("HRV looking strong at \(hrv)ms.")
        } else if hrv >= 35 {
            parts.append("HRV at \(hrv)ms — moderate.")
        } else {
            parts.append("HRV is low at \(hrv)ms. Nervous system needs a break.")
        }

        if let name = store.todayWorkout?.name {
            if overall >= 80 { parts.append("You're primed — let's crush \(name).") }
            else if overall >= 60 { parts.append("I've tuned \(name) to your current state.") }
            else { parts.append("Go lighter on \(name) or swap for mobility work today.") }
        }

        return parts.joined(separator: " ")
    }

    var body: some View {
        Button(action: {
            FDS.haptic(.light)
            store.activeTab = .chat
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 10) {
                    // ARIA avatar with pulse
                    ZStack {
                        Circle()
                            .fill(Color.ember.opacity(0.22))
                            .frame(width: 52, height: 52)
                            .blur(radius: 10)
                            .scaleEffect(pulseRing ? 1.45 : 1.0)
                            .opacity(pulseRing ? 0 : 0.7)

                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.ember, Color(hex: "FF2200")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.ember.opacity(glowBeat ? 0.7 : 0.3), radius: glowBeat ? 16 : 8)
                            .overlay(Text("A").font(.system(size: 20, weight: .black)).foregroundColor(.white))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("ARIA")
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(.ember)
                                .tracking(1.5)
                            HStack(spacing: 4) {
                                Circle().fill(Color(hex: "22C55E")).frame(width: 5, height: 5)
                                Text("Online")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(hex: "22C55E"))
                            }
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color(hex: "22C55E").opacity(0.1))
                            .cornerRadius(FDS.Radius.pill)
                        }
                        Text("AI Fitness Coach · Forge")
                            .font(.system(size: 11)).foregroundColor(.textMuted)
                    }
                    Spacer()

                    // Mic button — launches voice chat
                    Button(action: {
                        FDS.haptic(.medium)
                        store.activeTab = .chat
                    }) {
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

                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.ember.opacity(0.45))
                }
                .padding(.bottom, 16)

                // Message bubble
                ZStack(alignment: .bottomTrailing) {
                    Text(displayedText.isEmpty && !isTyping ? fullGreeting : displayedText)
                        .font(.system(size: 15.5, weight: .regular))
                        .foregroundColor(.textPrimary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isTyping {
                        Rectangle()
                            .fill(Color.ember)
                            .frame(width: 2, height: 16)
                            .cornerRadius(1)
                            .offset(x: 4)
                    }
                }
                .padding(16)
                .background(Color.surfaceElevated)
                .cornerRadius(FDS.Radius.md)
                .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md)
                    .stroke(Color.ember.opacity(0.12), lineWidth: 1))
                .padding(.bottom, 16)

                // Footer chips
                HStack(spacing: 0) {
                    FooterActionChip(icon: "message.fill",  label: "Reply",        color: .ember)
                    Spacer()
                    FooterActionChip(icon: "sparkles",      label: "Ask Anything", color: .textSecondary)
                    Spacer()
                    FooterActionChip(icon: "calendar",      label: "Plan Week",    color: .textSecondary)
                }
            }
            .padding(20)
            .background(ZStack {
                Color.surface
                LinearGradient(
                    colors: [Color.ember.opacity(0.05), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            })
            .cornerRadius(FDS.Radius.xl)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xl)
                .stroke(LinearGradient(
                    colors: [Color.ember.opacity(0.38), Color.ember.opacity(0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1))
            .shadow(color: Color.ember.opacity(0.12), radius: 24, y: 8)
            .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
        .scaleEffect(appeared ? 1 : 0.97)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.15)) { appeared = true }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { pulseRing = true }
            withAnimation(.easeInOut(duration: FDS.Duration.breathe).repeatForever(autoreverses: true)) { glowBeat = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { startTypewriter() }
        }
    }

    private func startTypewriter() {
        let text = fullGreeting
        displayedText = ""; isTyping = true; var idx = 0
        func next() {
            guard idx < text.count else { isTyping = false; return }
            let i = text.index(text.startIndex, offsetBy: idx)
            displayedText.append(text[i]); idx += 1
            let delay: Double = text[i] == " " ? 0.042 : (text[i] == "." ? 0.18 : 0.024)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { next() }
        }
        next()
    }
}

private struct FooterActionChip: View {
    let icon: String; let label: String; let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12))
            Text(label).font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(color)
    }
}

// ============================================================
// MARK: - Readiness Section
// ============================================================

struct ReadinessSectionView: View {
    @EnvironmentObject var store: AppStore
    var onCelebrate: () -> Void = {}
    @State private var appeared     = false
    @State private var showDetails  = false

    private let breakdownItems: [(String, KeyPath<ReadinessData, Int>, Bool)] = [
        ("Sleep Quality", \.sleepQuality,  false),
        ("Recovery",      \.recoveryScore, false),
        ("Stress",        \.stressLevel,   true),
        ("Energy",        \.energyBank,    false),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("READINESS SCORE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary).tracking(2)
                    Text("Updated just now")
                        .font(.system(size: 10)).foregroundColor(.textMuted)
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
                    .animation(FDS.Spring.snap, value: showDetails)
                }
            }
            .padding(.bottom, 28)

            // Double-glow readiness ring
            ReadinessRingView(score: store.readiness.overall, size: 196, strokeWidth: 15)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
                .onTapGesture {
                    if store.readiness.overall >= 85 { onCelebrate() }
                }

            // Breakdown grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(breakdownItems.enumerated()), id: \.offset) { i, item in
                    let value = store.readiness[keyPath: item.1]
                    BreakdownCardView(label: item.0, value: value, inverted: item.2, index: i)
                }
            }

            // Expandable detail rows
            if showDetails {
                VStack(spacing: 10) {
                    Divider().padding(.vertical, 12)
                    ReadinessInsightRow(icon: "moon.stars.fill",          title: "Deep Sleep",    value: "\(store.dailyMetrics.deepSleep/60)h \(store.dailyMetrics.deepSleep%60)m", color: .steel)
                    ReadinessInsightRow(icon: "waveform.path.ecg.rectangle.fill", title: "HRV", value: "\(store.dailyMetrics.hrv)ms",      color: .danger)
                    ReadinessInsightRow(icon: "figure.cooldown",           title: "Training Load", value: "Moderate",                        color: .ember)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                    removal:   .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                ))
            }
        }
        .padding(24)
        .background(ZStack {
            Color.surface
            RadialGradient(
                colors: [readinessColor(store.readiness.overall).opacity(0.08), .clear],
                center: .center, startRadius: 40, endRadius: 240
            )
        })
        .cornerRadius(FDS.Radius.xl)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xl)
            .stroke(readinessColor(store.readiness.overall).opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 28)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.25)) { appeared = true } }
    }
}

struct ReadinessInsightRow: View {
    let icon: String; let title: String; let value: String; let color: Color
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 38, height: 38)
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
            }
            Text(title).font(.system(size: 14, weight: .medium)).foregroundColor(.textSecondary)
            Spacer()
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.surfaceElevated).cornerRadius(FDS.Radius.sm)
    }
}

struct BreakdownCardView: View {
    let label: String; let value: Int; let inverted: Bool; let index: Int
    @State private var appeared = false
    private var display:    Int   { inverted ? 100 - value : value }
    private var dot:        Color { readinessColor(display) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(dot).frame(width: 8, height: 8).shadow(color: dot.opacity(0.5), radius: 4)
                Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(.textSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(display)%")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.textPrimary)
                .contentTransition(.numericText())

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.borderColor.opacity(0.6)).frame(height: 3)
                    RoundedRectangle(cornerRadius: 3).fill(dot)
                        .frame(width: appeared ? geo.size.width * CGFloat(display)/100 : 0, height: 3)
                        .animation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.8 + Double(index)*0.1), value: appeared)
                }
            }
            .frame(height: 3)
        }
        .padding(14).background(Color.surfaceElevated).cornerRadius(FDS.Radius.md)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(dot.opacity(0.2), lineWidth: 1))
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.6 + Double(index)*0.08)) { appeared = true } }
    }
}

// ============================================================
// MARK: - Readiness Ring (Double-glow enhanced)
// ============================================================

struct ReadinessRingView: View {
    let score:       Int
    let size:        CGFloat
    let strokeWidth: CGFloat
    var showLabel:   Bool = true

    @State private var progress:   CGFloat = 0
    @State private var glowPulse:  Bool    = false
    @State private var outerPulse: Bool    = false

    private var color: Color { readinessColor(score) }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size, height: size)

            // Outer diffuse glow (award-winning depth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: strokeWidth + 14, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .blur(radius: 18)
                .scaleEffect(outerPulse ? 1.02 : 0.99)
                .opacity(outerPulse ? 0.7 : 1.0)

            // Inner glow
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: strokeWidth + 6, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .blur(radius: 8)
                .opacity(glowPulse ? 0.55 : 0.85)

            // Primary arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.6), color, color.opacity(0.85)],
                        center: .center,
                        startAngle: .degrees(-90), endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.55), radius: 16)

            // Tip dot
            if progress > 0.02 {
                Circle()
                    .fill(color)
                    .frame(width: strokeWidth * 0.85, height: strokeWidth * 0.85)
                    .shadow(color: color, radius: 6)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(-90 + Double(progress) * 360))
            }

            // Center content
            if showLabel {
                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: size * 0.24, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(
                            colors: [.textPrimary, color],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .contentTransition(.numericText())
                    Text(readinessLabel(score).uppercased())
                        .font(.system(size: size * 0.07, weight: .black))
                        .foregroundColor(color).tracking(1.8)
                    Text("Readiness")
                        .font(.system(size: size * 0.058, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 1.6, dampingFraction: 0.68).delay(0.55)) {
                progress = CGFloat(score) / 100
            }
            withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) { glowPulse = true }
            withAnimation(.easeInOut(duration: 3.1).repeatForever(autoreverses: true)) { outerPulse = true }
        }
    }
}

// ============================================================
// MARK: - Readiness Trend Chart (7-day line + area)
// ============================================================

struct ReadinessTrendSection: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    // Sample data — replace with store.readinessTrend in production
    private var trendData: [(day: String, score: Int)] {
        let days = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        let base = max(40, store.readiness.overall - 20)
        return days.enumerated().map { i, d in
            let noise = Int.random(in: -8...12)
            return (d, min(100, max(30, base + noise + i * 2)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("READINESS TREND")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary).tracking(2)
                    Text("Last 7 days")
                        .font(.system(size: 10)).foregroundColor(.textMuted)
                }
                Spacer()
                // Delta badge
                let first = trendData.first?.score ?? 70
                let last  = trendData.last?.score  ?? 70
                let delta = last - first
                HStack(spacing: 4) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(abs(delta))%")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(delta >= 0 ? Color(hex: "22C55E") : .danger)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background((delta >= 0 ? Color(hex: "22C55E") : Color.danger).opacity(0.1))
                .cornerRadius(FDS.Radius.pill)
            }

            // Swift Charts area + line
            Chart {
                ForEach(Array(trendData.enumerated()), id: \.offset) { i, point in
                    AreaMark(
                        x: .value("Day", point.day),
                        y: .value("Score", appeared ? point.score : 0)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [readinessColor(point.score).opacity(0.3), .clear],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Score", appeared ? point.score : 0)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: trendData.map { readinessColor($0.score) },
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Day", point.day),
                        y: .value("Score", appeared ? point.score : 0)
                    )
                    .foregroundStyle(readinessColor(point.score))
                    .symbolSize(i == trendData.count - 1 ? 60 : 30)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(Color.textMuted)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 90)
            .animation(.spring(response: 1.2, dampingFraction: 0.72).delay(0.3), value: appeared)
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(FDS.Radius.xl)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xl).stroke(Color.borderColor, lineWidth: 0.5))
        .forgeCardShadow()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.35)) { appeared = true } }
    }
}

// ============================================================
// MARK: - Streak Calendar Mini
// ============================================================

struct StreakCalendarSection: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    // Last 7 days — true if workout completed
    private var weekDays: [(label: String, hasWorkout: Bool, isToday: Bool)] {
        let cal = Calendar.current
        let today = Date()
        return (0..<7).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let f = DateFormatter(); f.dateFormat = "EEE"
            let label = f.string(from: date)
            let isToday = offset == 0
            // Check store.workoutHistory for real data - convert string date to Date
            let hasWorkout = store.workoutHistory.contains { history in
                guard let historyDate = ISO8601DateFormatter().date(from: history.date) else { return false }
                return cal.isDate(historyDate, inSameDayAs: date)
            }
            return (label, hasWorkout, isToday)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: 13)).foregroundColor(.ember)
                    Text("\(store.currentStreak)-DAY STREAK")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.ember).tracking(2)
                }
                Spacer()
                Text("This Week")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.textMuted)
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
                                    .font(.system(size: 14)).foregroundColor(.ember)
                                    .shadow(color: Color.ember.opacity(0.5), radius: 4)
                            } else if day.isToday {
                                Circle().stroke(Color.ember.opacity(0.6), lineWidth: 1.5).frame(width: 34, height: 34)
                                Circle().fill(Color.ember).frame(width: 6, height: 6)
                            } else {
                                Circle().fill(Color.white.opacity(0.08)).frame(width: 8, height: 8)
                            }
                        }
                        .scaleEffect(appeared ? 1 : 0.6)
                        .opacity(appeared ? 1 : 0)
                        .animation(FDS.Spring.hero.delay(0.1 + Double(i) * 0.06), value: appeared)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(FDS.Radius.xl)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xl).stroke(Color.ember.opacity(0.12), lineWidth: 1))
        .forgeCardShadow()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.4)) { appeared = true } }
    }
}

// ============================================================
// MARK: - Today's Plan Card
// ============================================================

struct TodayPlanCardView: View {
    let workout: WorkoutPlan
    @EnvironmentObject var store: AppStore
    @State private var appeared      = false
    @State private var startPressed  = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TODAY'S PLAN")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary).tracking(2)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 10))
                    Text("AI Optimized").font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.ember)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color.ember.opacity(0.12)).cornerRadius(FDS.Radius.xs)
            }
            .padding(.bottom, 14)

            Text(workout.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.textPrimary).padding(.bottom, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    InfoPill(icon: "dumbbell.fill",  text: workout.type.label)
                    InfoPill(icon: "clock.fill",     text: "~\(workout.duration) min")
                    IntensityInfoPill(intensity: workout.intensity)
                    InfoPill(icon: "flame.fill",     text: "\(workout.estimatedCalories) cal")
                }
            }
            .padding(.bottom, 24)

            // Match quality bar
            let matchScore = Double(store.readiness.overall) / 100
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Readiness Match")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.textMuted)
                    Spacer()
                    Text(matchScore > 0.75 ? "Well Matched" : matchScore > 0.5 ? "Manageable" : "Intensity Mismatch")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(matchScore > 0.75 ? Color(hex: "22C55E") : matchScore > 0.5 ? .ember : .danger)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.borderColor.opacity(0.5)).frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(matchScore > 0.75 ? Color(hex: "22C55E") : matchScore > 0.5 ? Color.ember : Color.danger)
                            .frame(width: appeared ? geo.size.width * matchScore : 0, height: 4)
                            .animation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.5), value: appeared)
                    }
                }
                .frame(height: 4)
            }
            .padding(.bottom, 20)

            VStack(spacing: 10) {
                ForEach(Array(workout.exercises.prefix(3).enumerated()), id: \.element.id) { i, ex in
                    ExercisePreviewRow(exercise: ex, index: i, appeared: appeared)
                }
                if workout.exercises.count > 3 {
                    HStack {
                        Text("+\(workout.exercises.count - 3) more exercises")
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary)
                        Spacer()
                        Image(systemName: "ellipsis").foregroundColor(.textMuted)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                }
            }
            .padding(.bottom, 24)

            VStack(spacing: 12) {
                Button {
                    FDS.haptic(.medium)
                    store.startWorkout()
                    store.activeTab = .workout
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold))
                        Text("Start Workout").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 17).padding(.horizontal, 22)
                    .frame(maxWidth: .infinity)
                    .background(FDS.Gradient.ember)
                    .cornerRadius(FDS.Radius.md)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: FDS.Radius.md)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.12), .clear], startPoint: .top, endPoint: .center))
                            .frame(height: 28)
                    }
                    .shadow(color: Color.ember.opacity(startPressed ? 0.2 : 0.5), radius: startPressed ? 6 : 20, y: startPressed ? 2 : 8)
                }
                .scaleEffect(startPressed ? 0.97 : 1.0)
                .animation(FDS.Spring.snap, value: startPressed)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in startPressed = true }
                        .onEnded   { _ in startPressed = false }
                )

                HStack(spacing: 12) {
                    SecondaryButton(icon: "arrow.triangle.2.circlepath", label: "Change Plan") {
                        FDS.haptic(.light); store.activeTab = .chat
                    }
                    SecondaryButton(icon: "square.and.arrow.up", label: "Share") {}
                }
            }
        }
        .padding(24)
        .background(ZStack {
            Color.surface
            LinearGradient(colors: [Color.ember.opacity(0.04), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        })
        .cornerRadius(FDS.Radius.xl)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xl)
            .stroke(LinearGradient(
                colors: [Color.ember.opacity(0.22), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ), lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 28)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.35)) { appeared = true } }
    }
}

private struct ExercisePreviewRow: View {
    let exercise: Exercise; let index: Int; let appeared: Bool
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [Color.ember.opacity(0.18), Color.ember.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                Text("\(index + 1)").font(.system(size: 13, weight: .bold)).foregroundColor(.ember)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.system(size: 15, weight: .medium)).foregroundColor(.textPrimary)
                Text("\(exercise.sets) sets × \(exercise.reps) reps").font(.system(size: 12)).foregroundColor(.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(.textMuted)
        }
        .padding(13).background(Color.surfaceElevated).cornerRadius(13)
        .opacity(appeared ? 1 : 0).offset(x: appeared ? 0 : -18)
        .animation(FDS.Spring.hero.delay(0.45 + Double(index)*0.08), value: appeared)
    }
}

private struct SecondaryButton: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13))
                Text(label).font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.textSecondary).frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(Color.surfaceElevated).cornerRadius(13)
        }
    }
}

struct InfoPill: View {
    let icon: String; let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(.textTertiary)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.surfaceElevated).cornerRadius(FDS.Radius.pill)
    }
}

struct IntensityInfoPill: View {
    let intensity: WorkoutIntensity
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(intensity.color).frame(width: 7, height: 7)
            Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundColor(.textTertiary)
            Text(intensity.label).font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.surfaceElevated).cornerRadius(FDS.Radius.pill)
    }
}

// ============================================================
// MARK: - Quick Stats
// ============================================================

struct QuickStatsView: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("TODAY'S ACTIVITY")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.textTertiary).tracking(2)
                Spacer()
                Button("View All") { store.activeTab = .workout }
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.ember)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    MetricCard(icon: "figure.walk",      iconColor: Color(hex: "22C55E"),
                               value: store.dailyMetrics.steps.formatted(), label: "Steps",       trend: .up,   trendValue: "+12%")
                    MetricCard(icon: "flame.fill",       iconColor: .ember,
                               value: "\(store.dailyMetrics.activeCalories)",  label: "Active Cal", trend: .up,   trendValue: "+8%")
                    MetricCard(icon: "waveform.path.ecg",iconColor: .danger,
                               value: "\(store.dailyMetrics.hrv)ms",           label: "HRV",        trend: .up,   trendValue: "+5%")
                    MetricCard(icon: "heart.fill",       iconColor: .steel,
                               value: "\(store.dailyMetrics.restingHR) bpm",   label: "Resting HR", trend: .down, trendValue: "-2%")
                }
                .padding(.horizontal, 1)
            }
        }
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.45)) { appeared = true } }
    }
}

enum TrendDir { case up, down, neutral }

struct MetricCard: View {
    let icon: String; let iconColor: Color
    let value: String; let label: String
    let trend: TrendDir; var trendValue: String = ""
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle().fill(iconColor.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 18)).foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(.textPrimary)
                    if !trendValue.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(trendValue).font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(trend == .up ? Color(hex: "22C55E") : .danger)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background((trend == .up ? Color(hex: "22C55E") : Color.danger).opacity(0.1))
                        .cornerRadius(5)
                    }
                }
                Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(.textTertiary)
            }
        }
        .padding(16).background(Color.surface).cornerRadius(FDS.Radius.lg)
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .opacity(appeared ? 1 : 0).scaleEffect(appeared ? 1 : 0.9)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.55)) { appeared = true } }
    }
}

// ============================================================
// MARK: - Insights
// ============================================================

struct InsightsSectionView: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    private var insights: [Insight] {
        var r: [Insight] = []
        if store.readiness.overall >= 85 {
            r.append(Insight(icon: "crown.fill", title: "Peak Readiness Window 👑",
                description: "You're in elite territory. This is your best time to PR or go heavy.",
                color: Color(hex: "22C55E"), priority: .high))
        }
        if store.readiness.overall < 70 {
            r.append(Insight(icon: "bed.double.fill", title: "Consider a Rest Day",
                description: "Recovery below optimal. A lighter session or full rest will pay off tomorrow.",
                color: .steel, priority: .high))
        }
        if store.dailyMetrics.hrv < 40 {
            r.append(Insight(icon: "waveform.path.ecg.rectangle.fill", title: "Low HRV Detected",
                description: "Nervous system under stress. Prioritize sleep and calm recovery work.",
                color: .danger, priority: .high))
        }
        if store.currentStreak >= 7 {
            r.append(Insight(icon: "flame.fill", title: "\(store.currentStreak)-Day Streak 🔥",
                description: "You're on a roll. Stay consistent and let recovery guide your intensity.",
                color: .ember, priority: .medium))
        }
        return r
    }

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("INSIGHTS")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.textTertiary).tracking(2)
                VStack(spacing: 10) {
                    ForEach(Array(insights.enumerated()), id: \.element.id) { i, insight in
                        InsightCard(insight: insight)
                            .forgeEntrance(index: i, appeared: appeared)
                    }
                }
            }
            .onAppear { withAnimation(FDS.Spring.hero.delay(0.55)) { appeared = true } }
        }
    }
}

struct Insight: Identifiable {
    let id = UUID()
    let icon: String; let title: String; let description: String
    let color: Color; let priority: Priority
    enum Priority { case high, medium, low }
}

struct InsightCard: View {
    let insight: Insight
    var body: some View {
        Button { FDS.haptic(.light) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(insight.color.opacity(0.14)).frame(width: 46, height: 46)
                    Image(systemName: insight.icon).font(.system(size: 20)).foregroundColor(insight.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                    Text(insight.description).font(.system(size: 13)).foregroundColor(.textSecondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(.textMuted)
            }
            .padding(16).background(Color.surface).cornerRadius(FDS.Radius.md)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(insight.color.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(.plain).forgePress()
    }
}

// ============================================================
// MARK: - Recent Activity (dynamic from store.workoutHistory)
// ============================================================

struct RecentActivityView: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("RECENT WORKOUTS")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.textTertiary).tracking(2)
                Spacer()
                Button("See All") { store.activeTab = .workout }
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.ember)
            }

            if store.workoutHistory.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "dumbbell").font(.system(size: 32)).foregroundColor(.textMuted)
                    Text("No recent workouts").font(.system(size: 14)).foregroundColor(.textMuted)
                    Text("Complete your first session to see history here.")
                        .font(.system(size: 12)).foregroundColor(.textMuted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(32)
                .background(Color.surface).cornerRadius(FDS.Radius.lg)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(store.workoutHistory.prefix(3).enumerated()), id: \.element.id) { i, session in
                        RecentWorkoutRow(session: session)
                            .forgeEntrance(index: i, appeared: appeared)
                    }
                }
            }
        }
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.65)) { appeared = true } }
    }
}

struct RecentWorkoutRow: View {
    let session: WorkoutHistory

    private var relativeDate: String {
        guard let date = ISO8601DateFormatter().date(from: session.date) else { return "Recently" }
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        return "\(days) days ago"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.ember.opacity(0.14)).frame(width: 50, height: 50)
                Image(systemName: "dumbbell.fill").font(.system(size: 20)).foregroundColor(.ember)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                HStack(spacing: 6) {
                    Text(relativeDate).font(.system(size: 12)).foregroundColor(.textTertiary)
                    Circle().fill(Color.textMuted).frame(width: 3, height: 3)
                    Text("\(session.duration) min").font(.system(size: 12)).foregroundColor(.textTertiary)
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundColor(Color(hex: "22C55E"))
        }
        .padding(16).background(Color.surface).cornerRadius(FDS.Radius.md)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .forgePress()
    }
}

// ============================================================
// MARK: - Voice Quick Launch Orb
// ============================================================

struct VoiceQuickLaunchOrb: View {
    @EnvironmentObject var store: AppStore
    @State private var pulse      = false
    @State private var outerPulse = false
    @State private var pressed    = false
    @State private var appeared   = false

    var body: some View {
        Button(action: {
            FDS.haptic(.heavy)
            store.activeTab = .chat
        }) {
            ZStack {
                // Outer diffuse pulse
                Circle()
                    .fill(Color.ember.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .scaleEffect(outerPulse ? 1.35 : 1.0)
                    .opacity(outerPulse ? 0 : 0.8)

                // Inner glow
                Circle()
                    .fill(Color.ember.opacity(0.25))
                    .frame(width: 62, height: 62)
                    .blur(radius: 12)
                    .scaleEffect(pulse ? 1.1 : 0.95)

                // Main orb
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "FF4C00"), Color(hex: "FF2200")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .overlay(alignment: .top) {
                        // Specular highlight
                        Ellipse()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 24, height: 10)
                            .blur(radius: 3)
                            .offset(y: 8)
                    }
                    .shadow(color: Color.ember.opacity(0.65), radius: 18, y: 8)
                    .shadow(color: Color.ember.opacity(0.3), radius: 36, y: 14)

                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            .scaleEffect(pressed ? 0.92 : (appeared ? 1.0 : 0.6))
            .opacity(appeared ? 1 : 0)
            .animation(FDS.Spring.snap, value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true  }
                .onEnded   { _ in pressed = false }
        )
        .onAppear {
            withAnimation(FDS.Spring.floaty.delay(0.8)) { appeared = true }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { outerPulse = true }
            withAnimation(.easeInOut(duration: FDS.Duration.breathe).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// ============================================================
// MARK: - Helpers
// ============================================================

// readinessColor and readinessLabel are defined in Theme.swift
// These are local fallbacks if not available
private func readinessColor(_ score: Int) -> Color {
    switch score {
    case 85...:  return Color(hex: "22C55E")
    case 70..<85: return Color.ember
    case 50..<70: return Color.steel
    default:      return Color(hex: "EF4444")
    }
}

private func readinessLabel(_ score: Int) -> String {
    switch score {
    case 85...:  return "Peak"
    case 70..<85: return "Good"
    case 50..<70: return "Fair"
    default:      return "Low"
    }
}
