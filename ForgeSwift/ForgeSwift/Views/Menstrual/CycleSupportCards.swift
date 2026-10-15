import SwiftUI

/// Basal body temperature entry unit. Stored value is always Celsius.
enum BBTUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit

    var id: String { rawValue }

    var symbol: String { self == .celsius ? "°C" : "°F" }

    var placeholder: String { self == .celsius ? "36.50" : "97.70" }

    var accessibilityName: String { self == .celsius ? "Celsius" : "Fahrenheit" }

    /// Physiologically plausible basal range — anything outside is an entry mistake.
    static let plausibleCelsius: ClosedRange<Double> = 34.0...40.0

    var plausibleCopy: String {
        self == .celsius ? "34–40 °C" : "93–104 °F"
    }

    func toCelsius(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return self == .celsius ? value : (value - 32) * 5 / 9
    }

    func fromCelsius(_ celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }
}

struct AddSupportedPersonSheet: View {
    @ObservedObject var cycleStore: MenstrualHealthStore
    var onAdded: (SupportedPerson) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var role: CycleSupportRole = .romantic
    @State private var name = ""
    @State private var label = CycleSupportRole.romantic.suggestedLabels.first ?? "partner"
    @State private var consent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    Text("Partner, relative, or parent — including a parent of a minor. Each person is their own. They need an iPhone; invites are iMessage only.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()

                    whoCard
                    fieldsBlock
                    consentCard
                    addButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .forgeScreenBackground(accent: .indigo)
            .navigationTitle("Add someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Who

    private var whoCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("WHO", tint: .indigo)
            VStack(spacing: ForgeLayout.tileGap) {
                ForEach(CycleSupportRole.selectableRoles) { option in
                    roleRow(option)
                }
            }
        }
        .forgeContentCard(tint: .indigo)
    }

    private func roleRow(_ option: CycleSupportRole) -> some View {
        let isSelected = role == option
        let fill = isSelected ? Color.indigo.opacity(0.12) : Color.white.opacity(0.045)
        let edge = isSelected ? Color.indigo.opacity(0.32) : Color.white.opacity(0.08)
        return Button {
            role = option
            label = option.suggestedLabels.first ?? label
            FDS.haptic(.select)
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: option.icon, tint: .indigo)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(option.label)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(option.pickerDetail)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.indigo)
                        .accessibilityHidden(true)
                }
            }
            .padding(ForgeLayout.tilePadding)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
                    .stroke(edge, lineWidth: ForgeUX.stroke)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityHint(option.pickerDetail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Fields

    private var fieldsBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            labeledField(
                title: "Name",
                placeholder: "Name (optional)",
                text: $name
            )
            labeledField(
                title: "Label",
                placeholder: role == .child ? "Label (daughter / child…)" : "Label (partner / wife…)",
                text: $label
            )
        }
    }

    private func labeledField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(title)
                .font(HomeType.micro)
                .foregroundStyle(Color.textSecondary)
            TextField(placeholder, text: text)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .textFieldStyle(.plain)
                .padding(.horizontal, ForgeLayout.tilePadding)
                .frame(minHeight: ForgeUX.minTap)
                .forgeInsetTile(radius: FDS.Radius.md)
                .accessibilityLabel(title)
        }
    }

    // MARK: - Consent and CTA

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Toggle(isOn: $consent) {
                Text(role == .child
                     ? "I'm supporting as a parent / caregiver"
                     : "I have their okay to keep notes")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
            }
            .tint(Color.indigo)
            .frame(minHeight: ForgeUX.minTap)

            Text(CyclePrivacy.partnerExtra)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .forgeContentCard(tint: .indigo)
    }

    private var addButton: some View {
        ForgePrimaryButton(
            title: "Add \(role.shortLabel.lowercased())",
            icon: "person.badge.plus",
            accent: .ember
        ) {
            let person = cycleStore.addSupportedPerson(
                name: name,
                role: role,
                relationshipLabel: label.isEmpty ? role.suggestedLabels.first : label,
                consentAcknowledged: consent
            )
            FDS.notificationHaptic(.success)
            onAdded(person)
            dismiss()
        }
    }
}

struct CycleAccuracyExplainerSheet: View {
    let report: CycleAccuracyReport
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 28

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    intro
                    if let mae = report.maeDays {
                        scoreCard(mae: mae)
                    }
                    methodCard
                    sexualHealthCard
                    footer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .background(Color.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.ember)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Blocks

    private var intro: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text("Science behind your estimates")
                .font(HomeType.sessionTitle)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            Text("Evidence-informed lifestyle methods. Personal timing error — not a global accuracy stamp. Forge is a coach, not a clinic.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }

    private func scoreCard(mae: Double) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("YOUR PERSONAL SCORE", tint: .vitality)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(String(format: "Avg ±%.1f days over last %d starts", mae, report.sampleCount))
                    .font(HomeType.cta)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(report.gradeDetail)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
        }
        .forgeContentCard(tint: .vitality)
    }

    private var methodCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            explainerRow("1", "Period episodes", "Group bleeding days into starts (light+ preferred). Reduces false short cycles from lone spotting.")
            explainerRow("2", "Recency-weighted median + MAD", "Recent cycles count more; robust stats resist outlier months.")
            explainerRow("3", "Ensemble forecast", "Blend recency median, last cycle, robust median, and ovu+luteal when high-signal.")
            explainerRow("4", "Ovulation stack", "LH → BBT 3-over-6 → peak mucus → calendar. Stronger markers raise ovulation confidence.")
            explainerRow("5", "Learned luteal", "When LH/BBT and a later start exist, personalize luteal length (clamped 10–16d).")
            explainerRow("6", "Feedback calibration", "Predicted vs actual start → bias correction (adaptive EMA). Your body isn’t “wrong” — the estimate improves.")
            explainerRow("7", "ARIA understands & evaluates", "ARIA critiques data quality (sparse, noisy, conflicts) then teaches next steps — numbers stay engine-owned.")
        }
        .forgeContentCard()
    }

    private var sexualHealthCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Sexual health (lifestyle)")
            Text("ARIA may discuss contraception options and sexual-health materials as lifestyle education when relevant. Forge cycle tracking itself is not a contraceptive method and is not a substitute for clinician-guided birth control.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .forgeContentCard()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text(CyclePrivacy.shortPromise)
                .font(HomeType.body)
                .foregroundStyle(Color.vitality)
                .forgeWrapping()
            Text(MenstrualCycleEngine.disclaimer)
                .font(HomeType.micro)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }

    private func explainerRow(_ n: String, _ title: String, _ body: String) -> some View {
        let diameter = ForgeLayout.scaledCap(badgeSize, base: 28)
        return HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Text(n)
                .font(HomeType.label)
                .monospacedDigit()
                .foregroundStyle(Color.ember)
                .hudInArcText()
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color.ember.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(body)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(n). \(title). \(body)")
    }
}

struct SexualHealthEntryCard: View {
    let store: AppStore
    let cycleStore: MenstrualHealthStore
    @State private var showDifficultyGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("SEXUAL HEALTH & INTIMACY", tint: .indigo)

            Text("Healthy sex, safe sex, positions, period sex, and how a partner can actually help — on this iPhone. Forge is not a contraceptive.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()

            VStack(spacing: ForgeLayout.rowGap) {
                ForEach(IntimacyFlow.allCases) { flow in
                    entryButton(flow)
                }
            }

            Text(SexualHealthCurriculum.medicalDisclaimer)
                .font(HomeType.micro)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .forgeContentCard(tint: .indigo)
        .sheet(isPresented: $showDifficultyGuide) {
            DifficultyConceivingGuideView {
                showDifficultyGuide = false
                startFlow(.difficultyConceiving)
            }
        }
    }

    private func entryButton(_ flow: IntimacyFlow) -> some View {
        Button {
            FDS.haptic(.press)
            if flow == .difficultyConceiving {
                showDifficultyGuide = true
            } else {
                startFlow(flow)
            }
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: flow.icon, tint: .indigo)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(flow.label)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(flow.subtitle)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                Image(systemName: flow == .difficultyConceiving ? "chevron.right" : "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, ForgeLayout.rowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityHint(flow.opensChat ? "Opens ARIA" : "Opens a guide")
    }

    private func startFlow(_ flow: IntimacyFlow) {
        let todayKey = CycleDayKey.key()
        let session = IntimacyFlowComposer.session(
            flow,
            phase: cycleStore.snapshot.phase,
            snapshot: cycleStore.snapshot.phase == .unknown ? nil : cycleStore.snapshot,
            todayLog: cycleStore.logs.first(where: { $0.dayKey == todayKey }),
            relationshipLabel: cycleStore.partnerSettings.relationshipLabel
        )
        store.startIntimacyFlow(session)
    }
}

struct CycleNotificationSettingsCard: View {
    @ObservedObject var cycleStore: MenstrualHealthStore

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("NOTIFICATIONS")

            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                notifRow(
                    icon: "thermometer",
                    title: "Daily BBT reminder",
                    subtitle: "Log your temperature before getting up",
                    isOn: Binding(
                        get: { cycleStore.settings.bbtReminderEnabled },
                        set: { val in cycleStore.updateSettings { $0.bbtReminderEnabled = val } }
                    )
                )

                if cycleStore.settings.bbtReminderEnabled {
                    reminderTimeRow
                }

                notifRow(
                    icon: "calendar.badge.exclamationmark",
                    title: "Fertile window alert",
                    subtitle: "2 days before your fertile window opens",
                    isOn: Binding(
                        get: { cycleStore.settings.fertileWindowAlertEnabled },
                        set: { val in cycleStore.updateSettings { $0.fertileWindowAlertEnabled = val } }
                    )
                )

                notifRow(
                    icon: "bell.badge",
                    title: "Period reminder",
                    subtitle: "1 day before your predicted period start",
                    isOn: Binding(
                        get: { cycleStore.settings.periodReminderEnabled },
                        set: { val in cycleStore.updateSettings { $0.periodReminderEnabled = val } }
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeWell()
        }
    }

    /// Label and menu Picker stack at accessibility sizes, so the title never
    /// compresses to an ellipsis.
    private var reminderTimeRow: some View {
        ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .center) {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "clock", tint: .ember)
                Text("Reminder time")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Hour", selection: Binding(
                get: { cycleStore.settings.bbtReminderHour },
                set: { val in cycleStore.updateSettings { $0.bbtReminderHour = val } }
            )) {
                ForEach(4..<10) { h in
                    Text("\(h):00 AM").tag(h)
                }
            }
            .pickerStyle(.menu)
            .tint(.ember)
            .frame(minHeight: ForgeUX.minTap)
        }
        .frame(minHeight: ForgeUX.minTap)
    }

    /// The Toggle's own label carries the title and subtitle, so VoiceOver
    /// announces a named switch instead of an unnamed one.
    private func notifRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: icon, tint: .ember)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(title)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    Text(subtitle)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
            }
        }
        .tint(.ember)
        .frame(minHeight: ForgeUX.minTap)
    }
}
