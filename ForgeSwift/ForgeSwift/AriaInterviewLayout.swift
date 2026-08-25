import SwiftUI

struct AriaInterviewLayout: View {
    @Bindable var coordinator: OnboardingCoordinator
    let onFinish: () -> Void
    @StateObject private var dictation = SpeechManager()

    var body: some View {
        // Header stays fixed in the safe area. Tall composers (e.g. 8 training
        // themes) scroll inside a capped region so they never crush the
        // transcript or push content under the status bar / Dynamic Island.
        GeometryReader { geo in
            let composerCap = max(240, geo.size.height * 0.55)
            VStack(spacing: 0) {
                header
                transcript
                    .frame(minHeight: 96, maxHeight: .infinity)
                composer(maxHeight: composerCap)
            }
        }
        .onChange(of: dictation.recognizedText) { _, text in
            guard dictation.isListening || dictation.voiceState == .processing else { return }
            // Live partials into free-text steps
            if coordinator.step == .name || coordinator.step == .conditions {
                coordinator.freeText = text
            }
        }
        .onChange(of: dictation.voiceState) { _, state in
            // Mirror mic state onto ARIA orb
            switch state {
            case .listening:
                coordinator.ariaOrbState = .listening
            case .processing:
                coordinator.ariaOrbState = .processing
            case .idle:
                if coordinator.isTyping {
                    coordinator.ariaOrbState = .processing
                } else if !coordinator.isTyping {
                    coordinator.ariaOrbState = .idle
                }
            case .speaking:
                coordinator.ariaOrbState = .speaking
            case .error:
                coordinator.ariaOrbState = .idle
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    // Soft glow when listening
                    if dictation.isListening {
                        Circle()
                            .fill(Color.ember.opacity(0.22))
                            .frame(width: 58, height: 58)
                            .blur(radius: 8)
                    }
                    AuroraOrbView(
                        state: dictation.isListening ? .listening : coordinator.ariaOrbState,
                        amplitude: dictation.isListening
                            ? dictation.amplitude
                            : (coordinator.ariaOrbState == .speaking ? 0.55 : 0.22),
                        mood: coordinator.ariaMood,
                        size: 48
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("ARIA")
                            .font(.caption2.weight(.black))
                            .tracking(2)
                            .foregroundColor(coordinator.ariaMood.accentColor)
                        if dictation.isListening {
                            Text("· listening")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.ember)
                                .transition(.opacity)
                        } else {
                            Text("· interview")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.textMuted)
                        }
                    }
                    Text(coordinator.step.progressLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(min(coordinator.step.rawValue + 1, AriaInterviewStep.allCases.count)) of \(AriaInterviewStep.allCases.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.4)
                        .foregroundColor(.ember)
                    Text(coordinator.step.progressLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.ember.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HealthKitStatusPill(state: coordinator.healthKitState)
            }
            .animation(FDS.Spring.snap, value: dictation.isListening)
            .animation(FDS.Spring.snap, value: coordinator.step)

            // Quiet progress — no score, just how far through the interview.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 5)
                    Capsule()
                        .fill(FDS.Gradient.ember)
                        .frame(width: max(10, geo.size.width * coordinator.progress), height: 5)
                        .shadow(color: Color.ember.opacity(0.55), radius: 6, y: 0)
                        .animation(FDS.Spring.standard, value: coordinator.progress)
                }
            }
            .frame(height: 5)

            // Step dots
            HStack(spacing: 4) {
                ForEach(AriaInterviewStep.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= coordinator.step.rawValue ? Color.ember : Color.white.opacity(0.12))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, FDS.Spacing.xl)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(coordinator.messages) { msg in
                        MessageBubble(message: msg)
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
        VStack(spacing: 12) {
            Divider().overlay(Color.white.opacity(0.06))

            if case .error(let msg) = dictation.voiceState {
                Text(msg)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, FDS.Spacing.xl)
            }

            // Reserve a bounded region for options. Long lists scroll here instead
            // of overflowing the screen or covering the header / ARIA transcript.
            ScrollView(showsIndicators: false) {
                composerBody
            }
            .frame(minHeight: min(180, maxHeight), maxHeight: maxHeight, alignment: .top)
        }
        .background(
            Color.background.opacity(0.96)
                .shadow(color: .black.opacity(0.35), radius: 20, y: -8)
        )
        .animation(FDS.Spring.page, value: coordinator.step)
    }

    @ViewBuilder
    private var composerBody: some View {
        Group {
            switch coordinator.step {
            case .intro:
                EmptyView()
            case .age:
                AgeComposer(coordinator: coordinator)
            case .name:
                NameComposer(coordinator: coordinator, dictation: dictation)
            case .health:
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
            case .biologicalSex:
                BiologicalSexStepView(coordinator: coordinator)
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
            case .trainingTheme:
                VStack(spacing: 10) {
                    OptionCardsComposer(
                        options: AriaTrainingTheme.allCases.map {
                            ($0.rawValue, $0.label, $0.tagline)
                        },
                        onSelect: { raw in
                            dictation.cancel()
                            if let theme = AriaTrainingTheme(rawValue: raw) {
                                coordinator.selectTrainingTheme(theme)
                            }
                        }
                    )
                    Button {
                        dictation.cancel()
                        coordinator.skipTrainingTheme()
                    } label: {
                        Text("Skip — classic coach")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            case .lifeContext:
                VStack(spacing: 10) {
                    OptionCardsComposer(
                        options: LifeContextOption.allCases.map { ($0.rawValue, $0.label, "") },
                        onSelect: { raw in
                            dictation.cancel()
                            if let o = LifeContextOption(rawValue: raw) {
                                coordinator.selectLifeContext(o)
                            }
                        }
                    )
                }
            case .conditions:
                ConditionsComposer(coordinator: coordinator, dictation: dictation)
            case .coaching:
                CoachingComposer(coordinator: coordinator)
            case .ready:
                ReadyComposer(coordinator: coordinator, onFinish: onFinish)
            }
        }
        .padding(.horizontal, FDS.Spacing.xl)
        .padding(.bottom, 28)
        .id(coordinator.step)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }
}
