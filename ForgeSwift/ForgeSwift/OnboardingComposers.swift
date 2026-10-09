import SwiftUI
import ForgeCore

/// First interview beat — living ARIA mark with soft presence, not fire.
struct IntroComposer: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: FDS.Spacing.lg) {
            ZStack {
                PremiumPresenceBloom(
                    size: 200,
                    accent: .ember,
                    frost: Color(hex: "A9D8FF")
                )
                AuroraOrbView(
                    state: coordinator.ariaOrbState,
                    amplitude: coordinator.ariaOrbState == .speaking ? 0.8 : 0.58,
                    mood: coordinator.ariaMood,
                    size: 140,
                    followPresence: true
                )
            }
            .frame(height: 188)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("ARIA")

            Text("ARIA")
                .font(ForgeType.micro)
                .tracking(ForgeType.eyebrowTracking)
                .foregroundStyle(Color.paper.opacity(0.72))

            Text("Your lifestyle coach — built for the life you already have.")
                .font(ForgeType.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FDS.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, FDS.Spacing.xs)
    }
}

/// Preferred name + optional last name. Modeled on Claude/Grok ("what should we call you")
/// and Apple Health Health Details (first / last as separate fields).
struct NameComposer: View {
    @Bindable var coordinator: OnboardingCoordinator
    @ObservedObject var dictation: SpeechManager
    @FocusState private var focusedField: NameField?

    private enum NameField: Hashable { case preferred, last }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                Text("Preferred name")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(Color.textSecondary)
                HStack(spacing: FDS.Spacing.md) {
                    TextField("Maya", text: $coordinator.profile.name)
                        .focused($focusedField, equals: .preferred)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                        .onSubmit { focusedField = .last }
                }
                .padding(.horizontal, FDS.Spacing.lg)
                .padding(.vertical, FDS.Spacing.md)
                .forgeInsetTile(radius: FDS.Radius.lg)
                .overlay {
                    RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                        .stroke(
                            focusedField == .preferred || dictation.isListening
                                ? Color.ember.opacity(0.55)
                                : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                }
                Text("What I’ll call you. First name is enough.")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                HStack(spacing: FDS.Spacing.sm) {
                    Text("Last name")
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text("optional")
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundStyle(Color.textMuted)
                }

                TextField("Chen", text: $coordinator.profile.lastName)
                    .focused($focusedField, equals: .last)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, FDS.Spacing.lg)
                    .padding(.vertical, FDS.Spacing.lg)
                    .forgeInsetTile(radius: FDS.Radius.lg)
                    .overlay {
                        RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                            .stroke(
                                focusedField == .last ? Color.ember.opacity(0.4) : Color.white.opacity(0.07),
                                lineWidth: 1
                            )
                    }
                    .onSubmit { submit() }
                Text("Stays on your profile. ARIA won’t say it unless you ask.")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            if coordinator.profile.isPreferredNameValid {
                HStack(spacing: FDS.Spacing.sm) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ember)
                    Text("ARIA will call you \(coordinator.profile.firstName) — every day.")
                        .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                }
                .padding(.horizontal, FDS.Spacing.lg)
                .padding(.vertical, FDS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ember.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
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
            if case .fillName(let name) = AriaInterviewVoice.matchSpoken(text, step: .name, profile: coordinator.profile) {
                coordinator.applySpokenName(name)
            }
        }
        .animation(FDS.Spring.snap, value: dictation.isListening)
        .animation(FDS.Spring.snap, value: coordinator.profile.isPreferredNameValid)
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
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            if !coordinator.profile.detailsSummaryLine.isEmpty {
                Text(coordinator.profile.detailsSummaryLine)
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, FDS.Spacing.lg)
                    .padding(.vertical, FDS.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
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
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            fieldHeader(
                "Date of birth",
                sourced: coordinator.profile.healthSourcedFields.contains(.birthday)
            )
            Text("Heart-rate zones, recovery norms, and 13+ safety.")
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textTertiary)

            if coordinator.profile.birthday == nil, !showBirthdayPicker {
                Button {
                    coordinator.profile.birthday = Self.startingBirthday
                    showBirthdayPicker = true
                    FDS.haptic(.light)
                } label: {
                    HStack {
                        Text("Select date")
                            .font(FDS.TypeScale.Dynamic.headline)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ember)
                    }
                    .padding(FDS.Spacing.lg)
                    .forgeInsetTile(radius: FDS.Radius.lg)
                }
                .buttonStyle(.plain)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(coordinator.isUnderage ? "Must be 13+" : "\(coordinator.profile.ageYears)")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(coordinator.isUnderage ? Color.danger : Color.textPrimary)
                        .contentTransition(.numericText())
                    Text(coordinator.isUnderage ? "" : "years old")
                        .font(FDS.TypeScale.Dynamic.body)
                        .foregroundStyle(Color.textSecondary)
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
                .preferredColorScheme(.dark)
                .frame(maxHeight: 120)
            }
        }
        .padding(FDS.Spacing.lg)
        .background(Color.surfaceElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var sexBlock: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            fieldHeader(
                "Biological sex",
                sourced: coordinator.profile.healthSourcedFields.contains(.sex)
            )
            Text("Calories, heart-rate zones, Cycle Health. Not gender — that’s in Profile.")
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            BiologicalSexStepView(coordinator: coordinator)
        }
        .padding(FDS.Spacing.lg)
        .background(Color.surfaceElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var bodyBlock: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
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
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textTertiary)

            if coordinator.profile.usesMetricUnits {
                HStack(spacing: FDS.Spacing.md) {
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
                HStack(spacing: FDS.Spacing.md) {
                    unitField(placeholder: "5", text: $heightFeet, unit: "ft") { syncImperialHeight() }
                    unitField(placeholder: "10", text: $heightInches, unit: "in") { syncImperialHeight() }
                    metricField(placeholder: "160", text: $weightText, unit: "lb") { value in
                        applyWeightText(value)
                    }
                }
            }
        }
        .padding(FDS.Spacing.lg)
        .background(Color.surfaceElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func fieldHeader(_ title: String, sourced: Bool) -> some View {
        HStack(spacing: FDS.Spacing.sm) {
            Text(title)
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textSecondary)
            if sourced {
                HStack(spacing: FDS.Spacing.xs) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("Apple Health")
                        .font(FDS.TypeScale.Dynamic.micro)
                }
                .foregroundStyle(Color.vitality)
                .padding(.horizontal, FDS.Spacing.sm)
                .padding(.vertical, FDS.Spacing.xs)
                .background(Color.vitality.opacity(0.14))
                .clipShape(Capsule())
            }
        }
    }

    private func unitField(placeholder: String, text: Binding<String>, unit: String, onChange: @escaping () -> Void) -> some View {
        HStack(spacing: FDS.Spacing.sm) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, FDS.Spacing.md)
                .onChange(of: text.wrappedValue) { _, _ in onChange() }
            Text(unit)
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textMuted)
        }
        .padding(.horizontal, FDS.Spacing.md)
        .background(Color.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
    }

    private func metricField(placeholder: String, text: Binding<String>, unit: String, onEdit: @escaping (String) -> Void) -> some View {
        HStack(spacing: FDS.Spacing.sm) {
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, FDS.Spacing.md)
                .onChange(of: text.wrappedValue) { _, value in
                    guard !hydratingFields else { return }
                    onEdit(value)
                }
            Text(unit)
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textMuted)
        }
        .padding(.horizontal, FDS.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
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
                    .foregroundStyle(dictation.isListening ? Color.ember : Color.textSecondary)
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

    private var pulling: Bool {
        coordinator.isHealthPulling
    }

    private var healthStatus: String {
        AriaInterviewVoice.healthStatusLabel(state: coordinator.healthKitState, pulling: pulling)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                Text(AriaInterviewVoice.healthWrapper)
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundStyle(Color.textPrimary)
                Text(AriaInterviewVoice.healthBody)
                    .font(FDS.TypeScale.Dynamic.body)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: FDS.Spacing.md) {
                ConnectionRow(
                    icon: "heart.text.square.fill", color: .vitality,
                    title: "Apple Health",
                    subtitle: "Sleep and movement I can learn with you",
                    state: coordinator.healthKitState,
                    statusOverride: healthStatus,
                    action: coordinator.connectHealthKit
                )
                ConnectionRow(
                    icon: "calendar", color: .steel,
                    title: "Apple Calendar",
                    subtitle: "This week's busy windows — never titles",
                    state: coordinator.calendarState,
                    action: { Task { await coordinator.connectCalendar() } }
                )
                ConnectionRow(
                    icon: "person.2.fill", color: Color(hex: "7EC8FF"),
                    title: "Contacts",
                    subtitle: "First names you pick — never the whole book",
                    state: coordinator.contactsState,
                    action: coordinator.connectContacts
                )
                ConnectionRow(
                    icon: "checklist", color: .ember,
                    title: "Reminders",
                    subtitle: "Counts only — titles stay on this iPhone",
                    state: coordinator.remindersState,
                    action: coordinator.connectReminders
                )
            }

            if let hint = coordinator.lastHealthSharingHint, !hint.isEmpty {
                Text(hint)
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(hint)
            }

            Button("Continue") { coordinator.continueFromHealth() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 44)
                .forgeGlassCard(cornerRadius: FDS.Radius.md, accent: .ember)

            if let line = coordinator.emptyBackfillLine {
                HStack(alignment: .top, spacing: FDS.Spacing.md) {
                    Text(line)
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Health Sharing") { coordinator.openHealthSharingManually() }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize()
                        .accessibilityLabel("Open Health Sharing")
                }
            }
        }
    }
}

private struct ConnectionRow: View {
    let icon: String; let color: Color; let title: String; let subtitle: String
    let state: HealthKitState
    var statusOverride: String? = nil
    let action: () -> Void

    private var statusText: String {
        statusOverride ?? AriaInterviewVoice.healthStatusLabel(state: state, pulling: state == .requesting)
    }

    private var isLive: Bool { statusText == "Connected" }
    private var isPulling: Bool { statusText == "Pulling…" }

    var body: some View {
        HStack(spacing: FDS.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: FDS.Radius.md).fill(color.opacity(0.12)).frame(width: 48, height: 48)
                if isPulling {
                    ProgressView().tint(color)
                } else {
                    Image(systemName: isLive ? "checkmark.seal.fill" : icon)
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(isLive ? Color.success : color)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundStyle(Color.textPrimary)
                Text(isLive || isPulling ? statusText : "\(statusText) · \(subtitle)")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(isLive ? Color.success : Color.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
            if !isLive {
                Button(action: action) {
                    Text(state == .denied ? "Reconnect" : "Connect").font(FDS.TypeScale.Dynamic.caption).foregroundStyle(.white)
                        .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.sm).background(color).clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm))
                }.disabled(isPulling)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
            }
        }
        .padding(FDS.Spacing.lg).background(Color.surfaceElevated.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FDS.Radius.lg)
                .stroke(Color(hex: "7EC8FF").opacity(isLive ? 0.42 : 0.14), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            Text(title)
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textSecondary)

            OnboardingFlowLayout(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    let selected = isSelected(item.id)
                    Button { onToggle(item.id) } label: {
                        Text(item.label)
                            .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                            .foregroundStyle(selected ? .white : Color.textSecondary)
                            .padding(.horizontal, FDS.Spacing.lg)
                            .padding(.vertical, FDS.Spacing.md)
                            .background(selected ? Color.ember.opacity(0.88) : Color.surfaceElevated)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(selected ? Color.ember.opacity(0.9) : Color.white.opacity(0.07), lineWidth: 1)
                            }
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
        VStack(spacing: FDS.Spacing.sm) {
            ForEach(options, id: \.id) { opt in
                Button { onSelect(opt.id) } label: {
                    HStack(spacing: FDS.Spacing.md) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(opt.title)
                                .font(FDS.TypeScale.Dynamic.headline)
                                .foregroundStyle(Color.textPrimary)
                            if !opt.subtitle.isEmpty {
                                Text(opt.subtitle)
                                    .font(FDS.TypeScale.Dynamic.caption)
                                    .foregroundStyle(Color.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                    }
                    .padding(FDS.Spacing.lg)
                    .background(Color.surfaceElevated.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    }
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
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            Text("Conditions to respect")
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textSecondary)

            Text("Optional. Lifestyle coach only — not medical care.")
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textTertiary)

            OnboardingFlowLayout(spacing: 8) {
                ForEach(ReportedCondition.allCases) { cond in
                    let selected = coordinator.profile.reportedConditions.contains(cond)
                    Button { coordinator.toggleCondition(cond) } label: {
                        Text(cond.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selected ? .white : Color.textSecondary)
                            .padding(.horizontal, FDS.Spacing.md)
                            .padding(.vertical, FDS.Spacing.sm)
                            .background(selected ? Color.ember.opacity(0.85) : Color.surface)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(selected ? Color.ember : Color.borderColor, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            if coordinator.profile.reportedConditions.contains(.other) {
                TextField("Anything else I should know? (optional)", text: $coordinator.freeText)
                    .padding(FDS.Spacing.md)
                    .forgeGlassCard(cornerRadius: FDS.Radius.md, accent: .ember)
            }

            if coordinator.profile.guidanceOnlyMode {
                Text("Guidance mode will be on: structure & pacing only — never treatment plans.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.warning)
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

struct HabitsComposer: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            Text(AriaInterviewVoice.habitsWrapper)
                .font(FDS.TypeScale.Dynamic.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Pick up to three. I just want to take care of you better.")
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: FDS.Spacing.sm) {
                ForEach(FriendHabitChip.allCases) { chip in
                    let selected = coordinator.profile.friendHabits.contains(chip)
                    Button { coordinator.toggleHabit(chip) } label: {
                        HStack(spacing: FDS.Spacing.md) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chip.label)
                                    .font(FDS.TypeScale.Dynamic.headline)
                                    .foregroundStyle(Color.textPrimary)
                                Text(chip.detail)
                                    .font(FDS.TypeScale.Dynamic.caption)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? Color.ember : Color.textMuted)
                        }
                        .padding(FDS.Spacing.lg)
                        .background(selected ? Color.ember.opacity(0.16) : Color.surfaceElevated.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                                .stroke(selected ? Color.ember.opacity(0.55) : Color.white.opacity(0.06), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!selected && coordinator.profile.friendHabits.count >= 3)
                }
            }

            PrimaryCTA(
                title: coordinator.profile.friendHabits.isEmpty ? "Skip" : "Continue",
                icon: "arrow.right",
                enabled: true,
                action: coordinator.confirmInterests
            )
        }
    }
}

struct CoachingComposer: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: FDS.Spacing.sm) {
            ForEach(OnboardingCoachingStyle.friendToneStyles) { style in
                Button {
                    coordinator.selectCoachingStyle(style)
                } label: {
                    HStack(spacing: FDS.Spacing.md) {
                        Image(systemName: style.icon)
                            .foregroundStyle(style.color)
                            .frame(width: 36, height: 36)
                            .background(style.color.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.friendToneTitle)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                            Text(style.friendToneLine)
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(FDS.Spacing.lg)
                    .background(Color.surfaceElevated.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                            .stroke(style.color.opacity(0.28), lineWidth: 1)
                    }
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
        VStack(spacing: FDS.Spacing.lg) {
            ZStack {
                PremiumPresenceBloom(
                    size: 130,
                    accent: .ember,
                    frost: Color(hex: "A9D8FF")
                )
                AuroraOrbView(
                    state: .idle,
                    amplitude: 0.55,
                    mood: .energized,
                    size: 88,
                    followPresence: true
                )
            }
            .frame(height: 108)
            .accessibilityLabel("ARIA")

            if !coordinator.profile.firstName.isEmpty {
                Text("You’re set, \(coordinator.profile.firstName). I’m here.")
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            if coordinator.profile.guidanceOnlyMode {
                Text("ARIA will coach with guidance only for the conditions you shared.")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
            // Liability disclaimer — must be agreed at the very end
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    coordinator.hasAgreedToTerms.toggle()
                    if coordinator.hasAgreedToTerms { FDS.haptic(.light) }
                }
            } label: {
                HStack(alignment: .top, spacing: FDS.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: FDS.Radius.xs).stroke(coordinator.hasAgreedToTerms ? Color.ember : Color.borderColor, lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                            .background(coordinator.hasAgreedToTerms ? Color.ember : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xs))
                        if coordinator.hasAgreedToTerms {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    Text("By agreeing to our Terms of Use, you acknowledge that Forge is an assistive coaching tool, not medical care. You are responsible for your own health. Any actions taken or injuries sustained are not the liability of Forge. Forge is designed to assist and advise, not to compel. By checking this box you waive all liability towards Forge.")
                        .font(FDS.TypeScale.Dynamic.micro)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .padding(FDS.Spacing.md)
                .background(Color.surfaceElevated.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(coordinator.hasAgreedToTerms ? Color.ember.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1) }
            }
            .buttonStyle(.plain)

            PrimaryCTA(
                title: coordinator.isPrepping
                    ? "Prepping Forge…"
                    : (coordinator.isCompleting ? "Starting…" : "Start with ARIA"),
                icon: "arrow.right",
                enabled: !coordinator.isCompleting && coordinator.canFinish,
                action: onFinish
            )
            if !coordinator.hasAgreedToTerms {
                Text("Please agree to the Terms to continue.")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.warning)
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
        PremiumPrimaryButton(
            title: title,
            icon: icon,
            enabled: enabled,
            action: action
        )
    }
}

struct MessageBubble: View {
    let message: AriaOnboardingMessage
    var onTap: (() -> Void)? = nil
    @State private var appeared = false

    var body: some View {
        Group {
            switch message.role {
            case .aria:
                HStack(alignment: .top, spacing: 0) {
                    Text(message.text)
                        .font(FDS.TypeScale.Dynamic.headline)
                        .foregroundStyle(Color.textPrimary)
                        .lineSpacing(4)
                        .padding(.horizontal, FDS.Spacing.lg)
                        .padding(.vertical, FDS.Spacing.md)
                        .forgeInsetTile(radius: FDS.Radius.lg)
                        .overlay {
                            RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                    Spacer(minLength: 36)
                }
                .onTapGesture { onTap?() }
                .accessibilityAddTraits(onTap == nil ? AccessibilityTraits() : .isButton)
                .accessibilityHint(onTap == nil ? "" : "Plays this line")
            case .user:
                HStack {
                    Spacer(minLength: 48)
                    Text(message.text)
                        .font(FDS.TypeScale.Dynamic.body)
                        .foregroundStyle(Color(hex: "0A0A0A"))
                        .padding(.horizontal, FDS.Spacing.lg)
                        .padding(.vertical, FDS.Spacing.md)
                        .background(Color.paper)
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
                }
            case .system:
                HStack {
                    Spacer()
                    Label(message.text, systemImage: "heart.text.square.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textMuted)
                        .padding(.horizontal, FDS.Spacing.md)
                        .padding(.vertical, FDS.Spacing.sm)
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

struct ScheduleComposer: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            HStack(spacing: FDS.Spacing.sm) {
                modeChip(.rotate)
                modeChip(.fixed)
            }

            if coordinator.profile.schedulePlanningMode == .fixed {
                Text("Tap a day to change the library and how many moves.")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(Color.textTertiary)
                VStack(spacing: FDS.Spacing.sm) {
                    ForEach(WeeklySplit.normalized(coordinator.profile.weeklySplit)) { slot in
                        dayRow(slot)
                    }
                }
            } else {
                Text(WeeklySplit.summary(mode: .rotate, split: coordinator.profile.weeklySplit))
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: { coordinator.confirmSchedule() }) {
                Text("That’s the week")
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundStyle(Color(hex: "0A0A0A"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FDS.Spacing.lg)
                    .background(Color.paper)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func modeChip(_ mode: SchedulePlanningMode) -> some View {
        let on = coordinator.profile.schedulePlanningMode == mode
        return Button {
            coordinator.selectScheduleMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                Text(mode.label)
                    .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                    .foregroundStyle(on ? .white : Color.textPrimary)
                Text(mode == .rotate ? "ARIA walks it" : "You assign days")
                    .font(.system(size: 11))
                    .foregroundStyle(on ? .white.opacity(0.8) : Color.textTertiary)
            }
            .padding(.horizontal, FDS.Spacing.md)
            .padding(.vertical, FDS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Color.ember : Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func dayRow(_ slot: WeeklySplitSlot) -> some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            HStack {
                Text(WeeklySplit.dayLabels[slot.weekday])
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 36, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FDS.Spacing.sm) {
                        ForEach(WeeklySplit.focusChoices, id: \.label) { choice in
                            let selected = slot.primary == choice.id && slot.extra == choice.extra
                            Button {
                                coordinator.setSplitSlot(WeeklySplitSlot(
                                    weekday: slot.weekday,
                                    primary: choice.id,
                                    extra: choice.extra,
                                    exerciseCount: choice.id == "rest" ? 0 : max(3, slot.exerciseCount)
                                ))
                            } label: {
                                Text(choice.label)
                                    .font(FDS.TypeScale.Dynamic.micro)
                                    .foregroundStyle(selected ? .white : Color.textSecondary)
                                    .padding(.horizontal, FDS.Spacing.sm)
                                    .padding(.vertical, FDS.Spacing.sm)
                                    .background(selected ? Color.ember : Color.surface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !slot.isRest {
                HStack(spacing: FDS.Spacing.md) {
                    Text("\(slot.exerciseCount) exercises")
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Button {
                        coordinator.setSplitSlot(WeeklySplitSlot(
                            weekday: slot.weekday,
                            primary: slot.primary,
                            extra: slot.extra,
                            exerciseCount: max(3, slot.exerciseCount - 1)
                        ))
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(Color.textSecondary)
                    }
                    Button {
                        coordinator.setSplitSlot(WeeklySplitSlot(
                            weekday: slot.weekday,
                            primary: slot.primary,
                            extra: slot.extra,
                            exerciseCount: min(8, slot.exerciseCount + 1)
                        ))
                    } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.ember)
                    }
                }
            }
        }
        .padding(FDS.Spacing.md)
        .forgeInsetTile(radius: FDS.Radius.md)
    }
}

struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: FDS.Spacing.md) {
            HStack(spacing: FDS.Spacing.xs) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.ember.opacity(0.85))
                        .frame(width: 6, height: 6)
                        .offset(y: reduceMotion ? 0 : sin(phase + Double(i)) * 3)
                }
            }
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.vertical, FDS.Spacing.md)
            .forgeInsetTile(radius: FDS.Radius.lg)
            .overlay {
                RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            Spacer()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
