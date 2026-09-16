import SwiftUI
import ForgeCore

// MARK: - Auth Welcome — premium Day 0 (Oura / Whoop–class)

/// Soft first gate: calm carousel → identity → account → ARIA interview.
/// No rage-fire. Presence is light, typography, and negative space.
struct AuthWelcomeView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var page = 0
    @State private var appeared = false
    @State private var showSignIn = false
    @State private var showSignUp = false
    @State private var floatPhase: CGFloat = 0
    @State private var autoAdvanceTask: Task<Void, Never>?

    private let pages = AuthHookPage.all

    var body: some View {
        ZStack {
            PremiumAtmosphere(
                accent: pages[safe: page]?.accent ?? .ember,
                secondary: pages[safe: page]?.frost ?? Color(hex: "A9D8FF")
            )

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .opacity(appeared ? 1 : 0)

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

                VStack(spacing: 18) {
                    progress
                    ctaBlock
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .safeAreaPadding(.bottom, 8)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
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
                withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                    floatPhase = 1
                }
            }
            scheduleAutoAdvance()
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
            AriaPresence.shared.stopSpeaking()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { AriaPresence.shared.stopSpeaking() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                ForgeBrandMark(size: 18)
                Text("Forge")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tracking(0.6)
                    .foregroundColor(.textPrimary)
            }
            Spacer()
            AriaSpokenMuteButton()
            Button {
                FDS.haptic(.light)
                showSignIn = true
            } label: {
                Text("Sign in")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.textPrimary.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var progress: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color(hex: "F7F4F0") : Color.white.opacity(0.16))
                        .frame(width: i == page ? 20 : 6, height: 4)
                        .animation(FDS.Spring.snap, value: page)
                }
            }
            Text("\(page + 1) of \(pages.count)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
        }
    }

    private var ctaBlock: some View {
        VStack(spacing: 14) {
            PremiumPrimaryButton(title: "Get started") {
                FDS.haptic(.medium)
                showSignUp = true
            }

            if page < pages.count - 1 {
                Button {
                    FDS.haptic(.light)
                    withAnimation(FDS.Spring.page) {
                        page = min(pages.count - 1, page + 1)
                    }
                } label: {
                    Text("See how it works")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            Text("Lifestyle fitness coaching · Live your best life")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    private func scheduleAutoAdvance() {
        autoAdvanceTask?.cancel()
        guard !reduceMotion, page < pages.count - 1 else { return }
        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_800_000_000)
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
    let accent: Color
    let frost: Color
    let reward: String

    static let all: [AuthHookPage] = [
        AuthHookPage(
            id: "aria",
            kicker: "Meet your coach",
            title: AriaOnboardingGuide.welcomeTitle,
            body: "ARIA is an adaptive lifestyle coach — present for readiness, sleep, and the session you'd skip. Small moves compound. You still decide.",
            icon: "sparkles",
            accent: Color(hex: "FF6B2B"),
            frost: Color(hex: "A9D8FF"),
            reward: "A coach who already knows you"
        ),
        AuthHookPage(
            id: "readiness",
            kicker: "Train on signal",
            title: "Know when to push or protect.",
            body: "ARIA turns your metrics into a plan that fits today. Progress compounds day to day — each session intentional, never a burden.",
            icon: "waveform.path.ecg",
            accent: Color(hex: "60A5FA"),
            frost: Color(hex: "A9D8FF"),
            reward: "Sessions that match how you feel"
        ),
        AuthHookPage(
            id: "life",
            kicker: "Built around your life",
            title: "Workouts, lifestyle, and cycle rhythm.",
            body: "Sleep, nutrition, free time, and how you show up for people you love — one private control center that respects the life you already have.",
            icon: "leaf.fill",
            accent: Color(hex: "34D399"),
            frost: Color(hex: "A9D8FF"),
            reward: "Private by design"
        ),
        AuthHookPage(
            id: "forge",
            kicker: "Start today",
            title: "Forge starts with one choice.",
            body: "Name your goal and how you want to train. Connect Health if you want. Walk out with a first plan and a coach that already knows you.",
            icon: "sparkles",
            accent: Color(hex: "F7F4F0"),
            frost: Color(hex: "FF6B2B"),
            reward: "Meet ARIA →"
        ),
    ]
}

private struct AuthHookPageView: View {
    let page: AuthHookPage
    let isActive: Bool
    let floatPhase: CGFloat

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)

            visual
                .frame(height: 200)
                .scaleEffect(isActive ? 1.0 + floatPhase * 0.01 : 0.96)
                .onChange(of: isActive) { _, active in
                    guard page.id == "aria" else { return }
                    if !active { AriaPresence.shared.stopSpeaking() }
                }

            VStack(spacing: 14) {
                Text(page.kicker)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .tracking(2.4)
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)

                Text(page.title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .minimumScaleFactor(0.88)

                Text(page.body)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)

                if page.id == "forge" {
                    Text(page.reward)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color.ember.opacity(0.9))
                        .padding(.top, 2)
                } else {
                    Text(page.reward)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 4)
        }
        .opacity(isActive ? 1 : 0.45)
        .animation(FDS.Spring.standard, value: isActive)
    }

    @ViewBuilder
    private var visual: some View {
        if page.id == "aria" {
            Button {
                FDS.haptic(.soft)
                AriaPresence.shared.speak(AriaOnboardingGuide.welcomeSpokenLine, interrupt: true)
            } label: {
                VStack(spacing: 12) {
                    ZStack {
                        PremiumPresenceBloom(size: 210, accent: page.accent, frost: page.frost)
                        AuroraOrbView(
                            state: .idle,
                            amplitude: 0.55,
                            mood: .energized,
                            size: 148,
                            followPresence: true
                        )
                    }
                    Text("ARIA")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(3.2)
                        .foregroundColor(Color(hex: "F7F4F0").opacity(0.72))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hear ARIA")
            .accessibilityHint("Plays her welcome line")
        } else {
            ZStack {
                PremiumPresenceBloom(size: 180, accent: page.accent, frost: page.frost, live: isActive)
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    .frame(width: 112, height: 112)
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 96, height: 96)
                Image(systemName: page.icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "F7F4F0"), page.accent.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .offset(y: isActive ? -floatPhase * 4 : 0)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Auth welcome") {
    AuthWelcomeView()
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}
