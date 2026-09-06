import SwiftUI

struct AriaInterviewLayout: View {
    @Bindable var coordinator: OnboardingCoordinator
    let onFinish: () -> Void
    @StateObject private var dictation = SpeechManager()
    private let presence = AriaPresence.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Header stays fixed in the safe area. Tall composers (e.g. 8 training
        // themes) scroll inside a capped region so they never crush the
        // transcript or push content under the status bar / Dynamic Island.
        GeometryReader { geo in
            let composerCap = coordinator.step == .details
                ? max(300, geo.size.height * 0.64)
                : max(248, geo.size.height * 0.52)
            VStack(spacing: 0) {
                header
                transcript
                    .frame(minHeight: 88, maxHeight: .infinity)
                composer(maxHeight: composerCap)
            }
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

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                if coordinator.canGoBack {
                    Button {
                        dictation.cancel()
                        coordinator.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                            .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }

                Button {
                    coordinator.replayLastAriaLine()
                } label: {
                    ZStack {
                        if dictation.isListening || presence.isSpeaking || coordinator.isTyping {
                            Circle()
                                .fill(coordinator.ariaMood.accentColor.opacity(0.28))
                                .frame(width: 72, height: 72)
                                .blur(radius: 12)
                        }
                        AuroraOrbView(
                            state: dictation.isListening ? .listening : coordinator.ariaOrbState,
                            amplitude: dictation.isListening
                                ? dictation.amplitude
                                : (presence.isSpeaking ? 0.7 : 0.28),
                            mood: coordinator.ariaMood,
                            size: 58,
                            followPresence: true
                        )
                    }
                    .frame(width: 62, height: 62)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replay ARIA")
                .accessibilityHint("Plays her last line")

                VStack(alignment: .leading, spacing: 3) {
                    Text(presenceCaption.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundColor(coordinator.ariaMood.accentColor)
                    Text(coordinator.step.progressLabel)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("Tap ARIA to hear her again")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textTertiary)
                }

                Spacer(minLength: 8)

                Text("\(coordinator.progressStepIndex) / \(coordinator.progressStepCount)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.textTertiary)
                    .monospacedDigit()
            }
            .animation(FDS.Spring.snap, value: dictation.isListening)
            .animation(FDS.Spring.snap, value: presence.isSpeaking)
            .animation(FDS.Spring.page, value: coordinator.step)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                    Capsule()
                        .fill(FDS.Gradient.ember)
                        .frame(width: max(10, geo.size.width * coordinator.progress), height: 4)
                        .shadow(color: Color.ember.opacity(0.45), radius: 5, y: 0)
                        .animation(FDS.Spring.standard, value: coordinator.progress)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, FDS.Spacing.xl)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(coordinator.messages) { msg in
                        MessageBubble(message: msg) {
                            if msg.role == .aria {
                                AriaPresence.shared.speak(msg.text, interrupt: true)
                            }
                        }
                        .id(msg.id)
                    }
                    if coordinator.isTyping {
                        TypingIndicator()
                            .id("typing")
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, FDS.Spacing.xl)
                .padding(.vertical, 8)
            }
            .onChange(of: coordinator.messages.count) { _, _ in
                withAnimation(FDS.Spring.snap) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: coordinator.isTyping) { _, typing in
                if typing {
                    withAnimation(FDS.Spring.snap) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func composer(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 8)

            if case .error(let msg) = dictation.voiceState {
                Text(msg)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, FDS.Spacing.xl)
                    .padding(.bottom, 8)
            }

            suggestedRepliesBar

            ScrollView(showsIndicators: false) {
                composerBody
            }
            .frame(minHeight: min(180, maxHeight), maxHeight: maxHeight, alignment: .top)

            if AriaInterviewVoice.shouldShowVoiceDock(for: coordinator.step) {
                voiceDock
            }
        }
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
            .fill(Color.surface.opacity(0.96))
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                )
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.45), radius: 28, y: -12)
        }
        .animation(FDS.Spring.page, value: coordinator.step)
    }

    @ViewBuilder
    private var suggestedRepliesBar: some View {
        let replies = AriaInterviewVoice.suggestedReplies(
            step: coordinator.step,
            profile: coordinator.profile,
            health: coordinator.healthKitState,
            calendar: coordinator.calendarState
        )
        if !replies.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("ANSWER ARIA")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.textMuted)
                    .padding(.horizontal, FDS.Spacing.xl)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(replies) { reply in
                            Button {
                                applyReply(reply)
                            } label: {
                                Text(reply.label)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(Color.ember.opacity(0.22))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(Color.ember.opacity(0.55), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(reply.label)
                        }
                    }
                    .padding(.horizontal, FDS.Spacing.xl)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var voiceDock: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dictation.isListening ? "ARIA is listening" : "Talk to ARIA")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(dictation.isListening ? .ember : .textPrimary)
                Text(dictation.isListening
                     ? (dictation.recognizedText.isEmpty ? "Go ahead — I’m with you." : dictation.recognizedText)
                     : AriaInterviewVoice.voiceHint(for: coordinator.step))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            DictationMicButton(dictation: dictation) {
                let spoken = dictation.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !spoken.isEmpty else { return }
                coordinator.handleSpokenReply(spoken)
            }
        }
        .padding(.horizontal, FDS.Spacing.xl)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
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

    @ViewBuilder
    private var composerBody: some View {
        Group {
            switch coordinator.step {
            case .intro:
                EmptyView()
            case .name:
                NameComposer(coordinator: coordinator, dictation: dictation)
            case .health:
                HealthComposer(coordinator: coordinator)
            case .details:
                DetailsComposer(coordinator: coordinator)
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
                    title: "Workouts",
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
                MultiChipComposer(
                    title: "Free time",
                    items: LifestyleInterest.allCases.map { ($0.id, $0.label) },
                    isSelected: { id in
                        coordinator.profile.freeTimeInterests.contains { $0.id == id }
                    },
                    onToggle: { id in
                        if let interest = LifestyleInterest.allCases.first(where: { $0.id == id }) {
                            coordinator.toggleInterest(interest)
                        }
                    },
                    canContinue: true,
                    continueTitle: coordinator.profile.freeTimeInterests.isEmpty ? "Skip" : "Continue",
                    onContinue: { coordinator.confirmInterests() }
                )
            case .conditions:
                ConditionsComposer(coordinator: coordinator, dictation: dictation)
            case .coaching:
                CoachingComposer(coordinator: coordinator)
            case .ready:
                ReadyComposer(coordinator: coordinator, onFinish: onFinish)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .id(coordinator.step)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }
}
