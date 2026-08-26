import SwiftUI
import UIKit

/// Preferred name + optional last name. Modeled on Claude/Grok ("what should we call you")
/// and Apple Health Health Details (first / last as separate fields).
struct NameComposer: View {
    @Bindable var coordinator: OnboardingCoordinator
    @ObservedObject var dictation: SpeechManager
    @FocusState private var focusedField: NameField?

    private enum NameField: Hashable { case preferred, last }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeledField(
                title: "Preferred name",
                footnote: "ARIA uses this in coaching. First name is enough.",
                placeholder: "Maya",
                text: $coordinator.profile.name,
                field: .preferred,
                contentType: .givenName
            )

            labeledField(
                title: "Last name",
                footnote: "Optional. Stays on your profile — ARIA won’t say it unless you ask.",
                placeholder: "Optional",
                text: $coordinator.profile.lastName,
                field: .last,
                contentType: .familyName
            )

            if coordinator.profile.isPreferredNameValid {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                    Text("ARIA will call you \(coordinator.profile.firstName).")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.textSecondary)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 10) {
                DictationMicButton(dictation: dictation) {
                    let spoken = dictation.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !spoken.isEmpty else { return }
                    let parts = spoken.split(separator: " ").map(String.init)
                    if focusedField == .last, parts.count == 1 {
                        coordinator.profile.lastName = spoken
                    } else if parts.count >= 2 {
                        coordinator.profile.name = parts[0]
                        coordinator.profile.lastName = parts.dropFirst().joined(separator: " ")
                    } else {
                        coordinator.profile.name = spoken
                    }
                }

                PrimaryCTA(
                    title: coordinator.profile.trimmedName.isEmpty ? "Continue" : "Confirm \(coordinator.profile.firstName)",
                    icon: "arrow.right",
                    enabled: coordinator.profile.isPreferredNameValid,
                    action: submit
                )
            }
        }
        .onAppear {
            if coordinator.profile.trimmedName.isEmpty {
                focusedField = .preferred
            }
        }
        .onChange(of: dictation.recognizedText) { _, text in
            guard dictation.isListening, focusedField != .last else { return }
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty { coordinator.profile.name = spoken }
        }
        .animation(FDS.Spring.snap, value: dictation.isListening)
        .animation(FDS.Spring.snap, value: coordinator.profile.isPreferredNameValid)
    }

    private func labeledField(
        title: String,
        footnote: String,
        placeholder: String,
        text: Binding<String>,
        field: NameField,
        contentType: UITextContentType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.black))
                .tracking(1.3)
                .foregroundColor(.textMuted)
            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .textContentType(contentType)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                        .stroke(
                            focusedField == field ? Color.ember.opacity(0.55) : Color.borderColor,
                            lineWidth: focusedField == field ? 1.5 : 1
                        )
                )
                .onSubmit {
                    if field == .preferred { focusedField = .last } else { submit() }
                }
            Text(footnote)
                .font(.caption2)
                .foregroundColor(.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() {
        dictation.cancel()
        coordinator.submitName()
    }
}

/// Date of birth, biological sex, height, weight — Apple Health / Bevel Health Details,
/// not a riddle. Prefills from Apple Health when connected; every field is labeled with why.
struct DetailsComposer: View {
    @Bindable var coordinator: OnboardingCoordinator
    @State private var showBirthdayPicker = false
    @State private var heightFeet = ""
    @State private var heightInches = ""
    @State private var heightCmText = ""
    @State private var weightText = ""
    @State private var hydratingFields = false

    private var minimumBirthday: Date {
        Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? Date()
    }

    private var birthdayBinding: Binding<Date> {
        Binding(
            get: { coordinator.profile.birthday ?? Self.startingBirthday },
            set: { coordinator.profile.birthday = $0 }
        )
    }

    private static var startingBirthday: Date {
        Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !coordinator.profile.detailsSummaryLine.isEmpty {
                Text(coordinator.profile.detailsSummaryLine)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.ember)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ember.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous))
            }

            birthdayBlock
            sexBlock
            unitsToggle
            heightBlock
            weightBlock

            PrimaryCTA(
                title: coordinator.isUnderage ? "Must be 13 or older" : "Confirm details",
                icon: "arrow.right",
                enabled: coordinator.profile.hasConfirmedDetails && !coordinator.isUnderage,
                action: coordinator.confirmDetails
            )
        }
        .onAppear { hydrateBodyFields() }
        .onChange(of: coordinator.profile.heightCm) { _, _ in hydrateBodyFields() }
        .onChange(of: coordinator.profile.weightKg) { _, _ in hydrateBodyFields() }
        .onChange(of: coordinator.profile.usesMetricUnits) { _, _ in hydrateBodyFields() }
    }

    private var birthdayBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldHeader(
                "Date of birth",
                sourced: coordinator.profile.healthSourcedFields.contains(.birthday)
            )
            Text("Used for 13+ safety, heart-rate zones, and recovery norms — not a vibe check.")
                .font(.caption2)
                .foregroundColor(.textTertiary)

            if coordinator.profile.birthday == nil, !showBirthdayPicker {
                Button {
                    coordinator.profile.birthday = Self.startingBirthday
                    showBirthdayPicker = true
                    FDS.haptic(.light)
                } label: {
                    HStack {
                        Text("Select date of birth")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Image(systemName: "calendar")
                            .foregroundColor(.ember)
                    }
                    .padding(14)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                            .stroke(Color.borderColor, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                DatePicker(
                    "Date of birth",
                    selection: birthdayBinding,
                    in: minimumBirthday...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxHeight: 132)

                Text(coordinator.isUnderage ? "Must be 13+" : "\(coordinator.profile.ageYears) years old")
                    .font(.title3.weight(.bold))
                    .foregroundColor(coordinator.isUnderage ? .danger : .textPrimary)
            }
        }
    }

    private var sexBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldHeader(
                "Biological sex",
                sourced: coordinator.profile.healthSourcedFields.contains(.sex)
            )
            Text("Used for calorie estimates, heart-rate zones, and Cycle Health. This is not gender — you can set that later in Profile.")
                .font(.caption2)
                .foregroundColor(.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            BiologicalSexStepView(coordinator: coordinator)
        }
    }

    private var unitsToggle: some View {
        HStack {
            Text("UNITS")
                .font(.caption2.weight(.black))
                .tracking(1.3)
                .foregroundColor(.textMuted)
            Spacer()
            Picker("Units", selection: $coordinator.profile.usesMetricUnits) {
                Text("ft / lb").tag(false)
                Text("cm / kg").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
        }
    }

    private var heightBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldHeader(
                coordinator.profile.usesMetricUnits ? "Height (cm)" : "Height",
                sourced: coordinator.profile.healthSourcedFields.contains(.height)
            )
            Text("Used for calorie and load math. Skip if you don’t know — Apple Health can fill this later.")
                .font(.caption2)
                .foregroundColor(.textTertiary)

            if coordinator.profile.usesMetricUnits {
                HStack(spacing: 8) {
                    TextField("170", text: $heightCmText)
                        .keyboardType(.decimalPad)
                        .padding(14)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                        .onChange(of: heightCmText) { _, value in
                            guard !hydratingFields else { return }
                            if let cm = Double(value.replacingOccurrences(of: ",", with: ".")),
                               (90...250).contains(cm) {
                                coordinator.profile.heightCm = cm
                                coordinator.profile.healthSourcedFields.remove(.height)
                            } else if value.trimmingCharacters(in: .whitespaces).isEmpty {
                                coordinator.profile.heightCm = nil
                            }
                        }
                    Text("cm")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textMuted)
                }
            } else {
                HStack(spacing: 10) {
                    unitField(placeholder: "5", text: $heightFeet, unit: "ft") { syncImperialHeight() }
                    unitField(placeholder: "10", text: $heightInches, unit: "in") { syncImperialHeight() }
                }
            }
        }
    }

    private var weightBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldHeader(
                coordinator.profile.usesMetricUnits ? "Weight (kg)" : "Weight (lb)",
                sourced: coordinator.profile.healthSourcedFields.contains(.weight)
            )
            Text("Used for calorie targets. Approximate is fine.")
                .font(.caption2)
                .foregroundColor(.textTertiary)

            HStack(spacing: 8) {
                TextField(coordinator.profile.usesMetricUnits ? "70" : "160", text: $weightText)
                    .keyboardType(.decimalPad)
                    .padding(14)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    .onChange(of: weightText) { _, value in
                        guard !hydratingFields else { return }
                        let cleaned = value.replacingOccurrences(of: ",", with: ".")
                        guard let number = Double(cleaned) else {
                            if value.trimmingCharacters(in: .whitespaces).isEmpty {
                                coordinator.profile.weightKg = nil
                            }
                            return
                        }
                        if coordinator.profile.usesMetricUnits {
                            guard (30...300).contains(number) else { return }
                            coordinator.profile.weightKg = number
                        } else {
                            guard (50...800).contains(number) else { return }
                            coordinator.profile.weightKg = OnboardingBodyUnits.kilograms(lbs: number)
                        }
                        coordinator.profile.healthSourcedFields.remove(.weight)
                    }
                Text(coordinator.profile.usesMetricUnits ? "kg" : "lb")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textMuted)
            }
        }
    }

    private func fieldHeader(_ title: String, sourced: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.black))
                .tracking(1.3)
                .foregroundColor(.textMuted)
            if sourced {
                Text("Apple Health")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.success)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.success.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
    }

    private func unitField(placeholder: String, text: Binding<String>, unit: String, onChange: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .padding(14)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                .onChange(of: text.wrappedValue) { _, _ in onChange() }
            Text(unit)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textMuted)
        }
    }

    private func hydrateBodyFields() {
        hydratingFields = true
        if let cm = coordinator.profile.heightCm {
            let pair = OnboardingBodyUnits.feetAndInches(cm: cm)
            heightFeet = String(pair.feet)
            heightInches = String(pair.inches)
            heightCmText = String(Int(cm.rounded()))
        }
        if let kg = coordinator.profile.weightKg {
            if coordinator.profile.usesMetricUnits {
                weightText = String(format: "%g", (kg * 10).rounded() / 10)
            } else {
                weightText = String(Int(OnboardingBodyUnits.pounds(kg: kg).rounded()))
            }
        }
        if coordinator.profile.birthday != nil {
            showBirthdayPicker = true
        }
        hydratingFields = false
    }

    private func syncImperialHeight() {
        guard !hydratingFields else { return }
        let feet = Int(heightFeet) ?? 0
        let inches = Int(heightInches) ?? 0
        if feet == 0 && inches == 0 && heightFeet.isEmpty && heightInches.isEmpty {
            coordinator.profile.heightCm = nil
            return
        }
        let totalInches = feet * 12 + inches
        guard (36...96).contains(totalInches) else { return }
        coordinator.profile.heightCm = OnboardingBodyUnits.centimeters(feet: feet, inches: inches)
        coordinator.profile.healthSourcedFields.remove(.height)
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
                title: coordinator.profile.reportedConditions.isEmpty ? "Skip" : "Continue",
                icon: "arrow.right",
                enabled: true,
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
