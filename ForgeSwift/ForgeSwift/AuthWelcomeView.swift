import SwiftUI

// MARK: - Auth Welcome — cinematic Day 0

/// Immersive first gate: story carousel → forge identity → account → ARIA interview.
struct AuthWelcomeView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var appeared = false
    @State private var showSignIn = false
    @State private var showSignUp = false
    @State private var ringPulse = false
    @State private var floatPhase: CGFloat = 0
    @State private var autoAdvanceTask: Task<Void, Never>?

    private let pages = AuthHookPage.all

    var body: some View {
        ZStack {
            AuthCinematicBackground(page: page)
                .ignoresSafeArea()

            // Floating embers
            if !reduceMotion, appeared {
                AuthEmberField()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                // Top brand strip
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(FDS.Gradient.ember)
                        Text("Forge")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .tracking(3)
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                    Button {
                        FDS.haptic(.light)
                        showSignIn = true
                    } label: {
                        Text("Sign in")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.ember)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.ember.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .opacity(appeared ? 1 : 0)

                // Story carousel
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, hook in
                        AuthHookPageView(page: hook, isActive: page == index, floatPhase: floatPhase)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(FDS.Spring.page, value: page)
                .onChange(of: page) { _, _ in
                    FDS.selectionHaptic()
                    scheduleAutoAdvance()
                }

                // Progress dots + chapter label
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Capsule()
                                .fill(i == page ? Color.ember : Color.white.opacity(0.18))
                                .frame(width: i == page ? 22 : 7, height: 7)
                                .animation(FDS.Spring.snap, value: page)
                        }
                    }

                    Text("CHAPTER \(page + 1) OF \(pages.count)")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.6)
                        .foregroundColor(.textTertiary)
                }
                .padding(.bottom, 18)

                // Primary CTAs
                VStack(spacing: 12) {
                    Button {
                        FDS.haptic(.heavy)
                        showSignUp = true
                    } label: {
                        HStack(spacing: 10) {
                            Text("Get started")
                                .font(.system(size: 17, weight: .bold))
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                        .background {
                            ZStack {
                                FDS.Gradient.ember
                                LinearGradient.premiumChrome
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                        .shadow(color: Color.ember.opacity(0.5), radius: 22, y: 10)
                    }
                    .buttonStyle(AuthPressButtonStyle())
                    .accessibilityLabel("Get started")

                    if page < pages.count - 1 {
                        Button {
                            FDS.haptic(.light)
                            withAnimation(FDS.Spring.page) {
                                page = min(pages.count - 1, page + 1)
                            }
                        } label: {
                            Text("See how it works")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Lifestyle fitness coaching · Live your best life")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 36)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
            }
        }
        .sheet(isPresented: $showSignIn) {
            AuthSignInView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showSignUp) {
            AuthSignUpFlowView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true }
            if !reduceMotion {
                withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                    ringPulse = true
                }
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    floatPhase = 1
                }
            }
            scheduleAutoAdvance()
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
        }
    }

    private func scheduleAutoAdvance() {
        autoAdvanceTask?.cancel()
        guard !reduceMotion, page < pages.count - 1 else { return }
        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(FDS.Spring.page) {
                page = min(pages.count - 1, page + 1)
            }
        }
    }
}

// MARK: - Hook content

private struct AuthHookPage: Identifiable {
    let id: String
    let kicker: String
    let title: String
    let body: String
    let icon: String
    let accentHex: String
    let reward: String

    static let all: [AuthHookPage] = [
        AuthHookPage(
            id: "aria",
            kicker: "MEET YOUR COACH",
            title: "ARIA is already listening.",
            body: "ARIA is an adaptive lifestyle coach, not a commander. She works with the life you already have — readiness, sleep, wearables — and raises quality of life the way compound interest works. Enough small moves and one day life is slightly different. Over time you see it and appreciate it. You still decide.",
            icon: "sparkles",
            accentHex: "FF5A00",
            reward: "A coach who already knows you"
        ),
        AuthHookPage(
            id: "readiness",
            kicker: "TRAIN ON SIGNAL",
            title: "Know when to push or protect.",
            body: "ARIA takes standardized metrics and creates a standardized plan that's best for you. All your stats are saved daily so you don't erase progress but rather you build on it the next day. Everytime you use ARIA it feels intentional not like its a burden.",
            icon: "waveform.path.ecg",
            accentHex: "38BDF8",
            reward: "Sessions that match how you feel"
        ),
        AuthHookPage(
            id: "life",
            kicker: "Workout based on your lifestyle.",
            title: "Workouts, lifestyle, and cycle rhythm.",
            body: "ARIA looks into how you eat and sleep, but it also seeks to learn more about how you spend your free time, how you provide support to those you love in their time of need — one control center and its private by design.",
            icon: "leaf.fill",
            accentHex: "22C55E",
            reward: "Private by design"
        ),
        AuthHookPage(
            id: "forge",
            kicker: " Start Today",
            title: "Forge starts with one choice.",
            body: "It doesn't take long. Name your goal and how you want to train. Connect Health if you want and walk out with a first plan and a coach that already knows you.",
            icon: "flame.fill",
            accentHex: "F59E0B",
            reward: "Meet ARIA →"
        ),
    ]
}

private struct AuthHookPageView: View {
    let page: AuthHookPage
    let isActive: Bool
    let floatPhase: CGFloat

    private var accent: Color { Color(hex: page.accentHex) }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 160, height: 160)
                    .blur(radius: 24)
                    .scaleEffect(isActive ? 1.05 + floatPhase * 0.04 : 0.92)
                Circle()
                    .stroke(accent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(0.45), accent.opacity(0.08), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 70
                        )
                    )
                    .frame(width: 110, height: 110)
                Image(systemName: page.icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: accent.opacity(0.6), radius: 12, y: 4)
                    .offset(y: isActive ? -floatPhase * 6 : 0)
            }
            .frame(height: 170)

            VStack(spacing: 12) {
                Text(page.kicker)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2.2)
                    .foregroundStyle(accent)

                Text(page.title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color.white.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .minimumScaleFactor(0.85)

                Text(page.body)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(page.reward)
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(accent.opacity(0.12))
                .clipShape(Capsule())
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 8)
        }
        .opacity(isActive ? 1 : 0.55)
        .scaleEffect(isActive ? 1 : 0.96)
        .animation(FDS.Spring.standard, value: isActive)
    }
}

// MARK: - Background + particles

private struct AuthCinematicBackground: View {
    let page: Int

    private var accent: Color {
        Color(hex: AuthHookPage.all[min(page, AuthHookPage.all.count - 1)].accentHex)
    }

    var body: some View {
        ZStack {
            Color.background
            RadialGradient(
                colors: [accent.opacity(0.22), Color.ember.opacity(0.08), .clear],
                center: UnitPoint(x: 0.5, y: 0.18),
                startRadius: 10,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.steel.opacity(0.08), .clear],
                center: UnitPoint(x: 0.9, y: 0.85),
                startRadius: 8,
                endRadius: 280
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.35)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .animation(.easeInOut(duration: 0.55), value: page)
    }
}

private struct AuthEmberField: View {
    @State private var t: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<18 {
                    let seed = Double(i) * 17.13
                    let x = (sin(time * 0.35 + seed) * 0.5 + 0.5) * size.width
                    let y = size.height - CGFloat((time * (12 + Double(i % 5)) + seed * 40)
                        .truncatingRemainder(dividingBy: Double(size.height + 40)))
                    let r = CGFloat(1.5 + Double(i % 3))
                    var path = Path()
                    path.addEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
                    context.fill(path, with: .color(Color.ember.opacity(0.15 + Double(i % 4) * 0.05)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct AuthPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(FDS.Spring.snap, value: configuration.isPressed)
    }
}
