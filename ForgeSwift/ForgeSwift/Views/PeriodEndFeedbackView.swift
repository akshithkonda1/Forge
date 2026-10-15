import SwiftUI

/// Ending screen after a period is marked finished — noninvasive questions so coaching keeps learning.
/// Answers stay on-device and are never used for ads or resale (see CyclePrivacy).
struct PeriodEndFeedbackView: View {
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    let episode: PeriodEpisode
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// One accent for every selection on this form.
    private let accent = Color.aurora

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    header
                    privacyBanner
                    periodCard
                    bodyLifeCard
                    coachingCard
                    notesCard
                    Text("Lifestyle coaching only — not medical advice. Answers stay on-device to help ARIA support you. Never sold or used for ads.")
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .forgeScreenBackground(accent: accent)
            .safeAreaInset(edge: .bottom) { bottomBar }
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

    // MARK: - Header and privacy

    private var header: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text("How was your period?")
                .font(HomeType.sessionTitle)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            Text("\(episode.dayCount) day\(episode.dayCount == 1 ? "" : "s") · ended \(shortDate(episode.endDayKey)). A few optional questions help ARIA learn what actually works for you.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }

    private var privacyBanner: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.vitality)
                .accessibilityHidden(true)
            Text(CyclePrivacy.shortPromise)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
        .forgeContentCard(tint: .vitality, padding: ForgeLayout.compactCardPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Card 1: Your period

    private var periodCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Your period", tint: accent)
            severityQuestion
            painQuestion
            energyQuestion
            lengthQuestion
            flowQuestion
        }
        .forgeContentCard(tint: accent)
    }

    private var severityQuestion: some View {
        question(title: "HOW WAS IT OVERALL?") {
            segmented(
                PeriodSeverity.allCases.map { ForgeSegmentOption(value: $0, title: $0.label, icon: $0.icon) },
                selection: $severity
            )
        }
    }

    // MARK: Pain

    private var painValue: Int { Int(peakPain) }

    private var painBand: String {
        switch painValue {
        case ...0: return "None"
        case 1...3: return "Mild"
        case 4...6: return "Moderate"
        default: return "Severe"
        }
    }

    /// Steel to ember as pain rises; severe softens to the miss steel. Never red.
    private var painTint: Color {
        switch painValue {
        case ...0: return Color.textTertiary
        case 1...3: return Color.steel
        case 4...6: return Color.ember
        default: return HudChrome.miss
        }
    }

    private var painQuestion: some View {
        question(
            title: "PEAK PAIN",
            subtitle: "0 = none · 10 = worst — optional, just helps recovery coaching"
        ) {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                painReadout
                Slider(value: $peakPain, in: 0...10, step: 1)
                    .tint(painTint)
                    .frame(minHeight: ForgeUX.minTap)
                    .accessibilityLabel("Peak pain")
                    .accessibilityValue("\(painValue) of 10, \(painBand)")
            }
        }
    }

    private var painReadout: some View {
        ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: ForgeLayout.pairGap) {
                Text("\(painValue)")
                    .font(HomeType.metric)
                    .foregroundStyle(painTint)
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : FDS.Spring.snap, value: painValue)
                Text("/ 10")
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 0)
            Text(painBand)
                .font(HomeType.label)
                .foregroundStyle(painTint)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
        }
        .accessibilityHidden(true)
    }

    // MARK: Energy, length, flow

    private var energyQuestion: some View {
        question(title: "ENERGY DURING THIS PERIOD") {
            segmented(
                PeriodEnergyLevel.allCases.map { ForgeSegmentOption(value: $0, title: $0.label) },
                selection: $energy
            )
        }
    }

    private var lengthQuestion: some View {
        question(
            title: "Compared to usual length",
            subtitle: "Just a feel — helps us learn your pattern"
        ) {
            segmented(
                PeriodLengthFeel.allCases.map { ForgeSegmentOption(value: $0, title: $0.label) },
                selection: $lengthFeel
            )
        }
    }

    private var flowQuestion: some View {
        question(
            title: "Overall flow",
            subtitle: "Heavier or lighter than what feels normal for you"
        ) {
            segmented(
                PeriodFlowFeel.allCases.map { ForgeSegmentOption(value: $0, title: $0.label) },
                selection: $flowFeel
            )
        }
    }

    // MARK: - Card 2: Body & life

    private var bodyLifeCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Body & life", tint: accent)
            sleepQuestion
            moodQuestion
            lifeImpactQuestion
            stressQuestion
        }
        .forgeContentCard(tint: accent)
    }

    private var sleepQuestion: some View {
        question(
            title: "SLEEP WHILE BLEEDING",
            subtitle: "Did this period mess with your sleep?"
        ) {
            segmented(
                PeriodSleepQuality.allCases.map { ForgeSegmentOption(value: $0, title: $0.label, icon: $0.icon) },
                selection: $sleepQuality
            )
        }
    }

    private var moodQuestion: some View {
        question(
            title: "MOOD OVERALL",
            subtitle: "Rough average for this bleed — not a diagnosis"
        ) {
            segmented(
                PeriodMoodOverall.allCases.map { ForgeSegmentOption(value: $0, title: $0.label, icon: $0.icon) },
                selection: $moodOverall
            )
        }
    }

    private var lifeImpactQuestion: some View {
        question(
            title: "TRAINING & DAILY LIFE",
            subtitle: "How much did this period limit what you could do?"
        ) {
            segmented(
                PeriodLifeImpact.allCases.map { ForgeSegmentOption(value: $0, title: $0.label) },
                selection: $lifeImpact
            )
        }
    }

    private var stressQuestion: some View {
        question(
            title: "STRESS THIS CYCLE",
            subtitle: "Optional context — stress often changes how periods feel"
        ) {
            segmented(
                PeriodStressLevel.allCases.map { ForgeSegmentOption(value: $0, title: $0.label) },
                selection: $stressLevel
            )
        }
    }

    // MARK: - Card 3: Coaching

    private var coachingCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Coaching", tint: accent)
            helpfulnessQuestion
            topicQuestion(
                title: "What helped",
                subtitle: "Tap anything that made this period easier",
                selection: $whatHelped,
                tint: Color.vitality
            )
            topicQuestion(
                title: "What didn’t help",
                subtitle: "We’ll dial these back next time",
                selection: $whatDidntHelp,
                tint: HudChrome.miss
            )
            topicQuestion(
                title: "Want more of",
                subtitle: "Coaching to lean into next cycle",
                selection: $wantMore,
                tint: accent
            )
            topicQuestion(
                title: "Want less of",
                subtitle: "Optional — things to skip",
                selection: $wantLess,
                tint: Color.steel
            )
        }
        .forgeContentCard(tint: accent)
    }

    private var helpfulnessQuestion: some View {
        question(
            title: "WAS COACHING USEFUL?",
            subtitle: "Be honest — this is how we keep learning what works for you."
        ) {
            segmented(
                CoachingHelpfulness.allCases.map { ForgeSegmentOption(value: $0, title: $0.label) },
                selection: $helpfulness
            )
        }
    }

    private func topicQuestion(
        title: String,
        subtitle: String,
        selection: Binding<Set<PeriodCoachingTopic>>,
        tint: Color
    ) -> some View {
        question(title: title, subtitle: subtitle) {
            ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.interactiveChipLineGap) {
                ForEach(PeriodCoachingTopic.allCases) { topic in
                    topicChip(topic, selection: selection, tint: tint)
                }
            }
        }
    }

    private func topicChip(
        _ topic: PeriodCoachingTopic,
        selection: Binding<Set<PeriodCoachingTopic>>,
        tint: Color
    ) -> some View {
        ForgeChipButton(
            label: topic.label,
            icon: topic.icon,
            energy: tint,
            selected: selection.wrappedValue.contains(topic)
        ) {
            selection.wrappedValue.formSymmetricDifference([topic])
        }
    }

    // MARK: - Card 4: Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeSectionHeader(
                title: "ANYTHING ELSE?",
                subtitle: "Optional — patterns, what you’d want next time, or nothing at all.",
                energy: accent
            )
            TextField("Optional notes for next time…", text: $notes, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.plain)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .topLeading)
                .forgeWell()
                .accessibilityLabel("Notes for next time")
        }
        .forgeContentCard(tint: accent)
    }

    // MARK: - Shared form pieces

    /// A question: eyebrow, optional supporting line, then its control.
    private func question<Control: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
            ForgeSectionHeader(title: title, subtitle: subtitle)
            control()
        }
    }

    /// Single-select row for three labelled steps. Bleeds to the card edge when
    /// it has to become a rail.
    private func segmented<Value: Hashable>(
        _ options: [ForgeSegmentOption<Value>],
        selection: Binding<Value>
    ) -> some View {
        ForgeSegmentedControl(
            options,
            selection: selection,
            accent: accent,
            bleed: ForgeLayout.cardPadding
        )
    }

    // MARK: - Submit

    private var bottomBar: some View {
        VStack(spacing: ForgeLayout.tileGap) {
            if let submittedSummary {
                ForgeToast(title: submittedSummary, energy: .vitality)
                    .lineLimit(3)
            }
            ForgePrimaryButton(
                title: "Save & teach ARIA",
                icon: "checkmark",
                accent: .ember,
                action: submit
            )
            .disabled(submittedSummary != nil)
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, FDS.Spacing.sm)
        .padding(.bottom, FDS.Spacing.sm)
        .forgeBarChrome(edge: .bottom)
    }

    private func submit() {
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
        AccessibilityNotification.Announcement(summary).post()
        FDS.notificationHaptic(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            onDone?()
            dismiss()
        }
    }

    private func shortDate(_ key: String) -> String {
        guard let d = CycleDayKey.date(from: key) else { return key }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}
