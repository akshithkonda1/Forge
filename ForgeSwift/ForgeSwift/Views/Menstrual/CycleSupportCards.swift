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
                VStack(alignment: .leading, spacing: 18) {
                    Text("Partner, relative, or parent — including a parent of a minor. Each person is their own. They need an iPhone; invites are iMessage only.")
                        .font(FDS.TypeScale.body(14))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHO")
                            .forgeSectionLabel()
                        ForEach(CycleSupportRole.selectableRoles) { option in
                            Button {
                                role = option
                                label = option.suggestedLabels.first ?? label
                                FDS.selectionHaptic()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: option.icon)
                                        .frame(width: 22)
                                    Text(option.label)
                                        .font(FDS.TypeScale.body(15))
                                    Spacer()
                                    if role == option {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color(hex: "6366F1"))
                                    }
                                }
                                .foregroundColor(role == option ? .textPrimary : .textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(role == option ? Color(hex: "6366F1").opacity(0.12) : Color.surfaceElevated)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TextField(role == .child ? "Name (optional)" : "Name (optional)", text: $name)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    TextField(role == .child ? "Label (daughter / child…)" : "Label (partner / wife…)", text: $label)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Toggle(isOn: $consent) {
                        Text(role == .child
                             ? "I'm supporting as a parent / caregiver"
                             : "I have their okay to keep notes")
                            .foregroundColor(.textPrimary)
                    }
                    .tint(Color(hex: "6366F1"))

                    Text(CyclePrivacy.partnerExtra)
                        .font(FDS.TypeScale.body(11))
                        .foregroundColor(.textTertiary)

                    Button {
                        let person = cycleStore.addSupportedPerson(
                            name: name,
                            role: role,
                            relationshipLabel: label.isEmpty ? role.suggestedLabels.first : label,
                            consentAcknowledged: consent
                        )
                        FDS.notificationHaptic(.success)
                        onAdded(person)
                        dismiss()
                    } label: {
                        Text("Add \(role.shortLabel.lowercased())")
                            .font(FDS.TypeScale.label(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color(hex: "6366F1"))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Add someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct CycleAccuracyExplainerSheet: View {
    let report: CycleAccuracyReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Science behind your estimates")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text("Evidence-informed lifestyle methods. Personal timing error — not a global accuracy stamp. Forge is a coach, not a clinic.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)

                    if let mae = report.maeDays {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("YOUR PERSONAL SCORE")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.4)
                                .foregroundColor(.textTertiary)
                            Text(String(format: "Avg ±%.1f days over last %d starts", mae, report.sampleCount))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text(report.gradeDetail)
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "22C55E").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    explainerRow("1", "Period episodes", "Group bleeding days into starts (light+ preferred). Reduces false short cycles from lone spotting.")
                    explainerRow("2", "Recency-weighted median + MAD", "Recent cycles count more; robust stats resist outlier months.")
                    explainerRow("3", "Ensemble forecast", "Blend recency median, last cycle, robust median, and ovu+luteal when high-signal.")
                    explainerRow("4", "Ovulation stack", "LH → BBT 3-over-6 → peak mucus → calendar. Stronger markers raise ovulation confidence.")
                    explainerRow("5", "Learned luteal", "When LH/BBT and a later start exist, personalize luteal length (clamped 10–16d).")
                    explainerRow("6", "Feedback calibration", "Predicted vs actual start → bias correction (adaptive EMA). Your body isn’t “wrong” — the estimate improves.")
                    explainerRow("7", "ARIA understands & evaluates", "ARIA critiques data quality (sparse, noisy, conflicts) then teaches next steps — numbers stay engine-owned.")

                    Text("Sexual health (lifestyle)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .padding(.top, 8)
                    Text("ARIA may discuss contraception options and sexual-health materials as lifestyle education when relevant. Forge cycle tracking itself is not a contraceptive method and is not a substitute for clinician-guided birth control.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)

                    Text(CyclePrivacy.shortPromise)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "22C55E"))
                        .padding(.top, 4)

                    Text(MenstrualCycleEngine.disclaimer)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textMuted)
                }
                .padding(20)
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

    private func explainerRow(_ n: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(.ember)
                .frame(width: 28, height: 28)
                .background(Color.ember.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
            }
        }
    }
}

struct SexualHealthEntryCard: View {
    let store: AppStore
    let cycleStore: MenstrualHealthStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SEXUAL HEALTH & CONTRACEPTION")
                .font(FDS.TypeScale.label(11))
                .foregroundColor(.textTertiary)
                .tracking(0.8)

            VStack(spacing: 8) {
                entryButton(
                    icon: "pills.fill",
                    label: "Contraception methods",
                    subtitle: "Biology-first overview with effectiveness data",
                    prompt: SexualHealthCoach.contraceptionOverviewPrompt(
                        biologicalSex: store.userProfile.biologicalSex,
                        snapshot: cycleStore.snapshot.phase != .unknown ? cycleStore.snapshot : nil,
                        isEducational: store.userProfile.educationalCycleMode,
                        isHormonal: cycleStore.settings.usesHormonalContraception
                    )
                )
                entryButton(
                    icon: "calendar.badge.checkmark",
                    label: "Fertility awareness (FAM)",
                    subtitle: "How reliable is FAM for your cycle specifically",
                    prompt: SexualHealthCoach.famReliabilityPrompt(snapshot: cycleStore.snapshot)
                )
                entryButton(
                    icon: "heart.circle.fill",
                    label: "Wellbeing in my phase",
                    subtitle: "Hormonal context for energy, mood & libido",
                    prompt: SexualHealthCoach.phaseWellnessPrompt(
                        phase: cycleStore.snapshot.phase,
                        snapshot: cycleStore.snapshot.phase != .unknown ? cycleStore.snapshot : nil
                    )
                )
                entryButton(
                    icon: "clock.badge.checkmark",
                    label: "Fertility timing (TTC)",
                    subtitle: "Optimise timing using your ovulation data",
                    prompt: SexualHealthCoach.ttcPrompt(snapshot: cycleStore.snapshot)
                )
            }

            Text(SexualHealthCurriculum.medicalDisclaimer)
                .font(FDS.TypeScale.micro(10))
                .foregroundColor(.textTertiary)
                .padding(.top, 2)
        }
        .padding(16)
        .forgeGlassCard(accent: Color(hex: "EC4899"))
    }

    private func entryButton(icon: String, label: String, subtitle: String, prompt: String) -> some View {
        Button {
            store.openChat(with: prompt, voice: false)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(.ember)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(FDS.TypeScale.label(14))
                        .foregroundColor(.textPrimary)
                    Text(subtitle)
                        .font(FDS.TypeScale.body(11))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CycleNotificationSettingsCard: View {
    @ObservedObject var cycleStore: MenstrualHealthStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTIFICATIONS")
                .font(FDS.TypeScale.label(12))
                .foregroundColor(.textSecondary)
                .tracking(0.8)

            VStack(spacing: 0) {
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
                    Divider().padding(.leading, 40)
                    HStack(spacing: 10) {
                        Image(systemName: "clock")
                            .font(.subheadline)
                            .foregroundColor(.ember)
                            .frame(width: 28)
                        Text("Reminder time")
                            .font(FDS.TypeScale.body(14))
                            .foregroundColor(.textPrimary)
                        Spacer()
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
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                Divider().padding(.leading, 40)
                notifRow(
                    icon: "calendar.badge.exclamationmark",
                    title: "Fertile window alert",
                    subtitle: "2 days before your fertile window opens",
                    isOn: Binding(
                        get: { cycleStore.settings.fertileWindowAlertEnabled },
                        set: { val in cycleStore.updateSettings { $0.fertileWindowAlertEnabled = val } }
                    )
                )

                Divider().padding(.leading, 40)
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
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        }
    }

    @ViewBuilder
    private func notifRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.ember)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FDS.TypeScale.body(14))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(FDS.TypeScale.body(11))
                    .foregroundColor(.textTertiary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .tint(.ember)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
