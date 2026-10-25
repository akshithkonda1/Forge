import SwiftUI
import ForgeCore

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Once per process — recreating this view must not put the splash back
    /// on top of Home and eat taps.
    @State private var showSplash = !Self.didFinishSplash
    /// Bound after first paint. Touching `AriaNeuralVoiceGate.shared` from
    /// `body` blocked the first frame on the voice catalog XPC.
    @State private var neuralVoiceGate: AriaNeuralVoiceGate?
    private static var didFinishSplash = false

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
            .environment(\.forgeWelcomeCovered, showSplash)
            .animation(ForgeMotion.crossfade, value: store.isAuthenticated)
            .animation(ForgeMotion.crossfade, value: store.isOnboarded)

            if showSplash {
                ForgeSplashScreen(signedIn: splashSignedIn)
                    .transition(.opacity)
                    .zIndex(999)
                    // Decorative: keep VoiceOver off "FORGE" / "Forged." as it fades.
                    .accessibilityHidden(true)
                    // Never block Home if the hide animation stalls.
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: neuralPromptBinding) {
            if let neuralVoiceGate {
                AriaNeuralVoiceSheet(gate: neuralVoiceGate)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                neuralVoiceGate?.refreshCatalog()
            }
        }
        .task {
            let gate = AriaNeuralVoiceGate.shared
            neuralVoiceGate = gate
            gate.refreshCatalog()
            guard showSplash else { return }
            try? await Task.sleep(
                nanoseconds: ForgeSplashTiming.pauseNanoseconds(
                    reduceMotion: reduceMotion,
                    signedIn: splashSignedIn
                )
            )
            Self.didFinishSplash = true
            withAnimation(.easeOut(duration: ForgeSplashTiming.fadeOut)) {
                showSplash = false
            }
        }
    }

    /// Existing auth tree only: AppStore flag, restored from `ForgeAuthClient`.
    private var splashSignedIn: Bool {
        store.isAuthenticated || ForgeAuthClient.shared.session != nil
    }

    private var neuralPromptBinding: Binding<Bool> {
        Binding(
            get: { neuralVoiceGate?.showPrompt ?? false },
            set: { neuralVoiceGate?.showPrompt = $0 }
        )
    }
}

// MARK: - Splash Screen

struct ForgeSplashScreen: View {
    /// Already-authenticated users get a trimmed beat: static flame, no swing.
    var signedIn: Bool = false
    @State private var logoOpacity: Double = 0
    @State private var textOffset: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PremiumAtmosphere(
                accent: ForgePalette.ember,
                secondary: Color(hex: "A9D8FF"),
                intensity: 1,
                loopMotion: false
            )

            VStack(spacing: FDS.Spacing.lg) {
                ForgeStrikeMark(
                    variation: .strike,
                    duration: ForgeStrikeGeometry.splashDuration,
                    playback: signedIn ? .trimmed : .full
                )
                .frame(width: 240, height: 200)

                VStack(spacing: FDS.Spacing.md) {
                    HStack(spacing: FDS.Spacing.md) {
                        ForgeBrandMark(size: 22)
                        Text("FORGE")
                            .font(ForgeType.display)
                            .tracking(6)
                            .foregroundColor(Color.paper)
                    }

                    Text("Forged.")
                        .font(ForgeType.micro)
                        .tracking(ForgeType.eyebrowTracking)
                        .foregroundColor(.textTertiary)
                }
                .opacity(logoOpacity)
                .offset(y: textOffset)
            }
        }
        .task {
            // One rigid tap as the hammer lands. Off under Reduce Motion
            // (static pose) and on the signed-in trim (no swing).
            guard !reduceMotion, !signedIn else { return }
            try? await Task.sleep(nanoseconds: UInt64(ForgeStrikeGeometry.splashImpactTime * 1_000_000_000))
            guard !Task.isCancelled else { return }
            ForgeHaptics.playStrike()
        }
        .onAppear {
            let base: Animation = reduceMotion
                ? .easeOut(duration: 0.25)
                : ForgeMotion.gentle
            withAnimation(base.delay(0.12)) {
                logoOpacity = 1
                textOffset = 0
            }
        }
    }
}

#Preview("Forge splash") {
    ForgeSplashScreen()
        .preferredColorScheme(.dark)
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
    @State private var showClinicalData = false
    @State private var cycleInitialPane: MenstrualHealthView.Pane = .me
    @ObservedObject private var wakeStore = SleepWakeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The nav hides while the keyboard is up, as the system tab bar does.
    @State private var keyboardVisible = false

    private var waitingToMeetAria: Bool {
        // Only on the ARIA tab. Covering Home from launch left the splash
        // and meet sheet stacked and made the page look frozen.
        !store.hasMetAria && store.activeTab == .chat
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Shell canvas: the shared screen atmosphere (tabs paint their own on top).
            Color.clear
                .ignoresSafeArea()
                .forgeScreenBackground(accent: .ember)

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
            .animation(ForgeMotion.crossfade, value: store.activeTab)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !waitingToMeetAria && !keyboardVisible {
                    ForgeBottomNav(namespace: namespace)
                }
            }

            if waitingToMeetAria {
                AriaMeetView(
                    onTalk: {
                        store.meetAria()
                        store.activeTab = .chat
                    },
                    onSkip: {
                        store.meetAria()
                        store.activeTab = .home
                    }
                )
                .zIndex(40)
            }

            if store.isOnboarded && !waitingToMeetAria {
                ForgeTutorialCoach()
                    .zIndex(30)
            }
        }
        .onChange(of: store.activeTab) { _, tab in
            switch tab {
            case .home: store.recordTutorial(.openedHome)
            case .sleep: store.recordTutorial(.openedSleep)
            case .progress: store.recordTutorial(.openedProgress)
            case .workout: store.recordTutorial(.openedTrain)
            case .lifestyle: store.recordTutorial(.openedLifestyle)
            case .profile: store.recordTutorial(.openedSettings)
            case .chat: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onChange(of: store.pendingCycleHealthOpen) { _, open in
            guard open else { return }
            presentCycleHealth()
        }
        .onChange(of: store.pendingHydrationOpen) { _, open in
            guard open else { return }
            presentHydration()
        }
        .onChange(of: store.pendingClinicalOpen) { _, open in
            guard open else { return }
            presentClinical()
        }
        .onAppear {
            if store.pendingCycleHealthOpen {
                presentCycleHealth()
            }
            if store.pendingHydrationOpen {
                presentHydration()
            }
            if store.pendingClinicalOpen {
                presentClinical()
            }
        }
        .fullScreenCover(isPresented: $showCycleHealth) {
            NavigationStack {
                MenstrualHealthView(initialPane: cycleInitialPane)
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            ShellCoverCloseButton(label: "Close Cycle Health") {
                                showCycleHealth = false
                            }
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showClinicalData) {
            ClinicalDataNonPHIView()
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showHydration) {
            NavigationStack {
                HydrationView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            ShellCoverCloseButton(label: "Close Hydration") {
                                showHydration = false
                            }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { wakeStore.isRinging },
            set: { if !$0 { wakeStore.dismiss() } }
        )) {
            SleepWakeScreen()
                .environmentObject(store)
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

    private func presentClinical() {
        showClinicalData = true
        store.pendingClinicalOpen = false
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

// MARK: - Cover close button

/// One close control for the shell's full-screen covers: a 44 pt target
/// around the 22 pt glyph.
private struct ShellCoverCloseButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.textSecondary)
                .frame(minWidth: ForgeUX.minTap, minHeight: ForgeUX.minTap)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Tab bar style

/// Shared look for all seven tabs: one fixed label font (the documented
/// tab-bar exception, with the Large Content Viewer standing in for scaling),
/// one inactive color, ember selection with no glow.
private enum ShellTabStyle {
    static let labelFont = ForgeFont.sans(10, weight: .semibold)
    static let labelTracking: CGFloat = 0.2
    static let rowHeight: CGFloat = 48
    static let iconSlotHeight: CGFloat = 26
    static let inactive = Color.textSecondary
    static let active = Color.ember
}

// MARK: - Bottom Navigation

struct ForgeBottomNav: View {
    @EnvironmentObject var store: AppStore
    var namespace: Namespace.ID

    /// Home · Train · Life · ARIA (center) · Sleep · Stats · You
    private let tabs: [TabItem] = [.home, .workout, .lifestyle, .chat, .sleep, .progress, .profile]

    private var barShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: FDS.Radius.xl,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: FDS.Radius.xl,
            style: .continuous
        )
    }

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
        // The home-indicator safe area already pads the bottom.
        .padding(.top, FDS.Spacing.xs)
        .padding(.bottom, 0)
        .accessibilityElement(children: .contain)
        .background { barBackground }
    }

    private var barBackground: some View {
        ZStack(alignment: .top) {
            barShape.fill(.ultraThinMaterial)
            barShape.fill(Color.background.opacity(0.62))
            Rectangle()
                .fill(Color.borderHairline)
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Regular Tab Button

struct RegularForgeTab: View {
    let tab: TabItem
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool { store.activeTab == tab }
    private var tint: Color { isActive ? ShellTabStyle.active : ShellTabStyle.inactive }

    var body: some View {
        Button {
            ForgeHaptics.play(.selection)
            withAnimation(reduceMotion ? nil : ForgeMotion.snappy) {
                store.activeTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                iconSlot
                Text(tab.shortLabel)
                    .font(ShellTabStyle.labelFont)
                    .tracking(ShellTabStyle.labelTracking)
                    .lineLimit(1)
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: ShellTabStyle.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityInputLabels([tab.shortLabel, tab.label])
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(tab.shortLabel, systemImage: isActive ? tab.systemImageFilled : tab.systemImage)
        }
    }

    /// Selection reads by color, the filled symbol and the sliding bar. No glow, no scale.
    private var iconSlot: some View {
        ZStack(alignment: .bottom) {
            Image(systemName: isActive ? tab.systemImageFilled : tab.systemImage)
                .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .frame(height: ShellTabStyle.iconSlotHeight)
            if isActive {
                Capsule()
                    .fill(FDS.Gradient.ember)
                    .frame(width: 14, height: 2.5)
                    .offset(y: 2)
                    .matchedGeometryEffect(id: "tab-dot", in: namespace)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - ARIA Center Button (Chat + Voice toggle)

struct ARIATabButton: View {
    var namespace: Namespace.ID
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool { store.activeTab == .chat }
    private var isVoiceMode: Bool { store.ariaVoiceMode }
    private var title: String { isVoiceMode ? "Voice" : "ARIA" }

    var body: some View {
        Button {
            ForgeHaptics.play(.selection)
            withAnimation(reduceMotion ? nil : ForgeMotion.snappy) {
                store.activeTab = .chat
            }
        } label: {
            VStack(spacing: 3) {
                orb
                Text(title)
                    .font(ShellTabStyle.labelFont)
                    .tracking(ShellTabStyle.labelTracking)
                    .lineLimit(1)
                    .foregroundStyle(isActive ? ShellTabStyle.active : ShellTabStyle.inactive)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: ShellTabStyle.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.55) {
            toggleVoiceMode()
        }
        .accessibilityLabel(isVoiceMode ? "ARIA Voice" : "ARIA")
        .accessibilityHint("Long-press to switch voice mode")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAction(named: isVoiceMode ? "Switch to chat" : "Switch to voice") {
            toggleVoiceMode()
        }
        .accessibilityShowsLargeContentViewer {
            Label(title, systemImage: "text.bubble")
        }
    }

    /// 32 pt mark in the same 26 pt slot as the other tabs' icons, so every
    /// label sits on one baseline. No backdrop wash.
    private var orb: some View {
        ZStack {
            ARIAIdentityMark(
                state: isVoiceMode ? .listening : .idle,
                mood: isVoiceMode ? .focused : .energized,
                size: 32,
                amplitude: isVoiceMode ? 0.4 : 0.2
            )
            .environment(\.forgeMinimalAnimation, !isActive && !isVoiceMode)
        }
        .frame(height: ShellTabStyle.iconSlotHeight)
        .accessibilityHidden(true)
    }

    private func toggleVoiceMode() {
        ForgeHaptics.play(.press)
        withAnimation(reduceMotion ? nil : ForgeMotion.snappy) {
            store.ariaVoiceMode.toggle()
            store.activeTab = .chat
            store.ariaVoiceLaunch = store.ariaVoiceMode
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
