import SwiftUI

/// Ending screen after a period is marked finished — noninvasive questions so coaching keeps learning.
/// Answers stay on-device and are never used for ads or resale (see CyclePrivacy).
struct PeriodEndFeedbackView: View {
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    let episode: PeriodEpisode
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var severity: PeriodSeverity = .moderate
    @State private var peakPain: Double = 4
    @State private var energy: PeriodEnergyLevel = .okay
    @State private var lengthFeel: PeriodLengthFeel = .typical
    @State private var flowFeel: PeriodFlowFeel = .typical
    @State private var sleepQuality: PeriodSleepQuality = .okay
    @State private var moodOverall: PeriodMoodOverall = .mixed
    @State private var lifeImpact: PeriodLifeImpact = .medium
    @State private var stressLevel: PeriodStressLevel = .medium
    @State private var helpfulness: CoachingHelpfulness = .somewhat
    @State private var whatHelped: Set<PeriodCoachingTopic> = []
    @State private var whatDidntHelp: Set<PeriodCoachingTopic> = []
    @State private var wantMore: Set<PeriodCoachingTopic> = []
    @State private var wantLess: Set<PeriodCoachingTopic> = []
    @State private var notes = ""
    @State private var submittedSummary: String?

    private let accent = Color(hex: "EF4444")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    privacyBanner

                    severitySection
                    painSection
                    energySection

                    comparisonSection(
                        title: "Compared to usual length",
                        subtitle: "Just a feel — helps us learn your pattern",
                        selection: lengthFeel,
                        options: PeriodLengthFeel.allCases,
                        label: { $0.label },
                        tint: Color(hex: "38BDF8")
                    ) { lengthFeel = $0 }

                    comparisonSection(
                        title: "Overall flow",
                        subtitle: "Heavier or lighter than what feels normal for you",
                        selection: flowFeel,
                        options: PeriodFlowFeel.allCases,
                        label: { $0.label },
                        tint: accent
                    ) { flowFeel = $0 }

                    sleepSection
                    moodSection
                    lifeImpactSection
                    stressSection

                    helpfulnessSection
                    topicSection(
                        title: "What helped",
                        subtitle: "Tap anything that made this period easier",
                        selection: $whatHelped,
                        tint: Color(hex: "22C55E")
                    )
                    topicSection(
                        title: "What didn’t help",
                        subtitle: "We’ll dial these back next time",
                        selection: $whatDidntHelp,
                        tint: Color(hex: "F59E0B")
                    )
                    topicSection(
                        title: "Want more of",
                        subtitle: "Coaching to lean into next cycle",
                        selection: $wantMore,
                        tint: Color(hex: "A855F7")
                    )
                    topicSection(
                        title: "Want less of",
                        subtitle: "Optional — things to skip",
                        selection: $wantLess,
                        tint: Color(hex: "6B7280")
                    )
                    notesSection
                    if let submittedSummary {
                        Text(submittedSummary)
                            .font(FDS.TypeScale.body(14))
                            .foregroundStyle(Color(hex: "22C55E"))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "22C55E").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    submitButton
                    Text("Lifestyle coaching only — not medical advice. Answers stay on-device to help ARIA support you. Never sold or used for ads.")
                        .font(FDS.TypeScale.micro(11))
                        .foregroundColor(.textSecondary)
                        .padding(.bottom, 24)
                }
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Period finished")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        cycleStore.dismissPeriodEndFeedback()
                        onDone?()
                        dismiss()
                    }
                    .foregroundColor(.textSecondary)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How was your period?")
                .font(FDS.TypeScale.title(22))
                .foregroundColor(.textPrimary)
            Text("\(episode.dayCount) day\(episode.dayCount == 1 ? "" : "s") · ended \(shortDate(episode.endDayKey)). A few optional questions help ARIA learn what actually works for you.")
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
        }
    }

    private var privacyBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "22C55E"))
            Text(CyclePrivacy.shortPromise)
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "22C55E").opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var severitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW WAS IT OVERALL?")
                .forgeSectionLabel()
            HStack(spacing: 8) {
                ForEach(PeriodSeverity.allCases) { level in
                    chip(
                        title: level.label,
                        icon: level.icon,
                        selected: severity == level,
                        tint: accent
                    ) {
                        severity = level
                        FDS.selectionHaptic()
                    }
                }
            }
        }
    }

    private var painSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PEAK PAIN")
                    .forgeSectionLabel()
                Spacer()
                Text("\(Int(peakPain))")
                    .font(FDS.TypeScale.label(16))
                    .foregroundColor(.textPrimary)
            }
            Slider(value: $peakPain, in: 0...10, step: 1)
                .tint(accent)
            Text("0 = none · 10 = worst — optional, just helps recovery coaching")
                .font(FDS.TypeScale.micro(11))
                .foregroundColor(.textSecondary)
        }
        .padding(16)
        .forgeGlassCard(accent: accent)
    }

    private var energySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ENERGY DURING THIS PERIOD")
                .forgeSectionLabel()
            HStack(spacing: 8) {
                ForEach(PeriodEnergyLevel.allCases) { level in
                    chip(
                        title: level.label,
                        icon: nil,
                        selected: energy == level,
                        tint: Color(hex: "38BDF8")
                    ) {
                        energy = level
                        FDS.selectionHaptic()
                    }
                }
            }
        }
    }

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SLEEP WHILE BLEEDING")
                .forgeSectionLabel()
            Text("Did this period mess with your sleep?")
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)
            HStack(spacing: 8) {
                ForEach(PeriodSleepQuality.allCases) { level in
                    chip(
                        title: level.label,
                        icon: level.icon,
                        selected: sleepQuality == level,
                        tint: Color(hex: "6366F1")
                    ) {
                        sleepQuality = level
                        FDS.selectionHaptic()
                    }
                }
            }
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MOOD OVERALL")
                .forgeSectionLabel()
            Text("Rough average for this bleed — not a diagnosis")
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)
            HStack(spacing: 8) {
                ForEach(PeriodMoodOverall.allCases) { level in
                    chip(
                        title: level.label,
                        icon: level.icon,
                        selected: moodOverall == level,
                        tint: Color(hex: "A855F7")
                    ) {
                        moodOverall = level
                        FDS.selectionHaptic()
                    }
                }
            }
        }
    }

    private var lifeImpactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRAINING & DAILY LIFE")
                .forgeSectionLabel()
            Text("How much did this period limit what you could do?")
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)
            HStack(spacing: 8) {
                ForEach(PeriodLifeImpact.allCases) { level in
                    chip(
                        title: level.label,
                        icon: nil,
                        selected: lifeImpact == level,
                        tint: Color(hex: "F59E0B")
                    ) {
                        lifeImpact = level
                        FDS.selectionHaptic()
                    }
                }
            }
        }
    }

    private var stressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STRESS THIS CYCLE")
                .forgeSectionLabel()
            Text("Optional context — stress often changes how periods feel")
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)
            HStack(spacing: 8) {
                ForEach(PeriodStressLevel.allCases) { level in
                    chip(
                        title: level.label,
                        icon: nil,
                        selected: stressLevel == level,
                        tint: Color(hex: "F87171")
                    ) {
                        stressLevel = level
                        FDS.selectionHaptic()
                    }
                }
            }
        }
    }

    private var helpfulnessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WAS COACHING USEFUL?")
                .forgeSectionLabel()
            Text("Be honest — this is how we keep learning what works for you.")
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)
            HStack(spacing: 8) {
                ForEach(CoachingHelpfulness.allCases) { level in
                    chip(
                        title: level.label,
                        icon: nil,
                        selected: helpfulness == level,
                        tint: Color(hex: "A855F7")
                    ) {
                        helpfulness = level
                        FDS.selectionHaptic()
                    }
                }
            }
        }
    }

    private func comparisonSection<T: Identifiable & Hashable>(
        title: String,
        subtitle: String,
        selection: T,
        options: [T],
        label: @escaping (T) -> String,
        tint: Color,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .forgeSectionLabel()
            Text(subtitle)
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)
            HStack(spacing: 8) {
                ForEach(options) { option in
                    chip(
                        title: label(option),
                        icon: nil,
                        selected: selection == option,
                        tint: tint
                    ) {
                        onSelect(option)
                        FDS.selectionHaptic()
                    }
                }
            }
        }
    }

    private func topicSection(
        title: String,
        subtitle: String,
        selection: Binding<Set<PeriodCoachingTopic>>,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .forgeSectionLabel()
            Text(subtitle)
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)
            let cols = [GridItem(.adaptive(minimum: 108), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(PeriodCoachingTopic.allCases) { topic in
                    let on = selection.wrappedValue.contains(topic)
                    Button {
                        if on { selection.wrappedValue.remove(topic) }
                        else { selection.wrappedValue.insert(topic) }
                        FDS.selectionHaptic()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: topic.icon)
                                .font(.system(size: 10))
                            Text(topic.label)
                                .font(FDS.TypeScale.micro(11))
                                .lineLimit(1)
                        }
                        .foregroundColor(on ? .white : .textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(on ? tint.opacity(0.9) : Color.surfaceElevated)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANYTHING ELSE?")
                .forgeSectionLabel()
            Text("Optional — patterns, what you’d want next time, or nothing at all.")
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)
            TextField("Optional notes for next time…", text: $notes, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.textPrimary)
        }
    }

    private var submitButton: some View {
        Button {
            let feedback = PeriodEndFeedback(
                startDayKey: episode.startDayKey,
                endDayKey: episode.endDayKey,
                dayCount: episode.dayCount,
                severity: severity,
                peakPain: Int(peakPain),
                energy: energy,
                lengthFeel: lengthFeel,
                flowFeel: flowFeel,
                sleepQuality: sleepQuality,
                moodOverall: moodOverall,
                lifeImpact: lifeImpact,
                stressLevel: stressLevel,
                coachingHelpfulness: helpfulness,
                whatHelped: Array(whatHelped),
                whatDidntHelp: Array(whatDidntHelp),
                wantMore: Array(wantMore),
                wantLess: Array(wantLess),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                recordedAt: Date()
            )
            let summary = cycleStore.submitPeriodEndFeedback(feedback)
            submittedSummary = summary
            FDS.notificationHaptic(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                onDone?()
                dismiss()
            }
        } label: {
            Text("Save & teach ARIA")
                .font(FDS.TypeScale.label(16))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "F87171"), Color(hex: "EF4444")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(submittedSummary != nil)
    }

    private func chip(title: String, icon: String?, selected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(FDS.TypeScale.label(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(selected ? .white : .textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? tint.opacity(0.9) : Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func shortDate(_ key: String) -> String {
        guard let d = CycleDayKey.date(from: key) else { return key }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}
