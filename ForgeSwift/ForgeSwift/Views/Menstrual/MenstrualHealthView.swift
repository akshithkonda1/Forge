import SwiftUI

// MARK: - Cycle Health (premium surface)

/// Flagship menstrual intelligence UI — self tracking + family support.
struct MenstrualHealthView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case me, partner
        var id: String { rawValue }
        var label: String {
            switch self {
            case .me: return "My cycle"
            case .partner: return "Support"
            }
        }
        var icon: String {
            switch self {
            case .me: return "circle.hexagongrid.fill"
            case .partner: return "heart.circle.fill"
            }
        }
    }

    @EnvironmentObject private var store: AppStore
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared

    var initialPane: Pane? = nil

    @State private var pane: Pane = .me
    @State private var selectedFlow: MenstrualFlowLevel = .medium
    @State private var selectedSymptoms: Set<CycleSymptom> = []
    @State private var bbtText = ""
    @State private var partnerFlow: MenstrualFlowLevel = .medium
    @State private var partnerNameDraft = ""
    @State private var partnerRelDraft = "partner"
    @State private var supportRole: CycleSupportRole = .romantic
    @State private var appeared = false
    @State private var ringPulse = false
    @State private var logExpanded = true
    @State private var historyExpanded = false
    @State private var privacyAccepted = false
    @State private var editingDayKey: String?
    @State private var editFlow: MenstrualFlowLevel = .medium
    @State private var editSymptoms: Set<CycleSymptom> = []
    @State private var editNotes = ""
    @State private var editBBT = ""
    @State private var editOvulationTest: OvulationTestResult?
    @State private var editMucus: CervicalMucusQuality?
    @State private var editPain = 0
    @State private var showWipeConfirm = false
    @State private var showDayEditor = false
    @State private var showAccuracyExplainer = false
    @State private var feedbackOffset = 1
    @State private var modelToast: String?
    /// Identifies the toast currently on screen so a newer toast's timer can't be
    /// cancelled early by an older one still counting down.
    @State private var toastToken = UUID()
    @State private var showPeriodEndFeedback = false
    @State private var periodEndEpisode: PeriodEpisode?
    @State private var bbtUnit: BBTUnit = .celsius
    @State private var saveError: String?

    private var accent: Color {
        let phase = pane == .me ? cycleStore.snapshot.phase : cycleStore.partnerSnapshot.phase
        return Color(hex: phase.accentHex)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    heroHeader
                    panePicker

                    switch pane {
                    case .me:
                        if !cycleStore.settings.enabled {
                            enableCard
                        } else {
                            phaseOrbitCard
                            cycleStageCard
                            if let condition = cycleStore.settings.condition.activeCase {
                                conditionCard(condition)
                            }
                            accuracyCard
                            ariaAnalystCard
                            if cycleStore.settings.highAccuracyMode {
                                highAccuracyCueCard
                            }
                            dayStrip
                            predictionGrid
                            if let score = cycleStore.snapshot.fertileScore {
                                FertileScoreCard(score: score, phase: cycleStore.snapshot.phase) {
                                    store.openChat(with: "My Fertile Score is \(score)/100 right now. What does that mean for training, recovery, and lifestyle timing today?")
                                }
                            }
                            CycleGoalSelectorCard(
                                goal: cycleStore.settings.cycleGoal,
                                onUpdate: { cycleStore.updateCycleGoal($0) }
                            )
                            if cycleStore.settings.cycleGoal == .ttc,
                               let tww = cycleStore.snapshot.twwDaysElapsed {
                                TWWSectionCard(daysElapsed: tww) {
                                    store.openChat(with: "I'm on day \(tww) of my two-week wait. What should I know?")
                                }
                            }
                            predictionFeedbackCard
                            quickLogCard
                            historyCard
                            insightsCard
                            ariaCoachCard
                            sexualHealthCard
                            settingsCard
                            disclaimerFooter
                        }
                    case .partner:
                        partnerContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
            .background {
                cycleAmbientBackground
            }

            if let modelToast {
                Text(modelToast)
                    .font(FDS.TypeScale.label(13))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.ember.opacity(0.92))
                    .clipShape(Capsule())
                    .shadow(color: Color.ember.opacity(0.4), radius: 12, y: 4)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .navigationTitle("Cycle Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if pane == .me, cycleStore.settings.enabled {
                        Button {
                            showAccuracyExplainer = true
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(accent)
                        }
                        .accessibilityLabel("Accuracy explainer")

                        Button {
                            Task {
                                await cycleStore.syncFromHealthKit()
                                cycleStore.refresh(from: store)
                                FDS.notificationHaptic(.success)
                            }
                        } label: {
                            if cycleStore.isSyncing {
                                ProgressView().tint(accent)
                            } else {
                                Image(systemName: "heart.text.square.fill")
                                    .foregroundStyle(accent)
                            }
                        }
                        .accessibilityLabel("Sync Apple Health")
                    }
                }
            }
        }
        .sheet(isPresented: $showAccuracyExplainer) {
            CycleAccuracyExplainerSheet(report: cycleStore.accuracyReport)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPeriodEndFeedback, onDismiss: {
            cycleStore.dismissPeriodEndFeedback()
            periodEndEpisode = nil
        }) {
            if let episode = periodEndEpisode ?? cycleStore.pendingPeriodEndEpisode {
                PeriodEndFeedbackView(episode: episode) {
                    showPeriodEndFeedback = false
                    periodEndEpisode = nil
                }
                .preferredColorScheme(.dark)
            }
        }
        .onChange(of: cycleStore.pendingPeriodEndEpisode) { _, episode in
            guard let episode else { return }
            periodEndEpisode = episode
            showPeriodEndFeedback = true
        }
        .onChange(of: cycleStore.lastModelUpdateMessage) { _, msg in
            guard let msg else { return }
            showToast(msg)
            cycleStore.lastModelUpdateMessage = nil
        }
        // Day editor and the wipe dialog used to hang off `settingsCard`, so they only
        // worked while that specific card happened to be in the view tree.
        .sheet(isPresented: $showDayEditor) { dayEditorSheet }
        .confirmationDialog(
            "Wipe all self cycle logs?",
            isPresented: $showWipeConfirm,
            titleVisibility: .visible
        ) {
            Button("Wipe logs only", role: .destructive) {
                cycleStore.wipeSelfCycleData(includingSettings: false)
                FDS.notificationHaptic(.warning)
                showToast("Cycle logs wiped")
            }
            Button("Wipe logs + disable tracking", role: .destructive) {
                cycleStore.wipeSelfCycleData(includingSettings: true)
                FDS.notificationHaptic(.warning)
                showToast("Cycle data wiped · tracking off")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Logs, learned bias, prediction history, and period feedback are erased. Partner / support logs are kept. This cannot be undone.")
        }
        .alert("Check that entry", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onAppear {
            if let sex = store.userProfile.biologicalSex {
                cycleStore.enableForBiologicalSexIfNeeded(sex)
            }
            cycleStore.enableForFemaleProfileIfNeeded(gender: store.userProfile.gender)
            if let initialPane {
                pane = initialPane
            } else if store.userProfile.gender != .female,
                      store.userProfile.biologicalSex?.cycleAutoEnabled != true,
                      !cycleStore.cycleSurfaceRelevant,
                      !cycleStore.settings.enabled {
                pane = .partner
            }
            partnerNameDraft = cycleStore.partnerSettings.partnerName
            partnerRelDraft = cycleStore.partnerSettings.relationshipLabel
            supportRole = cycleStore.partnerSettings.resolvedRole
            privacyAccepted = cycleStore.settings.privacyAcknowledged
            cycleStore.refresh(from: store)
            Task { await cycleStore.syncFromHealthKit() }
            withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true }
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                ringPulse = true
            }
        }
    }

    /// The end-to-end arc of the current cycle: bleed → post-period → fertile → pre-menstrual.
    /// This is the surface that makes "my period finished" visibly mean something.
    private var cycleStageCard: some View {
        let snap = cycleStore.snapshot
        let stage = snap.stage
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("WHERE YOU ARE").forgeSectionLabel()
                Spacer()
                Text(stage.label)
                    .font(FDS.TypeScale.micro(11))
                    .foregroundStyle(stageColor(stage))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(stageColor(stage).opacity(0.14))
                    .clipShape(Capsule())
            }

            stageTrack(current: stage)

            if !snap.stageNarrative.isEmpty {
                Text(snap.stageNarrative)
                    .font(FDS.TypeScale.body(13))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Facts, not vibes: real dates for the two things people actually plan around.
            VStack(spacing: 8) {
                if let end = snap.currentPeriodEndDayKey, let count = snap.currentPeriodDayCount {
                    stageFact(
                        icon: snap.periodEndConfirmed ? "checkmark.circle.fill" : "drop.circle",
                        label: snap.periodEndConfirmed ? "Period finished" : "Last bleed logged",
                        value: "\(shortDate(end)) · \(count) day\(count == 1 ? "" : "s")",
                        color: Color(hex: "EF4444")
                    )
                }
                if let fs = snap.fertileWindowStartDayKey, let fe = snap.fertileWindowEndDayKey {
                    stageFact(
                        icon: "waveform.path.ecg",
                        label: "Fertile window",
                        value: "\(shortDate(fs)) – \(shortDate(fe))",
                        color: Color(hex: "F59E0B")
                    )
                }
                if let next = snap.nextPeriod {
                    stageFact(
                        icon: "calendar",
                        label: "Next period",
                        value: snap.daysUntilNextPeriod.map { d in
                            d < 0 ? "\(shortDate(next.medianDayKey)) · \(-d)d overdue"
                                  : "\(shortDate(next.medianDayKey)) · in \(d)d"
                        } ?? shortDate(next.medianDayKey),
                        color: Color(hex: "6366F1")
                    )
                }
            }

            // The one action that closes the loop, offered exactly when it applies.
            if stage == .period, !snap.periodEndConfirmed {
                Button {
                    let msg = cycleStore.confirmPeriodEndedToday()
                    cycleStore.refresh(from: store)
                    cycleStore.refreshAnalyst(lastAction: "period_ended_today")
                    showToast(msg)
                    if let episode = cycleStore.pendingPeriodEndEpisode {
                        periodEndEpisode = episode
                        showPeriodEndFeedback = true
                    }
                } label: {
                    Label("My period finished", systemImage: "checkmark.flag.fill")
                        .font(FDS.TypeScale.label(14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "A78BFA"), Color(hex: "6366F1")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .forgeGlassCard(accent: stageColor(stage))
        .accessibilityElement(children: .contain)
    }

    private func stageColor(_ stage: CycleStage) -> Color {
        switch stage {
        case .period:        return Color(hex: "EF4444")
        case .postPeriod:    return Color(hex: "22C55E")
        case .fertile:       return Color(hex: "F59E0B")
        case .ovulation:     return Color(hex: "A855F7")
        case .premenstrual:  return Color(hex: "6366F1")
        case .unknown:       return .steel
        }
    }

    private func stageIcon(_ stage: CycleStage) -> String {
        switch stage {
        case .period:        return "drop.fill"
        case .postPeriod:    return "checkmark.circle.fill"
        case .fertile:       return "waveform.path.ecg"
        case .ovulation:     return "sparkles"
        case .premenstrual:  return "moon.fill"
        case .unknown:       return "circle.dashed"
        }
    }

    private func stageTrack(current: CycleStage) -> some View {
        let ordered: [CycleStage] = [.period, .postPeriod, .fertile, .ovulation, .premenstrual]
        let currentIndex = ordered.firstIndex(of: current)
        return HStack(spacing: 6) {
            ForEach(Array(ordered.enumerated()), id: \.element) { index, stage in
                let isCurrent = stage == current
                let isPast = currentIndex.map { index < $0 } ?? false
                VStack(spacing: 6) {
                    Image(systemName: stageIcon(stage))
                        .font(.system(size: isCurrent ? 14 : 11, weight: .semibold))
                        .foregroundStyle(
                            isCurrent ? stageColor(stage)
                                : (isPast ? Color.textSecondary : Color.textMuted)
                        )
                    Capsule()
                        .fill(
                            isCurrent ? stageColor(stage)
                                : (isPast ? Color.textSecondary.opacity(0.4) : Color.white.opacity(0.08))
                        )
                        .frame(height: isCurrent ? 4 : 3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cycle stage: \(current.label)")
    }

    private func stageFact(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textTertiary)
            Spacer()
            Text(value)
                .font(FDS.TypeScale.label(13))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    /// Condition context, shown right under the phase orbit so the user can see *why*
    /// their windows behave differently — and take it straight to ARIA.
    private func conditionCard(_ condition: CycleCondition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: condition.icon)
                    .foregroundStyle(Color(hex: "38BDF8"))
                Text(condition.label.uppercased())
                    .forgeSectionLabel()
                    .foregroundStyle(Color(hex: "38BDF8"))
            }
            Text(condition.trackingImplication)
                .font(FDS.TypeScale.body(13))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                store.openChat(
                    with: "I track my cycle with \(condition.label). I'm on \(cycleStore.snapshot.phase.label)"
                        + (cycleStore.snapshot.dayInCycle.map { ", day \($0)" } ?? "")
                        + ". What should I expect this week, and what's worth raising with a clinician?",
                    voice: false
                )
            } label: {
                Label("Ask ARIA about \(condition.label)", systemImage: "sparkles")
                    .font(FDS.TypeScale.label(13))
                    .foregroundStyle(Color.ember)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(accent: Color(hex: "38BDF8"))
        .accessibilityElement(children: .contain)
    }

    // MARK: Ambient

    private var cycleAmbientBackground: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            RadialGradient(
                colors: [accent.opacity(0.18), .clear],
                center: UnitPoint(x: 0.5, y: 0.08),
                startRadius: 20,
                endRadius: 320
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color.steel.opacity(0.06), .clear],
                center: UnitPoint(x: 0.9, y: 0.75),
                startRadius: 10,
                endRadius: 260
            )
            .ignoresSafeArea()
        }
    }

    // MARK: Header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pane == .me ? "CYCLE INTELLIGENCE" : "FAMILY SUPPORT")
                .forgeSectionLabel()
                .foregroundStyle(accent.opacity(0.9))
            Text(pane == .me ? "Know your rhythm" : "Show up for them")
                .font(FDS.TypeScale.display(30))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color.white.opacity(0.78)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text(
                pane == .me
                    ? "Periods, fertile windows, and recovery — personal math from your signals. Lifestyle guidance only."
                    : "Partners, spouses, daughters — log what they share so ARIA can coach you with care."
            )
            .font(FDS.TypeScale.body(14))
            .foregroundColor(.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    private var panePicker: some View {
        HStack(spacing: 6) {
            ForEach(Pane.allCases) { p in
                Button {
                    withAnimation(FDS.Spring.snap) { pane = p }
                    FDS.selectionHaptic()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: p.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(p.label)
                            .font(FDS.TypeScale.label(13))
                    }
                    .foregroundColor(pane == p ? .white : .textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if pane == p {
                            Capsule().fill(
                                LinearGradient(
                                    colors: [accent, accent.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: accent.opacity(0.35), radius: 12, y: 4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.surfaceElevated.opacity(0.9))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: Enable self

    private var enableCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "EF4444").opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "drop.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(hex: "EF4444"))
            }
            Text("Track with precision")
                .font(FDS.TypeScale.title(20))
                .foregroundColor(.textPrimary)
            Text("Log flow, symptoms, and optional BBT. ARIA personalizes cycle length, ovulation estimates, and training bias — never medical diagnosis.")
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
            featureRow("drop.circle.fill", "Period episodes & predictions")
            featureRow("waveform.path.ecg", "Multi-signal confidence + feedback MAE")
            featureRow("sparkles", "Phase-aware ARIA coaching")
            featureRow("lock.shield.fill", CyclePrivacy.shortPromise)

            Toggle(isOn: $privacyAccepted) {
                Text("I understand cycle data is for my coaching only — never sold")
                    .font(FDS.TypeScale.body(13))
                    .foregroundColor(.textSecondary)
            }
            .tint(Color(hex: "22C55E"))

            Button {
                guard privacyAccepted else { return }
                cycleStore.updateSettings {
                    $0.enabled = true
                    $0.shareWithAria = true
                    $0.privacyAcknowledged = true
                }
                FDS.haptic(.medium)
                showToast("Cycle tracking on")
                Task { await cycleStore.syncFromHealthKit() }
            } label: {
                Text("Enable my cycle")
                    .font(FDS.TypeScale.label(16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: privacyAccepted
                                ? [Color(hex: "F87171"), Color(hex: "EF4444"), Color(hex: "DC2626")]
                                : [Color.surfaceElevated, Color.surfaceElevated],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color(hex: "EF4444").opacity(privacyAccepted ? 0.4 : 0), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(!privacyAccepted)
        }
        .padding(22)
        .forgeGlassCard(accent: Color(hex: "EF4444"))
    }

    // MARK: Accuracy

    private var accuracyCard: some View {
        let report = cycleStore.accuracyReport
        let eval = cycleStore.lastEvaluation
        let gradeColor = Color(hex: eval.qualityGrade.accentHex)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PREDICTION ACCURACY")
                    .forgeSectionLabel()
                Spacer()
                Text(eval.qualityGrade.label)
                    .font(FDS.TypeScale.micro(11))
                    .foregroundStyle(gradeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(gradeColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            HStack(spacing: 10) {
                accuracyPill(
                    title: "MAE",
                    value: report.maeDays.map { String(format: "%.1fd" , $0) } ?? "—",
                    color: Color(hex: "22C55E")
                )
                accuracyPill(
                    title: "±1 DAY",
                    value: report.withinOneDayRate.map { "\(Int($0 * 100))%" } ?? "—",
                    color: Color(hex: "A855F7")
                )
                accuracyPill(
                    title: "±2 DAY",
                    value: report.withinTwoDayRate.map { "\(Int($0 * 100))%" } ?? "—",
                    color: .steel
                )
            }
            HStack(spacing: 10) {
                accuracyPill(
                    title: "SAMPLES",
                    value: "\(report.sampleCount)",
                    color: .ember
                )
                accuracyPill(
                    title: "PERIOD CONF",
                    value: "\(Int(cycleStore.snapshot.periodTimingConfidence * 100))%",
                    color: Color(hex: "38BDF8")
                )
                accuracyPill(
                    title: "OVU CONF",
                    value: "\(Int(cycleStore.snapshot.ovulationConfidence * 100))%",
                    color: Color(hex: "A855F7")
                )
            }
            Text(report.gradeDetail)
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)
            Text(eval.userFacingSummary)
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textTertiary)
            if abs(report.calibrationOffsetDays) >= 0.2 {
                Text("Bias auto-correct: \(report.calibrationOffsetDays >= 0 ? "+" : "")\(String(format: "%.1f", report.calibrationOffsetDays)) days · \(cycleStore.snapshot.predictionMethodSummary)")
                    .font(FDS.TypeScale.micro(11))
                    .foregroundColor(.textTertiary)
            }

            // Forecast trail
            if !cycleStore.forecastArchive.filter({ !$0.isOpen }).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FORECAST TRAIL")
                        .font(FDS.TypeScale.micro(10))
                        .tracking(1.2)
                        .foregroundColor(.textTertiary)
                    ForEach(cycleStore.forecastArchive.filter { !$0.isOpen }.suffix(4).reversed()) { rec in
                        HStack {
                            Text(shortDate(rec.predictedMedianDayKey))
                                .font(FDS.TypeScale.micro(11))
                                .foregroundColor(.textSecondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundColor(.textMuted)
                            Text((rec.scoredActualStartDayKey).map(shortDate) ?? "—")
                                .font(FDS.TypeScale.micro(11))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            if let e = rec.scoredErrorDays {
                                Text(e >= 0 ? "+\(e)d" : "\(e)d")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(abs(e) <= 1 ? Color(hex: "22C55E") : Color.warning)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }

            Text("Personal timing error — multi-signal + confirms. Not a fake global % badge. Not itself birth control.")
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textMuted)

            HStack(spacing: 14) {
                Button {
                    showAccuracyExplainer = true
                    FDS.haptic(.light)
                } label: {
                    Text("Science & methods")
                        .font(FDS.TypeScale.label(13))
                        .foregroundStyle(Color(hex: "22C55E"))
                }
                .buttonStyle(.plain)

                if cycleStore.settings.shareWithAria,
                   let prompt = cycleStore.ariaChatPromptForCycle() {
                    Button {
                        store.openChat(with: prompt, voice: false)
                    } label: {
                        Text("Ask ARIA")
                            .font(FDS.TypeScale.label(13))
                            .foregroundStyle(Color.ember)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "22C55E"))
    }

    private var ariaAnalystCard: some View {
        let brief = cycleStore.lastAriaBrief
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ARIA · UNDERSTAND · EVALUATE · TEACH")
                    .forgeSectionLabel()
                Spacer()
                if let g = brief?.evaluationGrade {
                    Text(g.label)
                        .font(FDS.TypeScale.micro(10))
                        .foregroundStyle(Color(hex: g.accentHex))
                }
            }
            if let brief {
                analystBlock("Understood", brief.understood)
                analystBlock("Evaluation", brief.evaluationPoints.joined(separator: " "))
                analystBlock("Teaching", brief.teaching)
                if let sexual = brief.sexualHealthLifestyleNote {
                    analystBlock("Sexual health (lifestyle)", sexual)
                }
                Text(brief.disclaimer)
                    .font(FDS.TypeScale.body(11))
                    .foregroundColor(.textMuted)
                Text(brief.privacyLine)
                    .font(FDS.TypeScale.body(11))
                    .foregroundColor(.textMuted)
            } else {
                Text("Log or confirm a start — ARIA will understand your data, evaluate quality, then teach next steps.")
                    .font(FDS.TypeScale.body(13))
                    .foregroundColor(.textSecondary)
            }

            if let msg = cycleStore.lastTeachingMessage {
                Text(msg)
                    .font(FDS.TypeScale.body(12))
                    .foregroundColor(.textSecondary)
                    .padding(12)
                    .background(Color.ember.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(18)
        .forgeGlassCard(accent: .ember)
    }

    private func analystBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(FDS.TypeScale.micro(10))
                .tracking(1.1)
                .foregroundColor(.textTertiary)
            Text(body)
                .font(FDS.TypeScale.body(13))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var highAccuracyCueCard: some View {
        let snap = cycleStore.snapshot
        let nearFertile = snap.phase == .fertileWindow || snap.phase == .ovulation
            || (snap.dayInCycle.map { d in
                guard let fs = snap.fertileStartDayInCycle, let fe = snap.fertileEndDayInCycle else { return false }
                return d >= max(1, fs - 2) && d <= fe + 1
            } ?? false)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(Color(hex: "A855F7"))
                Text("HIGH-ACCURACY MODE")
                    .forgeSectionLabel()
                    .foregroundStyle(Color(hex: "A855F7"))
            }
            if nearFertile {
                Text("Fertile window nearby — log BBT, OPK if you have it, and confirm period start the same day it begins.")
                    .font(FDS.TypeScale.body(13))
                    .foregroundColor(.textSecondary)
            } else {
                Text("On: we nudge BBT/OPK around fertile days and same-day period confirms for sharper personal MAE. Lifestyle only — not birth control.")
                    .font(FDS.TypeScale.body(13))
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(16)
        .forgeGlassCard(accent: Color(hex: "A855F7"))
    }

    private var predictionFeedbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOG START & END")
                .forgeSectionLabel()
            Text("Confirm start and finish. Starts sharpen forecasts; Period finished opens a short “How was your period?” check-in so ARIA learns what helps you — on-device only, never sold.")
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)

            HStack(spacing: 10) {
                Button {
                    let msg = cycleStore.confirmPeriodStartedToday(
                        flow: selectedFlow == .none ? .medium : selectedFlow
                    )
                    cycleStore.refresh(from: store)
                    cycleStore.refreshAnalyst(lastAction: "period_started_today")
                    showToast(msg)
                } label: {
                    Label("Period start", systemImage: "flag.fill")
                        .font(FDS.TypeScale.label(14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "F87171"), Color(hex: "EF4444")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    let msg = cycleStore.confirmPeriodEndedToday()
                    cycleStore.refresh(from: store)
                    cycleStore.refreshAnalyst(lastAction: "period_ended_today")
                    showToast(msg)
                    if let episode = cycleStore.pendingPeriodEndEpisode {
                        periodEndEpisode = episode
                        showPeriodEndFeedback = true
                    }
                } label: {
                    Label("Period finished", systemImage: "checkmark.flag.fill")
                        .font(FDS.TypeScale.label(14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "A78BFA"), Color(hex: "6366F1")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if cycleStore.coachingPreferences.sampleCount > 0,
               let summary = cycleStore.coachingPreferences.lastLearnedSummary {
                Text(summary)
                    .font(FDS.TypeScale.body(12))
                    .foregroundStyle(Color(hex: "A855F7"))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "A855F7").opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack {
                Text("Offset days")
                    .font(FDS.TypeScale.label(12))
                    .foregroundColor(.textSecondary)
                Spacer()
                Stepper(value: $feedbackOffset, in: 1...7) {
                    Text("\(feedbackOffset)")
                        .font(FDS.TypeScale.label(14))
                        .foregroundColor(.textPrimary)
                        .frame(minWidth: 24)
                }
            }

            HStack(spacing: 8) {
                feedbackChip("Early by \(feedbackOffset)", icon: "arrow.left") {
                    let msg = cycleStore.confirmPeriodOffsetFromPrediction(
                        daysFromPredicted: -feedbackOffset,
                        flow: selectedFlow == .none ? .medium : selectedFlow
                    )
                    cycleStore.refresh(from: store)
                    showToast(msg)
                }
                feedbackChip("Late by \(feedbackOffset)", icon: "arrow.right") {
                    let msg = cycleStore.confirmPeriodOffsetFromPrediction(
                        daysFromPredicted: feedbackOffset,
                        flow: selectedFlow == .none ? .medium : selectedFlow
                    )
                    cycleStore.refresh(from: store)
                    showToast(msg)
                }
            }

            Button {
                let msg = cycleStore.reportStillNoPeriod()
                showToast(msg)
            } label: {
                Label("Still no period", systemImage: "clock.badge.questionmark")
                    .font(FDS.TypeScale.label(13))
                    .foregroundStyle(Color.warning)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "EF4444"))
    }

    private func feedbackChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(FDS.TypeScale.label(12))
            }
            .foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func showToast(_ msg: String) {
        let token = UUID()
        toastToken = token
        withAnimation(FDS.Spring.snap) { modelToast = msg }
        FDS.notificationHaptic(.success)
        UIAccessibility.post(notification: .announcement, argument: msg)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            // Only the toast that scheduled this timer may dismiss it — otherwise a
            // second action inside the window cleared the *new* message early.
            guard toastToken == token else { return }
            withAnimation { modelToast = nil }
        }
    }

    private func accuracyPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(FDS.TypeScale.micro(9))
                .tracking(1.1)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(FDS.TypeScale.label(15))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "EF4444"))
                .frame(width: 22)
            Text(text)
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: Phase orbit

    private var phaseOrbitCard: some View {
        let snap = cycleStore.snapshot
        let phaseColor = Color(hex: snap.phase.accentHex)
        return VStack(spacing: 18) {
            ZStack {
                // Outer glow
                Circle()
                    .stroke(phaseColor.opacity(ringPulse ? 0.35 : 0.12), lineWidth: 18)
                    .frame(width: 200, height: 200)
                    .blur(radius: 2)
                // Track
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 14)
                    .frame(width: 188, height: 188)
                // Progress by day in cycle
                Circle()
                    .trim(from: 0, to: cycleProgress(snap))
                    .stroke(
                        AngularGradient(
                            colors: [
                                phaseColor.opacity(0.3),
                                phaseColor,
                                Color.white.opacity(0.5),
                                phaseColor.opacity(0.8),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .frame(width: 188, height: 188)
                    .rotationEffect(.degrees(-90))
                // Confidence ring
                Circle()
                    .trim(from: 0, to: CGFloat(snap.confidence))
                    .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Image(systemName: snap.phase.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(phaseColor)
                    if let day = snap.dayInCycle {
                        Text("Day \(day)")
                            .font(FDS.TypeScale.display(36))
                            .foregroundColor(.textPrimary)
                    } else {
                        Text("—")
                            .font(FDS.TypeScale.display(36))
                            .foregroundColor(.textTertiary)
                    }
                    Text(snap.phase.label.uppercased())
                        .font(FDS.TypeScale.micro(11))
                        .tracking(1.4)
                        .foregroundStyle(phaseColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            HStack(spacing: 10) {
                metricPill(
                    title: "CONFIDENCE",
                    value: "\(Int(snap.confidence * 100))%",
                    color: phaseColor
                )
                metricPill(
                    title: "CYCLE",
                    value: "\(Int(snap.cycleLengthMedian.rounded()))d",
                    color: .steel
                )
                metricPill(
                    title: "PERIOD",
                    value: "~\(Int(snap.periodLengthMedian.rounded()))d",
                    color: Color(hex: "F87171")
                )
            }

            if snap.isCurrentlyBleeding {
                Label("Bleeding logged today", systemImage: "drop.fill")
                    .font(FDS.TypeScale.label(13))
                    .foregroundStyle(Color(hex: "F87171"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "EF4444").opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(snap.trainingNote)
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(22)
        .forgeGlassCard(accent: phaseColor)
    }

    private func cycleProgress(_ snap: MenstrualCycleSnapshot) -> CGFloat {
        guard let day = snap.dayInCycle else { return 0.08 }
        let len = max(21, min(45, snap.cycleLengthMedian))
        return min(0.98, CGFloat(day) / CGFloat(len))
    }

    private func metricPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(FDS.TypeScale.micro(9))
                .tracking(1.2)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(FDS.TypeScale.label(15))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: Day strip

    private var dayStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LAST 14 DAYS")
                    .forgeSectionLabel()
                Spacer()
                Text(cycleStore.snapshot.dataQuality.capitalized)
                    .font(FDS.TypeScale.micro(10))
                    .foregroundColor(.textTertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentDayKeys(), id: \.self) { key in
                        dayCell(key)
                    }
                }
            }
        }
        .padding(18)
        .forgeGlassCard(accent: accent.opacity(0.6))
    }

    private func recentDayKeys() -> [String] {
        (0..<14).reversed().compactMap { offset in
            guard let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return CycleDayKey.key(for: d)
        }
    }

    private func dayCell(_ key: String) -> some View {
        let log = cycleStore.logs.first { $0.dayKey == key }
        let flow = log?.flow ?? .none
        let isToday = key == CycleDayKey.key()
        let dayNum: String = {
            guard let d = CycleDayKey.date(from: key) else { return "·" }
            return "\(Calendar.current.component(.day, from: d))"
        }()
        return Button {
            openDayEditor(key: key)
        } label: {
            VStack(spacing: 6) {
                Text(dayNum)
                    .font(FDS.TypeScale.micro(10))
                    .foregroundColor(isToday ? accent : .textTertiary)
                Circle()
                    .fill(flowDotColor(flow))
                    .frame(width: flow.isBleeding ? 14 : 8, height: flow.isBleeding ? 14 : 8)
                    .overlay {
                        if isToday {
                            Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                                .frame(width: 20, height: 20)
                        }
                    }
                if !(log?.symptoms.isEmpty ?? true) {
                    Circle().fill(Color.ember.opacity(0.7)).frame(width: 3, height: 3)
                } else {
                    Circle().fill(Color.clear).frame(width: 3, height: 3)
                }
            }
            .frame(width: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit day \(dayNum)")
    }

    private func openDayEditor(key: String) {
        editingDayKey = key
        let log = cycleStore.logs.first { $0.dayKey == key }
        editFlow = log?.flow ?? .none
        editSymptoms = Set(log?.symptoms ?? [])
        editNotes = log?.notes ?? ""
        editBBT = log?.bbtCelsius.map { String(format: "%.2f", bbtUnit.fromCelsius($0)) } ?? ""
        editOvulationTest = log?.ovulationTest
        editMucus = log?.mucus
        editPain = log?.painScale ?? 0
        showDayEditor = true
        FDS.haptic(.light)
    }

    private func flowDotColor(_ flow: MenstrualFlowLevel) -> Color {
        switch flow {
        case .heavy: return Color(hex: "DC2626")
        case .medium: return Color(hex: "EF4444")
        case .light: return Color(hex: "F87171")
        case .spotting: return Color(hex: "FCA5A5")
        default: return Color.white.opacity(0.1)
        }
    }

    // MARK: Predictions

    private var predictionGrid: some View {
        let snap = cycleStore.snapshot
        return VStack(alignment: .leading, spacing: 12) {
            Text("AHEAD").forgeSectionLabel()
            HStack(spacing: 10) {
                predictionTile(
                    icon: "calendar",
                    title: "Next period",
                    value: snap.nextPeriod.map { shortDate($0.medianDayKey) } ?? "—",
                    sub: snap.nextPeriod.map { "\(shortDate($0.earliestDayKey))–\(shortDate($0.latestDayKey))" } ?? "Log starts to predict",
                    color: Color(hex: "EF4444")
                )
                predictionTile(
                    icon: "sparkles",
                    title: "Ovulation est.",
                    value: snap.ovulationDayInCycle.map { "Day \($0)" } ?? "—",
                    sub: snap.ovulationMethod?.replacingOccurrences(of: "_", with: " ") ?? "Learning",
                    color: Color(hex: "A855F7")
                )
            }
            if let fs = snap.fertileStartDayInCycle, let fe = snap.fertileEndDayInCycle {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(Color(hex: "F59E0B"))
                    Text("Fertile window · days \(fs)–\(fe)")
                        .font(FDS.TypeScale.label(13))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    if snap.irregularityFlag {
                        Text("Variable")
                            .font(FDS.TypeScale.micro(10))
                            .foregroundStyle(Color.warning)
                    }
                }
                .padding(14)
                .background(Color(hex: "F59E0B").opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func predictionTile(icon: String, title: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            Text(title.uppercased())
                .font(FDS.TypeScale.micro(9))
                .tracking(1.1)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(FDS.TypeScale.title(18))
                .foregroundColor(.textPrimary)
            Text(sub)
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: color)
    }

    // MARK: Quick log

    private var quickLogCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(FDS.Spring.snap) { logExpanded.toggle() }
            } label: {
                HStack {
                    Text("LOG TODAY")
                        .forgeSectionLabel()
                    Spacer()
                    Image(systemName: logExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if logExpanded {
                Text("Flow")
                    .font(FDS.TypeScale.label(12))
                    .foregroundColor(.textSecondary)
                flowSelector(selection: $selectedFlow, accent: Color(hex: "EF4444"))

                Text("Symptoms")
                    .font(FDS.TypeScale.label(12))
                    .foregroundColor(.textSecondary)
                    .padding(.top, 4)
                symptomGrid

                HStack(spacing: 10) {
                    Text("BBT")
                        .font(FDS.TypeScale.label(12))
                        .foregroundColor(.textSecondary)
                    // The field was hard-coded to °C, so anyone using a Fahrenheit
                    // thermometer either skipped BBT or typed "97.8" and had it silently
                    // rejected as an impossible Celsius reading.
                    Picker("Unit", selection: $bbtUnit) {
                        ForEach(BBTUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 108)
                    Spacer()
                    TextField(bbtUnit.placeholder, text: $bbtText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(FDS.TypeScale.label(15))
                        .foregroundColor(.textPrimary)
                        .frame(width: 78)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("Basal body temperature in \(bbtUnit.accessibilityName)")
                }

                Button { saveToday() } label: {
                    Text("Save log")
                        .font(FDS.TypeScale.label(15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "F87171"), Color(hex: "EF4444")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button {
                        cycleStore.logPeriodStart(flow: selectedFlow == .none ? .medium : selectedFlow)
                        cycleStore.refresh(from: store)
                        FDS.notificationHaptic(.success)
                        showToast("Period start logged")
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Period start")
                                .font(FDS.TypeScale.micro(11))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(Color(hex: "EF4444"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "EF4444").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log period start")

                    Button {
                        let msg = cycleStore.confirmPeriodEndedToday()
                        cycleStore.refresh(from: store)
                        showToast(msg)
                        if let episode = cycleStore.pendingPeriodEndEpisode {
                            periodEndEpisode = episode
                            showPeriodEndFeedback = true
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.flag.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Period finished")
                                .font(FDS.TypeScale.micro(11))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(Color(hex: "6366F1"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "6366F1").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log period finished and answer how it went")
                }
            }
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "EF4444"))
    }

    private var symptomGrid: some View {
        let cols = [GridItem(.adaptive(minimum: 96), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(CycleSymptom.allCases) { symptom in
                let on = selectedSymptoms.contains(symptom)
                Button {
                    if on { selectedSymptoms.remove(symptom) } else { selectedSymptoms.insert(symptom) }
                    FDS.selectionHaptic()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: symptom.icon)
                            .font(.system(size: 10))
                        Text(symptom.label)
                            .font(FDS.TypeScale.micro(11))
                            .lineLimit(1)
                    }
                    .foregroundColor(on ? .white : .textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(on ? accent.opacity(0.85) : Color.surfaceElevated)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func flowSelector(selection: Binding<MenstrualFlowLevel>, accent: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([MenstrualFlowLevel.none, .spotting, .light, .medium, .heavy], id: \.self) { level in
                    Button {
                        selection.wrappedValue = level
                        FDS.selectionHaptic()
                    } label: {
                        Text(level.label)
                            .font(FDS.TypeScale.label(13))
                            .foregroundColor(selection.wrappedValue == level ? .white : .textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(selection.wrappedValue == level ? accent : Color.surfaceElevated)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: History

    private var historyCard: some View {
        // Card used to be hidden entirely when `logs` was empty, which also hid the only
        // control that expands it — so a user with no logs could never see the empty state.
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(FDS.Spring.snap) { historyExpanded.toggle() }
            } label: {
                HStack {
                    Text("RECENT LOGS")
                        .forgeSectionLabel()
                    Spacer()
                    Text("\(cycleStore.logs.count)")
                        .font(FDS.TypeScale.micro(11))
                        .foregroundColor(.textTertiary)
                    Image(systemName: historyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recent logs, \(cycleStore.logs.count) entries")
            .accessibilityHint(historyExpanded ? "Collapses the list" : "Expands the list")

            if historyExpanded {
                if cycleStore.logs.isEmpty {
                    Text("Nothing logged yet. Save a day above and it will show up here.")
                        .font(FDS.TypeScale.body(13))
                        .foregroundColor(.textTertiary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(cycleStore.logs.suffix(12).reversed()) { log in
                        Button {
                            openDayEditor(key: log.dayKey)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(flowDotColor(log.flow))
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shortDate(log.dayKey))
                                        .font(FDS.TypeScale.label(13))
                                        .foregroundColor(.textPrimary)
                                    Text(log.flow.label + (log.symptoms.isEmpty ? "" : " · \(log.symptoms.count) symptoms"))
                                        .font(FDS.TypeScale.body(11))
                                        .foregroundColor(.textTertiary)
                                }
                                Spacer()
                                if let bbt = log.bbtCelsius {
                                    Text(String(format: "%.2f%@", bbtUnit.fromCelsius(bbt), bbtUnit.symbol))
                                        .font(FDS.TypeScale.micro(11))
                                        .foregroundColor(.steel)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the day editor")
                    }
                }
            }
        }
        .padding(18)
        .forgeGlassCard(accent: .steel)
    }

    // MARK: Insights + ARIA

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INSIGHTS").forgeSectionLabel()
            ForEach(cycleStore.snapshot.insights.prefix(5), id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(line)
                        .font(FDS.TypeScale.body(13))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(cycleStore.snapshot.readinessNote)
                .font(FDS.TypeScale.label(13))
                .foregroundColor(.textPrimary)
                .padding(.top, 4)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "6366F1"))
    }

    private var ariaCoachCard: some View {
        Button {
            let phase = cycleStore.snapshot.phase.label
            store.openChat(
                with: "I'm in \(phase) — how should I train and recover today?",
                voice: false
            )
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.premiumSurface)
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.ember)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask ARIA about today")
                        .font(FDS.TypeScale.label(15))
                        .foregroundColor(.textPrimary)
                    Text("Phase-aware training & recovery")
                        .font(FDS.TypeScale.body(12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ember)
            }
            .padding(18)
            .forgeGlassCard(accent: .ember)
        }
        .buttonStyle(.plain)
    }

    private var sexualHealthCard: some View {
        SexualHealthEntryCard(
            store: store,
            cycleStore: cycleStore
        )
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PRIVACY & CONTROL").forgeSectionLabel()

            privacyShieldBanner

            CycleNotificationSettingsCard(cycleStore: cycleStore)

            CycleConditionSelectorCard(
                condition: Binding(
                    get: { cycleStore.settings.condition },
                    set: { cycleStore.updateCondition($0) }
                )
            )

            Toggle(isOn: Binding(
                get: { cycleStore.settings.shareWithAria },
                set: { v in cycleStore.updateSettings { $0.shareWithAria = v } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share cycle with ARIA")
                        .foregroundColor(.textPrimary)
                    Text("Read-only for your coaching. Off = ARIA never sees cycle phase.")
                        .font(FDS.TypeScale.body(11))
                        .foregroundColor(.textTertiary)
                }
            }
            .tint(.ember)

            Toggle(isOn: Binding(
                get: { cycleStore.settings.usesHormonalContraception },
                set: { v in cycleStore.updateSettings { $0.usesHormonalContraception = v } }
            )) {
                Text("On hormonal contraception")
                    .foregroundColor(.textPrimary)
            }
            .tint(.ember)

            Toggle(isOn: Binding(
                get: { cycleStore.settings.highAccuracyMode },
                set: { v in cycleStore.updateSettings { $0.highAccuracyMode = v } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("High-accuracy mode")
                        .foregroundColor(.textPrimary)
                    Text("BBT/OPK cues + same-day confirms. Lifestyle only — not contraception.")
                        .font(FDS.TypeScale.body(11))
                        .foregroundColor(.textTertiary)
                }
            }
            .tint(Color(hex: "A855F7"))

            Toggle(isOn: Binding(
                get: { cycleStore.settings.enabled },
                set: { v in cycleStore.updateSettings { $0.enabled = v } }
            )) {
                Text("Tracking enabled")
                    .foregroundColor(.textPrimary)
            }
            .tint(.ember)

            Button(role: .destructive) {
                showWipeConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Wipe my cycle logs")
                        .font(FDS.TypeScale.label(14))
                    Spacer()
                }
                .foregroundColor(.danger)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "22C55E"))
    }

    private var dayEditorSheet: some View {
        NavigationStack {
            Form {
                Section("Day") {
                    Text(editingDayKey.map(shortDate) ?? "—")
                        .foregroundColor(.secondary)
                }
                Section("Flow") {
                    Picker("Flow", selection: $editFlow) {
                        ForEach([MenstrualFlowLevel.none, .spotting, .light, .medium, .heavy], id: \.self) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Symptoms") {
                    ForEach(CycleSymptom.allCases) { symptom in
                        Toggle(symptom.label, isOn: Binding(
                            get: { editSymptoms.contains(symptom) },
                            set: { on in
                                if on { editSymptoms.insert(symptom) } else { editSymptoms.remove(symptom) }
                            }
                        ))
                    }
                }
                Section("Basal temperature") {
                    HStack {
                        Picker("Unit", selection: $bbtUnit) {
                            ForEach(BBTUnit.allCases) { unit in
                                Text(unit.symbol).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 116)
                        Spacer()
                        TextField(bbtUnit.placeholder, text: $editBBT)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    if !editBBT.isEmpty {
                        Button("Clear temperature", role: .destructive) { editBBT = "" }
                            .font(.footnote)
                    }
                }
                // `painScale` existed on the model with an endometriosis comment but had
                // no entry point anywhere in the app — the field could never be set.
                Section("Pain") {
                    HStack {
                        Text(editPain == 0 ? "None" : "\(editPain)/10")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 64, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { Double(editPain) },
                                set: { editPain = Int($0.rounded()) }
                            ),
                            in: 0...10,
                            step: 1
                        )
                        .tint(editPain >= 7 ? .red : .orange)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Pain level")
                    .accessibilityValue(editPain == 0 ? "None" : "\(editPain) out of 10")
                }
                // OPK and mucus were read-only imports from Apple Health with no way to
                // enter or correct them in Forge, even though the engine ranks them above
                // the calendar fallback when estimating ovulation.
                Section("Fertility signals") {
                    Picker("Ovulation test", selection: $editOvulationTest) {
                        Text("Not logged").tag(OvulationTestResult?.none)
                        ForEach(OvulationTestResult.allCases, id: \.self) { result in
                            Text(result.label).tag(OvulationTestResult?.some(result))
                        }
                    }
                    Picker("Cervical mucus", selection: $editMucus) {
                        Text("Not logged").tag(CervicalMucusQuality?.none)
                        ForEach(CervicalMucusQuality.allCases, id: \.self) { quality in
                            Text(quality.label).tag(CervicalMucusQuality?.some(quality))
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $editNotes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let key = editingDayKey, cycleStore.logs.contains(where: { $0.dayKey == key }) {
                    Section {
                        Button("Delete this day", role: .destructive) {
                            cycleStore.deleteLog(dayKey: key)
                            showDayEditor = false
                            FDS.notificationHaptic(.warning)
                            showToast("Day deleted")
                        }
                    }
                }
            }
            .navigationTitle("Edit day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDayEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveDayEdit() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func saveDayEdit() {
        guard let key = editingDayKey else { return }
        let raw = editBBT.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        var bbtCelsius: Double?
        if !raw.isEmpty {
            guard let entered = Double(raw), let celsius = bbtUnit.toCelsius(entered),
                  BBTUnit.plausibleCelsius.contains(celsius) else {
                saveError = "Basal temperature should be about \(bbtUnit.plausibleCopy). Check the reading and try again."
                FDS.notificationHaptic(.error)
                return
            }
            bbtCelsius = celsius
        }
        let trimmedNotes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        cycleStore.upsertLog(
            CycleDayLog(
                dayKey: key,
                flow: editFlow,
                symptoms: Array(editSymptoms),
                bbtCelsius: bbtCelsius,
                ovulationTest: editOvulationTest,
                mucus: editMucus,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                source: "manual",
                painScale: editPain > 0 ? editPain : nil
            ),
            // The editor shows the complete state of the day, so an emptied note or a
            // cleared temperature has to actually clear — a merge-only upsert kept them.
            fieldsAreAuthoritative: true
        )
        cycleStore.refresh(from: store)
        showDayEditor = false
        FDS.notificationHaptic(.success)
        showToast("Saved \(shortDate(key))")
    }

    private var privacyShieldBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(hex: "22C55E"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(CyclePrivacy.title)
                        .font(FDS.TypeScale.label(15))
                        .foregroundColor(.textPrimary)
                    Text(CyclePrivacy.shortPromise)
                        .font(FDS.TypeScale.body(12))
                        .foregroundColor(.textSecondary)
                }
            }
            ForEach(CyclePrivacy.bullets, id: \.text) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "22C55E"))
                        .frame(width: 18)
                    Text(item.text)
                        .font(FDS.TypeScale.body(12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(Color(hex: "22C55E").opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(hex: "22C55E").opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CyclePrivacy.title + ". " + CyclePrivacy.shortPromise)
    }

    private var disclaimerFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CyclePrivacy.policy)
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textTertiary)
            Text(MenstrualCycleEngine.disclaimer)
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    // MARK: Partner / support

    private var partnerContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !cycleStore.partnerSettings.enabled {
                partnerEnableCard
            } else if !cycleStore.partnerSettings.consentAcknowledged {
                partnerConsentCard
            } else {
                partnerPhaseHero
                if let brief = cycleStore.partnerSupportBrief {
                    partnerSupportCard(brief)
                }
                partnerLogger
                partnerSettingsCard
                Text(PartnerSupportBrief.disclaimer)
                    .font(FDS.TypeScale.body(11))
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private var partnerEnableCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(colors: [Color(hex: "818CF8"), Color(hex: "6366F1")], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("Support someone you love")
                .font(FDS.TypeScale.title(20))
                .foregroundColor(.textPrimary)
            Text("Partners, spouses — and many fathers with daughters. Log period starts they share; ARIA coaches you on comfort, plans, and what not to say.")
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
            Text(CyclePrivacy.shortPromise)
                .font(FDS.TypeScale.body(12))
                .foregroundStyle(Color(hex: "22C55E"))
            rolePicker
            Button {
                cycleStore.updatePartnerSettings {
                    $0.enabled = true
                    $0.shareWithAria = true
                    $0.supportRole = supportRole
                    $0.relationshipLabel = supportRole.suggestedLabels.first ?? "partner"
                }
                partnerRelDraft = supportRole.suggestedLabels.first ?? "partner"
                FDS.haptic(.medium)
            } label: {
                Text("Continue")
                    .font(FDS.TypeScale.label(16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "818CF8"), Color(hex: "6366F1")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .forgeGlassCard(accent: Color(hex: "6366F1"))
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHO")
                .forgeSectionLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CycleSupportRole.allCases) { role in
                        Button {
                            supportRole = role
                            partnerRelDraft = role.suggestedLabels.first ?? partnerRelDraft
                            FDS.selectionHaptic()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: role.icon)
                                Text(role.shortLabel)
                                    .font(FDS.TypeScale.label(13))
                            }
                            .foregroundColor(supportRole == role ? .white : .textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(supportRole == role ? Color(hex: "6366F1") : Color.surfaceElevated)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var partnerConsentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(supportRole == .child ? "Care first" : "Consent first")
                .font(FDS.TypeScale.title(18))
                .foregroundColor(.textPrimary)
            Text(
                supportRole == .child
                    ? "Only track what fits your caregiver role — preferably with her knowledge. Period starts are enough."
                    : "Only log what they’re comfortable sharing. Starts alone unlock strong support coaching."
            )
            .font(FDS.TypeScale.body(14))
            .foregroundColor(.textSecondary)
            rolePicker
            TextField(supportRole == .child ? "Name (optional)" : "Name (optional)", text: $partnerNameDraft)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            TextField(
                supportRole == .child ? "Label (daughter / child…)" : "Label (partner / wife…)",
                text: $partnerRelDraft
            )
            .textFieldStyle(.plain)
            .padding(12)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                cycleStore.updatePartnerSettings {
                    $0.consentAcknowledged = true
                    $0.partnerName = partnerNameDraft
                    $0.supportRole = supportRole
                    $0.relationshipLabel = partnerRelDraft.isEmpty
                        ? (supportRole.suggestedLabels.first ?? "partner")
                        : partnerRelDraft
                    $0.shareWithAria = true
                }
                FDS.notificationHaptic(.success)
            } label: {
                Text(supportRole == .child ? "I’m supporting as a parent" : "I have their okay")
                    .font(FDS.TypeScale.label(15))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.ember)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .forgeGlassCard(accent: .warning)
    }

    private var partnerPhaseHero: some View {
        let snap = cycleStore.partnerSnapshot
        let phaseColor = Color(hex: snap.phase.accentHex)
        let name = cycleStore.partnerSettings.displayName
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(phaseColor.opacity(0.25), lineWidth: 8)
                        .frame(width: 72, height: 72)
                    Circle()
                        .trim(from: 0, to: cycleProgress(snap))
                        .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: snap.phase.icon)
                        .foregroundStyle(phaseColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.uppercased())
                        .font(FDS.TypeScale.micro(10))
                        .tracking(1.3)
                        .foregroundStyle(phaseColor)
                    Text(snap.stage == .unknown ? snap.phase.label : snap.stage.partnerLabel(name: name))
                        .font(FDS.TypeScale.title(20))
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let day = snap.dayInCycle {
                        Text("Day \(day) · \(Int(snap.confidence * 100))% confidence")
                            .font(FDS.TypeScale.body(13))
                            .foregroundColor(.textSecondary)
                    }
                }
                Spacer()
            }
            // The transition itself is the useful signal for a supporter.
            if snap.stage == .postPeriod, let since = snap.daysSincePeriodEnd, since <= 2 {
                Label(
                    since == 0 ? "Finished today — back to everyday support"
                               : "Finished \(since == 1 ? "yesterday" : "\(since) days ago") — back to everyday support",
                    systemImage: "arrow.uturn.forward.circle.fill"
                )
                .font(FDS.TypeScale.label(13))
                .foregroundStyle(Color(hex: "22C55E"))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "22C55E").opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if let next = snap.nextPeriod {
                Text("Next period window · \(shortDate(next.earliestDayKey)) – \(shortDate(next.latestDayKey))")
                    .font(FDS.TypeScale.body(13))
                    .foregroundColor(.textSecondary)
            }
            Button {
                let role = cycleStore.partnerSettings.resolvedRole
                let prompt = role == .child
                    ? "Help me support my daughter \(name) — \(snap.phase.label). What should I do?"
                    : "Help me support \(name) — \(snap.phase.label). What should I do?"
                store.openChat(with: prompt, voice: false)
            } label: {
                Label("Ask ARIA how to show up", systemImage: "message.fill")
                    .font(FDS.TypeScale.label(14))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(phaseColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .forgeGlassCard(accent: phaseColor)
    }

    private func partnerSupportCard(_ brief: PartnerSupportBrief) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(brief.role == .child ? "PARENT PLAYBOOK" : "HOW YOU SHOW UP")
                .forgeSectionLabel()
            Text(brief.headline)
                .font(FDS.TypeScale.label(15))
                .foregroundColor(.textPrimary)
            ForEach(brief.supportMoves.prefix(4), id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "22C55E"))
                    Text(line)
                        .font(FDS.TypeScale.body(13))
                        .foregroundColor(.textSecondary)
                }
            }
            Text("Ease off")
                .font(FDS.TypeScale.label(13))
                .foregroundColor(.textPrimary)
                .padding(.top, 4)
            ForEach(brief.avoidMoves.prefix(3), id: \.self) { line in
                Text("• \(line)")
                    .font(FDS.TypeScale.body(13))
                    .foregroundColor(.textSecondary)
            }
            Text(brief.communicationTip)
                .font(FDS.TypeScale.label(13))
                .foregroundStyle(Color.ember)
                .padding(.top, 6)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "22C55E"))
    }

    private var partnerLogger: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOG FOR \(cycleStore.partnerSettings.displayName.uppercased())")
                .forgeSectionLabel()
            Text("Confirming their start keeps support predictions sharp — history is retained.")
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)
            flowSelector(selection: $partnerFlow, accent: Color(hex: "6366F1"))

            Button {
                cycleStore.logPartnerPeriodStart(flow: partnerFlow == .none ? .medium : partnerFlow)
                showToast(cycleStore.lastModelUpdateMessage ?? "Logged · support model refreshed")
            } label: {
                Label("Their period started", systemImage: "flag.fill")
                    .font(FDS.TypeScale.label(15))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "818CF8"), Color(hex: "6366F1")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                // Without this, support coaching had no way to leave period mode — it sat
                // there until the median bleed length elapsed, regardless of reality.
                Button {
                    let msg = cycleStore.logPartnerPeriodEnd()
                    cycleStore.refresh(from: store)
                    showToast(msg)
                } label: {
                    Label("Their period finished", systemImage: "checkmark.flag.fill")
                        .font(FDS.TypeScale.label(14))
                        .foregroundStyle(Color(hex: "22C55E"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "22C55E").opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(cycleStore.partnerSnapshot.stage != .period)
                .opacity(cycleStore.partnerSnapshot.stage == .period ? 1 : 0.45)

                Button {
                    cycleStore.logPartnerToday(flow: partnerFlow)
                    FDS.notificationHaptic(.success)
                    showToast("Saved today for \(cycleStore.partnerSettings.displayName)")
                } label: {
                    Text("Save today")
                        .font(FDS.TypeScale.label(14))
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "6366F1"))
    }

    private var partnerSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SETTINGS").forgeSectionLabel()
            rolePicker
            TextField("Name", text: $partnerNameDraft)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            TextField("Relationship label", text: $partnerRelDraft)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button("Save") {
                cycleStore.updatePartnerSettings {
                    $0.partnerName = partnerNameDraft
                    $0.supportRole = supportRole
                    $0.relationshipLabel = partnerRelDraft.isEmpty
                        ? (supportRole.suggestedLabels.first ?? "partner")
                        : partnerRelDraft
                }
                FDS.haptic(.light)
            }
            .font(FDS.TypeScale.label(14))
            .foregroundColor(.ember)
            Toggle(isOn: Binding(
                get: { cycleStore.partnerSettings.shareWithAria },
                set: { v in cycleStore.updatePartnerSettings { $0.shareWithAria = v } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share with ARIA").foregroundColor(.textPrimary)
                    Text("Read for coaching only — never sold or resold.")
                        .font(FDS.TypeScale.body(11))
                        .foregroundColor(.textTertiary)
                }
            }
            .tint(.ember)
            Toggle(isOn: Binding(
                get: { cycleStore.partnerSettings.enabled },
                set: { v in
                    cycleStore.updatePartnerSettings {
                        $0.enabled = v
                        if !v { $0.consentAcknowledged = false }
                    }
                }
            )) {
                Text("Support tracking on").foregroundColor(.textPrimary)
            }
            .tint(.ember)
        }
        .padding(18)
        .forgeGlassCard(accent: .steel)
    }

    // MARK: Actions

    private func saveToday() {
        let raw = bbtText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        var bbtCelsius: Double?
        if !raw.isEmpty {
            // An unvalidated field accepted anything — "99" was stored as 99 °C, which
            // poisons the BBT shift detector for every future cycle.
            guard let entered = Double(raw), let celsius = bbtUnit.toCelsius(entered),
                  BBTUnit.plausibleCelsius.contains(celsius) else {
                saveError = "Basal temperature should be about \(bbtUnit.plausibleCopy). Check the reading and try again."
                FDS.notificationHaptic(.error)
                return
            }
            bbtCelsius = celsius
        }

        cycleStore.logToday(
            flow: selectedFlow,
            symptoms: Array(selectedSymptoms),
            bbtCelsius: bbtCelsius
        )
        cycleStore.refresh(from: store)
        // Draft state persisted after saving, so re-opening the card showed yesterday's
        // symptoms as if they were today's unsaved entry.
        bbtText = ""
        selectedSymptoms = []
        showToast(bbtCelsius == nil ? "Saved today's log" : "Saved today's log · BBT recorded")
    }

    private func shortDate(_ key: String) -> String {
        CycleDayKey.shortDisplay(key)
    }
}

// MARK: - BBT unit

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

// MARK: - Home chip

struct CycleHealthChip: View {
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    var preferPartner: Bool = false
    var onTap: () -> Void

    private var showingPartner: Bool {
        preferPartner
            || (cycleStore.partnerSettings.enabled && cycleStore.partnerSettings.consentAcknowledged
                && !cycleStore.settings.enabled)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                let phase = showingPartner ? cycleStore.partnerSnapshot.phase : cycleStore.snapshot.phase
                ZStack {
                    Circle()
                        .fill(Color(hex: phase.accentHex).opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: showingPartner ? "heart.circle.fill" : phase.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: phase.accentHex))
                }
                VStack(alignment: .leading, spacing: 3) {
                    if showingPartner {
                        let snap = cycleStore.partnerSnapshot
                        Text(cycleStore.partnerSettings.displayName)
                            .font(FDS.TypeScale.label(14))
                            .foregroundColor(.textPrimary)
                        if snap.stage == .postPeriod, let since = snap.daysSincePeriodEnd, since <= 2 {
                            Text("Period finished \(since == 0 ? "today" : (since == 1 ? "yesterday" : "\(since)d ago"))")
                                .font(FDS.TypeScale.body(12))
                                .foregroundStyle(Color(hex: "22C55E"))
                        } else if let day = snap.dayInCycle {
                            Text("\(phase.shortLabel) · day \(day)")
                                .font(FDS.TypeScale.body(12))
                                .foregroundColor(.textTertiary)
                        } else {
                            Text(cycleStore.partnerSettings.enabled ? "Partner cycle" : "Set up support")
                                .font(FDS.TypeScale.body(12))
                                .foregroundColor(.textTertiary)
                        }
                    } else {
                        let snap = cycleStore.snapshot
                        Text(cycleStore.settings.enabled
                             ? (snap.stage == .unknown ? phase.label : snap.stage.label)
                             : "Cycle Health")
                            .font(FDS.TypeScale.label(14))
                            .foregroundColor(.textPrimary)
                        if cycleStore.settings.enabled, snap.stage == .postPeriod,
                           let since = snap.daysSincePeriodEnd, since <= 2 {
                            Text(since == 0 ? "Finished today · back to normal" : "Finished \(since)d ago · back to normal")
                                .font(FDS.TypeScale.body(12))
                                .foregroundStyle(Color(hex: "22C55E"))
                        } else if cycleStore.settings.enabled, let day = snap.dayInCycle {
                            Text("Day \(day) · \(Int(snap.confidence * 100))% conf")
                                .font(FDS.TypeScale.body(12))
                                .foregroundColor(.textTertiary)
                        } else {
                            Text("Tap to set up your rhythm")
                                .font(FDS.TypeScale.body(12))
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(16)
            .forgeGlassCard(accent: Color(hex: (showingPartner ? cycleStore.partnerSnapshot.phase : cycleStore.snapshot.phase).accentHex))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Accuracy explainer

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

// MARK: - Sexual Health Entry Card

private struct SexualHealthEntryCard: View {
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

// MARK: - Cycle Notification Settings Card

private struct CycleNotificationSettingsCard: View {
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

// MARK: - Fertile Score Card

private struct FertileScoreCard: View {
    let score: Int
    let phase: MenstrualPhase
    let onAskARIA: () -> Void

    private var band: (label: String, color: Color) {
        switch score {
        case 75...: return ("Peak window", Color(hex: "F472B6"))
        case 45..<75: return ("Elevated", Color.ember)
        case 20..<45: return ("Rising / fading", Color.steel)
        default: return ("Low likelihood", Color.textTertiary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FERTILE SCORE")
                        .font(FDS.TypeScale.label(11))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(score)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(band.color)
                        Text("/ 100")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(band.label)
                        .font(FDS.TypeScale.label(12))
                        .foregroundStyle(band.color)
                    Text(phase.label)
                        .font(FDS.TypeScale.body(12))
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.steel, Color.ember, Color(hex: "F472B6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * CGFloat(score) / 100.0))
                }
            }
            .frame(height: 8)

            Text("Multi-signal confidence from ovulation method, cycle history, and phase proximity. Lifestyle timing only — not contraception.")
                .font(FDS.TypeScale.body(12))
                .foregroundStyle(.secondary)

            Button(action: onAskARIA) {
                Label("Ask ARIA about this score", systemImage: "sparkles")
                    .font(FDS.TypeScale.label(13))
            }
            .buttonStyle(.bordered)
            .tint(band.color)
        }
        .padding()
        .forgeGlassCard(accent: band.color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fertile score \(score) out of 100, \(band.label)")
    }
}

// MARK: - Cycle Goal Selector Card

private struct CycleGoalSelectorCard: View {
    let goal: CycleGoal
    let onUpdate: (CycleGoal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your cycle goal")
                .font(FDS.TypeScale.body(12))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(CycleGoal.allCases) { g in
                    Button {
                        onUpdate(g)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: g.icon)
                                .font(.title3)
                            Text(g.label)
                                .font(FDS.TypeScale.body(11))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(goal == g ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                        .foregroundStyle(goal == g ? Color.ember : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: FDS.Radius.sm)
                                .strokeBorder(goal == g ? Color.ember : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            if goal == .avoidPregnancy {
                Label("FAM requires consistent tracking — not a substitute for medical contraception.", systemImage: "exclamationmark.triangle.fill")
                    .font(FDS.TypeScale.body(11))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        .padding()
        .forgeGlassCard(accent: .ember)
    }
}

// MARK: - Two-Week Wait Card

private struct TWWSectionCard: View {
    let daysElapsed: Int
    let onAskARIA: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hourglass")
                    .foregroundStyle(Color.ember)
                Text("Two-Week Wait")
                    .font(FDS.TypeScale.body(15))
                    .fontWeight(.semibold)
            }
            Text("Day \(daysElapsed) of your two-week wait")
                .font(FDS.TypeScale.body(14))
            Text("\(max(0, 14 - daysElapsed)) days until you can test")
                .font(FDS.TypeScale.body(12))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(min(daysElapsed, 14)), total: 14.0)
                .tint(Color.ember)
            Button("Ask ARIA about the two-week wait") {
                onAskARIA()
            }
            .buttonStyle(.bordered)
            .tint(Color.ember)
        }
        .padding()
        .forgeGlassCard(accent: .ember)
    }
}

// MARK: - Condition Selector Card

private struct CycleConditionSelectorCard: View {
    @Binding var condition: CycleCondition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HEALTH CONDITION")
                    .font(FDS.TypeScale.label(12))
                    .foregroundColor(.textSecondary)
                Text("Personalises cycle predictions and ARIA coaching")
                    .font(FDS.TypeScale.body(11))
                    .foregroundColor(.textTertiary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(CycleCondition.allCases) { c in
                    Button {
                        condition = c
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: c.icon)
                                .font(.title3)
                            Text(c.label)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(condition == c ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                        .foregroundStyle(condition == c ? Color.ember : Color.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: FDS.Radius.sm)
                                .strokeBorder(condition == c ? Color.ember : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .forgeGlassCard(accent: .ember)
    }
}
