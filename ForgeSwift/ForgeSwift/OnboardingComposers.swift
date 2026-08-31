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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Preferred name")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.textSecondary)
                HStack(spacing: 10) {
                    TextField("Maya", text: $coordinator.profile.name)
                        .focused($focusedField, equals: .preferred)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .onSubmit { focusedField = .last }

                    DictationMicButton(dictation: dictation) {
                        applySpokenName()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            focusedField == .preferred || dictation.isListening
                                ? Color.ember.opacity(0.55)
                                : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
                Text("What you’ll hear in coaching. First name is enough.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Last name")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.textSecondary)
                    Text("optional")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.textMuted)
                }

                TextField("Chen", text: $coordinator.profile.lastName)
                    .focused($focusedField, equals: .last)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                focusedField == .last ? Color.ember.opacity(0.4) : Color.white.opacity(0.07),
                                lineWidth: 1
                            )
                    )
                    .onSubmit { submit() }
                Text("Stays on your profile. ARIA won’t say it unless you ask.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)
            }

            if coordinator.profile.isPreferredNameValid {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.ember)
                    Text("ARIA will call you \(coordinator.profile.firstName).")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ember.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            PrimaryCTA(
                title: coordinator.profile.trimmedName.isEmpty ? "Continue" : "Continue as \(coordinator.profile.firstName)",
                icon: "arrow.right",
                enabled: coordinator.profile.isPreferredNameValid,
                action: submit
            )
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

    private func applySpokenName() {
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
        VStack(alignment: .leading, spacing: 14) {
            if !coordinator.profile.detailsSummaryLine.isEmpty {
                Text(coordinator.profile.detailsSummaryLine)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            birthdayBlock
            sexBlock
            bodyBlock

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
        VStack(alignment: .leading, spacing: 10) {
            fieldHeader(
                "Date of birth",
                sourced: coordinator.profile.healthSourcedFields.contains(.birthday)
            )
            Text("Heart-rate zones, recovery norms, and 13+ safety.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)

            if coordinator.profile.birthday == nil, !showBirthdayPicker {
                Button {
                    coordinator.profile.birthday = Self.startingBirthday
                    showBirthdayPicker = true
                    FDS.haptic(.light)
                } label: {
                    HStack {
                        Text("Select date")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.ember)
                    }
                    .padding(16)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(coordinator.isUnderage ? "Must be 13+" : "\(coordinator.profile.ageYears)")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundColor(coordinator.isUnderage ? .danger : .textPrimary)
                        .contentTransition(.numericText())
                    Text(coordinator.isUnderage ? "" : "years old")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
                DatePicker(
                    "Date of birth",
                    selection: birthdayBinding,
                    in: minimumBirthday...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxHeight: 120)
            }
        }
        .padding(16)
        .background(Color.surfaceElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var sexBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldHeader(
                "Biological sex",
                sourced: coordinator.profile.healthSourcedFields.contains(.sex)
            )
            Text("Calories, heart-rate zones, Cycle Health. Not gender — that’s in Profile.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            BiologicalSexStepView(coordinator: coordinator)
        }
        .padding(16)
        .background(Color.surfaceElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var bodyBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                fieldHeader(
                    "Height & weight",
                    sourced: coordinator.profile.healthSourcedFields.contains(.height)
                        || coordinator.profile.healthSourcedFields.contains(.weight)
                )
                Spacer()
                Picker("Units", selection: $coordinator.profile.usesMetricUnits) {
                    Text("ft / lb").tag(false)
                    Text("cm / kg").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 168)
            }
            Text("Optional. Used for calorie and load math.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)

            if coordinator.profile.usesMetricUnits {
                HStack(spacing: 10) {
                    metricField(placeholder: "170", text: $heightCmText, unit: "cm") { value in
                        if let cm = Double(value.replacingOccurrences(of: ",", with: ".")),
                           (90...250).contains(cm) {
                            coordinator.profile.heightCm = cm
                            coordinator.profile.healthSourcedFields.remove(.height)
                        } else if value.trimmingCharacters(in: .whitespaces).isEmpty {
                            coordinator.profile.heightCm = nil
                        }
                    }
                    metricField(placeholder: "70", text: $weightText, unit: "kg") { value in
                        applyWeightText(value)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    unitField(placeholder: "5", text: $heightFeet, unit: "ft") { syncImperialHeight() }
                    unitField(placeholder: "10", text: $heightInches, unit: "in") { syncImperialHeight() }
                    metricField(placeholder: "160", text: $weightText, unit: "lb") { value in
                        applyWeightText(value)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.surfaceElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func fieldHeader(_ title: String, sourced: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.textSecondary)
            if sourced {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("Apple Health")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.vitality)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.vitality.opacity(0.14))
                .clipShape(Capsule())
            }
        }
    }

    private func unitField(placeholder: String, text: Binding<String>, unit: String, onChange: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .onChange(of: text.wrappedValue) { _, _ in onChange() }
            Text(unit)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textMuted)
        }
        .padding(.horizontal, 10)
        .background(Color.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metricField(placeholder: String, text: Binding<String>, unit: String, onEdit: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .onChange(of: text.wrappedValue) { _, value in
                    guard !hydratingFields else { return }
                    onEdit(value)
                }
            Text(unit)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textMuted)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Color.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func applyWeightText(_ value: String) {
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
        VStack(spacing: 16) {
            // Health + Calendar — one permission moment, two toggles
            VStack(spacing: 12) {
                ConnectionRow(
                    icon: "heart.text.square.fill", color: .vitality,
                    title: "Apple Health", subtitle: "Sleep, heart, activity — on this iPhone",
                    state: coordinator.healthKitState, action: coordinator.connectHealthKit
                )
                ConnectionRow(
                    icon: "calendar", color: .steel,
                    title: "Apple Calendar", subtitle: "Busy windows only — never titles. Fits training around your day.",
                    state: coordinator.calendarState, action: { Task { await coordinator.connectCalendar() } }
                )
            }

            Text("Both optional. One tap each, or skip — you can add them later in Settings.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)

            Button("Continue") { Task { await coordinator.continueFromHealth() } }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
        }
    }
}

private struct ConnectionRow: View {
    let icon: String; let color: Color; let title: String; let subtitle: String
    let state: HealthKitState; let action: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.12)).frame(width: 48, height: 48)
                if state == .requesting {
                    ProgressView().tint(color)
                } else {
                    Image(systemName: state == .authorized ? "checkmark.seal.fill" : icon)
                        .font(.system(size: 22, weight: .semibold)).foregroundColor(state == .authorized ? .success : color)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.textPrimary)
                Text(state == .authorized ? "Connected" : subtitle).font(.system(size: 12, weight: .medium)).foregroundColor(state == .authorized ? .success : .textTertiary).lineLimit(2)
            }
            Spacer()
            if state != .authorized {
                Button(action: action) {
                    Text("Connect").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(color).cornerRadius(9)
                }.disabled(state == .requesting)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.success)
            }
        }
        .padding(14).background(Color.surfaceElevated.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.textSecondary)

            OnboardingFlowLayout(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    let selected = isSelected(item.id)
                    Button { onToggle(item.id) } label: {
                        Text(item.label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(selected ? .white : .textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(selected ? Color.ember.opacity(0.88) : Color.surfaceElevated)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(selected ? Color.ember.opacity(0.9) : Color.white.opacity(0.07), lineWidth: 1)
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
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(opt.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.textPrimary)
                            if !opt.subtitle.isEmpty {
                                Text(opt.subtitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textMuted)
                    }
                    .padding(16)
                    .background(Color.surfaceElevated.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
                .buttonStyle(AuthPressButtonStyle())
            }
        }
    }
}

struct ConditionsComposer: View {
    @Bindable var coordinator: OnboardingCoordinator
    @ObservedObject var dictation: SpeechManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conditions to respect")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.textSecondary)

            Text("Optional. Lifestyle coach only — not medical care.")
                .font(.system(size: 12, weight: .medium))
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
                    .padding(16)
                    .background(Color.surfaceElevated.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(style.color.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(AuthPressButtonStyle())
            }
        }
    }
}

struct ReadyComposer: View {
    @Bindable var coordinator: OnboardingCoordinator
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if !coordinator.profile.firstName.isEmpty {
                Text("You’re set, \(coordinator.profile.firstName).")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
            }
            if coordinator.profile.guidanceOnlyMode {
                Text("ARIA will coach with guidance only for the conditions you shared.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
            }
            // Liability disclaimer — must be agreed at the very end
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    coordinator.hasAgreedToTerms.toggle()
                    if coordinator.hasAgreedToTerms { FDS.haptic(.light) }
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).stroke(coordinator.hasAgreedToTerms ? Color.ember : Color.borderColor, lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                            .background(coordinator.hasAgreedToTerms ? Color.ember : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        if coordinator.hasAgreedToTerms {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        }
                    }
                    Text("By agreeing to our Terms of Use, you acknowledge that Forge is an assistive coaching tool, not medical care. You are responsible for your own health. Any actions taken or injuries sustained are not the liability of Forge. Forge is designed to assist and advise, not to compel. By checking this box you waive all liability towards Forge.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .padding(12)
                .background(Color.surfaceElevated.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(coordinator.hasAgreedToTerms ? Color.ember.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1))
            }
            .buttonStyle(.plain)

            PrimaryCTA(
                title: coordinator.isCompleting ? "Starting…" : "Start with ARIA",
                icon: "arrow.right",
                enabled: !coordinator.isCompleting && coordinator.canFinish,
                action: onFinish
            )
            if !coordinator.hasAgreedToTerms {
                Text("Please agree to the Terms to continue.")
                    .font(.caption.weight(.semibold)).foregroundColor(.warning)
            }
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
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(enabled ? AnyShapeStyle(FDS.Gradient.ember) : AnyShapeStyle(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: enabled ? Color.ember.opacity(0.35) : .clear, radius: 16, y: 8)
        }
        .buttonStyle(AuthPressButtonStyle())
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
                HStack(alignment: .top, spacing: 0) {
                    Text(message.text)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .lineSpacing(4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Spacer(minLength: 36)
                }
            case .user:
                HStack {
                    Spacer(minLength: 48)
                    Text(message.text)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.ember.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.textMuted)
                        .frame(width: 6, height: 6)
                        .offset(y: sin(phase + Double(i)) * 3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
