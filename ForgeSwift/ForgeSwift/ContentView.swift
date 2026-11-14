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
    @State private var splashBlocksHits = !Self.didFinishSplash
    /// Mount the app chrome on the next turn so the splash's first frame
    /// is only the matched launch field + strike, not AuthWelcome/Home.
    @State private var revealApp = Self.didFinishSplash
    /// Bound after first paint. Touching `AriaNeuralVoiceGate.shared` from
    /// `body` blocked the first frame on the voice catalog XPC.
    @State private var neuralVoiceGate: AriaNeuralVoiceGate?
    /// Same rule as the neural gate: do not touch the shared Kokoro gate from `body`.
    @State private var kokoroVoiceGate: AriaKokoroVoiceGate?
    /// First SwiftUI commit is the splash field only — except leftover /
    /// wedged prep, which must paint AriaForgePrep on that commit.
    /// AuthWelcome / interview / Home attach after that paint — every build,
    /// not a simulator env.
    @State private var revealRoot = Self.didFinishSplash
    private static var didFinishSplash = false

    var body: some View {
        let leftoverPrep = LaunchFirstCommit.leftoverPrepPending(
            needsForgePrep: store.needsForgePrep
        )
        ZStack {
            launchRoot(leftoverPrep: leftoverPrep)
                .animation(reduceMotion ? nil : ForgeMotion.crossfade, value: store.isAuthenticated)
                .animation(reduceMotion ? nil : ForgeMotion.crossfade, value: store.isOnboarded)

            if showSplash && LaunchFirstCommit.splashCoversFirstCommit(leftoverPrep: leftoverPrep) {
                ForgeSplashScreen(signedIn: store.isAuthenticated, onSkip: { dismissSplash() })
                    .transition(.opacity)
                    .zIndex(999)
                    // Decorative: keep VoiceOver off "FORGE" / "Forged." as it fades.
                    .accessibilityHidden(true)
                    // Tap skips. Hits pass through once the fade starts.
                    .allowsHitTesting(splashBlocksHits)
            }
        }
        .sheet(isPresented: neuralPromptBinding) {
            if let neuralVoiceGate {
                AriaNeuralVoiceSheet(gate: neuralVoiceGate)
            }
        }
        .sheet(isPresented: kokoroPromptBinding(
            blocked: LaunchPromptGate.blocksPresentation(leftoverPrep: leftoverPrep, splashVisible: showSplash)
        )) {
            if let kokoroVoiceGate {
                AriaKokoroVoiceSheet(gate: kokoroVoiceGate)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                neuralVoiceGate?.refreshCatalog()
                store.refreshOnDeviceModel()
            }
        }
        .onAppear {
            if leftoverPrep {
                revealRoot = true
                showSplash = false
                splashBlocksHits = false
                Self.didFinishSplash = true
            }
        }
        .task {
            let leftoverPrep = LaunchFirstCommit.leftoverPrepPending(
                needsForgePrep: store.needsForgePrep
            )
            if leftoverPrep {
                revealRoot = true
                showSplash = false
                splashBlocksHits = false
                Self.didFinishSplash = true
                AriaForgePrep.armLeftoverTimeout(store: store)
                AriaForgePrep.armWatchdogTimer(store: store)
                await LaunchFirstFrame.afterPaint()
                return
            }
            await LaunchFirstFrame.afterPaint()
            revealRoot = true
            // Cheap cache only. CFPreferencesAppSynchronize on this hop
            // pinned kill_relaunch sample 0 at 3.00s after SIGKILL.
            // Leftover miss is recovered on a background queue; the process
            // watchdog still fail-opens at leftoverFailOpen.
            if store.needsForgePrep {
                AriaForgePrep.armLeftoverTimeout(store: store)
                AriaForgePrep.armWatchdogTimer(store: store)
            } else if !store.isOnboarded {
                AriaForgePrep.refreshInterviewOffMainActor(store: store)
            }
            guard showSplash else {
                attachVoiceGates(presentKokoroPrompt: false)
                return
            }
            try? await Task.sleep(
                nanoseconds: ForgeSplashTiming.pauseNanoseconds(
                    reduceMotion: reduceMotion,
                    signedIn: store.isAuthenticated
                )
            )
            dismissSplash()
            attachVoiceGates(presentKokoroPrompt: false)
            if store.isAuthenticated, !store.isOnboarded {
                await presentDeferredNotifications()
            }
        }
        .onChange(of: store.isOnboarded) { _, onboarded in
            if onboarded, !store.needsForgePrep {
                attachVoiceGates(presentKokoroPrompt: true)
                Task { await presentDeferredNotifications() }
            }
        }
    }

    @ViewBuilder
    private func launchRoot(leftoverPrep: Bool) -> some View {
        if leftoverPrep {
            OnboardingView()
        } else if !revealRoot {
            LaunchBrandField()
        } else {
            switch store.launchRootDestination {
            case .authWelcome:
                AuthWelcomeView()
            case .onboarding:
                OnboardingView()
            case .home:
                if showSplash {
                    LaunchBrandField()
                } else {
                    MainTabView()
                }
            }
        }
    }

    private func dismissSplash() {
        Self.didFinishSplash = true
        splashBlocksHits = false
        withAnimation(.easeOut(duration: ForgeSplashTiming.fadeOut)) {
            showSplash = false
        }
    }

    private func presentDeferredNotifications() async {
        let leftover = LaunchFirstCommit.leftoverPrepPending(needsForgePrep: store.needsForgePrep)
        guard !LaunchPromptGate.blocksPresentation(leftoverPrep: leftover, splashVisible: showSplash) else { return }
        let remain = max(0, LaunchPromptGate.firstFrameSettle - AriaForgePrep.elapsedSinceProcessStartForTests())
        if remain > 0 {
            try? await Task.sleep(nanoseconds: UInt64((remain * 1_000_000_000).rounded()))
        }
        guard LaunchPromptGate.allowsPresentation(
            leftoverPrep: LaunchFirstCommit.leftoverPrepPending(needsForgePrep: store.needsForgePrep),
            splashVisible: showSplash,
            elapsed: AriaForgePrep.elapsedSinceProcessStartForTests()
        ) else { return }
        await ForgeNotificationScheduler.promptAuthorization()
        await SleepAlarmScheduler.rearmAfterPromptGateIfNeeded()
    }

    private func attachVoiceGates(presentKokoroPrompt: Bool) {
        let neural = AriaNeuralVoiceGate.shared
        neuralVoiceGate = neural
        neural.refreshCatalog()
        let kokoro = AriaKokoroVoiceGate.shared
        kokoroVoiceGate = kokoro
        Task { await kokoro.refresh(presentPrompt: presentKokoroPrompt) }
    }

    private var neuralPromptBinding: Binding<Bool> {
        Binding(
            get: { neuralVoiceGate?.showPrompt ?? false },
            set: { neuralVoiceGate?.showPrompt = $0 }
        )
    }

    private func kokoroPromptBinding(blocked: Bool) -> Binding<Bool> {
        Binding(
            get: { !blocked && (kokoroVoiceGate?.showPrompt ?? false) },
            set: { kokoroVoiceGate?.showPrompt = $0 }
        )
    }
}

// MARK: - First-commit brand field

/// Cheap launch canvas. Matches `LaunchScreen.storyboard` so the storyboard
/// → first SwiftUI commit is two consecutive non-blank frames. No Metal,
/// no blur, no speech.
struct LaunchBrandField: View {
    static let markSide: CGFloat = 220
    static let background = Color(red: 8 / 255, green: 8 / 255, blue: 12 / 255)
    static let ember = Color(red: 1, green: 77 / 255, blue: 0)

    var body: some View {
        ZStack {
            Self.background
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Self.ember)
                .frame(width: Self.markSide, height: Self.markSide)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Splash Screen

struct ForgeSplashScreen: View {
    static let backdropHex = "09090B"
    static let launchColorName = "LaunchBackground"

    var signedIn: Bool = false
    var onSkip: (() -> Void)? = nil

    // Visible on the first commit. Starting at opacity 0 made the splash a
    // uniform black frame, which the launch gate counts as blank.
    @State private var logoOpacity: Double = 1
    @State private var textOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var side: CGFloat { LaunchBrandField.markSide }
    private var settled: Bool { reduceMotion || signedIn }

    var body: some View {
        ZStack {
            Color(hex: Self.backdropHex)
                .ignoresSafeArea()

            // Same 220 pt ember as LaunchScreen.storyboard. Without this mark
            // the first SwiftUI commit is a blank field and the launch gate
            // resets its streak.
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(LaunchBrandField.ember)
                .frame(width: side, height: side)
                .accessibilityHidden(true)

            VStack(spacing: FDS.Spacing.xl) {
                ForgeStrikeMark(playback: settled ? .trimmed : .full)
                    .frame(width: side, height: side)

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
        .contentShape(Rectangle())
        .onTapGesture { onSkip?() }
        .accessibilityAction(.escape) { onSkip?() }
        .task {
            // One rigid tap as the hammer lands. Off under Reduce Motion
            // and on the signed-in trim (no swing).
            guard !settled else { return }
            try? await Task.sleep(nanoseconds: UInt64(ForgeStrikeGeometry.splashImpactTime * 1_000_000_000))
            guard !Task.isCancelled else { return }
            ForgeHaptics.playStrike()
        }
        .onAppear {
            if settled {
                logoOpacity = 1
                textOffset = 0
                return
            }
            withAnimation(ForgeMotion.gentle.delay(ForgeStrikeGeometry.splashImpactTime)) {
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
                    .fill(Color.ember)
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
