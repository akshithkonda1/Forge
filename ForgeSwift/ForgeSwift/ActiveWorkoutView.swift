import SwiftUI
import UIKit
import ForgeCore

@MainActor
struct ActiveWorkoutView: View {
    @EnvironmentObject var store: AppStore
    /// Nothing pulses while idle in-session; Reduce Motion also removes the event motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onWorkoutEnd: (WorkoutSummaryData) -> Void

    // Bio metrics
    @State private var elapsedSecs:    Int    = 0
    /// Last live sample, 0 until one arrives. Drives display only — engines get `liveHeartRate`.
    @State private var simulatedHR:    Int    = 0
    @State private var liveHeartRate:  Int?   = nil
    @State private var heartRateIsLive = false
    @State private var peakHR:         Int    = 72
    @State private var hrHistory:      [Int]  = []
    @State private var estimatedCals:  Double = 0

    // Rest
    @State private var isResting:      Bool   = false
    @State private var restTimeLeft:   Int    = 0
    @State private var restTotal:      Int    = 90

    // Set logging
    @State private var setLog:         [SetLogEntry] = []
    @State private var showSetLogger:  Bool   = false
    @State private var loggedReps:     Int    = 0
    @State private var currentWeight:  Int    = 0
    @State private var loggedRPE:      Int    = 7
    @State private var showPRBanner:   Bool   = false
    @State private var prExerciseName: String = ""

    // Pain
    @State private var painLog:        [PainEntry] = []
    @State private var showPainLogger: Bool   = false

    // Adaptive / ARIA
    @State private var voiceCoach = VoiceCoachManager()
    @State private var autoRegLog:     [String] = []
    @State private var muscleVolume:   [TargetMuscle: Double] = [:]
    @State private var pendingSwap:    ExerciseDefinition? = nil
    @State private var swapReason:     String = ""
    @State private var showSwapBanner: Bool   = false
    @State private var showFormCoach:  Bool   = false

    // End
    @State private var showEndConfirm: Bool   = false
    @State private var sessionStartedAt: Date = Date()
    @State private var didWarnHR: Bool        = false

    // Volume
    @State private var totalVolume:    Int    = 0

    // Demo
    @State private var selectedDemoTab: ExerciseDemoTab = .video
    @State private var showDemo: Bool = false

    // Event moment: the set ring glows once per logged set.
    @State private var setLoggedPulse: Bool = false

    // Music
    @StateObject private var music = MusicControllerFactory.make(for: .appleMusic)

    // Tasks
    @State private var elapsedTask: Task<Void, Never>? = nil
    @State private var calTask:     Task<Void, Never>? = nil
    @State private var restTask:    Task<Void, Never>? = nil

    private var exercises:       [Exercise] { store.todayWorkout?.exercises ?? [] }
    private var currentExercise: Exercise?  { exercises.indices.contains(store.currentExerciseIndex) ? exercises[store.currentExerciseIndex] : nil }
    private var currentZone: WorkoutHRZone { WorkoutHRZone.zone(for: simulatedHR) }
    /// Zone for the engines — nil without a live sample, never "Rest" from a 0 bpm placeholder.
    private var liveZone: Int? { heartRateIsLive ? currentZone.index : nil }
    private var currentDef: ExerciseDefinition? { currentExercise.flatMap { ExerciseLibrary.definition(for: $0) } }
    /// No real-time SpO₂ source exists during a workout (HealthKit only gives a
    /// daily average), so the coach gets nil — "no reading" — never a stand-in value.
    private var liveSpO2: Int? { nil }

    /// Live auto-regulation read for the current exercise.
    private var recommendation: SetRecommendation {
        let ex = currentExercise
        let prev = ex.map { e in setLog.filter { $0.exerciseName == e.name } } ?? []
        let target = ex?.reps.repMidpoint ?? 8
        let pain = ex.flatMap { e in painLog.filter { $0.exerciseName == e.name }.map { $0.severity }.max() }
        let painLoc = ex.flatMap { e in painLog.filter { $0.exerciseName == e.name }.last?.location }
        return AdaptiveEngine.recommend(
            definition: currentDef, targetReps: target, targetRPE: currentDef?.rpeTarget ?? 8,
            baseRest: ex?.restSeconds ?? 90, currentWeight: currentWeight,
            lastRPE: prev.last?.rpe, lastReps: prev.last?.repsPerformed,
            readiness: store.readiness, experience: store.userProfile.experienceLevel,
            currentHR: liveHeartRate, hrZone: liveZone, spO2: liveSpO2,
            painSeverity: pain, painLocation: painLoc)
    }

    // MARK: Motion helpers

    private var motionStandard: Animation? { reduceMotion ? nil : FDS.Spring.standard }
    private var motionSnap: Animation? { reduceMotion ? nil : FDS.Spring.snap }

    /// Every state change in this view goes through here, so Reduce Motion is honoured in one place.
    private func withMotion(_ animation: Animation = FDS.Spring.standard, _ change: () -> Void) {
        withAnimation(reduceMotion ? nil : animation) { change() }
    }

    private func overlayTransition(edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    private var expandTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }

    private var restTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity)
    }

    private var cardTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                          removal: .move(edge: .leading).combined(with: .opacity))
    }

    var body: some View {
        ZStack {
            WorkoutBackground(accentColor: currentZone.color).ignoresSafeArea()

            if let exercise = currentExercise {
                sessionLayout(exercise: exercise)
            } else {
                emptyLayout
            }

            overlays
        }
        .sheet(isPresented: $showFormCoach) {
            if let exercise = currentExercise {
                FormCheckCameraView(exercise: exercise, definition: currentDef, liveContext: liveContext(for: exercise))
            }
        }
        .sheet(item: $store.pendingShowHow) { def in
            ExerciseDetailSheet(def: def)
        }
        .onAppear  {
            if store.todayWorkout == nil {
                store.rebuildTodayPlanFromLife()
            }
            sessionStartedAt = Date()
            startTasks()
            setupCurrentWeight()
            startHealthHeartRate()
            syncVoiceCoach()
            voiceCoach.setVoiceEnabled(AriaTrainVoice.isEnabled)
            voiceCoach.announceWorkoutStart()
            publishLiveActivity()
        }
        .onDisappear {
            cancelTasks()
            HealthKitManager.shared.stopLiveHeartRateUpdates()
        }
        .animation(motionStandard, value: showPRBanner)
        .animation(motionStandard, value: showSwapBanner)
        .animation(motionStandard, value: showSetLogger)
        .animation(motionStandard, value: showPainLogger)
    }

    private func sessionLayout(exercise: Exercise) -> some View {
        VStack(spacing: 0) {
            cockpitHeader
            exerciseProgressRow
            if !dynamicTypeSize.isAccessibilitySize {
                liveMetricsBar
            }
            MusicControlBar(controller: music, compact: true)
                .padding(.horizontal, ForgeLayout.screenInset)
                .padding(.vertical, FDS.Spacing.sm)
            mainContent(exercise: exercise)
            voiceCoachBar
        }
    }

    private var emptyLayout: some View {
        VStack(spacing: ForgeLayout.sectionGap) {
            ForgeEmptyStateCard(
                icon: "figure.strengthtraining.traditional",
                title: "Today’s session",
                message: "ARIA writes this from how you live — sleep, cycle, gear, readiness. Not a catalog.",
                cta: "Write session",
                action: { store.startLifeShapedSession() }
            )
            .padding(.horizontal, ForgeLayout.screenInset)
            voiceCoachBar
        }
    }

    /// Overlays — highest zIndex first.
    @ViewBuilder
    private var overlays: some View {
        if showSwapBanner, let swap = pendingSwap {
            SubstitutionBanner(target: swap, reason: swapReason,
                               onApply: { applySwap(swap) },
                               onDismiss: { withMotion { showSwapBanner = false } })
            .transition(overlayTransition(edge: .top)).zIndex(30)
        }
        if showPRBanner {
            PRBannerView(exerciseName: prExerciseName)
                .transition(overlayTransition(edge: .top)).zIndex(20)
        }
        if showSetLogger, let exercise = currentExercise {
            SetLoggerPanel(
                exercise: exercise, definition: currentDef, currentSet: store.currentSet,
                recommendation: recommendation,
                proposedReps: $loggedReps, proposedWeight: $currentWeight, proposedRPE: $loggedRPE,
                onConfirm: { confirmSet(exercise: exercise) },
                onCancel: { withMotion { showSetLogger = false } }
            )
            .transition(overlayTransition(edge: .bottom)).zIndex(15)
        }
        if showPainLogger, let exercise = currentExercise {
            PainLoggerPanel(
                exerciseName: exercise.name,
                onLog: { entry in handlePain(entry, exercise: exercise) },
                onCancel: { withMotion { showPainLogger = false } }
            )
            .transition(overlayTransition(edge: .bottom)).zIndex(15)
        }
    }

    private func liveContext(for exercise: Exercise) -> ARIALiveContext {
        ARIALiveContext(
            exerciseName: exercise.name,
            setLabel: "Set \(store.currentSet) of \(exercise.sets)",
            weight: currentWeight, reps: exercise.reps,
            heartRate: liveHeartRate, hrZone: liveZone, spO2: liveSpO2,
            elapsed: formatTime(elapsedSecs, flashColon: true),
            cues: currentDef?.cues ?? [])
    }

    // MARK: Cockpit Header

    private var cockpitHeader: some View {
        ForgeAdaptiveStack(spacing: FDS.Spacing.md) {
            HStack(spacing: FDS.Spacing.md) {
                zoneAccentBar
                headerTitleBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: FDS.Spacing.md) {
                elapsedTime
                endButton
            }
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, ForgeLayout.screenTop)
        .padding(.bottom, FDS.Spacing.sm)
    }

    private var zoneAccentBar: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(currentZone.color)
            .frame(width: 3, height: 36)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: currentZone.label)
            .accessibilityHidden(true)
    }

    private var headerSubtitle: String {
        let type = store.todayWorkout?.type.label ?? ""
        let intensity = store.todayWorkout?.intensity.label ?? ""
        return "\(type) · \(intensity)"
    }

    private var headerTitleBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
            Text(store.todayWorkout?.name ?? "")
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            Text(headerSubtitle)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// Plain metric text. The colon is stable, so numericText animates once a second.
    private var elapsedTime: some View {
        Text(formatTime(elapsedSecs, flashColon: true))
            .font(HomeType.metric)
            .monospacedDigit()
            .foregroundStyle(Color.textPrimary)
            .forgeSingleLine()
            .contentTransition(.numericText())
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Elapsed time")
            .accessibilityValue(spokenDuration(elapsedSecs))
    }

    private var endFill: Color {
        showEndConfirm ? Color.danger.opacity(0.16) : Color.white.opacity(0.08)
    }

    private var endStroke: Color {
        showEndConfirm ? Color.danger.opacity(0.32) : Color.white.opacity(0.12)
    }

    private var endButton: some View {
        Button(action: handleEnd) {
            Text(showEndConfirm ? "Confirm?" : "End")
                .font(HomeType.label)
                .foregroundStyle(showEndConfirm ? Color.danger : Color.textPrimary)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                .padding(.horizontal, FDS.Spacing.md)
                .frame(minWidth: ForgeUX.minTap, minHeight: ForgeUX.minTap)
                .background(endFill)
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                        .stroke(endStroke, lineWidth: ForgeUX.hairline)
                )
        }
        .buttonStyle(.plain)
        .animation(motionSnap, value: showEndConfirm)
        .accessibilityLabel(showEndConfirm ? "Confirm end session" : "End session")
        .accessibilityHint(showEndConfirm ? "Ends and saves this session to Apple Health" : "Activate twice to end and save this session")
    }

    // MARK: Exercise progress

    /// A 4 pt segmented row: ember for done and current, quiet for upcoming.
    private var exerciseProgressRow: some View {
        HStack(spacing: 3) {
            ForEach(exercises.indices, id: \.self) { idx in
                Capsule()
                    .fill(idx <= store.currentExerciseIndex ? Color.ember : Color.white.opacity(0.12))
                    .frame(height: 4)
            }
        }
        .animation(motionSnap, value: store.currentExerciseIndex)
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.bottom, FDS.Spacing.sm)
        .accessibilityElement()
        .accessibilityLabel("Exercise \(store.currentExerciseIndex + 1) of \(exercises.count)")
        .accessibilityValue(currentExercise?.name ?? "")
    }

    // MARK: Live Metrics Bar

    /// Fixed chrome: three equal columns that never re-column, so the height stays bounded.
    private var liveMetricsBar: some View {
        ForgeEqualColumnsLayout(columns: 3, spacing: ForgeLayout.tileGap) {
            liveMetricTiles
        }
        .environment(\.forgeFillsCell, true)
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.vertical, FDS.Spacing.sm)
    }

    @ViewBuilder
    private var liveMetricTiles: some View {
        heartRateTile
        energyTile
        volumeTile
    }

    /// Zone is derived from heart rate, so it reads as the tile's unit, not a second chip.
    private var heartRateTile: some View {
        ForgeStatTile(
            label: "Heart rate",
            value: simulatedHR > 0 ? "\(simulatedHR)" : "—",
            unit: heartRateIsLive ? currentZone.label : nil,
            energy: currentZone.color
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: currentZone.label)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(simulatedHR > 0
            ? "\(simulatedHR) beats per minute, \(currentZone.label)"
            : "No live heart rate from Apple Health")
    }

    private var energyTile: some View {
        ForgeStatTile(label: "Energy", value: "\(Int(estimatedCals))", unit: "kcal", energy: Color.ember)
            .accessibilityLabel("Energy burned")
            .accessibilityValue("\(Int(estimatedCals)) calories")
    }

    private var volumeTile: some View {
        ForgeStatTile(label: "Volume", value: "\(totalVolume.formattedVolume)", unit: "lb", energy: Color.steel)
            .accessibilityLabel("Session volume")
            .accessibilityValue("\(totalVolume) pounds")
    }

    // MARK: Main Content

    @ViewBuilder
    private func mainContent(exercise: Exercise) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: ForgeLayout.sectionGap) {
                if dynamicTypeSize.isAccessibilitySize {
                    ForgeStatGrid(columns: 3) { liveMetricTiles }
                        .padding(.horizontal, ForgeLayout.screenInset)
                        .padding(.top, ForgeLayout.screenTop)
                }
                if isResting {
                    RestTimerView(restTimeLeft: restTimeLeft, totalRest: restTotal,
                                  nextLabel: nextLabel(exercise: exercise), onSkip: skipRest)
                        .transition(restTransition)
                } else {
                    exerciseCard(exercise: exercise)
                        .transition(cardTransition)
                }
            }
        }
        .animation(motionStandard, value: isResting)
        .animation(motionStandard, value: store.currentExerciseIndex)
    }

    // MARK: Exercise Card

    /// Cockpit order: the set hero (load and reps), the Log Set primary, then coaching.
    private func exerciseCard(exercise: Exercise) -> some View {
        VStack(spacing: ForgeLayout.sectionGap) {
            setHeroPlate(exercise: exercise)
            actionButtons(exercise: exercise)
            coachingCard(exercise: exercise)
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 0 : ForgeLayout.screenTop)
        .padding(.bottom, ForgeLayout.scrollBottomClearance)
    }

    // MARK: Set hero

    private func setHeroPlate(exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            Text(exercise.name)
                .font(HomeType.sessionTitle)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            setProgressRow(exercise: exercise)
            if exercise.weight != nil {
                loadBlock(exercise: exercise)
                weightStepperRow
            } else {
                repsBlock(exercise: exercise)
            }
            ForgeChip(label: "\(recommendation.restSeconds)s rest", icon: "clock.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPlate(energy: Color.ember)
        .accessibilityElement(children: .contain)
    }

    private func setProgressPercent(exercise: Exercise) -> Int {
        let done = max(0, store.currentSet - 1)
        return min(100, done * 100 / max(1, exercise.sets))
    }

    private func setProgressRow(exercise: Exercise) -> some View {
        HStack(alignment: .center, spacing: ForgeLayout.rowGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("Set \(store.currentSet) of \(exercise.sets)")
                    .font(HomeType.cta)
                    .foregroundStyle(Color.ember)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                setDots(exercise: exercise)
            }
            Spacer(minLength: ForgeLayout.rowGap)
            HudProgressRing(
                progress: setProgressPercent(exercise: exercise),
                energy: Color.ember,
                size: 56,
                stroke: HudChrome.compactStroke,
                eventGlow: setLoggedPulse
            ) { EmptyView() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Set \(store.currentSet) of \(exercise.sets)")
        .accessibilityValue("\(max(0, store.currentSet - 1)) sets done")
    }

    private func setDotColor(_ index: Int) -> Color {
        if index < store.currentSet - 1 { return Color.vitality }
        if index == store.currentSet - 1 { return Color.ember }
        return Color.white.opacity(0.14)
    }

    private func setDots(exercise: Exercise) -> some View {
        HStack(spacing: ForgeLayout.pairGap) {
            ForEach(0..<exercise.sets, id: \.self) { i in
                Circle()
                    .fill(setDotColor(i))
                    .frame(width: 10, height: 10)
                    .animation(motionSnap, value: store.currentSet)
            }
        }
        .accessibilityHidden(true)
    }

    /// Numeric reps read as "× 8–10 reps"; anything else (a time, AMRAP) is shown as written.
    private func repsTargetLabel(_ reps: String) -> String {
        let numeric = !reps.isEmpty && reps.allSatisfy { $0.isNumber || $0 == "-" || $0 == "–" }
        guard numeric else { return "× \(reps)" }
        return "× \(reps.replacingOccurrences(of: "-", with: "–")) reps"
    }

    /// The in-session numeral exception: 58 pt rounded bold, one line, shrinks before it wraps.
    private func heroNumeral(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 58, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            .layoutPriority(1)
    }

    private func loadBlock(exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
                heroNumeral("\(currentWeight)")
                    .animation(motionSnap, value: currentWeight)
                Text("LBS")
                    .forgeSectionLabel(tint: Color.ember)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Working weight")
            .accessibilityValue("\(currentWeight) pounds")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: currentWeight += 5
                case .decrement: currentWeight = max(0, currentWeight - 5)
                @unknown default: break
                }
            }
            Text(repsTargetLabel(exercise.reps))
                .font(HomeType.metric)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func repsBlock(exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            heroNumeral(exercise.reps)
            Text("REPS")
                .forgeSectionLabel(tint: Color.ember)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target reps")
        .accessibilityValue(exercise.reps)
    }

    private var weightStepperRow: some View {
        HStack(spacing: ForgeLayout.tileGap) {
            weightStepButton(delta: -5)
            weightStepButton(delta: 5)
        }
    }

    private func weightStepButton(delta: Int) -> some View {
        let isPlus = delta > 0
        let tint: Color = isPlus ? Color.ember : Color.textPrimary
        let fill: Color = isPlus ? Color.ember.opacity(0.14) : Color.white.opacity(0.08)
        let edge: Color = isPlus ? Color.ember.opacity(0.32) : Color.white.opacity(0.12)
        return Button {
            currentWeight = max(0, currentWeight + delta)
            FDS.haptic(.press)
        } label: {
            Image(systemName: isPlus ? "plus" : "minus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                        .stroke(edge, lineWidth: ForgeUX.hairline)
                )
        }
        .buttonStyle(ForgePressStyle())
        .accessibilityLabel(isPlus ? "Increase weight by 5 pounds" : "Decrease weight by 5 pounds")
    }

    // MARK: Coaching card

    private func coachingCard(exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Coaching", tint: Color.ember)
            referenceBlock(exercise: exercise)
            evidenceBlock(exercise: exercise)
            demoBlock(exercise: exercise)
        }
        .forgeContentCard(tint: Color.ember)
    }

    private func referenceBlock(exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeSecondaryButton(title: "Show me how", icon: "books.vertical", accent: Color.ember) {
                store.showHowToPerform(exercise.name)
            }
            if let def = currentDef {
                muscleChips(def)
            }
            if let notes = exercise.notes {
                Text(notes)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
        }
    }

    private func muscleChips(_ def: ExerciseDefinition) -> some View {
        ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.chipGap) {
            ForEach(def.primary.prefix(3)) { m in
                ForgeChip(label: m.label, energy: m.accent, selected: true)
            }
            ForgeChip(label: "Tempo \(def.tempo)")
        }
    }

    private func evidenceBlock(exercise: Exercise) -> some View {
        let prevSets = setLog.filter { $0.exerciseName == exercise.name }
        return VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            if !prevSets.isEmpty {
                ledgerBlock(entries: prevSets)
            }
            AutoRegStrip(recommendation: recommendation)
        }
    }

    private func ledgerBlock(entries: [SetLogEntry]) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text("Previous sets")
                .forgeSectionLabel(tint: Color.textTertiary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                ForEach(entries) { entry in
                    ledgerRow(entry)
                }
            }
        }
    }

    private func ledgerSummary(_ entry: SetLogEntry) -> String {
        if entry.weightUsed > 0 {
            return "Set \(entry.setNumber) · \(entry.weightUsed) × \(entry.repsPerformed)"
        }
        return "Set \(entry.setNumber) · \(entry.repsPerformed) reps"
    }

    private func ledgerRow(_ entry: SetLogEntry) -> some View {
        let rpeText = Text("RPE \(entry.rpe)").foregroundStyle(rpeColor(entry.rpe))
        return HStack(spacing: FDS.Spacing.sm) {
            Text("\(ledgerSummary(entry)) · \(rpeText)")
                .font(HomeType.label)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            Spacer(minLength: FDS.Spacing.sm)
            if entry.isPersonalRecord {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.amber)
                    .accessibilityLabel("Personal record")
            }
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }

    private func demoBlock(exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeTextLink(title: "Technique", accent: Color.ember, expanded: showDemo) {
                withMotion { showDemo.toggle() }
            }
            if showDemo {
                ExerciseDemonstrationView(exercise: exercise, definition: currentDef, selectedTab: $selectedDemoTab,
                                          onLaunchCamera: { showFormCoach = true })
                    .transition(expandTransition)
            }
        }
    }

    // MARK: Action Buttons

    private func actionButtons(exercise: Exercise) -> some View {
        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx  = store.currentExerciseIndex >= exercises.count - 1
        let isFinish  = isLastSet && isLastEx
        let title = isFinish ? "Log & Finish" : isLastSet ? "Log Set · Next Exercise" : "Log Set"
        let icon = isFinish ? "checkmark.circle.fill" : "pencil.and.list.clipboard"
        let subtitle: String? = (isLastSet && !isLastEx) ? nextLabel(exercise: exercise) : nil
        return VStack(spacing: ForgeLayout.tileGap) {
            ForgePrimaryButton(title: title, icon: icon, accent: Color.ember, subtitle: subtitle) {
                beginSetLog(exercise: exercise)
            }
            ForgeSecondaryButton(title: "I feel another set", icon: "plus.circle.fill", accent: Color.steel) {
                store.addFeltSet(exerciseId: exercise.id)
            }
            .accessibilityLabel("Add a set because you feel it")
            .accessibilityHint("Adds one working set to this movement without undoing ARIA's scale")
            secondaryActionRow
        }
    }

    private var secondaryActionRow: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.tileGap, threshold: .xxxLarge) {
            ForgeSecondaryButton(title: "Skip", accent: Color.textSecondary) { skipExercise() }
            ForgeSecondaryButton(title: painLog.isEmpty ? "Pain" : "Pain (\(painLog.count))", accent: Color.amber) {
                withMotion { showPainLogger = true }
            }
            ForgeSecondaryButton(title: "Form", accent: Color.vitality) { showFormCoach = true }
        }
    }

    private func beginSetLog(exercise: Exercise) {
        loggedReps = recommendation.repTarget > 0 ? recommendation.repTarget : (Int(exercise.reps) ?? exercise.reps.repMidpoint)
        loggedRPE  = recommendation.rpeTarget
        withMotion { showSetLogger = true }
    }

    // MARK: Coach Bar (contextual, data-driven)

    private var liveCoachCues: [String] {
        var cues: [String] = []
        let voice = AriaVoiceEngine.speak(
            intent: .trainingPlan,
            context: store.makeTrainerContext(),
            input: currentExercise.map { "Cue me through \($0.name)" } ?? "What's the next set?",
            facts: AriaSpeechFacts()
        )
        if !voice.isEmpty { cues.append(voice) }
        cues.append(recommendation.rationale)
        if let def = currentDef { cues.append(contentsOf: def.cues) }
        if heartRateIsLive, currentZone.index >= 4 {
            cues.append("Heart rate is climbing — keep technique tight as you fatigue.")
        }
        return cues
    }

    private func syncVoiceCoach() {
        voiceCoach.updateContext(WorkoutContext(
            workoutName: store.todayWorkout?.name ?? "",
            exerciseName: currentExercise?.name ?? "",
            currentSet: store.currentSet,
            sets: currentExercise?.sets ?? 1,
            reps: currentExercise?.reps ?? "",
            weight: currentWeight > 0 ? "\(currentWeight)" : "",
            elapsedTime: formatTime(elapsedSecs, flashColon: false),
            heartRate: liveHeartRate,
            hrZone: liveZone,
            calories: Int(estimatedCals),
            restSeconds: currentExercise?.restSeconds ?? 90,
            notes: currentDef?.cues.first ?? liveCoachCues.first ?? ""
        ))
    }

    private func publishLiveActivity() {
        let type: ForgeWorkoutType = {
            switch store.todayWorkout?.type {
            case .cardio: return .cardio
            case .hiit: return .hiit
            case .yoga: return .yoga
            case .mobility: return .mobility
            default: return .strength
            }
        }()
        let state = WorkoutLiveState(
            workoutType: type,
            phase: isResting ? .resting : .active,
            startedAt: sessionStartedAt,
            elapsedSeconds: TimeInterval(elapsedSecs),
            heartRate: liveHeartRate.map { Double($0) },
            zoneNumber: liveZone,
            activeCalories: estimatedCals,
            currentExerciseName: currentExercise?.name,
            currentExerciseIndex: store.currentExerciseIndex,
            totalExercises: exercises.count,
            currentSetIndex: store.currentSet,
            totalSetsInExercise: currentExercise?.sets,
            restSecondsRemaining: isResting ? restTimeLeft : nil
        )
        Task { await WorkoutActivityCoordinator.shared.startOrUpdate(state) }
    }

    private var voiceCoachBar: some View {
        VoiceCoachBar(coach: voiceCoach)
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.vertical, FDS.Spacing.sm)
            .onChange(of: store.currentExerciseIndex) { _, _ in
                syncVoiceCoach()
                publishLiveActivity()
            }
            .onChange(of: store.currentSet) { _, _ in
                syncVoiceCoach()
                publishLiveActivity()
            }
    }

    // MARK: Logic

    /// Effort ramp: quiet, then amber, then ember. Never an error red.
    private func rpeColor(_ rpe: Int) -> Color { rpe <= 4 ? Color.textTertiary : rpe <= 7 ? Color.amber : Color.ember }
    private func setupCurrentWeight() { currentWeight = currentExercise?.weight ?? 0 }

    private func confirmSet(exercise: Exercise) {
        withMotion { showSetLogger = false }
        voiceCoach.announceSetComplete(
            setNumber: store.currentSet,
            totalSets: exercise.sets,
            restSeconds: exercise.restSeconds
        )
        syncVoiceCoach()
        let prev = setLog.filter { $0.exerciseName == exercise.name }
        let existingMax = prev.map { $0.weightUsed }.max() ?? 0
        let isPR = currentWeight > existingMax && currentWeight > 0

        // Auto-regulation logging: did load change vs the previous set on this lift?
        if let last = prev.last, last.weightUsed != currentWeight, currentWeight > 0 {
            let dir = currentWeight > last.weightUsed ? "↑" : "↓"
            autoRegLog.append("\(exercise.name): load \(last.weightUsed)→\(currentWeight) \(dir) (\(last.rpe >= 9 ? "RPE-capped" : "RPE-driven"))")
        }

        let entry = SetLogEntry(exerciseName: exercise.name, setNumber: store.currentSet,
                                repsPerformed: loggedReps, weightUsed: currentWeight, rpe: loggedRPE, isPersonalRecord: isPR)
        setLog.append(entry)
        totalVolume += entry.volume
        accrueMuscleVolume(for: exercise, volume: Double(max(entry.volume, loggedReps)))

        if isPR {
            prExerciseName = exercise.name
            withMotion(FDS.Spring.hero) { showPRBanner = true }
            Task { try? await Task.sleep(for: .seconds(2.5)); withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { showPRBanner = false } }
        }
        // Event moment: a logged set (or PR) fires the ring glow and a success haptic.
        FDS.haptic(.success)
        setLoggedPulse = true
        Task { try? await Task.sleep(for: .seconds(1.4)); setLoggedPulse = false }

        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx  = store.currentExerciseIndex >= exercises.count - 1
        if isLastSet && isLastEx {
            voiceCoach.announceWorkoutComplete(
                duration: formatTime(elapsedSecs, flashColon: false),
                calories: Int(estimatedCals)
            )
            endWorkout()
            return
        }
        let restFor = recommendation.restSeconds
        if isLastSet { store.nextExercise(); setupCurrentWeight() } else { store.nextSet() }
        startRest(seconds: restFor)
    }

    private func accrueMuscleVolume(for exercise: Exercise, volume: Double) {
        guard let def = ExerciseLibrary.definition(for: exercise) else { muscleVolume[.fullBody, default: 0] += volume; return }
        for m in def.primary { muscleVolume[m, default: 0] += volume }
        for m in def.secondary { muscleVolume[m, default: 0] += volume * 0.4 }
    }

    private func handlePain(_ entry: PainEntry, exercise: Exercise) {
        painLog.append(entry)
        withMotion { showPainLogger = false }
        FDS.haptic(.destructive)
        let def = ExerciseLibrary.definition(for: exercise)
        let contraindicated = def?.painContraindications.contains(entry.location) ?? false
        if entry.severity >= 7 || (entry.severity >= 5 && contraindicated) {
            if let swap = AdaptiveEngine.substitution(for: exercise, painLocation: entry.location) {
                pendingSwap = swap
                swapReason = "\(entry.location) at \(entry.severity)/10"
                withMotion { showSwapBanner = true }
                autoRegLog.append("\(entry.location) pain \(entry.severity)/10 → ARIA proposed \(swap.name)")
            }
        }
    }

    private func applySwap(_ def: ExerciseDefinition) {
        guard exercises.indices.contains(store.currentExerciseIndex) else { return }
        let old = exercises[store.currentExerciseIndex].name
        let new = Exercise(id: UUID().uuidString, name: def.name, sets: exercises[store.currentExerciseIndex].sets,
                           reps: def.repRangeLabel.replacingOccurrences(of: "–", with: "-"),
                           weight: def.equipment == .bodyweight ? nil : max(20, (exercises[store.currentExerciseIndex].weight ?? 45) * 7 / 10),
                           restSeconds: def.restSeconds, notes: def.cues.first, videoURL: nil, has3DModel: false)
        withMotion {
            store.todayWorkout?.exercises[store.currentExerciseIndex] = new
            store.currentSet = 1
            showSwapBanner = false
        }
        autoRegLog.append("Swapped \(old) → \(def.name) (\(swapReason))")
        setupCurrentWeight()
        FDS.haptic(.success)
    }

    private func endWorkout() {
        cancelTasks()
        HealthKitManager.shared.stopLiveHeartRateUpdates()
        // No live samples → no heart-rate numbers. `peakHR` starts at a placeholder;
        // it is not workout data.
        let avgHR  = hrHistory.isEmpty ? 0 : hrHistory.reduce(0, +) / hrHistory.count
        let sessionPeakHR = hrHistory.max() ?? 0
        let rpes   = setLog.map { Double($0.rpe) }
        let avgRPE = rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
        let prs    = Array(Set(setLog.filter { $0.isPersonalRecord }.map { $0.exerciseName }))
        let painFlags = Array(Set(painLog.map { "\($0.location) (\($0.severity)/10)" }))
        var mvStr: [String: Double] = [:]
        for (m, v) in muscleVolume { mvStr[m.rawValue] = v }
        let data = WorkoutSummaryData(
            duration: elapsedSecs, totalVolume: totalVolume, totalSets: setLog.count,
            totalReps: setLog.reduce(0) { $0 + $1.repsPerformed }, peakHR: sessionPeakHR, avgHR: avgHR,
            peakO2: 0, minO2: 0, caloriesBurned: Int(estimatedCals), personalRecords: prs,
            exercisesCompleted: min(store.currentExerciseIndex + 1, exercises.count), avgRPE: avgRPE, hrHistory: hrHistory,
            muscleVolume: mvStr, autoRegLog: autoRegLog, painFlags: painFlags,
            readiness: store.readiness.overall, workoutName: store.todayWorkout?.name ?? "Train")
        store.endWorkout(
            startedAt: sessionStartedAt,
            elapsedSeconds: elapsedSecs,
            energyKilocalories: estimatedCals
        )
        Task { await WorkoutActivityCoordinator.shared.finishActivity() }
        onWorkoutEnd(data)
    }

    private func skipExercise() {
        if store.currentExerciseIndex >= exercises.count - 1 { endWorkout() }
        else { store.nextExercise(); isResting = false; restTimeLeft = 0; restTask?.cancel(); setupCurrentWeight() }
    }
    private func skipRest() {
        restTask?.cancel(); restTask = nil
        withMotion { isResting = false }
        restTimeLeft = 0; FDS.haptic(.press)
        voiceCoach.announceRestOver(nextExerciseName: currentExercise?.name ?? "next lift")
        publishLiveActivity()
    }
    private func handleEnd() {
        if showEndConfirm { endWorkout() }
        else {
            showEndConfirm = true; FDS.haptic(.destructive)
            Task { try? await Task.sleep(for: .seconds(3)); showEndConfirm = false }
        }
    }
    private func startRest(seconds: Int) {
        restTotal = max(1, seconds); restTimeLeft = seconds
        withMotion { isResting = true }
        restTask?.cancel()
            restTask = Task {
            while restTimeLeft > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if restTimeLeft <= 1 {
                    restTimeLeft = 0
                    withMotion { isResting = false }
                    FDS.haptic(.success)
                    await MainActor.run {
                        voiceCoach.announceRestOver(nextExerciseName: currentExercise?.name ?? "next lift")
                        publishLiveActivity()
                    }
                    return
                }
                restTimeLeft -= 1
            }
        }
    }
    private func nextLabel(exercise: Exercise) -> String {
        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx  = store.currentExerciseIndex >= exercises.count - 1
        if isLastSet && isLastEx { return "Session complete" }
        if isLastSet {
            let next = exercises.indices.contains(store.currentExerciseIndex + 1) ? exercises[store.currentExerciseIndex + 1].name : "Done"
            return "Next: \(next)"
        }
        return "Set \(store.currentSet) of \(exercise.sets) done"
    }

    private func startHealthHeartRate() {
        // Only samples from this session count as live — an older one is
        // usually a resting reading and would be coached on as workout HR.
        let liveSince = sessionStartedAt.addingTimeInterval(-60)
        Task {
            if let bpm = await HealthKitManager.shared.latestHeartRateBPM(since: liveSince) {
                applyLiveHeartRate(bpm, warn: false)
            }
            HealthKitManager.shared.startLiveHeartRateUpdates(since: liveSince) { bpm in
                Task { @MainActor in
                    applyLiveHeartRate(bpm, warn: true)
                }
            }
        }
    }

    private func applyLiveHeartRate(_ bpm: Int, warn: Bool) {
        liveHeartRate = bpm
        heartRateIsLive = true
        simulatedHR = bpm
        hrHistory.append(bpm)
        if bpm > peakHR { peakHR = bpm }
        if warn, bpm >= 175, !didWarnHR {
            didWarnHR = true
            voiceCoach.announceHRWarning(hr: bpm)
        }
    }

    // MARK: Tasks

    private func startTasks() {
        elapsedTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                elapsedSecs += 1
                if elapsedSecs % 5 == 0 { publishLiveActivity() }
            }
        }
        calTask = Task {
            let weightKg = store.userProfile.weight ?? 80
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1)); guard !Task.isCancelled else { return }
                // MET-based expenditure: kcal/sec = MET · 3.5 · kg / 200 / 60, scaled by HR drive.
                let met = isResting ? 1.5 : (currentDef?.met ?? 5.0)
                let hrScale = simulatedHR > 150 ? 1.15 : simulatedHR > 130 ? 1.05 : 1.0
                estimatedCals += (met * 3.5 * weightKg / 200 / 60) * hrScale
            }
        }
    }
    private func cancelTasks() {
        [elapsedTask, calTask, restTask].forEach { $0?.cancel() }
        elapsedTask = nil; calTask = nil; restTask = nil
    }
    private func formatTime(_ s: Int, flashColon: Bool = true) -> String {
        // A plain space would give the clock a line-break opportunity, so a tight
        // header renders "00 / 14" stacked. U+00A0 blinks identically and can't wrap.
        let sep = flashColon ? ":" : "\u{00A0}"
        return String(format: "%02d\(sep)%02d", s / 60, s % 60)
    }

    /// VoiceOver reads "14 minutes 5 seconds" rather than spelling out "00:14:05".
    private func spokenDuration(_ s: Int) -> String {
        let minutes = s / 60, seconds = s % 60
        if minutes == 0 { return "\(seconds) second\(seconds == 1 ? "" : "s")" }
        return "\(minutes) minute\(minutes == 1 ? "" : "s") \(seconds) second\(seconds == 1 ? "" : "s")"
    }
}
