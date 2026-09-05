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

    private var accent: Color {
        let phase = pane == .me ? cycleStore.snapshot.phase : cycleStore.partnerSnapshot.phase
        return Color(hex: phase.accentHex)
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
                        VStack(spacing: 16) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.vitality)
                            Text("Cycle Health is locked")
                                .font(FDS.TypeScale.title(20))
                                .foregroundColor(.textPrimary)
                            Text("Face ID or your device passcode. Discretion Mode is on.")
                                .font(FDS.TypeScale.body(14))
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                            Button("Unlock") { unlockCycleIfNeeded() }
                                .buttonStyle(.borderedProminent)
                                .tint(.ember)
                        }
                        .padding(28)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
    }

    private var rootStack: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    heroHeader
                    panePicker
                    paneBody
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
            .background { cycleAmbientBackground }

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
        Group {
            shareSupportCard
            settingsCard
            disclaimerFooter
        }
    }

    @ViewBuilder
    private var meEnabledPrimary: some View {
        phaseOrbitCard
        cycleStageCard
        extraCareCard
        trainingPrescriptionCard
        if let condition = cycleStore.settings.condition.activeCase {
            conditionCard(condition)
        }
        quickLogCard
        dayStrip
        if cycleStore.snapshot.cyclesObserved > 0 {
            predictionGrid
            fertileScoreSection
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
        ariaCoachCard
        sexualHealthCard
        // Grouped rather than listed flat: `ViewBuilder` takes at most ten
        // children, and adding sharing as an eleventh sibling is a compile
        // error with a diagnostic that points nowhere near the real cause.
        Group {
            shareSupportCard
            settingsCard
            disclaimerFooter
        }
    }

    /// Entry point to partner sharing. Sits below the coaching cards and above
    /// settings on purpose: sharing your cycle with someone is a considered
    /// decision, not a toggle you should meet before you have looked at your
    /// own data.
    private var extraCareCard: some View {
        let active = cycleStore.settings.extraCareIsActive()
        return Button {
            cycleStore.updateSettings { s in
                s.needExtraCareDayKey = active ? nil : CycleDayKey.key()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: active ? "heart.circle.fill" : "heart.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.ember)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(active ? "Extra care is on" : "Need extra care today")
                        .font(FDS.TypeScale.label(15))
                        .foregroundColor(.textPrimary)
                    Text("Supporters see a thoughtfulness ping — not why. Expires in 48 hours.")
                        .font(FDS.TypeScale.body(12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeGlassCard(accent: .ember)
        }
        .buttonStyle(.plain)
    }

    private var trainingPrescriptionCard: some View {
        CycleTrainingPrescriptionCard(prescription: cycleStore.trainingPrescription) {
            let rx = cycleStore.trainingPrescription
            store.openChat(with: "My goal is \(cycleStore.settings.lifestyleGoal.label). I'm in \(cycleStore.snapshot.phase.label). \(rx.headline) \(rx.volumeLine) Shape today's session.")
        }
    }

    private var shareSupportCard: some View {
        Button {
            showSharing = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.2.badge.key.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.ember)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Invite someone to support me")
                        .font(FDS.TypeScale.label(15))
                        .foregroundColor(.textPrimary)
                    Text("They see how to help. They never see your log.")
                        .font(FDS.TypeScale.body(12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundColor(.textTertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeGlassCard(accent: .ember)
        }
        .buttonStyle(.plain)
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
        Text(message)
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

    @ToolbarContentBuilder
    private var cycleToolbar: some ToolbarContent {
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
        withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true }
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            ringPulse = true
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
            stageFactsSection(snap: snap)

            // One episode control — start or finish — not a third copy further down the page.
            if stage == .period, !snap.periodEndConfirmed {
                periodFinishedButton
            } else {
                periodStartButton
            }
        }
        .padding(18)
        .forgeGlassCard(accent: stageColor(stage))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func stageFactsSection(snap: MenstrualCycleSnapshot) -> some View {
        VStack(spacing: 8) {
            if let end = snap.currentPeriodEndDayKey, let count = snap.currentPeriodDayCount {
                let daysLabel = count == 1 ? "1 day" : "\(count) days"
                stageFact(
                    icon: snap.periodEndConfirmed ? "checkmark.circle.fill" : "drop.circle",
                    label: snap.periodEndConfirmed ? "Period finished" : "Last bleed logged",
                    value: "\(shortDate(end)) · \(daysLabel)",
                    color: Color(hex: "EF4444")
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
                    color: Color(hex: "F59E0B")
                )
            }
            if let next = snap.nextPeriod {
                stageFact(
                    icon: "calendar",
                    label: "Next period",
                    value: nextPeriodValue(next: next, daysUntil: snap.daysUntilNextPeriod),
                    color: Color(hex: "6366F1")
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

    private var periodFinishedButton: some View {
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

    private var periodStartButton: some View {
        Button {
            let msg = cycleStore.confirmPeriodStartedToday(
                flow: selectedFlow == .none ? .medium : selectedFlow
            )
            cycleStore.refresh(from: store)
            cycleStore.refreshAnalyst(lastAction: "period_started_today")
            showToast(msg)
        } label: {
            Label("My period started", systemImage: "flag.fill")
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
    }

    private var coldStartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ANCHOR THIS CYCLE")
                .forgeSectionLabel()
            Text("When did your last period start?")
                .font(FDS.TypeScale.title(20))
                .foregroundColor(.textPrimary)
            Text("One start date unlocks phase, next period, and training bias. Everything else can wait.")
                .font(FDS.TypeScale.body(13))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
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
            .tint(Color(hex: "EF4444"))
            .foregroundColor(.textPrimary)

            Button {
                logColdStart(on: CycleDayKey.key(for: coldStartDate))
            } label: {
                Text("Log this start")
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
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "EF4444"))
    }

    private func coldStartChip(_ title: String, daysAgo: Int) -> some View {
        Button {
            if let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) {
                coldStartDate = date
                logColdStart(on: CycleDayKey.key(for: date))
            }
        } label: {
            Text(title)
                .font(FDS.TypeScale.label(12))
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func logColdStart(on dayKey: String) {
        cycleStore.logPeriodStart(on: dayKey, flow: selectedFlow == .none ? .medium : selectedFlow)
        cycleStore.refresh(from: store)
        cycleStore.refreshAnalyst(lastAction: "period_started")
        showToast("Start logged · \(shortDate(dayKey))")
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
                    $0.shareWithAria = false
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
            Text("FORECAST OFFSET")
                .forgeSectionLabel()
            Text("If the window was early or late, tell the model once. Start and finish live in Where you are.")
                .font(FDS.TypeScale.body(12))
                .foregroundColor(.textSecondary)

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
            let prompt: String = {
                if cycleStore.settings.shareWithAria {
                    let phase = cycleStore.snapshot.phase.label
                    let rx = cycleStore.trainingPrescription
                    return "My goal is \(cycleStore.settings.lifestyleGoal.label). I'm in \(phase). \(rx.headline) How should I train today?"
                }
                return "Help me train and recover today."
            }()
            store.openChat(with: prompt, voice: false)
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
                    Text("Off until you turn it on. ARIA never sees phase unless you opt in.")
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
                    Text("On or off — always. When on, BBT/OPK cues and learned period-end prefs tighten today's training cap.")
                        .font(FDS.TypeScale.body(11))
                        .foregroundColor(.textTertiary)
                }
            }
            .tint(Color(hex: "A855F7"))

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
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textTertiary)

            Button {
                showRhythmReport = true
            } label: {
                HStack {
                    Image(systemName: "lock.rectangle.stack.fill")
                    Text("12-month Vault report")
                        .font(FDS.TypeScale.label(14))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.textTertiary)
                }
                .foregroundColor(.textPrimary)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

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
            // A digest someone shared with this user comes first, above anything
            // logged locally. It is the only part of this pane that is actually
            // *from them* rather than the user's own notes about them, so it
            // outranks a guess assembled from manual entries.
            sharedWithMeSection

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
                    .font(FDS.TypeScale.body(11))
                    .foregroundColor(.textTertiary)
            }
        }
    }

    /// Partner, daughter, sister — each is a chip, not a rewrite of the last one.
    @ViewBuilder
    private var peopleStrip: some View {
        if !cycleStore.supportedPeople.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("PEOPLE YOU SUPPORT")
                    .forgeSectionLabel()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cycleStore.supportedPeople) { person in
                            Button {
                                cycleStore.selectPerson(person.id)
                                FDS.selectionHaptic()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: person.role.icon)
                                    Text(person.displayName)
                                        .font(FDS.TypeScale.label(13))
                                }
                                .foregroundColor(cycleStore.selectedPersonId == person.id ? .white : .textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    cycleStore.selectedPersonId == person.id
                                        ? Color(hex: "6366F1")
                                        : Color.surfaceElevated
                                )
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            showAddPerson = true
                            FDS.haptic(.light)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Add")
                                    .font(FDS.TypeScale.label(13))
                            }
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.surfaceElevated)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
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
            VStack(alignment: .leading, spacing: 10) {
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
                    Button {
                        cycleStore.adoptReceivedDigests([received])
                        if let person = cycleStore.personBound(to: received.id) {
                            cycleStore.selectPerson(person.id)
                            let msg = cycleStore.logPartnerPeriodEnd(personId: person.id)
                            cycleStore.refresh(from: store)
                            showToast(msg)
                        }
                    } label: {
                        Label("Mark \(received.ownerName)'s period finished", systemImage: "checkmark.flag.fill")
                            .font(FDS.TypeScale.label(13))
                            .foregroundStyle(Color(hex: "22C55E"))
                    }
                    .buttonStyle(.plain)
                }
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
            Text(cycleStore.supportedPeople.isEmpty
                 ? "Support someone you love"
                 : "Turn support back on")
                .font(FDS.TypeScale.title(20))
                .foregroundColor(.textPrimary)
            Text("Partners, daughters, family, friends — each person is their own. Log what they share; ARIA coaches you in that role, not through one romantic lens.")
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
            Text(CyclePrivacy.shortPromise)
                .font(FDS.TypeScale.body(12))
                .foregroundStyle(Color(hex: "22C55E"))
            rolePicker
            Button {
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
                    ForEach(CycleSupportRole.selectableRoles) { role in
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
                    $0.shareWithAria = false
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
                    Text("Off until you turn it on. ARIA coaches you from what you log.")
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
            Button(role: .destructive) {
                confirmRemovePerson = true
            } label: {
                Label("Remove \(cycleStore.partnerSettings.displayName)", systemImage: "person.crop.circle.badge.minus")
                    .font(FDS.TypeScale.label(13))
                    .foregroundStyle(Color(hex: "F87171"))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
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
