import SwiftUI
import UIKit
import ForgeCore

// MARK: - Auth Welcome — premium Day 0 (Oura / Whoop–class)

/// Soft first gate: calm carousel → identity → account → ARIA interview.
/// Each page plays one hammer-and-flame beat, then holds. The beat replays
/// whenever that page is the one on screen.
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
    /// Bumps when the welcome screen is shown again, so the current beat replays.
    @State private var strikeSeed = 0
    @State private var welcomeWasBackgrounded = false

    private let pages = AuthHookPage.all

    var body: some View {
        ZStack {
            PremiumAtmosphere(
                accent: pages[safe: page]?.accent ?? .ember,
                secondary: pages[safe: page]?.frost ?? ForgeProgressChrome.plate
            )

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, ForgeLayout.screenInset)
                    .padding(.top, ForgeLayout.screenTop)
                    .premiumEntrance(index: 0, appeared: appeared)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, hook in
                        AuthHookPageView(page: hook, isActive: page == index, replaySeed: strikeSeed)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .forgeAnimation(ForgeMotion.smooth, value: page)
                .onChange(of: page) { _, _ in
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
            strikeSeed += 1
            withAnimation(reduceMotion ? nil : ForgeMotion.gentle.delay(0.05)) { appeared = true }
            scheduleAutoAdvance()
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
            AriaPresence.shared.stopSpeaking()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if welcomeWasBackgrounded {
                    strikeSeed += 1
                }
                welcomeWasBackgrounded = false
            } else {
                welcomeWasBackgrounded = true
                AriaPresence.shared.stopSpeaking()
            }
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
                showSignUp = true
            }

            if page < pages.count - 1 {
                Button {
                    withAnimation(reduceMotion ? nil : ForgeMotion.smooth) {
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
            withForgeMotion(ForgeMotion.smooth) {
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
    let variation: ForgeStrikeVariation
    let accent: Color
    let frost: Color
    let reward: String

    static let all: [AuthHookPage] = [
        AuthHookPage(
            id: "aria",
            kicker: "Meet your coach",
            title: AriaOnboardingGuide.welcomeTitle,
            body: "ARIA is an adaptive lifestyle coach — present for readiness, sleep, and the session you'd skip. Small moves compound. You still decide.",
            variation: .strike,
            accent: Color.ember,
            frost: ForgeProgressChrome.plate,
            reward: "A coach who already knows you"
        ),
        AuthHookPage(
            id: "readiness",
            kicker: "Train on signal",
            title: "Know when to push or protect.",
            body: "ARIA turns your metrics into a plan that fits today. Progress compounds day to day — each session intentional, never a burden.",
            variation: .quench,
            accent: Color.steel,
            frost: ForgeProgressChrome.plate,
            reward: "Sessions that match how you feel"
        ),
        AuthHookPage(
            id: "life",
            kicker: "Built around your life",
            title: "Workouts, lifestyle, and cycle rhythm.",
            body: "Sleep, nutrition, free time, and how you show up for people you love — one private control center that respects the life you already have.",
            variation: .spark,
            accent: Color.success,
            frost: ForgeProgressChrome.plate,
            reward: "Private by design"
        ),
        AuthHookPage(
            id: "forge",
            kicker: "Start today",
            title: "Forge starts with one choice.",
            body: "Name your goal and how you want to train. Connect Health if you want. Walk out with a first plan and a coach that already knows you.",
            variation: .temper,
            accent: Color.paper,
            frost: Color.ember,
            reward: "Meet ARIA →"
        ),
    ]
}

private struct AuthHookPageView: View {
    let page: AuthHookPage
    let isActive: Bool
    var replaySeed: Int = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var replay = 0

    var body: some View {
        pageLayout
            .opacity(isActive ? 1 : 0.4)
            .scaleEffect(isActive ? 1 : 0.97)
            .forgeAnimation(ForgeMotion.smooth, value: isActive)
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
                .frame(height: page.id == "aria" ? 268 : 224)
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

    private var visual: some View {
        VStack(spacing: FDS.Spacing.xs) {
            ForgeStrikeMark(
                variation: page.variation,
                isActive: isActive,
                replayToken: replay &+ replaySeed
            )
            .frame(width: 240, height: 188)
            .contentShape(Rectangle())
            .onTapGesture { replay += 1 }
            .accessibilityElement()
            .accessibilityLabel(page.variation.accessibilityLabel)
            .accessibilityHint("Replays this strike")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { replay += 1 }

            Text(page.variation.title)
                .font(ForgeType.micro)
                .tracking(1.6)
                .foregroundColor(.textTertiary)
                .accessibilityHidden(true)

            if page.id == "aria" {
                hearAria
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var hearAria: some View {
        Button {
            AriaPresence.shared.speak(AriaOnboardingGuide.welcomeSpokenLine, interrupt: true)
        } label: {
            Text("Hear ARIA")
                .font(HomeType.label)
                .foregroundColor(.textSecondary)
                .frame(minHeight: ForgeUX.minTap)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hear ARIA")
        .accessibilityHint("Plays her welcome line")
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
