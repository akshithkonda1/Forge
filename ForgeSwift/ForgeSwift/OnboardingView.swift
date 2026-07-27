import SwiftUI

// MARK: - Gradients

extension LinearGradient {
    static let ember = LinearGradient(
        colors: [Color.ember, Color.ember.opacity(0.82)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let deepEmber = LinearGradient(
        colors: [Color(hex: "1A0800"), Color(hex: "0A0A0A")],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Onboarding enums

enum OnboardingFitnessGoal: String, CaseIterable, Identifiable {
    case loseWeight, buildMuscle, improveEndurance, increaseFlexibility,
         betterSleep, reducStress, athleticPerformance, generalHealth
    var id: String { rawValue }
    var label: String {
        switch self {
        case .loseWeight:           return "Lose Weight"
        case .buildMuscle:          return "Build Muscle"
        case .improveEndurance:     return "Endurance"
        case .increaseFlexibility:  return "Flexibility"
        case .betterSleep:          return "Better Sleep"
        case .reducStress:          return "Reduce Stress"
        case .athleticPerformance:  return "Athletic Performance"
        case .generalHealth:        return "General Health"
        }
    }
    var icon: String {
        switch self {
        case .loseWeight:           return "arrow.down.circle.fill"
        case .buildMuscle:          return "dumbbell.fill"
        case .improveEndurance:     return "figure.run"
        case .increaseFlexibility:  return "figure.flexibility"
        case .betterSleep:          return "moon.zzz.fill"
        case .reducStress:          return "brain.head.profile"
        case .athleticPerformance:  return "trophy.fill"
        case .generalHealth:        return "heart.fill"
        }
    }
    var coreGoal: UserFitnessGoal {
        switch self {
        case .loseWeight:           return .loseFat
        case .buildMuscle:          return .buildMuscle
        case .improveEndurance:     return .improveEndurance
        case .athleticPerformance:  return .athleticPerformance
        default:                    return .generalFitness
        }
    }
}

enum OnboardingWorkoutType: String, CaseIterable, Identifiable {
    case weightlifting, hiit, running, cycling, yoga, swimming,
         boxing, calisthenics, crossfit, pilates, climbing, martial_arts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weightlifting:  return "Weightlifting"
        case .hiit:           return "HIIT"
        case .running:        return "Running"
        case .cycling:        return "Cycling"
        case .yoga:           return "Yoga"
        case .swimming:       return "Swimming"
        case .boxing:         return "Boxing"
        case .calisthenics:   return "Calisthenics"
        case .crossfit:       return "CrossFit"
        case .pilates:        return "Pilates"
        case .climbing:       return "Climbing"
        case .martial_arts:   return "Martial Arts"
        }
    }
    var coreType: WorkoutType {
        switch self {
        case .weightlifting, .calisthenics, .crossfit: return .strength
        case .hiit:                                    return .hiit
        case .running, .cycling, .swimming:            return .cardio
        case .yoga, .pilates:                          return .yoga
        default:                                       return .strength
        }
    }
}

enum OnboardingCoachingStyle: String, CaseIterable, Identifiable {
    case driven, balanced, supportive, scientist, elite
    var id: String { rawValue }
    var label: String {
        switch self {
        case .driven:     return "Driven"
        case .balanced:   return "Balanced"
        case .supportive: return "Supportive"
        case .scientist:  return "The Scientist"
        case .elite:      return "Elite"
        }
    }
    var description: String {
        switch self {
        case .driven:     return "Intense accountability. Clear standards."
        case .balanced:   return "Science-backed intensity with room to breathe."
        case .supportive: return "Patient coaching that celebrates every win."
        case .scientist:  return "Data-first — explain the why."
        case .elite:      return "Performance system: readiness, output, recovery."
        }
    }
    var icon: String {
        switch self {
        case .driven:     return "bolt.fill"
        case .balanced:   return "scale.3d"
        case .supportive: return "heart.fill"
        case .scientist:  return "waveform.path.ecg"
        case .elite:      return "crown.fill"
        }
    }
    var color: Color {
        switch self {
        case .driven:     return .ember
        case .balanced:   return .steel
        case .supportive: return Color(hex: "22C55E")
        case .scientist:  return Color(hex: "A855F7")
        case .elite:      return Color(hex: "F59E0B")
        }
    }
    var coreStyle: CoachingStyle {
        switch self {
        case .driven:     return .pushHard
        case .balanced:   return .balanced
        case .supportive: return .patient
        case .scientist:  return .dataDriven
        case .elite:      return .ultraElite
        }
    }
}

// MARK: - OnboardingProfile

struct OnboardingProfile {
    var name: String = ""
    var birthday: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    var gender: Gender = .preferNotToSay
    var heightCm: Double = 170
    var weightKg: Double = 70
    var fitnessGoals: [OnboardingFitnessGoal] = []
    var experienceLevel: ExperienceLevel = .intermediate
    var preferredWorkouts: [OnboardingWorkoutType] = []
    var coachingStyle: OnboardingCoachingStyle = .balanced

    // Lifestyle
    var sleepBand: SleepRhythmBand?
    var freeTimeInterests: [LifestyleInterest] = []
    var lifeContext: LifeContextOption?
    /// How ARIA should frame plans (Solo Leveling, classic coach, etc.).
    var trainingTheme: AriaTrainingTheme = .classic

    // Coach constraints (not a clinical record)
    var reportedConditions: [ReportedCondition] = []
    var conditionsNote: String?
    var guidanceOnlyMode: Bool = false

    // Biological sex — drives cycle auto-enable and educational mode
    var biologicalSex: BiologicalSex? = nil
    var educationalCycleMode: Bool = false

    func toCoreProfile() -> UserProfile {
        UserProfile(
            name: name,
            gender: gender,
            fitnessGoals: fitnessGoals.map(\.coreGoal).reduce(into: [UserFitnessGoal]()) { acc, goal in
                if !acc.contains(goal) { acc.append(goal) }   // several onboarding goals map to .generalFitness; dedupe to avoid duplicate Identifiable IDs
            },
            experienceLevel: experienceLevel,
            preferredWorkouts: Array(Set(preferredWorkouts.map(\.coreType))),
            coachingStyle: coachingStyle.coreStyle,
            connectedDevices: [],
            weeklySchedule: [],
            trainingEquipment: .commercialGym,
            age: Calendar.current.dateComponents([.year], from: birthday, to: Date()).year,
            weight: weightKg,
            height: heightCm,
            trainingTheme: trainingTheme,
            interestTags: freeTimeInterests.map(\.tag),
            biologicalSex: biologicalSex,
            educationalCycleMode: educationalCycleMode
        )
    }

    func lifestyleTagsForContext() -> [String] {
        var tags: [String] = []
        if let sleepBand { tags.append(sleepBand.tag) }
        tags.append(contentsOf: freeTimeInterests.map(\.tag))
        if let lifeContext, let t = lifeContext.tag { tags.append(t) }
        if trainingTheme != .classic { tags.append(trainingTheme.lifestyleTag) }
        if !name.trimmingCharacters(in: .whitespaces).isEmpty {
            tags.append("name:\(name.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        tags.append(contentsOf: preferredWorkouts.prefix(4).map { "likes:\($0.rawValue)" })
        tags.append("experience:\(experienceLevel.rawValue)")
        tags.append("coach:\(coachingStyle.rawValue)")
        return Array(Set(tags)).sorted()
    }

    func constraintsForContext() -> [String] {
        var c: [String] = []
        for cond in reportedConditions {
            if let tag = cond.tag { c.append(tag) }
        }
        if guidanceOnlyMode {
            c.append("guidance_only:true")
            c.append("role:lifestyle_coach_not_doctor")
        }
        if let note = conditionsNote, !note.isEmpty {
            c.append("condition_note:\(note.prefix(80))")
        }
        return c
    }
}

extension AppStore {
    /// Shared draft filled during immersive sign-up (name + first quest).
    static var _signUpDraftProfile = OnboardingProfile()
    var tempOnboardingProfile: OnboardingProfile {
        get { Self._signUpDraftProfile }
        set { Self._signUpDraftProfile = newValue }
    }
}

// MARK: - Root: single ARIA interview view

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var coordinator = OnboardingCoordinator()

    var body: some View {
        @Bindable var coordinator = coordinator

        ZStack {
            Color.background.ignoresSafeArea()
            ForgeAmbientBackground(step: coordinator.step.rawValue)
                .ignoresSafeArea()

            if coordinator.showAgeBlocked {
                AgeBlockedView { coordinator.resetAfterAgeBlock() }
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                AriaInterviewLayout(coordinator: coordinator) {
                    coordinator.complete(in: store)
                }
            }

            #if DEBUG
            DevSkipButton(coordinator: coordinator)
            #endif
        }
        .animation(FDS.Spring.hero, value: coordinator.showAgeBlocked)
        .onAppear { coordinator.startIfNeeded() }
    }
}

// MARK: - Interview layout

private struct AriaInterviewLayout: View {
    @Bindable var coordinator: OnboardingCoordinator
    let onFinish: () -> Void
    @StateObject private var dictation = SpeechManager()

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            composer
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

                // Quest XP chip — addictive progress language
                VStack(alignment: .trailing, spacing: 2) {
                    Text("QUEST \(min(coordinator.step.rawValue + 1, AriaInterviewStep.allCases.count))/\(AriaInterviewStep.allCases.count)")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.6)
                        .foregroundColor(.ember)
                    Text("\(Int(coordinator.progress * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.ember.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HealthKitStatusPill(state: coordinator.healthKitState)
            }
            .animation(FDS.Spring.snap, value: dictation.isListening)
            .animation(FDS.Spring.snap, value: coordinator.step)

            // XP-style progress with glow
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

            // Milestone dots
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
    private var composer: some View {
        VStack(spacing: 12) {
            Divider().overlay(Color.white.opacity(0.06))

            if case .error(let msg) = dictation.voiceState {
                Text(msg)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, FDS.Spacing.xl)
            }

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
                        onContinue: {
                            dictation.cancel()
                            coordinator.confirmGoals()
                        }
                    )
                case .biologicalSex:
                    BiologicalSexStepView(coordinator: coordinator)
                case .experience:
                    OptionCardsComposer(
                        options: ExperienceLevel.allCases.map { ($0.rawValue, $0.label, $0.description) },
                        onSelect: { raw in
                            dictation.cancel()
                            if let level = ExperienceLevel(rawValue: raw) {
                                coordinator.selectExperience(level)
                            }
                        }
                    )
                case .workouts:
                    MultiChipComposer(
                        title: "Training you enjoy",
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
                        onContinue: {
                            dictation.cancel()
                            coordinator.confirmWorkouts()
                        }
                    )
                case .sleep:
                    OptionCardsComposer(
                        options: SleepRhythmBand.allCases.map { ($0.rawValue, $0.label, $0.detail) },
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
                            if let i = LifestyleInterest.allCases.first(where: { $0.id == id }) {
                                coordinator.toggleInterest(i)
                            }
                        },
                        canContinue: true,
                        continueTitle: coordinator.profile.freeTimeInterests.isEmpty ? "Skip" : "Continue",
                        onContinue: {
                            dictation.cancel()
                            coordinator.confirmInterests()
                        }
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
        .background(
            Color.background.opacity(0.96)
                .shadow(color: .black.opacity(0.35), radius: 20, y: -8)
        )
        .animation(FDS.Spring.page, value: coordinator.step)
    }
}

// MARK: - Composers

private struct AgeComposer: View {
    @Bindable var coordinator: OnboardingCoordinator

    private var minimumBirthday: Date {
        Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(spacing: 12) {
            DatePicker(
                "Birthday",
                selection: $coordinator.profile.birthday,
                in: minimumBirthday...Date(),
                displayedComponents: [.date]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)
            .frame(maxHeight: 140)

            Text(coordinator.isUnderage ? "Must be 13+" : "\(coordinator.profile.ageYears) years old")
                .font(.caption.weight(.bold))
                .foregroundColor(coordinator.isUnderage ? .danger : .success)

            PrimaryCTA(
                title: coordinator.isUnderage ? "Age requirement not met" : "Continue",
                icon: "arrow.right",
                enabled: !coordinator.isUnderage,
                action: coordinator.confirmAge
            )
        }
    }
}

private struct NameComposer: View {
    @Bindable var coordinator: OnboardingCoordinator
    @ObservedObject var dictation: SpeechManager
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            if dictation.isListening {
                Text(coordinator.freeText.isEmpty ? "Say your name…" : "\"\(coordinator.freeText)\"")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            HStack(spacing: 10) {
                TextField("Your name", text: $coordinator.freeText)
                    .focused($focused)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                            .stroke(
                                dictation.isListening
                                    ? Color.ember.opacity(0.7)
                                    : (focused ? Color.ember.opacity(0.5) : Color.borderColor),
                                lineWidth: dictation.isListening ? 1.5 : 1
                            )
                    )
                    .onSubmit { submit() }

                DictationMicButton(dictation: dictation) {
                    // Finalized utterance — ensure freeText has last transcript
                    let spoken = dictation.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !spoken.isEmpty {
                        coordinator.freeText = spoken
                    }
                    if !coordinator.freeText.trimmingCharacters(in: .whitespaces).isEmpty {
                        submit()
                    }
                }

                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(FDS.Gradient.ember)
                }
                .disabled(coordinator.freeText.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(coordinator.freeText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
        }
        .onAppear { focused = true }
        .animation(FDS.Spring.snap, value: dictation.isListening)
    }

    private func submit() {
        dictation.cancel()
        coordinator.submitName()
    }
}

/// Mic control for free-text interview steps.
private struct DictationMicButton: View {
    @ObservedObject var dictation: SpeechManager
    /// Called once when recognition finalizes with text (silence / stop).
    var onFinalized: (() -> Void)? = nil
    @State private var wasListening = false

    var body: some View {
        Button {
            FDS.haptic(.medium)
            if dictation.isListening {
                dictation.stopListening(submit: true)
            } else {
                dictation.startListening()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(dictation.isListening ? Color.ember.opacity(0.22) : Color.surface)
                    .frame(width: 44, height: 44)
                if dictation.isListening {
                    Circle()
                        .stroke(Color.ember.opacity(0.55), lineWidth: 2)
                        .frame(width: 44 + CGFloat(dictation.amplitude) * 10, height: 44 + CGFloat(dictation.amplitude) * 10)
                }
                Image(systemName: dictation.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(dictation.isListening ? .ember : .textSecondary)
                    .symbolEffect(.variableColor.iterative, isActive: dictation.isListening)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate answer")
        .onChange(of: dictation.voiceState) { _, new in
            switch new {
            case .listening, .processing:
                wasListening = true
            case .idle:
                if wasListening,
                   !dictation.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onFinalized?()
                }
                wasListening = false
            case .speaking, .error:
                wasListening = false
            }
        }
    }
}

private struct HealthComposer: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 10) {
            PrimaryCTA(
                title: coordinator.healthKitState == .requesting ? "Connecting…" : "Connect HealthKit",
                icon: "heart.text.square.fill",
                enabled: coordinator.healthKitState != .requesting && coordinator.healthKitState != .unavailable,
                action: coordinator.connectHealthKit
            )
            Button("Skip for now") { coordinator.skipHealthKit() }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
        }
    }
}

private struct MultiChipComposer: View {
    let title: String
    let items: [(id: String, label: String)]
    let isSelected: (String) -> Bool
    let onToggle: (String) -> Void
    let canContinue: Bool
    let continueTitle: String
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption2.weight(.black))
                .tracking(1.4)
                .foregroundColor(.textMuted)

            OnboardingFlowLayout(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    let selected = isSelected(item.id)
                    Button { onToggle(item.id) } label: {
                        Text(item.label)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(selected ? .white : .textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(selected ? Color.ember.opacity(0.85) : Color.surface)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(selected ? Color.ember : Color.borderColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            PrimaryCTA(title: continueTitle, icon: "arrow.right", enabled: canContinue, action: onContinue)
        }
    }
}

private struct OptionCardsComposer: View {
    let options: [(id: String, title: String, subtitle: String)]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(options, id: \.id) { opt in
                Button { onSelect(opt.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(opt.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.textPrimary)
                            if !opt.subtitle.isEmpty {
                                Text(opt.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.textMuted)
                    }
                    .padding(14)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                            .stroke(Color.borderColor, lineWidth: 0.7)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ConditionsComposer: View {
    @Bindable var coordinator: OnboardingCoordinator
    @ObservedObject var dictation: SpeechManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONDITIONS TO RESPECT")
                .font(.caption2.weight(.black))
                .tracking(1.4)
                .foregroundColor(.textMuted)

            Text("Optional. Lifestyle coach only — not medical care.")
                .font(.caption)
                .foregroundColor(.textTertiary)

            OnboardingFlowLayout(spacing: 8) {
                ForEach(ReportedCondition.allCases) { cond in
                    let selected = coordinator.profile.reportedConditions.contains(cond)
                    Button { coordinator.toggleCondition(cond) } label: {
                        Text(cond.label)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(selected ? .white : .textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(selected ? Color.ember.opacity(0.85) : Color.surface)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(selected ? Color.ember : Color.borderColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if coordinator.profile.reportedConditions.contains(.other) {
                HStack(spacing: 10) {
                    TextField("Anything else I should know? (optional)", text: $coordinator.freeText)
                        .padding(12)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    DictationMicButton(dictation: dictation)
                }
            }

            if coordinator.profile.guidanceOnlyMode {
                Text("Guidance mode will be on: structure & pacing only — never treatment plans.")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.warning)
            }

            PrimaryCTA(
                title: "Continue",
                icon: "arrow.right",
                enabled: !coordinator.profile.reportedConditions.isEmpty,
                action: {
                    dictation.cancel()
                    coordinator.confirmConditions()
                }
            )
        }
    }
}

private struct CoachingComposer: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 8) {
            ForEach(OnboardingCoachingStyle.allCases) { style in
                Button {
                    coordinator.selectCoachingStyle(style)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: style.icon)
                            .foregroundColor(style.color)
                            .frame(width: 36, height: 36)
                            .background(style.color.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.label)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.textPrimary)
                            Text(style.description)
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                            .stroke(style.color.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ReadyComposer: View {
    @Bindable var coordinator: OnboardingCoordinator
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if coordinator.profile.guidanceOnlyMode {
                Text("ARIA will coach with guidance only for the conditions you shared.")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
            }
            PrimaryCTA(
                title: coordinator.isCompleting ? "Activating ARIA…" : "Start training with ARIA",
                icon: "flame.fill",
                enabled: !coordinator.isCompleting && coordinator.canFinish,
                action: onFinish
            )
        }
    }
}

private struct PrimaryCTA: View {
    let title: String
    let icon: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.headline.weight(.bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(enabled ? AnyShapeStyle(FDS.Gradient.ember) : AnyShapeStyle(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Bubbles

private struct MessageBubble: View {
    let message: AriaOnboardingMessage
    @State private var appeared = false

    var body: some View {
        Group {
            switch message.role {
            case .aria:
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(FDS.Gradient.ember)
                        .frame(width: 28, height: 28)
                        .overlay(Text("A").font(.caption2.weight(.black)).foregroundColor(.white))
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundColor(.textPrimary)
                        .lineSpacing(3)
                        .padding(12)
                        .background(Color.surface.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.ember.opacity(0.2), lineWidth: 1)
                        )
                    Spacer(minLength: 24)
                }
            case .user:
                HStack {
                    Spacer(minLength: 40)
                    Text(message.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.ember.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            case .system:
                HStack {
                    Spacer()
                    Label(message.text, systemImage: "heart.text.square.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                    Spacer()
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(FDS.Spring.standard) { appeared = true }
        }
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(FDS.Gradient.ember)
                .frame(width: 28, height: 28)
                .overlay(Text("A").font(.caption2.weight(.black)).foregroundColor(.white))
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.textMuted)
                        .frame(width: 6, height: 6)
                        .offset(y: sin(phase + Double(i)) * 3)
                }
            }
            .padding(12)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

private struct HealthKitStatusPill: View {
    let state: HealthKitState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(state.label)
                .font(.caption2.weight(.bold))
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.borderColor, lineWidth: 0.5))
    }

    private var dotColor: Color {
        switch state {
        case .authorized: return .success
        case .requesting: return .warning
        case .denied, .unavailable: return .textMuted
        case .unknown: return .steel
        }
    }
}

// MARK: - Age blocked

private struct AgeBlockedView: View {
    let onReset: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.danger)
            Text("Access Restricted")
                .font(.title.weight(.bold))
                .foregroundColor(.textPrimary)
            Text("FORGE requires users to be at least 13 years old.")
                .font(.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(action: onReset) {
                Text("Review birthday")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
            }
            .padding(.horizontal, FDS.Spacing.xl)
            .padding(.bottom, 40)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { appeared = true }
    }
}

// MARK: - Ambient background

struct ForgeAmbientBackground: View {
    let step: Int
    @State private var phase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.background, Color(hex: "140A06").opacity(0.78), Color.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [routeColor.opacity(0.18), routeColor.opacity(0.05), .clear],
                center: UnitPoint(x: 0.32, y: 0.18),
                startRadius: 10,
                endRadius: 520
            )
            .blur(radius: 44)

            if !reduceMotion {
                RadialGradient(
                    colors: [Color.ember.opacity(0.09), .clear],
                    center: UnitPoint(x: 0.5 + 0.24 * cos(phase), y: 0.48 + 0.18 * sin(phase)),
                    startRadius: 0,
                    endRadius: 360
                )
                .blur(radius: 60)
                .onAppear {
                    withAnimation(.linear(duration: FDS.Duration.ambient).repeatForever(autoreverses: false)) {
                        phase = .pi * 2
                    }
                }
            }
        }
    }

    private var routeColor: Color {
        switch step {
        case 0, 1, 2: return Color(hex: "A855F7")
        case 3: return .steel
        case 7, 8, 9: return Color(hex: "22C55E")
        case 10: return .warning
        default: return .ember
        }
    }
}

// MARK: - Shared helpers (used by SmartProfileSetupView etc.)

struct ForgeSectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var accentColor: Color = .ember
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Capsule().fill(accentColor).frame(width: appeared ? 22 : 8, height: 3)
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(2.8)
                    .foregroundColor(accentColor)
            }
            .opacity(appeared ? 1 : 0)

            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(LinearGradient(
                    colors: [.white, Color.white.opacity(0.76)],
                    startPoint: .top, endPoint: .bottom
                ))
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)

            Text(subtitle)
                .font(.body)
                .foregroundColor(.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
        }
        .animation(FDS.Spring.hero, value: appeared)
        .onAppear { appeared = true }
    }
}

struct ForgeTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(focused ? .ember : .textMuted)
                .frame(width: 22)
            ZStack(alignment: .leading) {
                if text.isEmpty { Text(placeholder).foregroundColor(.textMuted) }
                if isSecure {
                    SecureField("", text: $text).focused($focused)
                } else {
                    TextField("", text: $text)
                        .focused($focused)
                        .keyboardType(keyboardType)
                }
            }
            .font(.body)
            .foregroundColor(.textPrimary)
            .tint(.ember)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .background(focused ? Color.ember.opacity(0.05) : Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                .stroke(focused ? Color.ember.opacity(0.60) : Color.borderColor, lineWidth: focused ? 1.4 : 0.7)
        )
    }
}

struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
    }
}

// MARK: - Shared cards (SmartProfileSetupView + others)

struct GenderSelectionCard: View {
    let gender: Gender
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
            FDS.selectionHaptic()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.ember.opacity(0.16) : Color.surfaceElevated)
                        .frame(width: 48, height: 48)
                    if isSelected {
                        Circle().stroke(Color.ember.opacity(0.4), lineWidth: 1.5).frame(width: 48, height: 48)
                    }
                    Image(systemName: gender.icon)
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? .ember : .textSecondary)
                }
                Text(gender.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isSelected ? .ember : .textPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.ember : Color.borderColor, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color.ember).frame(width: 12, height: 12)
                    }
                }
            }
            .padding(16)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(isSelected ? Color.ember.opacity(0.5) : Color.borderColor, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TogglePill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isSelected ? .ember : .textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color.ember.opacity(0.13) : Color.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color.ember.opacity(0.55) : Color.borderColor,
                        lineWidth: isSelected ? 1.4 : 0.7
                    )
                )
        }
        .buttonStyle(.plain)
        .animation(FDS.Spring.snap, value: isSelected)
    }
}

// MARK: - Dev skip

#if DEBUG
private struct DevSkipButton: View {
    var coordinator: OnboardingCoordinator
    @EnvironmentObject private var store: AppStore
    @State private var expanded = false

    var body: some View {
        VStack {
            HStack {
                Spacer()
                if expanded {
                    Button("Skip All →") { coordinator.devSkipToEnd(in: store) }
                        .font(.caption.weight(.black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.ember)
                        .clipShape(Capsule())
                } else {
                    Button("DEV") { withAnimation(FDS.Spring.snap) { expanded = true } }
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.warning)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, FDS.Spacing.xl)
            .padding(.top, 8)
            Spacer()
        }
    }
}
#endif

#Preview("ARIA Onboarding") {
    OnboardingView()
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}
