import SwiftUI
import ForgeCore

// MARK: - Shared onboarding pieces

/// Terms copy, shown in full at the end of the interview.
private let onboardingTermsCopy = "By agreeing to our Terms of Use, you acknowledge that Forge is an assistive coaching tool, not medical care. You are responsible for your own health. Any actions taken or injuries sustained are not the liability of Forge. Forge is designed to assist and advise, not to compel. By checking this box you waive all liability towards Forge."

/// Helper, hint and footnote sentences: regular-weight body, wraps, never clipped.
private struct OnboardingFootnote: View {
    let text: String
    var tint: Color = Color.textTertiary

    init(_ text: String, tint: Color = Color.textTertiary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(HomeType.body)
            .foregroundStyle(tint)
            .multilineTextAlignment(.leading)
            .forgeWrapping()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Eyebrow label above a field, with an optional quiet qualifier.
private struct OnboardingFieldLabel: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
            Text(title)
                .forgeSectionLabel(tint: Color.textSecondary)
            if let detail {
                Text(detail)
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}

/// Field chrome for inputs that sit on the atmosphere: 48 pt minimum, the
/// opaque inset tile (which already draws the hairline) and one focus stroke.
private struct OnboardingFieldChrome: ViewModifier {
    var focused: Bool
    var tint: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, FDS.Spacing.lg)
            .frame(minHeight: 48)
            .forgeInsetTile(radius: FDS.Radius.lg)
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                        .stroke(tint.opacity(0.55), lineWidth: 1)
                }
            }
    }
}

/// One selectable answer on the Home agenda-row anatomy: optional icon well,
/// status title over a wrapping body subtitle, and a chevron or a selection
/// mark. These rows sit on the atmosphere, so the chrome stays the opaque
/// inset tile rather than a well.
private struct OnboardingOptionRow: View {
    var icon: String? = nil
    var tint: Color = Color.ember
    let title: String
    var subtitle: String = ""
    var showsChevron: Bool = false
    /// nil = not a selectable row; otherwise whether it is currently chosen.
    var selection: Bool? = nil

    private var isSelected: Bool { selection == true }

    var body: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            if let icon {
                ForgeIconWell(systemImage: icon, tint: tint)
            }
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .forgeWrapping()
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.leading)
                        .forgeWrapping()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            accessory
        }
        .padding(.horizontal, FDS.Spacing.lg)
        .padding(.vertical, FDS.Spacing.md)
        .frame(minHeight: ForgeUX.minTap)
        .forgeInsetTile(radius: FDS.Radius.lg)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                    .stroke(tint.opacity(0.32), lineWidth: ForgeUX.hairline)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var accessory: some View {
        if let selection {
            Image(systemName: selection ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(selection ? tint : Color.textMuted)
                .accessibilityHidden(true)
        } else if showsChevron {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
    }
}

/// First interview beat — living ARIA mark with soft presence, not fire.
struct IntroComposer: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: ForgeLayout.blockGap) {
            ZStack {
                PremiumPresenceBloom(
                    size: 176,
                    accent: .ember,
                    frost: Color(hex: "A9D8FF")
                )
                AuroraOrbView(
                    state: coordinator.ariaOrbState,
                    amplitude: coordinator.ariaOrbState == .speaking ? 0.8 : 0.58,
                    mood: coordinator.ariaMood,
                    size: 124,
                    followPresence: true
                )
            }
            // The bloom's outer halo is 1.12x its size; the frame matches it so
            // the composer's ScrollView never cuts through the glow.
            .frame(height: 198)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("ARIA")

            VStack(spacing: ForgeLayout.pairGap) {
                Text("ARIA")
                    .forgeSectionLabel(tint: Color.paper.opacity(0.72))
                Text("Your lifestyle coach — built for the life you already have.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Preferred name + optional last name. Modeled on Claude/Grok ("what should we call you")
/// and Apple Health Health Details (first / last as separate fields).
struct NameComposer: View {
    @Bindable var coordinator: OnboardingCoordinator
    @ObservedObject var dictation: SpeechManager
    @FocusState private var focusedField: NameField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum NameField: Hashable { case preferred, last }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.cardPadding) {
            preferredBlock
            lastNameBlock

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
        .animation(reduceMotion ? nil : ForgeMotion.snappy, value: dictation.isListening)
    }

    private var preferredBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            OnboardingFieldLabel(title: "Preferred name")
            TextField("Maya", text: $coordinator.profile.name)
                .focused($focusedField, equals: .preferred)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focusedField = .last }
                .font(ForgeType.title)
                .foregroundStyle(Color.textPrimary)
                .accessibilityLabel("Preferred name")
                .modifier(OnboardingFieldChrome(
                    focused: focusedField == .preferred || dictation.isListening,
                    tint: Color.aurora
                ))
            OnboardingFootnote("What I’ll call you. First name is enough.")
        }
    }

    private var lastNameBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            OnboardingFieldLabel(title: "Last name", detail: "optional")
            TextField("Chen", text: $coordinator.profile.lastName)
                .focused($focusedField, equals: .last)
                .textContentType(.familyName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { submit() }
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .accessibilityLabel("Last name, optional")
                .modifier(OnboardingFieldChrome(focused: focusedField == .last, tint: Color.aurora))
            OnboardingFootnote("Stays on your profile. ARIA won’t say it unless you ask.")
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

    /// Content height that makes a default-padded well a 44 pt target.
    private var wellContentMinHeight: CGFloat {
        ForgeUX.minTap - 2 * ForgeLayout.tilePadding
    }

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
        VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            if !coordinator.profile.detailsSummaryLine.isEmpty {
                Text(coordinator.profile.detailsSummaryLine)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .forgeWrapping()
                    .padding(.horizontal, FDS.Spacing.lg)
                    .padding(.vertical, FDS.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeInsetTile(radius: FDS.Radius.md)
            }

            birthdayBlock
            // After the age block only the birthday is in question; sex and
            // body selection are gated on the `.details` step and would no-op.
            if !coordinator.isReviewingBirthday {
                sexBlock
                bodyBlock
            }

            PrimaryCTA(
                title: coordinator.isUnderage
                    ? "Must be 13 or older"
                    : (coordinator.isReviewingBirthday ? "Confirm birthday" : "Confirm details"),
                icon: "arrow.right",
                enabled: coordinator.isReviewingBirthday
                    ? coordinator.profile.hasBirthday && !coordinator.isUnderage
                    : coordinator.profile.hasConfirmedDetails && !coordinator.isUnderage,
                action: {
                    if coordinator.isReviewingBirthday {
                        coordinator.confirmBirthdayReview()
                    } else {
                        coordinator.confirmDetails()
                    }
                }
            )
        }
        .onAppear { hydrateBodyFields() }
        .onChange(of: coordinator.profile.heightCm) { _, _ in hydrateBodyFields() }
        .onChange(of: coordinator.profile.weightKg) { _, _ in hydrateBodyFields() }
        .onChange(of: coordinator.profile.usesMetricUnits) { _, _ in hydrateBodyFields() }
    }

    private var birthdayBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            fieldHeader(
                "Date of birth",
                sourced: coordinator.profile.healthSourcedFields.contains(.birthday)
            )
            OnboardingFootnote("Heart-rate zones, recovery norms, and 13+ safety.")
            birthdayEntry
        }
        .forgeContentCard()
    }

    @ViewBuilder
    private var birthdayEntry: some View {
        if coordinator.profile.birthday == nil, !showBirthdayPicker {
            Button {
                coordinator.profile.birthday = Self.startingBirthday
                showBirthdayPicker = true
                ForgeHaptics.play(.press)
            } label: {
                HStack {
                    Text("Select date")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ember)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: wellContentMinHeight)
                .forgeWell()
            }
            .buttonStyle(ForgePressStyle())
        } else {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                birthdayAgeLine
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
    }

    private var birthdayAgeLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
            Text(coordinator.isUnderage ? "Must be 13+" : "\(coordinator.profile.ageYears)")
                .font(HomeType.heroScore)
                .foregroundStyle(coordinator.isUnderage ? Color.danger : Color.textPrimary)
                .contentTransition(.numericText())
                .forgeSingleLine()
                .layoutPriority(1)
            if !coordinator.isUnderage {
                Text("years old")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }
            Spacer(minLength: 0)
        }
    }

    private var sexBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            fieldHeader(
                "Biological sex",
                sourced: coordinator.profile.healthSourcedFields.contains(.sex)
            )
            OnboardingFootnote("Calories, heart-rate zones, Cycle Health. Not gender — that’s in Profile.")

            BiologicalSexStepView(coordinator: coordinator)
        }
        .forgeContentCard()
    }

    private var bodyBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            fieldHeader(
                "Height & weight",
                sourced: coordinator.profile.healthSourcedFields.contains(.height)
                    || coordinator.profile.healthSourcedFields.contains(.weight)
            )
            OnboardingFootnote("Optional. Used for calorie and load math.")
            Picker("Units", selection: $coordinator.profile.usesMetricUnits) {
                Text("ft / lb").tag(false)
                Text("cm / kg").tag(true)
            }
            .pickerStyle(.segmented)

            if coordinator.profile.usesMetricUnits {
                metricFields
            } else {
                imperialFields
            }
        }
        .forgeContentCard()
    }

    private var metricFields: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
            metricField(label: "Height, centimeters", placeholder: "170", text: $heightCmText, unit: "cm") { value in
                if let cm = Double(value.replacingOccurrences(of: ",", with: ".")),
                   (90...250).contains(cm) {
                    coordinator.profile.heightCm = cm
                    coordinator.profile.healthSourcedFields.remove(.height)
                } else if value.trimmingCharacters(in: .whitespaces).isEmpty {
                    coordinator.profile.heightCm = nil
                }
            }
            metricField(label: "Weight, kilograms", placeholder: "70", text: $weightText, unit: "kg") { value in
                applyWeightText(value)
            }
        }
    }

    /// Two rows (height pair, then weight) so no field is squeezed to a third of the width.
    private var imperialFields: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
            ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
                unitField(label: "Height, feet", placeholder: "5", text: $heightFeet, unit: "ft") { syncImperialHeight() }
                unitField(label: "Height, inches", placeholder: "10", text: $heightInches, unit: "in") { syncImperialHeight() }
            }
            metricField(label: "Weight, pounds", placeholder: "160", text: $weightText, unit: "lb") { value in
                applyWeightText(value)
            }
        }
    }

    private func fieldHeader(_ title: String, sourced: Bool) -> some View {
        ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
            Text(title)
                .forgeSectionLabel(tint: Color.textSecondary)
            if sourced {
                ForgeChip(label: "Apple Health", icon: "heart.fill", energy: Color.vitality, selected: true)
            }
        }
    }

    private func unitField(label: String, placeholder: String, text: Binding<String>, unit: String, onChange: @escaping () -> Void) -> some View {
        HStack(spacing: FDS.Spacing.sm) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .font(HomeType.metric)
                .multilineTextAlignment(.center)
                .accessibilityLabel(label)
                .onChange(of: text.wrappedValue) { _, _ in onChange() }
            Text(unit)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: wellContentMinHeight)
        .forgeWell()
    }

    private func metricField(label: String, placeholder: String, text: Binding<String>, unit: String, onEdit: @escaping (String) -> Void) -> some View {
        HStack(spacing: FDS.Spacing.sm) {
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(HomeType.metric)
                .multilineTextAlignment(.center)
                .accessibilityLabel(label)
                .onChange(of: text.wrappedValue) { _, value in
                    guard !hydratingFields else { return }
                    onEdit(value)
                }
            Text(unit)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: wellContentMinHeight)
        .forgeWell()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            ForgeHaptics.play(.press)
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
                    .symbolEffect(.variableColor.iterative, isActive: dictation.isListening && !reduceMotion)
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
        VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            connectionsCard

            if let hint = coordinator.lastHealthSharingHint, !hint.isEmpty {
                OnboardingFootnote(hint, tint: Color.textSecondary)
                    .accessibilityLabel(hint)
            }

            PrimaryCTA(
                title: "Continue",
                icon: "arrow.right",
                enabled: true,
                action: coordinator.continueFromHealth
            )

            if let line = coordinator.emptyBackfillLine {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    OnboardingFootnote(line)
                    ForgeSecondaryButton(
                        title: "Open Health Sharing",
                        accent: Color.steel,
                        action: { coordinator.openHealthSharingManually() }
                    )
                }
            }
        }
    }

    /// One card, four agenda rows, no per-row boxes. The eyebrow is the one
    /// header the step needs: ARIA's spoken prompt already sits in the transcript.
    private var connectionsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(AriaInterviewVoice.healthWrapper, tint: Color.steel)
            VStack(spacing: ForgeLayout.rowGap) {
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
                    icon: "person.2.fill", color: HudChrome.plate,
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
        }
        .forgeContentCard(accent: Color.steel)
    }
}

/// A service row on the Home agenda anatomy: 36 pt well, status title with a
/// state pill, the full privacy promise (it wraps, never truncates) and a
/// trailing "Connect". The whole row is the button until it is connected.
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
    private var actionTitle: String { state == .denied ? "Reconnect" : "Connect" }

    var body: some View {
        if isLive || isPulling {
            rowContent
                .accessibilityElement(children: .combine)
        } else {
            Button {
                ForgeHaptics.play(.press)
                action()
            } label: {
                rowContent
            }
            .buttonStyle(ForgePressStyle())
            .accessibilityLabel("\(actionTitle) \(title)")
            .accessibilityValue(statusText)
            .accessibilityHint(subtitle)
        }
    }

    private var rowContent: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            leadingWell
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
                    Text(title)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                    statusPill
                }
                Text(subtitle)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.leading)
                    .forgeWrapping()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            trailingMark
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingWell: some View {
        if isPulling {
            ZStack {
                Circle().fill(color.opacity(0.16))
                ProgressView()
                    .controlSize(.small)
                    .tint(color)
            }
            .frame(width: ForgeLayout.iconWell, height: ForgeLayout.iconWell)
            .accessibilityHidden(true)
        } else {
            ForgeIconWell(
                systemImage: isLive ? "checkmark.seal.fill" : icon,
                tint: isLive ? Color.success : color
            )
        }
    }

    private var statusPill: some View {
        let tone: Color = isLive ? Color.success : Color.textSecondary
        let fill: Color = isLive ? Color.success.opacity(0.14) : Color.white.opacity(0.08)
        return Text(statusText)
            .font(HomeType.micro)
            .foregroundStyle(tone)
            .lineLimit(1)
            .padding(.horizontal, FDS.Spacing.sm)
            .padding(.vertical, 3)
            .background(Capsule().fill(fill))
    }

    @ViewBuilder
    private var trailingMark: some View {
        if isLive {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.success)
                .accessibilityHidden(true)
        } else if !isPulling {
            Text(actionTitle)
                .font(HomeType.label)
                .foregroundStyle(color)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
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
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text(title)
                .forgeSectionLabel(tint: Color.textSecondary)
                .accessibilityAddTraits(.isHeader)

            ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.interactiveChipLineGap) {
                ForEach(items, id: \.id) { item in
                    ForgeChipButton(
                        label: item.label,
                        energy: Color.ember,
                        selected: isSelected(item.id)
                    ) {
                        onToggle(item.id)
                    }
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
        VStack(spacing: ForgeLayout.tileGap) {
            ForEach(options, id: \.id) { opt in
                Button {
                    ForgeHaptics.play(.selection)
                    onSelect(opt.id)
                } label: {
                    OnboardingOptionRow(
                        tint: Color.ember,
                        title: opt.title,
                        subtitle: opt.subtitle,
                        showsChevron: true
                    )
                }
                .buttonStyle(ForgePressStyle())
            }
        }
    }
}

struct ConditionsComposer: View {
    @Bindable var coordinator: OnboardingCoordinator
    @ObservedObject var dictation: SpeechManager

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("Conditions to respect")
                    .forgeSectionLabel(tint: Color.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                OnboardingFootnote("Optional. Lifestyle coach only — not medical care.")
            }

            ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.interactiveChipLineGap) {
                ForEach(ReportedCondition.allCases) { cond in
                    ForgeChipButton(
                        label: cond.label,
                        energy: Color.ember,
                        selected: coordinator.profile.reportedConditions.contains(cond)
                    ) {
                        coordinator.toggleCondition(cond)
                    }
                }
            }

            if coordinator.profile.reportedConditions.contains(.other) {
                TextField("Anything else I should know? (optional)", text: $coordinator.freeText)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textPrimary)
                    .modifier(OnboardingFieldChrome(focused: dictation.isListening, tint: Color.ember))
            }

            if coordinator.profile.guidanceOnlyMode {
                OnboardingFootnote(
                    "Guidance mode will be on: structure & pacing only.",
                    tint: Color.textSecondary
                )
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
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            // ARIA's "pick up to three" prompt is already in the transcript.
            Text(AriaInterviewVoice.habitsWrapper)
                .forgeSectionLabel(tint: Color.vitality)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: ForgeLayout.tileGap) {
                ForEach(FriendHabitChip.allCases) { chip in
                    habitRow(chip)
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

    private func habitRow(_ chip: FriendHabitChip) -> some View {
        let selected = coordinator.profile.friendHabits.contains(chip)
        let atLimit = !selected && coordinator.profile.friendHabits.count >= 3
        return Button {
            ForgeHaptics.play(.selection)
            coordinator.toggleHabit(chip)
        } label: {
            OnboardingOptionRow(
                tint: Color.vitality,
                title: chip.label,
                subtitle: chip.detail,
                selection: selected
            )
        }
        .buttonStyle(ForgePressStyle())
        .disabled(atLimit)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CoachingComposer: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: ForgeLayout.tileGap) {
            ForEach(OnboardingCoachingStyle.friendToneStyles) { style in
                Button {
                    ForgeHaptics.play(.selection)
                    coordinator.selectCoachingStyle(style)
                } label: {
                    OnboardingOptionRow(
                        icon: style.icon,
                        tint: style.color,
                        title: style.friendToneTitle,
                        subtitle: style.friendToneLine,
                        showsChevron: true
                    )
                }
                .buttonStyle(ForgePressStyle())
            }
        }
    }
}

struct ReadyComposer: View {
    @Bindable var coordinator: OnboardingCoordinator
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: ForgeLayout.blockGap) {
            ZStack {
                PremiumPresenceBloom(
                    size: 120,
                    accent: .ember,
                    frost: Color(hex: "A9D8FF")
                )
                AuroraOrbView(
                    state: .idle,
                    amplitude: 0.55,
                    mood: .energized,
                    size: 80,
                    followPresence: true
                )
            }
            // Sized to the bloom's 1.12x halo so the composer's ScrollView does not clip it.
            .frame(height: 136)
            .accessibilityLabel("ARIA")

            if !coordinator.profile.firstName.isEmpty {
                Text("You’re set, \(coordinator.profile.firstName). I’m here.")
                    .font(ForgeType.title)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity)
            }
            if coordinator.profile.guidanceOnlyMode {
                Text("ARIA will coach with guidance only for the conditions you shared.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity)
            }

            // Liability disclaimer — must be agreed at the very end
            termsRow

            PrimaryCTA(
                title: coordinator.isPrepping
                    ? "Prepping Forge…"
                    : (coordinator.isCompleting ? "Starting…" : "Start with ARIA"),
                icon: "arrow.right",
                enabled: !coordinator.isCompleting && coordinator.canFinish,
                busy: coordinator.isPrepping || coordinator.isCompleting,
                action: onFinish
            )
            if !coordinator.hasAgreedToTerms {
                Text("Please agree to the Terms to continue.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var termsRow: some View {
        let agreed = coordinator.hasAgreedToTerms
        return Button {
            withAnimation(reduceMotion ? nil : ForgeMotion.snappy) {
                coordinator.hasAgreedToTerms.toggle()
            }
            if coordinator.hasAgreedToTerms { ForgeHaptics.play(.selection) }
        } label: {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                Image(systemName: agreed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(agreed ? Color.ember : Color.textTertiary)
                    .accessibilityHidden(true)
                Text(onboardingTermsCopy)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.leading)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(FDS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .forgeInsetTile(radius: FDS.Radius.md)
            .overlay {
                if agreed {
                    RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                        .stroke(Color.ember.opacity(0.4), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Agree to the Terms of Use. \(onboardingTermsCopy)")
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(agreed ? "Checked" : "Unchecked")
    }
}

struct PrimaryCTA: View {
    let title: String
    let icon: String
    let enabled: Bool
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        PremiumPrimaryButton(
            title: title,
            icon: icon,
            enabled: enabled,
            busy: busy,
            action: action
        )
    }
}

struct MessageBubble: View {
    let message: AriaOnboardingMessage
    var onTap: (() -> Void)? = nil

    var body: some View {
        switch message.role {
        case .aria:
            ariaBubble
        case .user:
            userBubble
        case .system:
            systemNote
        }
    }

    private var ariaBubble: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(message.text)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .forgeWrapping()
                .padding(.horizontal, FDS.Spacing.lg)
                .padding(.vertical, FDS.Spacing.md)
                .forgeInsetTile(radius: FDS.Radius.lg)
            Spacer(minLength: 36)
        }
        .onTapGesture { onTap?() }
        .accessibilityAddTraits(onTap == nil ? AccessibilityTraits() : .isButton)
        .accessibilityHint(onTap == nil ? "" : "Plays this line")
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.text)
                .font(HomeType.body)
                .foregroundStyle(Color.background)
                .multilineTextAlignment(.leading)
                .forgeWrapping()
                .padding(.horizontal, FDS.Spacing.lg)
                .padding(.vertical, FDS.Spacing.md)
                .background(Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
        }
    }

    private var systemNote: some View {
        HStack {
            Spacer()
            Label(message.text, systemImage: "heart.text.square.fill")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FDS.Spacing.md)
                .padding(.vertical, FDS.Spacing.sm)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
            Spacer()
        }
    }
}

struct ScheduleComposer: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeAdaptiveStack(spacing: ForgeLayout.tileGap, alignment: .top) {
                modeChip(.rotate)
                modeChip(.fixed)
            }

            if coordinator.profile.schedulePlanningMode == .fixed {
                OnboardingFootnote("Tap a day to change the library and how many moves.")
                VStack(spacing: ForgeLayout.tileGap) {
                    ForEach(WeeklySplit.normalized(coordinator.profile.weeklySplit)) { slot in
                        dayRow(slot)
                    }
                }
            } else {
                OnboardingFootnote(
                    WeeklySplit.summary(mode: .rotate, split: coordinator.profile.weeklySplit),
                    tint: Color.textSecondary
                )
            }

            PrimaryCTA(
                title: "That’s the week",
                icon: "arrow.right",
                enabled: true,
                action: { coordinator.confirmSchedule() }
            )
        }
    }

    private func modeChip(_ mode: SchedulePlanningMode) -> some View {
        let on = coordinator.profile.schedulePlanningMode == mode
        let fill: Color = on ? Color.ember.opacity(0.14) : Color.surfaceElevated
        let edge: Color = on ? Color.ember.opacity(0.32) : Color.borderHairline
        return Button {
            ForgeHaptics.play(.selection)
            coordinator.selectScheduleMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(mode.label)
                    .font(HomeType.status)
                    .foregroundStyle(on ? Color.ember : Color.textPrimary)
                    .forgeWrapping()
                Text(mode == .rotate ? "ARIA walks it" : "You assign days")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
            .padding(FDS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(edge, lineWidth: ForgeUX.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ForgePressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func dayRow(_ slot: WeeklySplitSlot) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text(WeeklySplit.dayLabels[slot.weekday])
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
            focusRail(slot)
            if !slot.isRest {
                countRow(slot)
            }
        }
        .padding(ForgeLayout.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeInsetTile(radius: FDS.Radius.md)
    }

    private func focusRail(_ slot: WeeklySplitSlot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ForgeLayout.chipGap) {
                ForEach(WeeklySplit.focusChoices, id: \.label) { choice in
                    ForgeChipButton(
                        label: choice.label,
                        energy: Color.ember,
                        selected: slot.primary == choice.id && slot.extra == choice.extra
                    ) {
                        coordinator.setSplitSlot(WeeklySplitSlot(
                            weekday: slot.weekday,
                            primary: choice.id,
                            extra: choice.extra,
                            exerciseCount: choice.id == "rest" ? 0 : max(3, slot.exerciseCount)
                        ))
                    }
                }
            }
            // Room for the chips' 44 pt tap outset inside the scroll view.
            .padding(.vertical, FDS.Spacing.sm)
        }
    }

    private func countRow(_ slot: WeeklySplitSlot) -> some View {
        HStack(spacing: ForgeLayout.rowGap) {
            Text("\(slot.exerciseCount) exercises")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
            Spacer(minLength: FDS.Spacing.sm)
            countStepper(slot, systemImage: "minus.circle.fill", label: "Fewer exercises", tint: Color.textSecondary, delta: -1)
            countStepper(slot, systemImage: "plus.circle.fill", label: "More exercises", tint: Color.ember, delta: 1)
        }
    }

    private func countStepper(_ slot: WeeklySplitSlot, systemImage: String, label: String, tint: Color, delta: Int) -> some View {
        let newCount = delta < 0 ? max(3, slot.exerciseCount - 1) : min(8, slot.exerciseCount + 1)
        return Button {
            ForgeHaptics.play(.selection)
            coordinator.setSplitSlot(WeeklySplitSlot(
                weekday: slot.weekday,
                primary: slot.primary,
                extra: slot.extra,
                exerciseCount: newCount
            ))
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(tint)
                .frame(minWidth: ForgeUX.minTap, minHeight: ForgeUX.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// ARIA is composing. An event state: the dots move only while the indicator
/// is on screen, and not at all under Reduce Motion.
struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: FDS.Spacing.md) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                dots(at: context.date.timeIntervalSinceReferenceDate)
            }
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.vertical, FDS.Spacing.md)
            .forgeInsetTile(radius: FDS.Radius.lg)
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ARIA is typing")
    }

    private func dots(at time: TimeInterval) -> some View {
        HStack(spacing: FDS.Spacing.xs) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.ember.opacity(0.85))
                    .frame(width: 6, height: 6)
                    .offset(y: reduceMotion ? 0 : sin(time * 5.0 + Double(i) * 0.9) * 3)
            }
        }
    }
}
