import SwiftUI
import UIKit
import ForgeCore

struct AriaInterviewLayout: View {
    @Bindable var coordinator: OnboardingCoordinator
    let onFinish: () -> Void
    @StateObject private var dictation = SpeechManager()
    private let presence = AriaPresence.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AriaSpokenMute.mutedKey) private var spokenMuted = true
    // Presentation-only layout state.
    @State private var headerHeight: CGFloat = 0
    @State private var keyboardVisible = false
    @State private var showsEarlier = false

    /// Orb in the presence row. 56 pt is the still pose, inside a 44 pt tap area.
    private static let orbSize: CGFloat = 56
    /// Below this usable height the transcript collapses to ARIA's latest line.
    private static let compactHeight: CGFloat = 700

    private var beat: AriaInterviewStep {
        AriaInterviewStep(OnboardingGraph.normalized(coordinator.step.graph))
    }

    private func motion(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    var body: some View {
        // Header stays fixed in the safe area. The composer sheet is capped as
        // a whole (grabber-less, replies, scroll, voice dock) so it never
        // crushes the transcript or pushes content under the Dynamic Island.
        // While the keyboard is up, or on a short screen, the transcript
        // collapses to ARIA's latest line.
        GeometryReader { geo in
            let collapsed = keyboardVisible || geo.size.height < Self.compactHeight
            let transcriptMin: CGFloat = collapsed ? 64 : 96
            let sheetFloor: CGFloat = keyboardVisible ? 120 : 200
            let sheetMax = max(sheetFloor, geo.size.height - headerHeight - transcriptMin)
            VStack(spacing: 0) {
                header
                transcript(collapsed: collapsed)
                    .frame(minHeight: transcriptMin, maxHeight: .infinity)
                composer(maxHeight: sheetMax)
            }
            .animation(motion(FDS.Spring.standard), value: collapsed)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onChange(of: dictation.recognizedText) { _, text in
            guard dictation.isListening || dictation.voiceState == .processing else { return }
            if coordinator.step == .conditions {
                coordinator.freeText = text
            }
            if coordinator.step == .name,
               case .fillName(let name) = AriaInterviewVoice.matchSpoken(text, step: .name, profile: coordinator.profile) {
                coordinator.applySpokenName(name)
            }
        }
        .onChange(of: dictation.voiceState) { _, state in
            switch state {
            case .listening:
                coordinator.interruptInterviewVoice()
                coordinator.ariaOrbState = .listening
            case .processing:
                coordinator.ariaOrbState = .processing
            case .idle:
                coordinator.ariaOrbState = coordinator.isTyping ? .processing : .listening
            case .speaking:
                coordinator.ariaOrbState = .speaking
            case .error:
                coordinator.ariaOrbState = .listening
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                dictation.cancel()
                coordinator.stopInterviewVoice()
            }
        }
        .onDisappear {
            dictation.cancel()
            coordinator.stopInterviewVoice()
        }
    }

    private var presenceCaption: String {
        AriaInterviewVoice.presenceCaption(
            listening: dictation.isListening,
            speaking: presence.isSpeaking,
            thinking: coordinator.isTyping || presence.isThinking
        )
    }

    // MARK: - Header

    /// Two rows. Row 1 is back, progress and mute at 44 pt each. Row 2 is the
    /// orb with ARIA's status and the step title, so text never competes with
    /// controls for width.
    private var header: some View {
        VStack(spacing: FDS.Spacing.sm) {
            controlsRow
            presenceRow
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, FDS.Spacing.sm)
        .padding(.bottom, FDS.Spacing.md)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            headerHeight = height
        }
    }

    private var controlsRow: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            if coordinator.canGoBack {
                ForgeIconButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Back",
                    tinted: false
                ) {
                    dictation.cancel()
                    coordinator.goBack()
                }
            } else {
                Color.clear
                    .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                    .accessibilityHidden(true)
            }

            progressBar

            AriaSpokenMuteButton()
        }
        .animation(motion(FDS.Spring.page), value: coordinator.step)
    }

    private var progressBar: some View {
        ForgeProgressBar(fraction: coordinator.progress, tint: Color.paper, height: 4)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progress")
            .accessibilityValue("Step \(coordinator.progressStepIndex) of \(coordinator.progressStepCount)")
    }

    private var presenceRow: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            orbButton

            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(presenceCaption)
                    .forgeSectionLabel(tint: coordinator.ariaMood.accentColor)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                Text(coordinator.step.progressLabel)
                    .font(ForgeType.title)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(motion(FDS.Spring.snap), value: dictation.isListening)
        .animation(motion(FDS.Spring.snap), value: presence.isSpeaking)
        .animation(motion(FDS.Spring.page), value: coordinator.step)
    }

    private var orbButton: some View {
        Button {
            coordinator.replayLastAriaLine()
        } label: {
            AuroraOrbView(
                state: dictation.isListening ? .listening : coordinator.ariaOrbState,
                amplitude: dictation.isListening
                    ? max(Float(0.55), dictation.amplitude)
                    : (presence.isSpeaking ? 0.82 : 0.46),
                mood: coordinator.ariaMood,
                size: Self.orbSize,
                followPresence: true
            )
            .frame(width: Self.orbSize, height: Self.orbSize)
            .frame(minWidth: ForgeUX.minTap, minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Replay ARIA")
        .accessibilityHint("Plays her last line")
        .accessibilityValue(spokenMuted ? "Voice is muted" : "")
    }

    // MARK: - Transcript

    private func transcript(collapsed: Bool) -> some View {
        let lastAria = coordinator.messages.last(where: { $0.role == .aria })
        let hasEarlier = coordinator.messages.contains { $0.id != lastAria?.id }
        let showsLastOnly = collapsed && (keyboardVisible || !showsEarlier)
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    if collapsed && hasEarlier && !keyboardVisible {
                        ForgeTextLink(
                            title: "Earlier",
                            accent: Color.textTertiary,
                            expanded: showsEarlier
                        ) {
                            withAnimation(motion(FDS.Spring.standard)) {
                                showsEarlier.toggle()
                            }
                        }
                    }
                    if showsLastOnly {
                        if let lastAria {
                            bubble(lastAria)
                        }
                    } else {
                        ForEach(coordinator.messages) { msg in
                            bubble(msg)
                        }
                    }
                    if coordinator.isTyping {
                        TypingIndicator()
                            .id("typing")
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, ForgeLayout.screenInset)
                .padding(.vertical, FDS.Spacing.sm)
            }
            .onChange(of: coordinator.messages.count) { _, _ in
                withAnimation(motion(FDS.Spring.snap)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: coordinator.isTyping) { _, typing in
                if typing {
                    withAnimation(motion(FDS.Spring.snap)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func bubble(_ msg: AriaOnboardingMessage) -> some View {
        MessageBubble(message: msg) {
            if msg.role == .aria {
                AriaPresence.shared.speak(msg.text, interrupt: true)
            }
        }
        .id(msg.id)
    }

    // MARK: - Composer sheet

    private func composer(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            errorLine

            if showsSuggestedReplies {
                suggestedRepliesBar
            }

            ScrollView(showsIndicators: false) {
                if coordinator.isReviewingBirthday {
                    birthdayReviewBody
                } else {
                    composerBody
                }
            }

            if showsVoiceDock {
                voiceDock
            }
        }
        .frame(maxHeight: maxHeight)
        .background { sheetBackground }
        .animation(motion(FDS.Spring.page), value: coordinator.step)
    }

    private var sheetBackground: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: FDS.Radius.xxl,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: FDS.Radius.xxl,
            style: .continuous
        )
        return shape
            .fill(Color.surface.opacity(0.96))
            .overlay {
                shape.stroke(Color.borderHairline, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.45), radius: 28, y: -12)
            .ignoresSafeArea(.container, edges: .bottom)
    }

    @ViewBuilder
    private var errorLine: some View {
        if case .error(let msg) = dictation.voiceState {
            Text(msg)
                .font(HomeType.body)
                .foregroundStyle(Color.warning)
                .forgeWrapping()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ForgeLayout.screenInset)
                .padding(.top, FDS.Spacing.md)
        }
    }

    // MARK: - Suggested replies

    /// Every beat except schedule and conditions already puts the same answers
    /// in the composer itself (cards, rows, a Continue button), so the reply
    /// chips only appear where there are no direct controls.
    private var repliesAreRedundant: Bool {
        switch beat {
        case .name, .health, .goals, .experience, .workouts, .sleep, .freeTime, .coaching:
            return true
        case .intro, .details, .schedule, .conditions, .ready:
            return false
        }
    }

    private var showsSuggestedReplies: Bool {
        !coordinator.isReviewingBirthday && !keyboardVisible && !repliesAreRedundant
    }

    private var showsVoiceDock: Bool {
        !coordinator.isReviewingBirthday
            && AriaInterviewVoice.shouldShowVoiceDock(for: beat)
            && (!keyboardVisible || dictation.isListening)
    }

    @ViewBuilder
    private var suggestedRepliesBar: some View {
        let replies = AriaInterviewVoice.suggestedReplies(
            step: beat,
            profile: coordinator.profile,
            health: coordinator.healthKitState,
            calendar: coordinator.calendarState,
            contacts: coordinator.contactsState,
            reminders: coordinator.remindersState
        )
        if !replies.isEmpty {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("Reply")
                    .forgeSectionLabel()
                ForgeFlowLayout(lineSpacing: ForgeLayout.interactiveChipLineGap) {
                    ForEach(replies) { reply in
                        ForgeChipButton(label: reply.label) {
                            applyReply(reply)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.top, FDS.Spacing.md)
            .padding(.bottom, FDS.Spacing.sm)
        }
    }

    // MARK: - Voice dock

    private var voiceDock: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(dictation.isListening ? "ARIA is listening" : "Talk to ARIA")
                    .font(HomeType.status)
                    .foregroundStyle(dictation.isListening ? Color.ember : Color.textPrimary)
                voiceDockDetail
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DictationMicButton(dictation: dictation) {
                let spoken = dictation.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !spoken.isEmpty else { return }
                coordinator.handleSpokenReply(spoken)
            }
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, FDS.Spacing.md)
        .padding(.bottom, FDS.Spacing.md)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    /// Live dictation keeps its newest words (the head truncates); hints wrap.
    @ViewBuilder
    private var voiceDockDetail: some View {
        if dictation.isListening {
            Text(dictation.recognizedText.isEmpty ? "Go ahead — I’m with you." : dictation.recognizedText)
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(3)
                .truncationMode(.head)
        } else {
            Text(AriaInterviewVoice.voiceHint(for: beat))
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }

    private func applyReply(_ reply: AriaInterviewVoice.Reply) {
        dictation.cancel()
        if reply.kind == .startTalking {
            coordinator.interruptInterviewVoice()
            dictation.startListening()
            return
        }
        coordinator.applySuggestedReply(reply)
    }

    /// After the age block: the birthday field from DetailsComposer, whatever
    /// beat is behind it. `.details` itself normalizes onto Health below.
    private var birthdayReviewBody: some View {
        DetailsComposer(coordinator: coordinator)
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.top, FDS.Spacing.lg)
            .padding(.bottom, FDS.Spacing.md)
            .transition(.opacity)
    }

    private var composerTransition: AnyTransition {
        reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.asymmetric(
                insertion: AnyTransition.move(edge: .bottom).combined(with: .opacity),
                removal: AnyTransition.opacity
            )
    }

    @ViewBuilder
    private var composerBody: some View {
        Group {
            switch AriaInterviewStep(OnboardingGraph.normalized(coordinator.step.graph)) {
            case .intro:
                IntroComposer(coordinator: coordinator)
            case .name:
                NameComposer(coordinator: coordinator, dictation: dictation)
            case .health:
                HealthComposer(coordinator: coordinator)
            case .details:
                HealthComposer(coordinator: coordinator)
            case .goals:
                MultiChipComposer(
                    title: "Goals",
                    items: OnboardingFitnessGoal.allCases.map { ($0.id, $0.label) },
                    isSelected: { id in
                        coordinator.profile.fitnessGoals.contains { $0.id == id }
                    },
                    onToggle: { id in
                        if let g = OnboardingFitnessGoal.allCases.first(where: { $0.id == id }) {
                            coordinator.toggleGoal(g)
                        }
                    },
                    canContinue: !coordinator.profile.fitnessGoals.isEmpty,
                    continueTitle: "Continue",
                    onContinue: { coordinator.confirmGoals() }
                )
            case .experience:
                OptionCardsComposer(
                    options: ExperienceLevel.allCases.map {
                        ($0.rawValue, $0.label, $0.description)
                    },
                    onSelect: { raw in
                        dictation.cancel()
                        if let level = ExperienceLevel(rawValue: raw) {
                            coordinator.selectExperience(level)
                        }
                    }
                )
            case .workouts:
                MultiChipComposer(
                    title: "Training & sports",
                    items: OnboardingWorkoutType.allCases.map { ($0.id, $0.label) },
                    isSelected: { id in
                        coordinator.profile.preferredWorkouts.contains { $0.id == id }
                    },
                    onToggle: { id in
                        if let w = OnboardingWorkoutType.allCases.first(where: { $0.id == id }) {
                            coordinator.toggleWorkout(w)
                        }
                    },
                    canContinue: !coordinator.profile.preferredWorkouts.isEmpty,
                    continueTitle: "Continue",
                    onContinue: { coordinator.confirmWorkouts() }
                )
            case .schedule:
                ScheduleComposer(coordinator: coordinator)
            case .sleep:
                OptionCardsComposer(
                    options: SleepRhythmBand.allCases.map {
                        ($0.rawValue, $0.label, $0.detail)
                    },
                    onSelect: { raw in
                        dictation.cancel()
                        if let band = SleepRhythmBand(rawValue: raw) {
                            coordinator.selectSleepBand(band)
                        }
                    }
                )
            case .freeTime:
                HabitsComposer(coordinator: coordinator)
            case .conditions:
                ConditionsComposer(coordinator: coordinator, dictation: dictation)
            case .coaching:
                CoachingComposer(coordinator: coordinator)
            case .ready:
                ReadyComposer(coordinator: coordinator, onFinish: onFinish)
            }
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, FDS.Spacing.lg)
        .padding(.bottom, FDS.Spacing.md)
        .id(coordinator.step)
        .transition(composerTransition)
    }
}
