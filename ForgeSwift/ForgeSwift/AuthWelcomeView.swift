import SwiftUI
import UIKit
import ForgeCore

// MARK: - Auth Welcome — premium Day 0 (Oura / Whoop–class)

/// Soft first gate: calm carousel → identity → account → ARIA interview.
/// No rage-fire. Presence is light, typography, and negative space.
struct AuthWelcomeView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var page = 0
    @State private var appeared = false
    @State private var showSignIn = false
    @State private var showSignUp = false
    @State private var autoAdvanceTask: Task<Void, Never>?

    private let pages = AuthHookPage.all

    var body: some View {
        ZStack {
            PremiumAtmosphere(
                accent: pages[safe: page]?.accent ?? .ember,
                secondary: pages[safe: page]?.frost ?? HudChrome.plate
            )

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, ForgeLayout.screenInset)
                    .padding(.top, ForgeLayout.screenTop)
                    .premiumEntrance(index: 0, appeared: appeared)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, hook in
                        AuthHookPageView(page: hook, isActive: page == index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(FDS.Spring.page, value: page)
                .onChange(of: page) { _, _ in
                    FDS.selectionHaptic()
                    scheduleAutoAdvance()
                }

                bottomDock
                    .premiumEntrance(index: 2, appeared: appeared)
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
            withAnimation(reduceMotion ? nil : FDS.Spring.hero.delay(0.05)) { appeared = true }
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
        HStack(spacing: FDS.Spacing.md) {
            HStack(spacing: FDS.Spacing.sm) {
                ForgeBrandMark(size: 18)
                Text("Forge")
                    .font(HomeType.status)
                    .foregroundColor(.textPrimary)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }
            Spacer(minLength: FDS.Spacing.sm)
            AriaSpokenMuteButton()
            signInButton
        }
    }

    private var signInButton: some View {
        Button {
            FDS.haptic(.press)
            showSignIn = true
        } label: {
            Text("Sign in")
                .font(HomeType.label)
                .foregroundColor(.textPrimary)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                .padding(.horizontal, FDS.Spacing.sm)
                .frame(minHeight: ForgeUX.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .accessibilityLabel("Sign in")
    }

    private var progress: some View {
        PremiumProgressDots(count: pages.count, current: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(page + 1) of \(pages.count)")
    }

    private var bottomDock: some View {
        VStack(spacing: ForgeLayout.blockGap) {
            progress
            ctaBlock
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.bottom, FDS.Spacing.sm)
    }

    private var ctaBlock: some View {
        VStack(spacing: ForgeLayout.tileGap) {
            PremiumPrimaryButton(title: "Get started") {
                FDS.haptic(.medium)
                showSignUp = true
            }

            if page < pages.count - 1 {
                Button {
                    FDS.haptic(.press)
                    withAnimation(reduceMotion ? nil : FDS.Spring.page) {
                        page = min(pages.count - 1, page + 1)
                    }
                } label: {
                    Text("See how it works")
                        .font(HomeType.body)
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: ForgeUX.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Text("Lifestyle fitness coaching · Live your best life")
                    .font(HomeType.micro)
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func scheduleAutoAdvance() {
        autoAdvanceTask?.cancel()
        guard !reduceMotion, !UIAccessibility.isVoiceOverRunning, page < pages.count - 1 else { return }
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
            icon: "text.bubble",
            accent: Color.ember,
            frost: HudChrome.plate,
            reward: "A coach who already knows you"
        ),
        AuthHookPage(
            id: "readiness",
            kicker: "Train on signal",
            title: "Know when to push or protect.",
            body: "ARIA turns your metrics into a plan that fits today. Progress compounds day to day — each session intentional, never a burden.",
            icon: "waveform.path.ecg",
            accent: Color.steel,
            frost: HudChrome.plate,
            reward: "Sessions that match how you feel"
        ),
        AuthHookPage(
            id: "life",
            kicker: "Built around your life",
            title: "Workouts, lifestyle, and cycle rhythm.",
            body: "Sleep, nutrition, free time, and how you show up for people you love — one private control center that respects the life you already have.",
            icon: "leaf.fill",
            accent: Color.success,
            frost: HudChrome.plate,
            reward: "Private by design"
        ),
        AuthHookPage(
            id: "forge",
            kicker: "Start today",
            title: "Forge starts with one choice.",
            body: "Name your goal and how you want to train. Connect Health if you want. Walk out with a first plan and a coach that already knows you.",
            icon: "text.bubble",
            accent: Color.paper,
            frost: Color.ember,
            reward: "Meet ARIA →"
        ),
    ]
}

private struct AuthHookPageView: View {
    let page: AuthHookPage
    let isActive: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        pageLayout
            .opacity(isActive ? 1 : 0.4)
            .scaleEffect(isActive ? 1 : 0.97)
            .animation(FDS.Spring.standard, value: isActive)
            .onChange(of: isActive) { _, active in
                guard page.id == "aria", !active else { return }
                AriaPresence.shared.stopSpeaking()
            }
    }

    /// Full page when it fits, copy only when it does not, and a scrolling
    /// copy-only page at accessibility sizes or on the smallest phones.
    @ViewBuilder
    private var pageLayout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            scrollingCopyPage
        } else {
            ViewThatFits(in: .vertical) {
                fullPage
                copyPage
                scrollingCopyPage
            }
        }
    }

    private var fullPage: some View {
        VStack(spacing: ForgeLayout.groupBreak) {
            Spacer(minLength: FDS.Spacing.sm)
            visual
                .frame(height: 220)
                .scaleEffect(isActive ? 1 : 0.96)
            copyBlock
            Spacer(minLength: FDS.Spacing.xs)
        }
    }

    private var copyPage: some View {
        VStack(spacing: ForgeLayout.groupBreak) {
            Spacer(minLength: FDS.Spacing.sm)
            copyBlock
            Spacer(minLength: FDS.Spacing.xs)
        }
    }

    private var scrollingCopyPage: some View {
        ScrollView(showsIndicators: false) {
            copyBlock
                .padding(.vertical, FDS.Spacing.lg)
        }
    }

    private var copyBlock: some View {
        VStack(spacing: ForgeLayout.blockGap) {
            VStack(spacing: ForgeLayout.pairGap) {
                Text(page.kicker)
                    .forgeSectionLabel()
                    .multilineTextAlignment(.center)

                Text(page.title)
                    .font(FDS.TypeScale.Dynamic.pageTitle)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .minimumScaleFactor(0.85)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(page.body)
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .forgeWrapping()

            Text(page.reward)
                .font(HomeType.label)
                .foregroundColor(page.id == "forge" ? Color.ember : Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, ForgeLayout.screenInset)
    }

    @ViewBuilder
    private var visual: some View {
        if page.id == "aria" {
            ariaVisual
        } else {
            iconVisual
        }
    }

    private var ariaVisual: some View {
        Button {
            FDS.haptic(.soft)
            AriaPresence.shared.speak(AriaOnboardingGuide.welcomeSpokenLine, interrupt: true)
        } label: {
            VStack(spacing: FDS.Spacing.sm) {
                ZStack {
                    PremiumPresenceBloom(size: 170, accent: page.accent, frost: page.frost, live: false)
                    AuroraOrbView(
                        state: .idle,
                        amplitude: 0.55,
                        mood: .energized,
                        size: 120,
                        followPresence: true
                    )
                }
                .frame(width: 190, height: 190)

                Text("ARIA")
                    .forgeSectionLabel(tint: Color.paper.opacity(0.72))
                    .accessibilityHidden(true)
            }
            .frame(minWidth: ForgeUX.minTap, minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hear ARIA")
        .accessibilityHint("Plays her welcome line")
    }

    private var iconVisual: some View {
        ZStack {
            PremiumPresenceBloom(size: 170, accent: page.accent, frost: page.frost, live: false)
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .frame(width: 112, height: 112)
            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 96, height: 96)
            Image(systemName: page.icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(iconGradient)
        }
        .frame(width: 190, height: 190)
        .accessibilityHidden(true)
    }

    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: [Color.paper, page.accent.opacity(0.9)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
