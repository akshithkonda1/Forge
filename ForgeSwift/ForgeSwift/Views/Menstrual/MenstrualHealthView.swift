import SwiftUI
import LocalAuthentication
import ForgeCore

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
    @State private var logExpanded = true
    // Presentation-only disclosure and event state.
    @State private var showAllSymptoms = false
    @State private var showMethod = false
    @State private var heroEventGlow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var orbitRingSize: CGFloat = 168
    @ScaledMetric(relativeTo: .title3) private var partnerRingSize: CGFloat = 72
    @ScaledMetric(relativeTo: .caption) private var dayCellSize: CGFloat = 36
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
    @State private var showSharing = false
    /// Sharing lives here as well as inside `CycleSharingView` so the Support
    /// pane can render a digest someone shared with this user without the
    /// sharing sheet ever being opened.
    @ObservedObject private var sharing = PartnerCycleSharing.shared
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
    @State private var showAddPerson = false
    @State private var confirmRemovePerson = false
    /// `handleAppear` used to re-apply `initialPane` on every appear, which
    /// snapped Support back to My cycle after a sheet dismissed.
    @State private var didApplyLaunchPane = false
    @State private var coldStartDate = Date()
    @State private var showRhythmReport = false
    @State private var supportCardDraft = ""

    private var accent: Color {
        let phase = pane == .me ? cycleStore.snapshot.phase : cycleStore.partnerSnapshot.phase
        return phaseColor(phase)
    }

    /// One color per cycle phase. Stages, the hero, the timeline and the
    /// flow dots all route through this so they always agree.
    private func phaseColor(_ phase: MenstrualPhase) -> Color {
        Color(hex: phase.accentHex)
    }

    /// Period identity color (menstruation's own hue, not a status color).
    private var periodColor: Color { phaseColor(.menstruation) }

    /// Runs a state change with the standard spring, or instantly under
    /// Reduce Motion.
    private func motion(_ animation: Animation = FDS.Spring.snap, _ changes: () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(animation) { changes() }
        }
    }

    private var expandTransition: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }

    /// Keeps the alert presentation binding out of the giant `body` expression.
    private var saveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    var body: some View {
        presentedRoot
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
            .onAppear(perform: handleAppear)
            .onChange(of: initialPane) { _, newPane in
                if let newPane { pane = newPane }
            }
    }

    /// Navigation chrome + presentation (sheets / dialogs / alert) broken out of `body`
    /// so the type checker doesn't time out on one enormous expression.
    private var presentedRoot: some View {
        navigatedRoot
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
            // Day editor and the wipe dialog used to hang off `settingsCard`, so they only
            // worked while that specific card happened to be in the view tree.
            .sheet(isPresented: $showDayEditor) { dayEditorSheet }
            .sheet(isPresented: $showSharing) {
                CycleSharingView(cycleStore: cycleStore)
                    .environmentObject(store)
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showRhythmReport) {
                CycleRhythmReportView(cycleStore: cycleStore)
            }
            .sheet(isPresented: $showAddPerson) {
                AddSupportedPersonSheet(cycleStore: cycleStore) { person in
                    partnerNameDraft = person.settings.partnerName
                    partnerRelDraft = person.settings.relationshipLabel
                    supportRole = person.role
                    showAddPerson = false
                }
                .preferredColorScheme(.dark)
            }
            .onChange(of: cycleStore.selectedPersonId) { _, _ in
                partnerNameDraft = cycleStore.partnerSettings.partnerName
                partnerRelDraft = cycleStore.partnerSettings.relationshipLabel
                supportRole = cycleStore.partnerSettings.resolvedRole
            }
            .confirmationDialog(
                "Remove \(cycleStore.partnerSettings.displayName)?",
                isPresented: $confirmRemovePerson,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let id = cycleStore.selectedPersonId {
                        cycleStore.removeSupportedPerson(id)
                    }
                }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("Local notes for them leave this device. A share they sent you stays until they revoke it.")
            }
            .confirmationDialog(
                "Wipe all self cycle logs?",
                isPresented: $showWipeConfirm,
                titleVisibility: .visible
            ) {
                Button("Wipe logs only", role: .destructive) {
                    cycleStore.wipeSelfCycleData(includingSettings: false)
                    FDS.notificationHaptic(.warning)
                    showToast("Cycle logs wiped", haptic: false)
                }
                Button("Wipe logs + disable tracking", role: .destructive) {
                    cycleStore.wipeSelfCycleData(includingSettings: true)
                    FDS.notificationHaptic(.warning)
                    showToast("Cycle data wiped · tracking off", haptic: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Logs, learned bias, prediction history, and period feedback are erased. Partner / support logs are kept. This cannot be undone.")
            }
            .alert("Check that entry", isPresented: saveErrorPresented) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
    }

    private var navigatedRoot: some View {
        rootStack
            .navigationTitle("Cycle Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { cycleToolbar }
            .overlay {
                if !cycleStore.cycleUnlockedThisSession,
                   cycleStore.settings.enabled,
                   cycleStore.settings.cycleLockEnabled || cycleStore.settings.discretionMode == .stealth {
                    ZStack {
                        Color.background.opacity(0.96).ignoresSafeArea()
                        VStack(spacing: ForgeLayout.blockGap) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.vitality)
                                .accessibilityHidden(true)
                            Text("Cycle Health is locked")
                                .font(HomeType.sessionTitle)
                                .foregroundColor(.textPrimary)
                                .multilineTextAlignment(.center)
                                .accessibilityAddTraits(.isHeader)
                            Text("Face ID or your device passcode. Discretion Mode is on.")
                                .font(HomeType.body)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                                .forgeWrapping()
                            ForgePrimaryButton(title: "Unlock", icon: "lock.open.fill", accent: .ember) {
                                unlockCycleIfNeeded()
                            }
                        }
                        .padding(ForgeLayout.cardPadding)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
    }

    private var rootStack: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                ForgeScreenStack {
                    heroHeader
                    panePicker
                    paneBody
                }
            }
            .forgeScreenBackground(accent: accent)

            if let modelToast {
                toastBanner(modelToast)
            }
        }
    }

    @ViewBuilder
    private var paneBody: some View {
        switch pane {
        case .me:
            mePaneContent
        case .partner:
            partnerContent
        }
    }

    @ViewBuilder
    private var mePaneContent: some View {
        if !cycleStore.settings.enabled {
            enableCard
        } else {
            meEnabledContent
        }
    }

    private var isColdStart: Bool {
        cycleStore.settings.enabled
            && cycleStore.snapshot.lastPeriodStartDayKey == nil
            && cycleStore.snapshot.cyclesObserved == 0
    }

    @ViewBuilder
    private var meEnabledContent: some View {
        if isColdStart {
            coldStartContent
        } else {
            meEnabledPrimary
            meEnabledSecondary
        }
    }

    @ViewBuilder
    private var coldStartContent: some View {
        phaseOrbitCard
        coldStartCard
        quickLogCard
        sexualHealthCard
        Group {
            settingsCard
            disclaimerFooter
        }
    }

    @ViewBuilder
    private var meEnabledPrimary: some View {
        // Hero, where you are (with the one primary action), today's log, then what is ahead.
        phaseOrbitCard
        cycleStageCard
        quickLogCard
        if cycleStore.snapshot.cyclesObserved > 0 {
            predictionGrid
            fertileScoreSection
        }
        dayStrip
        trainingPrescriptionCard
        if let condition = cycleStore.settings.condition.activeCase {
            conditionCard(condition)
        }
    }

    @ViewBuilder
    private var meEnabledSecondary: some View {
        Group {
            if cycleStore.accuracyReport.sampleCount > 0 {
                accuracyCard
            }
            ariaAnalystCard
            if cycleStore.settings.highAccuracyMode {
                highAccuracyCueCard
            }
            CycleGoalSelectorCard(
                goal: cycleStore.settings.cycleGoal,
                lifestyleGoal: cycleStore.settings.lifestyleGoal,
                periodTrainingStyle: cycleStore.settings.periodTrainingStyle,
                onUpdate: { cycleStore.updateCycleGoal($0) },
                onLifestyle: { goal in cycleStore.updateSettings { $0.lifestyleGoal = goal } },
                onPeriodStyle: { style in cycleStore.updateSettings { $0.periodTrainingStyle = style } }
            )
            twwSection
        }
        predictionFeedbackCard
        historyCard
        insightsCard
        // Support entry points sit together after the insights.
        supportCardComposer
        extraCareCard
        ariaCoachCard
        sexualHealthCard
        // Grouped rather than listed flat: `ViewBuilder` takes at most ten
        // children, and adding sharing as an eleventh sibling is a compile
        // error with a diagnostic that points nowhere near the real cause.
        Group {
            settingsCard
            disclaimerFooter
        }
    }

    /// Owner-authored holistic Support card — single line, 280 chars, vaulted.
    /// Whole-person intent (`symptoms`/`flow`/`notes` stay vaulted) that travels
    /// in `PartnerCycleDigest` so male can grasp conversations ARIA has *and*
    /// things she didn't tell him directly — without auto-sharing a diary.
    /// Female keeps full snapshot (phase, scores, training) inside Cycle Health;
    /// this card is the only holistic line that leaves it, and workout listing
    /// never shows period phases.
    private var supportCardComposer: some View {
        let trimmedDraft = supportCardDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftUnchanged = trimmedDraft == (cycleStore.settings.supportCardLine ?? "")
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Support card for partner", meta: "\(supportCardDraft.count)/280", metaColor: .textTertiary, tint: .ember)
            Text("What helps you, in your words. Shared on Support coach + Timing. Never auto-filled from cramps/pain/notes.")
                .font(HomeType.body)
                .foregroundColor(.textTertiary)
                .forgeWrapping()
            TextField("e.g. tea + quiet tonight, heat pad helps, space first 2 days…", text: $supportCardDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(HomeType.body)
                .foregroundColor(.textPrimary)
                .lineLimit(3...4)
                .frame(minHeight: ForgeUX.minTap, alignment: .topLeading)
                .forgeWell()
                .onChange(of: supportCardDraft) { _, v in if v.count > 280 { supportCardDraft = String(v.prefix(280)) } }
                .onAppear { supportCardDraft = cycleStore.settings.supportCardLine ?? "" }
                .onChange(of: cycleStore.settings.supportCardLine) { _, v in supportCardDraft = v ?? "" }
            if let preview = (trimmedDraft.isEmpty ? nil : trimmedDraft) ?? cycleStore.settings.supportCardLine {
                Text("Partner will see: \"\(preview)\"")
                    .font(HomeType.body)
                    .foregroundColor(.textSecondary)
                    .forgeWrapping()
            }
            ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
                ForgeSecondaryButton(title: "Save card", accent: .indigo) {
                    cycleStore.updateSupportCard(supportCardDraft)
                    FDS.notificationHaptic(.success)
                }
                .disabled(draftUnchanged)
                .opacity(draftUnchanged ? 0.5 : 1)
                if cycleStore.settings.supportCardLine != nil {
                    ForgeTextLink(title: "Clear", accent: .indigo) {
                        supportCardDraft = ""
                        cycleStore.updateSupportCard(nil)
                    }
                }
            }
        }
        .forgeContentCard()
    }

    /// Extra care ping for supporters — stays on My cycle because it is about
    /// *today's* body, not an invite.
    private var extraCareCard: some View {
        let active = cycleStore.settings.extraCareIsActive()
        return Button {
            FDS.haptic(.press)
            cycleStore.updateSettings { s in
                s.needExtraCareDayKey = active ? nil : CycleDayKey.key()
            }
        } label: {
            actionRowLabel(
                icon: active ? "heart.circle.fill" : "heart.circle",
                tint: .ember,
                title: active ? "Extra care is on" : "Need extra care today",
                subtitle: "Supporters see a thoughtfulness ping — not why. Expires in 48 hours.",
                showChevron: false
            )
            .forgeContentCard(tint: .ember)
        }
        .buttonStyle(.plain)
        .accessibilityValue(active ? "On" : "Off")
        .accessibilityHint("Toggles the extra care ping for your supporters")
    }

    /// Shared anatomy for tappable action cards: icon well, status title,
    /// body subtitle and an optional chevron.
    private func actionRowLabel(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        showChevron: Bool = true
    ) -> some View {
        HStack(spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: icon, tint: tint)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var trainingPrescriptionCard: some View {
        CycleTrainingPrescriptionCard(prescription: cycleStore.trainingPrescription) {
            let rx = cycleStore.trainingPrescription
            store.openChat(with: "My goal is \(cycleStore.settings.lifestyleGoal.label). I'm in \(cycleStore.snapshot.phase.label). \(rx.headline) \(rx.volumeLine) Shape today's session.")
        }
    }

    /// Invite lives on Support. My cycle is the owner's log — not the place
    /// you send someone a share.
    private var shareSupportCard: some View {
        Button {
            FDS.haptic(.press)
            showSharing = true
        } label: {
            actionRowLabel(
                icon: "person.2.badge.key.fill",
                tint: .ember,
                title: "Invite someone to support me",
                subtitle: "They see how to help. They never see your log."
            )
            .forgeContentCard(tint: .ember)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens sharing")
    }

    @ViewBuilder
    private var fertileScoreSection: some View {
        if let score = cycleStore.snapshot.fertileScore {
            FertileScoreCard(score: score, phase: cycleStore.snapshot.phase) {
                store.openChat(with: "My Fertile Score is \(score)/100 right now. What does that mean for training, recovery, and lifestyle timing today?")
            }
        }
    }

    @ViewBuilder
    private var twwSection: some View {
        if cycleStore.settings.cycleGoal == .ttc,
           let tww = cycleStore.snapshot.twwDaysElapsed {
            TWWSectionCard(daysElapsed: tww) {
                store.openChat(with: "I'm on day \(tww) of my two-week wait. What should I know?")
            }
        }
    }

    private func toastBanner(_ message: String) -> some View {
        ForgeToast(title: message, energy: accent)
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.bottom, FDS.Spacing.lg)
            .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity))
    }

    @ToolbarContentBuilder
    private var cycleToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: FDS.Spacing.md) {
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

    private func handleAppear() {
        if let sex = store.userProfile.biologicalSex {
            cycleStore.enableForBiologicalSexIfNeeded(sex)
        }
        cycleStore.enableForFemaleProfileIfNeeded(gender: store.userProfile.gender)
        if let sex = store.userProfile.biologicalSex {
            cycleStore.enableForBiologicalSexIfNeeded(sex)
        }
        if !didApplyLaunchPane {
            if let initialPane {
                pane = initialPane
            } else if store.userProfile.gender != .female,
                      store.userProfile.biologicalSex?.cycleAutoEnabled != true,
                      !cycleStore.settings.enabled {
                pane = .partner
            }
            didApplyLaunchPane = true
        }
        partnerNameDraft = cycleStore.partnerSettings.partnerName
        partnerRelDraft = cycleStore.partnerSettings.relationshipLabel
        supportRole = cycleStore.partnerSettings.resolvedRole
        privacyAccepted = cycleStore.settings.privacyAcknowledged
        if store.pendingCycleSharingOpen {
            showSharing = true
            store.pendingCycleSharingOpen = false
        }
        cycleStore.seedTestReadyCycleIfNeeded(testReady: AriaService.shouldUseTestReadyDummy)
        cycleStore.refresh(from: store)
        Task { await cycleStore.syncFromHealthKit() }
        // Refetched every appearance rather than cached: a revoke on the owner's
        // side shows up as the zone disappearing, and the supporter should stop
        // seeing a digest on their next visit, not whenever a push happens to
        // arrive.
        Task { await cycleStore.syncSharedPeriodFinished() }
        unlockCycleIfNeeded()
    }

    /// The end-to-end arc of the current cycle: bleed → post-period → fertile → pre-menstrual.
    /// Its one episode control (start or finish) is the pane's primary action,
    /// and it is not repeated anywhere further down the page.
    private var cycleStageCard: some View {
        let snap = cycleStore.snapshot
        let stage = snap.stage
        let tint = stageColor(stage)
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
                ForgeCardHeader("WHERE YOU ARE")
                HudVibeChip(label: stage.label, energy: tint)
            }

            cycleTimeline(snap: snap, stage: stage)

            if !snap.stageNarrative.isEmpty {
                Text(snap.stageNarrative)
                    .font(HomeType.body)
                    .foregroundColor(.textSecondary)
                    .forgeWrapping()
            }

            // Facts, not vibes: real dates for the two things people actually plan around.
            stageFactsSection(snap: snap)

            // One episode control — start or finish — not a third copy further down the page.
            if stage == .period, !snap.periodEndConfirmed {
                periodFinishedButton
            } else {
                periodStartButton
            }
        }
        .forgeContentCard(tint: tint)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func stageFactsSection(snap: MenstrualCycleSnapshot) -> some View {
        VStack(spacing: FDS.Spacing.sm) {
            if let end = snap.currentPeriodEndDayKey, let count = snap.currentPeriodDayCount {
                let daysLabel = count == 1 ? "1 day" : "\(count) days"
                stageFact(
                    icon: snap.periodEndConfirmed ? "checkmark.circle.fill" : "drop.circle",
                    label: snap.periodEndConfirmed ? "Period finished" : "Last bleed logged",
                    value: "\(shortDate(end)) · \(daysLabel)",
                    color: periodColor
                )
            }
            if let startDay = snap.fertileStartDayInCycle,
               let endDay = snap.fertileEndDayInCycle,
               let lastStart = snap.lastPeriodStartDayKey,
               let fs = CycleDayKey.addDays(lastStart, startDay - 1),
               let fe = CycleDayKey.addDays(lastStart, endDay - 1) {
                stageFact(
                    icon: "waveform.path.ecg",
                    label: "Fertile window",
                    value: "\(shortDate(fs)) – \(shortDate(fe))",
                    color: phaseColor(.fertileWindow)
                )
            }
            if let next = snap.nextPeriod {
                stageFact(
                    icon: "calendar",
                    label: "Next period",
                    value: nextPeriodValue(next: next, daysUntil: snap.daysUntilNextPeriod),
                    color: periodColor
                )
            }
        }
    }

    private func nextPeriodValue(next: CyclePredictionRange, daysUntil: Int?) -> String {
        let date = shortDate(next.medianDayKey)
        guard let d = daysUntil else { return date }
        if d < 0 {
            return "\(date) · \(-d)d overdue"
        }
        return "\(date) · in \(d)d"
    }

    /// Brief glow on the hero ring for a confirmed period start or finish.
    private func pulseHeroRing() {
        guard !reduceMotion else { return }
        heroEventGlow = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            heroEventGlow = false
        }
    }

    private var periodFinishedButton: some View {
        ForgePrimaryButton(title: "My period finished", icon: "checkmark.circle.fill", accent: .ember) {
            let msg = cycleStore.confirmPeriodEndedToday()
            cycleStore.refresh(from: store)
            cycleStore.refreshAnalyst(lastAction: "period_ended_today")
            showToast(msg, haptic: false)
            pulseHeroRing()
            if let episode = cycleStore.pendingPeriodEndEpisode {
                periodEndEpisode = episode
                showPeriodEndFeedback = true
            }
        }
    }

    private var periodStartButton: some View {
        ForgePrimaryButton(title: "My period started", icon: "flag.fill", accent: .ember) {
            let msg = cycleStore.confirmPeriodStartedToday(
                flow: selectedFlow == .none ? .medium : selectedFlow
            )
            cycleStore.refresh(from: store)
            cycleStore.refreshAnalyst(lastAction: "period_started_today")
            showToast(msg, haptic: false)
            pulseHeroRing()
        }
    }

    private var coldStartCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("ANCHOR THIS CYCLE")
            Text("When did your last period start?")
                .font(HomeType.sessionTitle)
                .foregroundColor(.textPrimary)
                .forgeWrapping()
            Text("One start date unlocks phase, next period, and training bias. Everything else can wait.")
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()

            ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.interactiveChipLineGap) {
                coldStartChip("Today", daysAgo: 0)
                coldStartChip("3 days ago", daysAgo: 3)
                coldStartChip("1 week ago", daysAgo: 7)
            }

            DatePicker(
                "Last start",
                selection: $coldStartDate,
                in: Calendar.current.date(byAdding: .day, value: -45, to: Date())!...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .tint(periodColor)
            .foregroundColor(.textPrimary)

            ForgePrimaryButton(title: "Log this start", accent: .ember) {
                logColdStart(on: CycleDayKey.key(for: coldStartDate))
            }
        }
        .forgeContentCard(tint: periodColor)
    }

    private func coldStartChip(_ title: String, daysAgo: Int) -> some View {
        ForgeChipButton(label: title, energy: periodColor) {
            if let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) {
                coldStartDate = date
                logColdStart(on: CycleDayKey.key(for: date))
            }
        }
    }

    private func logColdStart(on dayKey: String) {
        cycleStore.logPeriodStart(on: dayKey, flow: selectedFlow == .none ? .medium : selectedFlow)
        cycleStore.refresh(from: store)
        cycleStore.refreshAnalyst(lastAction: "period_started")
        showToast("Start logged · \(shortDate(dayKey))", haptic: false)
        pulseHeroRing()
    }

    /// Each stage takes its phase's own color so stages and phases agree.
    private func stageColor(_ stage: CycleStage) -> Color {
        switch stage {
        case .period:        return phaseColor(.menstruation)
        case .postPeriod:    return phaseColor(.follicular)
        case .fertile:       return phaseColor(.fertileWindow)
        case .ovulation:     return phaseColor(.ovulation)
        case .premenstrual:  return phaseColor(.luteal)
        case .unknown:       return phaseColor(.unknown)
        }
    }

    /// Proportional cycle map: day 1 to the typical cycle length, with the
    /// period, the fertile window, the ovulation estimate and today marked in
    /// phase colors. Presentation only, built from the current snapshot.
    private func cycleTimeline(snap: MenstrualCycleSnapshot, stage: CycleStage) -> some View {
        let length: Double = max(21, min(45, snap.cycleLengthMedian))
        let periodDays: Double = min(length, max(1, snap.periodLengthMedian.rounded()))
        let fertileRange: ClosedRange<Double>? = {
            guard let fs = snap.fertileStartDayInCycle,
                  let fe = snap.fertileEndDayInCycle,
                  fe >= fs else { return nil }
            return Double(fs - 1)...Double(fe)
        }()
        let ovulationPos: Double? = snap.ovulationDayInCycle.map { Double($0) - 0.5 }
        let todayPos: Double? = snap.dayInCycle.map { Double($0) - 0.5 }

        var parts: [String] = ["Cycle map, \(stage.label)"]
        if let d = snap.dayInCycle { parts.append("day \(d) of about \(Int(length))") }
        parts.append("period about \(Int(periodDays)) days")
        if let range = fertileRange {
            parts.append("fertile window days \(Int(range.lowerBound) + 1) to \(Int(range.upperBound))")
        }
        if let o = snap.ovulationDayInCycle { parts.append("ovulation estimated day \(o)") }
        let summary = parts.joined(separator: ", ")

        return VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            GeometryReader { geo in
                timelineTrack(
                    width: geo.size.width,
                    length: length,
                    periodDays: periodDays,
                    fertileRange: fertileRange,
                    ovulationPos: ovulationPos,
                    todayPos: todayPos
                )
            }
            .frame(height: 20)
            HStack {
                Text("Day 1")
                Spacer(minLength: FDS.Spacing.sm)
                Text("Day \(Int(length))")
            }
            .font(HomeType.micro)
            .monospacedDigit()
            .foregroundStyle(Color.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func timelineTrack(
        width: CGFloat,
        length: Double,
        periodDays: Double,
        fertileRange: ClosedRange<Double>?,
        ovulationPos: Double?,
        todayPos: Double?
    ) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(height: 8)
            timelineBand(from: 0, to: periodDays, length: length, width: width, color: periodColor)
            if let fertileRange {
                timelineBand(
                    from: fertileRange.lowerBound,
                    to: fertileRange.upperBound,
                    length: length,
                    width: width,
                    color: phaseColor(.fertileWindow)
                )
            }
            if let ovulationPos {
                Circle()
                    .fill(phaseColor(.ovulation))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.background, lineWidth: 2))
                    .offset(x: CGFloat(ovulationPos / length) * width - 6)
            }
            if let todayPos {
                Capsule()
                    .fill(Color.textPrimary)
                    .frame(width: 3, height: 20)
                    .offset(x: CGFloat(min(max(todayPos / length, 0), 1)) * width - 1.5)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func timelineBand(from start: Double, to end: Double, length: Double, width: CGFloat, color: Color) -> some View {
        let x = CGFloat(start / length) * width
        let w = max(4, CGFloat((end - start) / length) * width)
        return Capsule()
            .fill(color.opacity(0.85))
            .frame(width: w, height: 8)
            .offset(x: x)
    }

    private func stageFact(icon: String, label: String, value: String, color: Color) -> some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap, alignment: .firstTextBaseline) {
            HStack(spacing: ForgeLayout.rowGap) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(label)
                    .font(HomeType.label)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: FDS.Spacing.xs)
            Text(value)
                .font(HomeType.status)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.trailing)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    /// Condition context, shown right under the hero so the user can see *why*
    /// their windows behave differently — and take it straight to ARIA.
    private func conditionCard(_ condition: CycleCondition) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: condition.label, tint: Color.steel)
            Text(condition.trackingImplication)
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()
            ForgeTextLink(title: "Ask ARIA about \(condition.label)", accent: .aurora) {
                store.openChat(
                    with: "I track my cycle with \(condition.label). I'm on \(cycleStore.snapshot.phase.label)"
                        + (cycleStore.snapshot.dayInCycle.map { ", day \($0)" } ?? "")
                        + ". What should I expect this week, and what's worth raising with a clinician?",
                    voice: false
                )
            }
        }
        .forgeContentCard(tint: Color.steel)
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pane == .me ? "CYCLE INTELLIGENCE" : "FAMILY SUPPORT")
                .forgeSectionLabel(tint: accent)
                .padding(.top, ForgeLayout.screenTop)
            ForgePageHeader(
                title: pane == .me ? "Know your rhythm" : "Show up for them",
                subtitle: pane == .me
                    ? "Periods, fertile windows, and recovery — personal math from your signals. Lifestyle guidance only."
                    : "Partners, spouses, daughters — log what they share so ARIA can coach you with care.",
                accent: accent
            )
        }
    }

    private var paneOptions: [ForgeSegmentOption<Pane>] {
        Pane.allCases.map { ForgeSegmentOption(value: $0, title: $0.label, icon: $0.icon) }
    }

    private var panePicker: some View {
        ForgeSegmentedControl(paneOptions, selection: $pane, accent: accent)
    }

    // MARK: Enable self

    private var isCyclePhysiologyProfile: Bool {
        store.userProfile.biologicalSex?.cycleAutoEnabled == true
            || store.userProfile.gender == .female
    }

    private var enableCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeIconWell(
                systemImage: isCyclePhysiologyProfile ? "drop.fill" : "person.crop.circle.badge.checkmark",
                tint: isCyclePhysiologyProfile ? periodColor : Color.vitality,
                diameter: 56
            )
            Text(isCyclePhysiologyProfile ? "Track with precision" : "This is my cycle")
                .font(HomeType.sessionTitle)
                .foregroundColor(.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            Text(isCyclePhysiologyProfile
                 ? "Log flow, symptoms, and optional BBT. ARIA personalizes cycle length, ovulation estimates, and training bias — never medical diagnosis."
                 : "Cycle tracking is built for the person whose cycle it is — typically female physiology. You can turn it on anytime if that's you. If you are here to help someone else, stay on Support.")
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForgeBulletRow(text: "Period episodes & predictions", tint: periodColor)
                ForgeBulletRow(text: "Multi-signal confidence + feedback MAE", tint: periodColor)
                ForgeBulletRow(text: "Phase-aware ARIA coaching", tint: periodColor)
                ForgeBulletRow(text: CyclePrivacy.shortPromise, tint: periodColor)
                if !isCyclePhysiologyProfile {
                    ForgeBulletRow(text: "Males can opt in at any time — Support stays available", tint: periodColor)
                }
            }

            Toggle(isOn: $privacyAccepted) {
                Text("I understand cycle data is for my coaching only — never sold")
                    .font(HomeType.body)
                    .foregroundColor(.textSecondary)
                    .forgeWrapping()
            }
            .tint(Color.vitality)

            ForgePrimaryButton(
                title: isCyclePhysiologyProfile ? "Enable my cycle" : "Turn on my cycle",
                accent: .ember
            ) {
                guard privacyAccepted else { return }
                cycleStore.updateSettings {
                    $0.enabled = true
                    $0.shareWithAria = false
                    $0.privacyAcknowledged = true
                }
                if !isCyclePhysiologyProfile {
                    store.userProfile.educationalCycleMode = true
                }
                showToast("Cycle tracking on", haptic: false)
                Task { await cycleStore.syncFromHealthKit() }
            }
            .disabled(!privacyAccepted)
            .opacity(privacyAccepted ? 1 : 0.5)
        }
        .forgeContentCard(tint: periodColor)
    }

    // MARK: Accuracy

    private var accuracyCard: some View {
        let report = cycleStore.accuracyReport
        let eval = cycleStore.lastEvaluation
        let gradeColor = Color(hex: eval.qualityGrade.accentHex)
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
                ForgeCardHeader("PREDICTION ACCURACY")
                HudVibeChip(label: eval.qualityGrade.label, energy: gradeColor)
            }
            accuracyStats(report: report)
            Text(report.gradeDetail)
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()

            Divider().background(Color.white.opacity(0.08))

            ForgeTextLink(title: "How we score this", accent: accent, expanded: showMethod) {
                motion(FDS.Spring.standard) { showMethod.toggle() }
            }
            if showMethod {
                accuracyMethodDetail(report: report, eval: eval)
                    .transition(expandTransition)
            }
        }
        .forgeContentCard(tint: accent)
    }

    private func accuracyStats(report: CycleAccuracyReport) -> some View {
        ForgeStatGrid(columns: 3) {
            ForgeStatTile(
                label: "MAE",
                value: report.maeDays.map { String(format: "%.1fd", $0) } ?? "—",
                energy: Color.vitality
            )
            ForgeStatTile(
                label: "±1 DAY",
                value: report.withinOneDayRate.map { "\(Int($0 * 100))%" } ?? "—",
                energy: Color.aurora
            )
            ForgeStatTile(
                label: "±2 DAY",
                value: report.withinTwoDayRate.map { "\(Int($0 * 100))%" } ?? "—",
                energy: Color.steel
            )
            ForgeStatTile(
                label: "SAMPLES",
                value: "\(report.sampleCount)",
                energy: Color.ember
            )
            ForgeStatTile(
                label: "PERIOD CONF",
                value: "\(Int(cycleStore.snapshot.periodTimingConfidence * 100))%",
                energy: Color.steel
            )
            ForgeStatTile(
                label: "OVU CONF",
                value: "\(Int(cycleStore.snapshot.ovulationConfidence * 100))%",
                energy: Color.aurora
            )
        }
    }

    /// The part of the accuracy card behind "How we score this".
    private func accuracyMethodDetail(report: CycleAccuracyReport, eval: CycleDataEvaluation) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text(eval.userFacingSummary)
                .font(HomeType.body)
                .foregroundColor(.textTertiary)
                .forgeWrapping()
            if abs(report.calibrationOffsetDays) >= 0.2 {
                Text("Bias auto-correct: \(report.calibrationOffsetDays >= 0 ? "+" : "")\(String(format: "%.1f", report.calibrationOffsetDays)) days · \(cycleStore.snapshot.predictionMethodSummary)")
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .forgeWrapping()
            }

            forecastTrail

            Text("Personal timing error — multi-signal + confirms. Not a fake global % badge. Not itself birth control.")
                .font(HomeType.body)
                .foregroundColor(.textTertiary)
                .forgeWrapping()

            ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
                ForgeTextLink(title: "Science & methods", accent: accent) {
                    showAccuracyExplainer = true
                }
                if cycleStore.settings.shareWithAria,
                   let prompt = cycleStore.ariaChatPromptForCycle() {
                    ForgeTextLink(title: "Ask ARIA", accent: .aurora) {
                        store.openChat(with: prompt, voice: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var forecastTrail: some View {
        let closed = cycleStore.forecastArchive.filter { !$0.isOpen }
        if !closed.isEmpty {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                Text("FORECAST TRAIL")
                    .forgeSectionLabel()
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: ForgeLayout.labelValueGap) {
                    ForEach(closed.suffix(4).reversed()) { rec in
                        forecastTrailRow(rec)
                    }
                }
            }
        }
    }

    private func forecastTrailRow(_ rec: CycleForecastRecord) -> some View {
        let predicted = shortDate(rec.predictedMedianDayKey)
        let actual = rec.scoredActualStartDayKey.map { shortDate($0) } ?? "—"
        let errorText: String = rec.scoredErrorDays.map { $0 >= 0 ? "+\($0)d" : "\($0)d" } ?? "—"
        let errorTint: Color = rec.scoredErrorDays.map { abs($0) <= 1 ? Color.vitality : HudChrome.miss } ?? Color.textMuted
        return ForgeMetricRow(
            label: "\(predicted) → \(actual)",
            value: errorText,
            tint: errorTint
        )
    }

    @ViewBuilder
    private var analystHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text("ARIA · UNDERSTAND · EVALUATE · TEACH")
                .forgeSectionLabel()
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
        } else {
            ForgeCardHeader("ARIA · UNDERSTAND · EVALUATE · TEACH")
        }
    }

    private var ariaAnalystCard: some View {
        let brief = cycleStore.lastAriaBrief
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            analystHeader
            if let g = brief?.evaluationGrade {
                HudVibeChip(label: g.label, energy: Color(hex: g.accentHex))
            }
            if let brief {
                analystBlock("Understood", brief.understood)
                analystBlock("Evaluation", brief.evaluationPoints.joined(separator: " "))
                analystBlock("Teaching", brief.teaching)
                if let sexual = brief.sexualHealthLifestyleNote {
                    analystBlock("Sexual health (lifestyle)", sexual)
                }
                Text(brief.disclaimer)
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .forgeWrapping()
                Text(brief.privacyLine)
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .forgeWrapping()
            } else {
                Text("Log or confirm a start — ARIA will understand your data, evaluate quality, then teach next steps.")
                    .font(HomeType.body)
                    .foregroundColor(.textSecondary)
                    .forgeWrapping()
            }

            if let msg = cycleStore.lastTeachingMessage {
                Text(msg)
                    .font(HomeType.body)
                    .foregroundColor(.textSecondary)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeWell()
            }
        }
        .forgeContentCard(tint: .ember)
    }

    private func analystBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(title)
                .forgeSectionLabel()
            Text(body)
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var highAccuracyCueCard: some View {
        let snap = cycleStore.snapshot
        let nearFertile = snap.phase == .fertileWindow || snap.phase == .ovulation
            || (snap.dayInCycle.map { d in
                guard let fs = snap.fertileStartDayInCycle, let fe = snap.fertileEndDayInCycle else { return false }
                return d >= max(1, fs - 2) && d <= fe + 1
            } ?? false)

        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("HIGH-ACCURACY MODE", tint: .aurora)
            if nearFertile {
                Text("Fertile window nearby — log BBT, OPK if you have it, and confirm period start the same day it begins.")
                    .font(HomeType.body)
                    .foregroundColor(.textSecondary)
                    .forgeWrapping()
            } else {
                Text("On: we nudge BBT/OPK around fertile days and same-day period confirms for sharper personal MAE. Lifestyle only — not birth control.")
                    .font(HomeType.body)
                    .foregroundColor(.textSecondary)
                    .forgeWrapping()
            }
        }
        .forgeContentCard(tint: .aurora)
    }

    private var predictionFeedbackCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("FORECAST OFFSET")
            Text("If the window was early or late, tell the model once. Start and finish live in Where you are.")
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()

            if cycleStore.coachingPreferences.sampleCount > 0,
               let summary = cycleStore.coachingPreferences.lastLearnedSummary {
                Text(summary)
                    .font(HomeType.body)
                    .foregroundStyle(Color.aurora)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeWell()
            }

            ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
                Text("Offset days")
                    .font(HomeType.label)
                    .foregroundColor(.textSecondary)
                Spacer(minLength: 0)
                Stepper(value: $feedbackOffset, in: 1...7) {
                    Text("\(feedbackOffset)")
                        .font(HomeType.metric)
                        .monospacedDigit()
                        .foregroundColor(.textPrimary)
                        .frame(minWidth: 24)
                }
            }

            ForgeAdaptiveStack(spacing: ForgeLayout.tileGap, threshold: .xxxLarge) {
                ForgeSecondaryButton(title: "Early by \(feedbackOffset)", icon: "arrow.left", accent: accent) {
                    let msg = cycleStore.confirmPeriodOffsetFromPrediction(
                        daysFromPredicted: -feedbackOffset,
                        flow: selectedFlow == .none ? .medium : selectedFlow
                    )
                    cycleStore.refresh(from: store)
                    showToast(msg, haptic: false)
                }
                ForgeSecondaryButton(title: "Late by \(feedbackOffset)", icon: "arrow.right", accent: accent) {
                    let msg = cycleStore.confirmPeriodOffsetFromPrediction(
                        daysFromPredicted: feedbackOffset,
                        flow: selectedFlow == .none ? .medium : selectedFlow
                    )
                    cycleStore.refresh(from: store)
                    showToast(msg, haptic: false)
                }
            }

            ForgeSecondaryButton(title: "Still no period", icon: "clock.badge.questionmark", accent: HudChrome.miss) {
                let msg = cycleStore.reportStillNoPeriod()
                showToast(msg, haptic: false)
            }
        }
        .forgeContentCard(tint: accent)
    }

    private func unlockCycleIfNeeded() {
        let locked = cycleStore.settings.cycleLockEnabled
            || cycleStore.settings.discretionMode == .stealth
        guard locked, cycleStore.settings.enabled, !cycleStore.cycleUnlockedThisSession else {
            cycleStore.cycleUnlockedThisSession = true
            return
        }
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            cycleStore.cycleUnlockedThisSession = true
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Cycle Health") { success, _ in
            DispatchQueue.main.async {
                cycleStore.cycleUnlockedThisSession = success
            }
        }
    }

    private func showToast(_ msg: String, haptic: Bool = true) {
        let token = UUID()
        toastToken = token
        motion { modelToast = msg }
        if haptic { FDS.haptic(.success) }
        UIAccessibility.post(notification: .announcement, argument: msg)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            // Only the toast that scheduled this timer may dismiss it — otherwise a
            // second action inside the window cleared the *new* message early.
            guard toastToken == token else { return }
            motion { modelToast = nil }
        }
    }

    // MARK: Phase orbit (hero)

    /// The pane's one hero: phase ring with the cycle day, the phase eyebrow,
    /// a three-stat strip and today's training note.
    private var phaseOrbitCard: some View {
        let snap = cycleStore.snapshot
        let heroColor = phaseColor(snap.phase)
        let ringSize = ForgeLayout.scaledCap(orbitRingSize, base: 168)
        let percent = Int((cycleProgress(snap) * 100).rounded())
        return VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            ForgeCardHeader(title: snap.phase.label, tint: heroColor) {
                if cycleStore.isSyncing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(heroColor)
                }
            }

            HudProgressRing(progress: percent, energy: heroColor, size: ringSize, eventGlow: heroEventGlow) {
                orbitCenter(snap: snap, color: heroColor)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(orbitAccessibilityLabel(snap))

            if snap.isCurrentlyBleeding {
                HudVibeChip(label: "Bleeding logged today", energy: periodColor)
                    .frame(maxWidth: .infinity)
            }

            ForgeStatGrid(columns: 3) {
                ForgeStatTile(
                    label: "CONFIDENCE",
                    value: "\(Int(snap.confidence * 100))%",
                    energy: heroColor
                )
                ForgeStatTile(
                    label: "CYCLE",
                    value: "\(Int(snap.cycleLengthMedian.rounded()))d",
                    energy: Color.steel
                )
                ForgeStatTile(
                    label: "PERIOD",
                    value: "~\(Int(snap.periodLengthMedian.rounded()))d",
                    energy: periodColor
                )
            }

            Text(snap.trainingNote)
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .forgeWrapping()
        }
        .hudPlate(energy: heroColor)
        .accessibilityElement(children: .contain)
    }

    private func orbitCenter(snap: MenstrualCycleSnapshot, color: Color) -> some View {
        VStack(spacing: ForgeLayout.labelValueGap) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: snap.phase.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            if let day = snap.dayInCycle {
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("DAY")
                        .font(HomeType.micro)
                        .tracking(1.4)
                        .foregroundStyle(Color.textTertiary)
                        .hudInArcText()
                }
                Text("\(day)")
                    .font(HomeType.heroScore)
                    .foregroundStyle(Color.textPrimary)
                    .hudInArcText()
                    .contentTransition(.numericText())
            } else {
                Text("—")
                    .font(HomeType.heroScore)
                    .foregroundStyle(Color.textTertiary)
                    .hudInArcText()
            }
        }
        .accessibilityHidden(true)
    }

    private func orbitAccessibilityLabel(_ snap: MenstrualCycleSnapshot) -> String {
        let day = snap.dayInCycle.map { "Day \($0)" } ?? "Day not known yet"
        return "\(day), \(snap.phase.label), confidence \(Int(snap.confidence * 100)) percent"
    }

    private func cycleProgress(_ snap: MenstrualCycleSnapshot) -> CGFloat {
        guard let day = snap.dayInCycle else { return 0.08 }
        let len = max(21, min(45, snap.cycleLengthMedian))
        return min(0.98, CGFloat(day) / CGFloat(len))
    }

    // MARK: Day strip

    private var dayStrip: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("LAST 14 DAYS", meta: cycleStore.snapshot.dataQuality.capitalized)
            // Edge-bleed rail that opens on today (the newest day is last).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FDS.Spacing.xs) {
                    ForEach(recentDayKeys(), id: \.self) { key in
                        dayCell(key)
                    }
                }
                .padding(.horizontal, ForgeLayout.cardPadding)
                .padding(.vertical, FDS.Spacing.sm)
            }
            .defaultScrollAnchor(.trailing)
            .padding(.horizontal, -ForgeLayout.cardPadding)
        }
        .forgeContentCard(tint: accent)
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
        let hasSymptoms = !(log?.symptoms.isEmpty ?? true)
        let cellWidth = max(ForgeUX.minTap, ForgeLayout.scaledCap(dayCellSize, base: 36))
        let dayNum: String = {
            guard let d = CycleDayKey.date(from: key) else { return "·" }
            return "\(Calendar.current.component(.day, from: d))"
        }()
        return Button {
            openDayEditor(key: key)
        } label: {
            VStack(spacing: FDS.Spacing.sm) {
                Text(dayNum)
                    .font(HomeType.micro)
                    .monospacedDigit()
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
                Circle()
                    .fill(hasSymptoms ? Color.ember.opacity(0.7) : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(minWidth: cellWidth, minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit day \(dayNum)")
        .accessibilityValue(flow.isBleeding ? "\(flow.label) flow" : "No flow logged")
        .accessibilityHint("Opens the day editor")
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
        FDS.haptic(.press)
    }

    /// Flow intensity is the period hue at four strengths.
    private func flowDotColor(_ flow: MenstrualFlowLevel) -> Color {
        switch flow {
        case .heavy: return periodColor
        case .medium: return periodColor.opacity(0.78)
        case .light: return periodColor.opacity(0.56)
        case .spotting: return periodColor.opacity(0.36)
        default: return Color.white.opacity(0.1)
        }
    }

    // MARK: Predictions

    private var predictionGrid: some View {
        let snap = cycleStore.snapshot
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("AHEAD")
            ForgeAdaptiveStack(spacing: ForgeLayout.tileGap, alignment: .top) {
                predictionTile(
                    icon: "calendar",
                    title: "Next period",
                    value: snap.nextPeriod.map { shortDate($0.medianDayKey) } ?? "—",
                    sub: snap.nextPeriod.map { "\(shortDate($0.earliestDayKey))–\(shortDate($0.latestDayKey))" } ?? "Log starts to predict",
                    color: periodColor
                )
                predictionTile(
                    icon: "sparkles",
                    title: "Ovulation est.",
                    value: snap.ovulationDayInCycle.map { "Day \($0)" } ?? "—",
                    sub: ovulationMethodLabel(snap.ovulationMethod),
                    color: phaseColor(.ovulation)
                )
            }
            if let fs = snap.fertileStartDayInCycle, let fe = snap.fertileEndDayInCycle {
                fertileWindowRow(start: fs, end: fe, irregular: snap.irregularityFlag)
            }
        }
        .forgeContentCard(tint: accent)
    }

    /// Human copy for the stored ovulation-method identifier.
    private func ovulationMethodLabel(_ method: String?) -> String {
        guard let method else { return "Learning" }
        switch method {
        case "lh_surge": return "LH surge"
        case "bbt_shift": return "Temperature shift"
        case "peak_mucus", "mucus": return "Cervical mucus"
        default: return method.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func fertileWindowRow(start: Int, end: Int, irregular: Bool) -> some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
            HStack(spacing: ForgeLayout.rowGap) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(phaseColor(.fertileWindow))
                    .accessibilityHidden(true)
                Text("Fertile window · days \(start)–\(end)")
                    .font(HomeType.status)
                    .foregroundColor(.textPrimary)
                    .forgeWrapping()
            }
            Spacer(minLength: 0)
            if irregular {
                HudVibeChip(label: "Variable", energy: HudChrome.miss)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private func predictionTile(icon: String, title: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(title)
                .font(HomeType.micro)
                .foregroundColor(.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(HomeType.metric)
                .monospacedDigit()
                .foregroundColor(.textPrimary)
                .forgeSingleLine()
                .contentTransition(.numericText())
            Text(sub)
                .font(HomeType.body)
                .foregroundColor(.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .accessibilityElement(children: .combine)
    }

    // MARK: Quick log

    private var quickLogCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Button {
                motion { logExpanded.toggle() }
            } label: {
                ForgeCardHeader(title: "LOG TODAY") {
                    Image(systemName: logExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: ForgeUX.minTap)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log today")
            .accessibilityValue(logExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides the logging controls")

            if logExpanded {
                quickLogBody
                    .transition(expandTransition)
            }
        }
        .forgeContentCard(accent: accent)
    }

    private var quickLogBody: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            quickLogGroup("Flow") {
                flowSelector(selection: $selectedFlow, accent: accent)
            }
            quickLogGroup("Symptoms") {
                symptomGrid
            }
            bbtRow
            ForgeSecondaryButton(title: "Save log", accent: accent) {
                saveToday()
            }
        }
    }

    private func quickLogGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text(label)
                .forgeSectionLabel()
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var bbtRow: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
            HStack(spacing: FDS.Spacing.md) {
                Text("BBT")
                    .font(HomeType.label)
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
                .frame(maxWidth: 160)
            }
            Spacer(minLength: 0)
            TextField(bbtUnit.placeholder, text: $bbtText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(HomeType.metric)
                .monospacedDigit()
                .foregroundColor(.textPrimary)
                .frame(minWidth: 72, minHeight: ForgeUX.minTap)
                .padding(.horizontal, FDS.Spacing.md)
                .forgeWell(padding: 0)
                .accessibilityLabel("Basal body temperature in \(bbtUnit.accessibilityName)")
        }
    }

    // MARK: Symptoms

    /// Symptoms that are most relevant to the current phase come first.
    private var leadSymptoms: [CycleSymptom] {
        switch cycleStore.snapshot.phase {
        case .menstruation:
            return [.cramps, .backache, .fatigue, .headache, .bloating, .pelvicPain, .moodLow, .nausea]
        case .follicular:
            return [.energyHigh, .moodHigh, .acne, .headache, .fatigue, .cravings, .insomnia, .bloating]
        case .fertileWindow, .ovulation:
            return [.libidoHigh, .energyHigh, .moodHigh, .pelvicPain, .bloating, .spotting, .headache, .cramps]
        case .luteal:
            return [.bloating, .cravings, .moodLow, .breastTenderness, .fatigue, .insomnia, .acne, .anxietyHigh]
        case .unknown:
            return [.cramps, .headache, .bloating, .fatigue, .moodLow, .backache, .cravings, .insomnia]
        }
    }

    /// Lead symptoms, plus any already-selected one so it never disappears
    /// behind the disclosure; everything once expanded.
    private var visibleSymptoms: [CycleSymptom] {
        let lead = leadSymptoms
        let rest = CycleSymptom.allCases.filter { !lead.contains($0) }
        if showAllSymptoms { return lead + rest }
        return lead + rest.filter { selectedSymptoms.contains($0) }
    }

    private var symptomGrid: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.interactiveChipLineGap) {
                ForEach(visibleSymptoms) { symptom in
                    ForgeChipButton(
                        label: symptom.label,
                        icon: symptom.icon,
                        energy: accent,
                        selected: selectedSymptoms.contains(symptom)
                    ) {
                        if selectedSymptoms.contains(symptom) {
                            selectedSymptoms.remove(symptom)
                        } else {
                            selectedSymptoms.insert(symptom)
                        }
                    }
                }
            }
            if showAllSymptoms || visibleSymptoms.count < CycleSymptom.allCases.count {
                ForgeTextLink(title: "More symptoms", accent: accent, expanded: showAllSymptoms) {
                    motion(FDS.Spring.standard) { showAllSymptoms.toggle() }
                }
            }
        }
    }

    private var flowOptions: [ForgeSegmentOption<MenstrualFlowLevel>] {
        [MenstrualFlowLevel.none, .spotting, .light, .medium, .heavy].map {
            ForgeSegmentOption(value: $0, title: $0.label)
        }
    }

    private func flowSelector(selection: Binding<MenstrualFlowLevel>, accent: Color) -> some View {
        ForgeSegmentedControl(
            flowOptions,
            selection: selection,
            accent: accent,
            bleed: ForgeLayout.cardPadding
        )
    }

    // MARK: History

    private var historyCard: some View {
        // Card used to be hidden entirely when `logs` was empty, which also hid the only
        // control that expands it — so a user with no logs could never see the empty state.
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Button {
                motion { historyExpanded.toggle() }
            } label: {
                ForgeCardHeader(title: "RECENT LOGS") {
                    HStack(spacing: FDS.Spacing.sm) {
                        ForgeCardMeta(text: "\(cycleStore.logs.count)", color: .textTertiary)
                        Image(systemName: historyExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: ForgeUX.minTap)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recent logs, \(cycleStore.logs.count) entries")
            .accessibilityHint(historyExpanded ? "Collapses the list" : "Expands the list")

            if historyExpanded {
                historyRows
                    .transition(expandTransition)
            }
        }
        .forgeContentCard()
    }

    @ViewBuilder
    private var historyRows: some View {
        if cycleStore.logs.isEmpty {
            ForgeEmptyNote(title: "Nothing logged yet. Save a day above and it will show up here.")
        } else {
            VStack(spacing: ForgeLayout.rowGap) {
                ForEach(cycleStore.logs.suffix(12).reversed()) { log in
                    historyRow(log)
                }
            }
        }
    }

    private func historyRow(_ log: CycleDayLog) -> some View {
        let subtitle = log.flow.label + (log.symptoms.isEmpty ? "" : " · \(log.symptoms.count) symptoms")
        let bbtValue: String? = log.bbtCelsius.map { String(format: "%.2f%@", bbtUnit.fromCelsius($0), bbtUnit.symbol) }
        return Button {
            openDayEditor(key: log.dayKey)
        } label: {
            ForgeListRow(
                icon: log.flow.isBleeding ? "drop.fill" : "circle.fill",
                iconColor: log.flow.isBleeding ? flowDotColor(log.flow) : Color.steel,
                title: shortDate(log.dayKey),
                subtitle: subtitle,
                trailing: bbtValue,
                showChevron: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the day editor")
    }

    // MARK: Insights + ARIA

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("INSIGHTS")
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(cycleStore.snapshot.insights.prefix(5), id: \.self) { line in
                    ForgeBulletRow(text: line, tint: accent)
                }
            }
            Text(cycleStore.snapshot.readinessNote)
                .font(HomeType.body)
                .foregroundColor(.textPrimary)
                .forgeWrapping()
        }
        .forgeContentCard(tint: .aurora)
    }

    private var ariaCoachCard: some View {
        Button {
            let prompt: String = {
                if cycleStore.settings.shareWithAria {
                    let phase = cycleStore.snapshot.phase.label
                    let rx = cycleStore.trainingPrescription
                    return "My goal is \(cycleStore.settings.lifestyleGoal.label). I'm in \(phase). \(rx.headline) How should I train today?"
                }
                return "Help me train and recover today."
            }()
            FDS.haptic(.press)
            store.openChat(with: prompt, voice: false)
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.premiumSurface)
                        .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                    ARIAIdentityMark(state: .idle, mood: .energized, size: 26, amplitude: 0.24)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("Ask ARIA about today")
                        .font(HomeType.status)
                        .foregroundColor(.textPrimary)
                        .forgeWrapping()
                    Text("Phase-aware training & recovery")
                        .font(HomeType.body)
                        .foregroundColor(.textTertiary)
                        .forgeWrapping()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .forgeContentCard(tint: .ember)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens ARIA chat")
    }

    private var sexualHealthCard: some View {
        SexualHealthEntryCard(
            store: store,
            cycleStore: cycleStore
        )
    }

    /// Toggle with a status title and an optional body subtitle.
    private func settingToggle(
        _ title: String,
        subtitle: String? = nil,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(title)
                    .font(HomeType.status)
                    .foregroundColor(.textPrimary)
                    .forgeWrapping()
                if let subtitle {
                    Text(subtitle)
                        .font(HomeType.body)
                        .foregroundColor(.textTertiary)
                        .forgeWrapping()
                }
            }
        }
        .tint(tint)
        .frame(minHeight: ForgeUX.minTap)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("PRIVACY & CONTROL")

            privacyShieldBanner

            CycleNotificationSettingsCard(cycleStore: cycleStore)

            CycleConditionSelectorCard(
                condition: Binding(
                    get: { cycleStore.settings.condition },
                    set: { cycleStore.updateCondition($0) }
                )
            )

            settingsToggles

            discretionControl

            settingsRows
        }
        .forgeContentCard()
    }

    private var settingsToggles: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            settingToggle(
                "ARIA reads cycle on this iPhone",
                subtitle: "ARIA may mention your cycle in chat on this iPhone. Samples never leave the device. Claude/Grok do not get your chart.",
                tint: .ember,
                isOn: Binding(
                    get: { cycleStore.settings.shareWithAria },
                    set: { v in cycleStore.updateSettings { $0.shareWithAria = v } }
                )
            )
            settingToggle(
                "On hormonal contraception",
                tint: .ember,
                isOn: Binding(
                    get: { cycleStore.settings.usesHormonalContraception },
                    set: { v in cycleStore.updateSettings { $0.usesHormonalContraception = v } }
                )
            )
            settingToggle(
                "High-accuracy mode",
                subtitle: "On or off — always. When on, BBT/OPK cues and learned period-end prefs tighten today's training cap.",
                tint: .aurora,
                isOn: Binding(
                    get: { cycleStore.settings.highAccuracyMode },
                    set: { v in cycleStore.updateSettings { $0.highAccuracyMode = v } }
                )
            )
        }
    }

    private var discretionControl: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Picker("Discretion", selection: Binding(
                get: { cycleStore.settings.discretionMode },
                set: { mode in cycleStore.updateSettings { $0.discretionMode = mode } }
            )) {
                ForEach(CycleDiscretionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(cycleStore.settings.discretionMode.detail)
                .font(HomeType.body)
                .foregroundColor(.textTertiary)
                .forgeWrapping()
        }
    }

    private var settingsRows: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Button {
                FDS.haptic(.press)
                showRhythmReport = true
            } label: {
                ForgeListRow(
                    icon: "lock.rectangle.stack.fill",
                    iconColor: .vitality,
                    title: "Apple Cycle report",
                    showChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the cycle report")

            settingToggle(
                "Tracking enabled",
                tint: .ember,
                isOn: Binding(
                    get: { cycleStore.settings.enabled },
                    set: { v in cycleStore.updateSettings { $0.enabled = v } }
                )
            )

            Button(role: .destructive) {
                FDS.haptic(.press)
                showWipeConfirm = true
            } label: {
                ForgeListRow(
                    icon: "trash.fill",
                    iconColor: .danger,
                    title: "Wipe my cycle logs"
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Asks you to confirm before erasing")
        }
    }

    private var flowLevels: [MenstrualFlowLevel] {
        [MenstrualFlowLevel.none, .spotting, .light, .medium, .heavy]
    }

    /// Five segments truncate their labels as text grows, so larger sizes use a menu.
    @ViewBuilder
    private var dayEditorFlowPicker: some View {
        if dynamicTypeSize >= .xLarge {
            Picker("Flow", selection: $editFlow) {
                ForEach(flowLevels, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Flow", selection: $editFlow) {
                ForEach(flowLevels, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var dayEditorSheet: some View {
        NavigationStack {
            Form {
                Section("Day") {
                    Text(editingDayKey.map(shortDate) ?? "—")
                        .foregroundColor(.secondary)
                }
                Section("Flow") {
                    dayEditorFlowPicker
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
                    ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
                        Picker("Unit", selection: $bbtUnit) {
                            ForEach(BBTUnit.allCases) { unit in
                                Text(unit.symbol).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 160)
                        Spacer(minLength: 0)
                        TextField(bbtUnit.placeholder, text: $editBBT)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 72)
                    }
                    if !editBBT.isEmpty {
                        Button("Clear temperature", role: .destructive) { editBBT = "" }
                            .font(.footnote)
                    }
                }
                // `painScale` existed on the model with an endometriosis comment but had
                // no entry point anywhere in the app — the field could never be set.
                Section("Pain") {
                    ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
                        Text(editPain == 0 ? "None" : "\(editPain)/10")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .frame(minWidth: 64, alignment: .leading)
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
                            showToast("Day deleted", haptic: false)
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
        showToast("Saved \(shortDate(key))", haptic: false)
    }

    private var privacyShieldBanner: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "lock.shield.fill", tint: .vitality)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(CyclePrivacy.title)
                        .font(HomeType.status)
                        .foregroundColor(.textPrimary)
                        .forgeWrapping()
                    Text(CyclePrivacy.shortPromise)
                        .font(HomeType.body)
                        .foregroundColor(.textSecondary)
                        .forgeWrapping()
                }
            }
            ForEach(CyclePrivacy.bullets, id: \.text) { item in
                HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.md) {
                    Image(systemName: item.icon)
                        .font(HomeType.label)
                        .foregroundStyle(Color.vitality)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(item.text)
                        .font(HomeType.body)
                        .foregroundColor(.textSecondary)
                        .forgeWrapping()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CyclePrivacy.title + ". " + CyclePrivacy.shortPromise)
    }

    private var disclaimerFooter: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text(CyclePrivacy.policy)
                .font(HomeType.body)
                .foregroundColor(.textTertiary)
                .forgeWrapping()
            Text(MenstrualCycleEngine.disclaimer)
                .font(HomeType.body)
                .foregroundColor(.textTertiary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Partner / support

    private var partnerContent: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            // A digest someone shared with this user comes first, above anything
            // logged locally. It is the only part of this pane that is actually
            // *from them* rather than the user's own notes about them, so it
            // outranks a guess assembled from manual entries.
            sharedWithMeSection

            shareSupportCard

            if !cycleStore.settings.enabled {
                myCycleOptInCard
            }

            peopleStrip

            if cycleStore.supportedPeople.isEmpty {
                partnerEnableCard
            } else if !cycleStore.partnerSettings.enabled {
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
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .forgeWrapping()
            }
        }
    }

    /// Support is help-someone. My cycle is *this body*. Males can opt in
    /// anytime without redoing onboarding.
    private var myCycleOptInCard: some View {
        Button {
            FDS.haptic(.select)
            pane = .me
        } label: {
            actionRowLabel(
                icon: "checkmark.seal.fill",
                tint: .vitality,
                title: "This is my cycle — turn on tracking",
                subtitle: isCyclePhysiologyProfile
                    ? "Open My cycle to enable your log."
                    : "Cycle tracking is for the person whose cycle it is. You can opt in anytime. Support stays here for helping someone else."
            )
            .forgeContentCard(tint: .vitality)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Switches to My cycle")
    }

    /// Partner, daughter, sister — each is a chip, not a rewrite of the last one.
    @ViewBuilder
    private var peopleStrip: some View {
        if !cycleStore.supportedPeople.isEmpty {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                ForgeSectionHeader(title: "PEOPLE YOU SUPPORT")
                // Edge-bleed rail: chips scroll to the screen edge, not the page inset.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ForgeLayout.chipGap) {
                        ForEach(cycleStore.supportedPeople) { person in
                            ForgeChipButton(
                                label: person.displayName,
                                icon: person.role.icon,
                                energy: .indigo,
                                selected: cycleStore.selectedPersonId == person.id
                            ) {
                                cycleStore.selectPerson(person.id)
                            }
                        }
                        ForgeChipButton(label: "Add", icon: "plus", energy: .indigo) {
                            showAddPerson = true
                        }
                    }
                    .padding(.horizontal, ForgeLayout.screenInset)
                    .padding(.vertical, FDS.Spacing.sm)
                }
                .padding(.horizontal, -ForgeLayout.screenInset)
            }
        }
    }

    /// Renders a digest received through CloudKit sharing.
    ///
    /// Note what is passed in: a `PartnerCycleDigest`, never `partnerSnapshot`.
    /// The local Support pane below is the user's *own* notes about someone —
    /// they typed it, so there is nothing to withhold. This section is the other
    /// direction, and it is the one that has to be redacted.
    @ViewBuilder
    private var sharedWithMeSection: some View {
        // One block per person. A supporter can hold shares from more than one
        // sharer — a partner and a daughter, say — and each gets its own lens,
        // because the role decides whether intimate material appears at all.
        ForEach(sharing.receivedDigests) { received in
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                SupporterDigestView(
                    digest: received.digest,
                    // The role comes from the share, not from local settings.
                    lens: PartnerSupportLens(
                        role: received.role,
                        supporterSex: store.userProfile.biologicalSex
                    ),
                    personName: received.ownerName
                )
                if !received.digest.periodFinished {
                    ForgeSecondaryButton(
                        title: "Mark \(received.ownerName)'s period finished",
                        icon: "checkmark.circle.fill",
                        accent: .vitality
                    ) {
                        cycleStore.adoptReceivedDigests([received])
                        if let person = cycleStore.personBound(to: received.id) {
                            cycleStore.selectPerson(person.id)
                            let msg = cycleStore.logPartnerPeriodEnd(personId: person.id)
                            cycleStore.refresh(from: store)
                            showToast(msg, haptic: false)
                        }
                    }
                }
            }
        }
    }

    private var partnerEnableCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeIconWell(systemImage: "heart.circle.fill", tint: .indigo, diameter: 56)
            Text(cycleStore.supportedPeople.isEmpty
                 ? "Support someone you love"
                 : "Turn support back on")
                .font(HomeType.sessionTitle)
                .foregroundColor(.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            Text("Partners, daughters, family, friends — each person is their own. Log what they share; ARIA coaches you in that role, not through one romantic lens.")
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()
            Text(CyclePrivacy.shortPromise)
                .font(HomeType.body)
                .foregroundStyle(Color.vitality)
                .forgeWrapping()
            rolePicker
            ForgePrimaryButton(title: "Continue", accent: .ember) {
                if cycleStore.supportedPeople.isEmpty || cycleStore.selectedPerson == nil {
                    _ = cycleStore.addSupportedPerson(
                        name: partnerNameDraft,
                        role: supportRole,
                        relationshipLabel: supportRole.suggestedLabels.first ?? "partner",
                        consentAcknowledged: false
                    )
                } else {
                    cycleStore.updatePartnerSettings {
                        $0.enabled = true
                        $0.shareWithAria = false
                        $0.supportRole = supportRole
                        $0.relationshipLabel = supportRole.suggestedLabels.first ?? "partner"
                    }
                }
                partnerRelDraft = supportRole.suggestedLabels.first ?? "partner"
            }
        }
        .forgeContentCard(tint: .indigo)
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text("WHO")
                .forgeSectionLabel()
                .accessibilityAddTraits(.isHeader)
            ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.interactiveChipLineGap) {
                ForEach(CycleSupportRole.selectableRoles) { role in
                    ForgeChipButton(
                        label: role.shortLabel,
                        icon: role.icon,
                        energy: .indigo,
                        selected: supportRole == role
                    ) {
                        supportRole = role
                        partnerRelDraft = role.suggestedLabels.first ?? partnerRelDraft
                    }
                }
            }
        }
    }

    private var partnerConsentCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text(supportRole == .child ? "Care first" : "Consent first")
                .font(HomeType.sessionTitle)
                .foregroundColor(.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            Text(
                supportRole == .child
                    ? "Only track what fits your caregiver role — preferably with her knowledge. Period starts are enough."
                    : "Only log what they’re comfortable sharing. Starts alone unlock strong support coaching."
            )
            .font(HomeType.body)
            .foregroundColor(.textSecondary)
            .forgeWrapping()
            rolePicker
            partnerTextField(supportRole == .child ? "Name (optional)" : "Name (optional)", text: $partnerNameDraft)
            partnerTextField(
                supportRole == .child ? "Label (daughter / child…)" : "Label (partner / wife…)",
                text: $partnerRelDraft
            )

            ForgePrimaryButton(
                title: supportRole == .child ? "I’m supporting as a parent" : "I have their okay",
                accent: .ember
            ) {
                cycleStore.updatePartnerSettings {
                    $0.consentAcknowledged = true
                    $0.partnerName = partnerNameDraft
                    $0.supportRole = supportRole
                    $0.relationshipLabel = partnerRelDraft.isEmpty
                        ? (supportRole.suggestedLabels.first ?? "partner")
                        : partnerRelDraft
                    $0.shareWithAria = false
                }
                FDS.notificationHaptic(.success)
            }
        }
        .forgeContentCard(tint: .indigo)
    }

    /// Single-line field in the shared inner well, 44 pt tall.
    private func partnerTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(HomeType.body)
            .foregroundColor(.textPrimary)
            .frame(minHeight: ForgeUX.minTap)
            .padding(.horizontal, FDS.Spacing.md)
            .forgeWell(padding: 0)
    }

    private var partnerPhaseHero: some View {
        let snap = cycleStore.partnerSnapshot
        let heroColor = phaseColor(snap.phase)
        let name = cycleStore.partnerSettings.displayName
        let ringSize = ForgeLayout.scaledCap(partnerRingSize, base: 72)
        let percent = Int((cycleProgress(snap) * 100).rounded())
        return VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
                HudProgressRing(progress: percent, energy: heroColor, size: ringSize) {
                    Image(systemName: snap.phase.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(heroColor)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(snap.phase.label), \(percent) percent through the cycle")
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(name)
                        .forgeSectionLabel(tint: heroColor)
                    Text(snap.stage == .unknown ? snap.phase.label : snap.stage.partnerLabel(name: name))
                        .font(HomeType.sessionTitle)
                        .foregroundColor(.textPrimary)
                        .forgeWrapping()
                    if let day = snap.dayInCycle {
                        Text("Day \(day) · \(Int(snap.confidence * 100))% confidence")
                            .font(HomeType.body)
                            .foregroundColor(.textSecondary)
                            .forgeWrapping()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The transition itself is the useful signal for a supporter.
            if snap.stage == .postPeriod, let since = snap.daysSincePeriodEnd, since <= 2 {
                Label(
                    since == 0 ? "Finished today — back to everyday support"
                               : "Finished \(since == 1 ? "yesterday" : "\(since) days ago") — back to everyday support",
                    systemImage: "arrow.uturn.forward.circle.fill"
                )
                .font(HomeType.body)
                .foregroundStyle(Color.vitality)
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeWell()
            }
            if let next = snap.nextPeriod {
                Text("Next period window · \(shortDate(next.earliestDayKey)) – \(shortDate(next.latestDayKey))")
                    .font(HomeType.body)
                    .foregroundColor(.textSecondary)
                    .forgeWrapping()
            }
            ForgePrimaryButton(title: "Ask ARIA how to show up", icon: "message.fill", accent: .ember) {
                let role = cycleStore.partnerSettings.resolvedRole
                let prompt = role == .child
                    ? "Help me support my daughter \(name) — \(snap.phase.label). What should I do?"
                    : "Help me support \(name) — \(snap.phase.label). What should I do?"
                store.openChat(with: prompt, voice: false)
            }
        }
        .hudPlate(energy: heroColor)
        .accessibilityElement(children: .contain)
    }

    private func partnerSupportCard(_ brief: PartnerSupportBrief) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(brief.role == .child ? "PARENT PLAYBOOK" : "HOW YOU SHOW UP")
            Text(brief.headline)
                .font(HomeType.status)
                .foregroundColor(.textPrimary)
                .forgeWrapping()
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(brief.supportMoves.prefix(4), id: \.self) { line in
                    ForgeBulletRow(text: line, tint: .vitality)
                }
            }
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                Text("Ease off")
                    .font(HomeType.status)
                    .foregroundColor(.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(brief.avoidMoves.prefix(3), id: \.self) { line in
                    ForgeBulletRow(text: line, tint: .textTertiary)
                }
            }
            Text(brief.communicationTip)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeWell()
        }
        .forgeContentCard(tint: .vitality)
    }

    private var partnerLogger: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("LOG FOR \(cycleStore.partnerSettings.displayName.uppercased())")
            Text("Confirming their start keeps support predictions sharp — history is retained.")
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()
            flowSelector(selection: $partnerFlow, accent: Color.indigo)

            ForgeSecondaryButton(title: "Their period started", icon: "flag.fill", accent: .indigo) {
                cycleStore.logPartnerPeriodStart(flow: partnerFlow == .none ? .medium : partnerFlow)
                showToast(cycleStore.lastModelUpdateMessage ?? "Logged · support model refreshed", haptic: false)
            }

            partnerLoggerPair
        }
        .forgeContentCard(tint: .indigo)
    }

    private var partnerLoggerPair: some View {
        let isPeriod = cycleStore.partnerSnapshot.stage == .period
        return ForgeAdaptiveStack(spacing: ForgeLayout.tileGap, threshold: .xLarge) {
            // Without this, support coaching had no way to leave period mode — it sat
            // there until the median bleed length elapsed, regardless of reality.
            ForgeSecondaryButton(title: "Their period finished", icon: "checkmark.circle.fill", accent: .vitality) {
                let msg = cycleStore.logPartnerPeriodEnd()
                cycleStore.refresh(from: store)
                showToast(msg, haptic: false)
            }
            .disabled(!isPeriod)
            .opacity(isPeriod ? 1 : 0.45)

            ForgeSecondaryButton(title: "Save today", accent: .steel) {
                cycleStore.logPartnerToday(flow: partnerFlow)
                FDS.notificationHaptic(.success)
                showToast("Saved today for \(cycleStore.partnerSettings.displayName)", haptic: false)
            }
        }
    }

    private var partnerSettingsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("SETTINGS")
            rolePicker
            partnerTextField("Name", text: $partnerNameDraft)
            partnerTextField("Relationship label", text: $partnerRelDraft)
            ForgeSecondaryButton(title: "Save", accent: .indigo) {
                cycleStore.updatePartnerSettings {
                    $0.partnerName = partnerNameDraft
                    $0.supportRole = supportRole
                    $0.relationshipLabel = partnerRelDraft.isEmpty
                        ? (supportRole.suggestedLabels.first ?? "partner")
                        : partnerRelDraft
                }
            }
            partnerSettingToggles
            ForgeSecondaryButton(
                title: "Remove \(cycleStore.partnerSettings.displayName)",
                icon: "person.crop.circle.badge.minus",
                accent: .danger
            ) {
                confirmRemovePerson = true
            }
        }
        .forgeContentCard()
    }

    private var partnerSettingToggles: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            settingToggle(
                "ARIA reads this on this iPhone",
                subtitle: "Never uploaded to Forge. Claude/Grok do not get their chart.",
                tint: .ember,
                isOn: Binding(
                    get: { cycleStore.partnerSettings.shareWithAria },
                    set: { v in cycleStore.updatePartnerSettings { $0.shareWithAria = v } }
                )
            )
            settingToggle(
                "Support tracking on",
                tint: .ember,
                isOn: Binding(
                    get: { cycleStore.partnerSettings.enabled },
                    set: { v in
                        cycleStore.updatePartnerSettings {
                            $0.enabled = v
                            if !v { $0.consentAcknowledged = false }
                        }
                    }
                )
            )
        }
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
