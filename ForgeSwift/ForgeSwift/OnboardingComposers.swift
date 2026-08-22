import SwiftUI

struct AgeComposer: View {
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

struct NameComposer: View {
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
struct DictationMicButton: View {
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

struct HealthComposer: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 10) {
            PrimaryCTA(
                title: coordinator.healthKitState == .requesting ? "Connecting…" : "Connect Apple Health",
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

struct MultiChipComposer: View {
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

struct OptionCardsComposer: View {
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

struct ConditionsComposer: View {
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

struct CoachingComposer: View {
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

struct ReadyComposer: View {
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

struct PrimaryCTA: View {
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

struct MessageBubble: View {
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

struct TypingIndicator: View {
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

struct HealthKitStatusPill: View {
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
