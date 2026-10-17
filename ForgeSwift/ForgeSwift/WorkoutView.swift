import SwiftUI
import UIKit
import ForgeCore

struct WorkoutView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var summaryData: WorkoutSummaryData? = nil
    @State private var showSummary = false

    private var swapAnimation: Animation? { reduceMotion ? nil : ForgeMotion.smooth }

    private func swapTransition(insertion: CGFloat, removal: CGFloat) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: insertion).combined(with: .opacity),
            removal: .scale(scale: removal).combined(with: .opacity)
        )
    }

    var body: some View {
        ZStack {
            if showSummary, let summary = summaryData {
                WorkoutSummaryView(data: summary, onDismiss: {
                    withAnimation(swapAnimation) {
                        showSummary = false; summaryData = nil
                    }
                })
                .transition(swapTransition(insertion: 0.94, removal: 1.04))
                .zIndex(10)
            } else if store.isWorkoutActive {
                ActiveWorkoutView { data in
                    summaryData = data
                    withAnimation(swapAnimation) { showSummary = true }
                }
                .transition(swapTransition(insertion: 0.96, removal: 1.04))
                .zIndex(5)
            } else {
                WorkoutIdleView()
                    .transition(swapTransition(insertion: 0.96, removal: 0.96))
                    .zIndex(1)
            }
        }
        .animation(swapAnimation, value: store.isWorkoutActive)
        .animation(swapAnimation, value: showSummary)
    }
}

struct WorkoutIdleView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var music = MusicControllerFactory.make(for: .appleMusic)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedExerciseIndex: Int? = nil
    @State private var showLibrary = false
    @State private var showDashboard = false
    @State private var showWeekPicker = false
    @State private var agingStamp = 0

    private var scaling: PlanScaling { AdaptiveEngine.scaling(readiness: store.readiness, experience: store.userProfile.experienceLevel) }

    private var todaySlot: WeeklySplitSlot {
        WeeklySplit.slot(for: WeeklySplit.sun0(from: Date()), in: store.userProfile.weeklySplit)
    }

    private var dayCall: TrainDayCall {
        TrainDayCall.resolve(
            readiness: store.readiness.overall,
            isRestDay: todaySlot.isRest,
            intensity: store.todayWorkout?.intensity
        )
    }

    private var aging: AgingSnapshot {
        AgingBridge.snapshot(
            age: store.userProfile.age,
            sexFemale: store.userProfile.biologicalSex == .female ? true
                : store.userProfile.biologicalSex == .male ? false : nil,
            stats: HealthKitManager.shared.todayStats
        )
    }

    /// Ember for a training day, steel for rest and easy.
    private var dayTone: Color {
        dayCall == .train ? Color.ember : Color.steel
    }

    var body: some View {
        VStack(spacing: 0) {
            todayRow
            if let workout = store.todayWorkout {
                scrollContent(workout: workout)
                dock(workout: workout)
            } else {
                WorkoutEmptyState()
            }
        }
        .forgeScreenBackground(accent: .ember)
        .sheet(isPresented: $showLibrary) { ExerciseLibraryView() }
        .sheet(isPresented: $showWeekPicker) {
            WeekSessionPicker { weekday in
                store.adoptSplitSession(weekday: weekday)
                showWeekPicker = false
            }
        }
        .sheet(item: $store.pendingShowHow) { def in
            ExerciseDetailSheet(def: def)
        }
        .sheet(isPresented: $showDashboard) {
            if let workout = store.todayWorkout {
                ARIADashboardView(snapshot: Self.plannedSnapshot(workout, readiness: store.readiness),
                                  isPreWorkout: true)
            }
        }
        .onAppear {
            if let current = store.todayWorkout, !current.autoScaled, scaling.isModified {
                store.todayWorkout = AdaptiveEngine.apply(
                    to: current,
                    readiness: store.readiness,
                    experience: store.userProfile.experienceLevel
                )
            }
            Task {
                await AriaAgingNorms.refresh()
                agingStamp += 1
            }
        }
    }

    // MARK: - Pinned TODAY row

    private var todayRow: some View {
        HStack {
            Text("TODAY")
                .forgeSectionLabel()
                .accessibilityAddTraits(.isHeader)
            Spacer()
            AriaTrainMuteButton()
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, ForgeLayout.screenTop)
    }

    // MARK: - Scroll content

    private func scrollContent(workout: WorkoutPlan) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                idleHero(workout: workout)

                if scaling.isModified {
                    AdaptiveScalingCard(scaling: scaling, applied: workout.autoScaled)
                }

                exerciseList(workout: workout)

                TrainDiscoveryCard()

                if typeSize.isAccessibilitySize {
                    compactToolbar(columns: 2)
                }
            }
            .forgeScreenInsets(top: FDS.Spacing.sm, bottom: ForgeLayout.rowGap)
        }
    }

    // MARK: - Dock (the Train exception: Start lives here)

    private func dock(workout: WorkoutPlan) -> some View {
        VStack(spacing: ForgeLayout.tileGap) {
            startButton(workout: workout)
            if !typeSize.isAccessibilitySize {
                compactToolbar(columns: 4)
            }
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, FDS.Spacing.sm)
        .padding(.bottom, FDS.Spacing.sm)
        .forgeBarChrome(edge: .bottom)
    }

    private func compactToolbar(columns: Int) -> some View {
        ForgeEqualColumnsLayout(columns: columns, spacing: ForgeLayout.tileGap) {
            toolbarCell(icon: "calendar", title: "Week", label: "Pick a session from this week") {
                showWeekPicker = true
            }
            toolbarCell(icon: "arrow.uturn.backward", title: "Yesterday", label: "Repeat yesterday's session") {
                store.adoptSplitSession(replayPrior: true)
            }
            toolbarCell(icon: "books.vertical.fill", title: "Library", label: "Open the exercise library") {
                showLibrary = true
            }
            toolbarCell(icon: "doc.text", title: "Brief", label: "Open the ARIA session brief") {
                showDashboard = true
            }
        }
    }

    private func toolbarCell(icon: String, title: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: ForgeLayout.pairGap) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(HomeType.micro)
                    .forgeSingleLine(minScale: 0.8)
            }
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, maxHeight: .infinity)
            .forgeWell(padding: FDS.Spacing.sm)
        }
        .buttonStyle(ForgePressStyle())
        .accessibilityLabel(label)
    }

    private func startButton(workout: WorkoutPlan) -> some View {
        ForgePrimaryButton(
            title: dayCall.cta,
            icon: "play.fill",
            accent: dayTone
        ) {
            if music.nowPlaying?.isPlaying == false { music.togglePlayPause() }
            withAnimation(reduceMotion ? nil : ForgeMotion.smooth) { store.startWorkout() }
        }
    }

    // MARK: - Hero

    private func idleHero(workout: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            heroEyebrowRow

            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(workout.name)
                    .font(ForgeType.pageTitle)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(headerWhy(workout))
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }

            ariaLine()

            factStrip(workout: workout)

            if aging.showsOnTrain {
                AgeCompareChip(snapshot: aging)
                    .id(agingStamp)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgePlate(energy: store.readiness.hasScore ? HomeReadiness.color(store.readiness.overall) : ForgeProgressChrome.miss)
        .accessibilityElement(children: .contain)
    }

    private var heroEyebrowRow: some View {
        let score = store.readiness.overall
        return ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
            Text(dayCall.title)
                .forgeSectionLabel(tint: dayTone)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Unmeasured readiness reads "—", never a 0 score.
            ForgeVibeChip(
                label: store.readiness.hasScore ? "\(score) · \(HomeReadiness.label(score))" : "Readiness —",
                energy: store.readiness.hasScore ? HomeReadiness.color(score) : ForgeProgressChrome.miss
            )
                .lineLimit(1)
                .layoutPriority(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(store.readiness.hasScore ? HomeReadiness.voiceOverLabel(score) : "Readiness not measured yet")
        }
    }

    private func factStrip(workout: WorkoutPlan) -> some View {
        ForgeStatGrid(columns: 3) {
            ForgeStatTile(label: "Duration", value: "\(workout.duration)", unit: "min", energy: .ember, icon: "clock.fill")
            ForgeStatTile(label: "Moves", value: "\(workout.exercises.count)", energy: .ember, icon: "list.bullet")
            ForgeStatTile(label: "Intensity", value: workout.intensity.label, energy: workout.intensity.color, icon: "flame.fill")
        }
    }

    private func headerWhy(_ workout: WorkoutPlan) -> String {
        if dayCall == .rest {
            return todaySlot.isRest
                ? "The week called rest. Easy core is on the board if you want it — nothing to prove."
                : "Today is rest-shaped. Move well or skip."
        }
        if let headline = workout.scaleHeadline, workout.autoScaled {
            return headline
        }
        return "\(workout.type.label) · ~\(workout.duration) min. One session, then you’re done."
    }

    private func ariaLine() -> some View {
        let line: String = {
            if !aging.trainingHint.isEmpty { return aging.trainingHint }
            let facts = AriaSpeechFacts()
            return AriaVoiceEngine.speak(
                intent: .trainingPlan,
                context: store.makeTrainerContext(),
                input: "What's on my board?",
                facts: facts
            )
        }()
        return Text(line)
            .font(HomeType.body)
            .foregroundStyle(Color.textTertiary)
            .forgeWrapping()
            .task { store.shareWorkoutInsightsIfNeeded([line]) }
    }

    // MARK: - Exercise list

    private func toggleExercise(_ idx: Int) {
        withAnimation(reduceMotion ? nil : ForgeMotion.smooth) {
            selectedExerciseIndex = selectedExerciseIndex == idx ? nil : idx
        }
    }

    private func exerciseList(workout: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Exercises", meta: "\(workout.exercises.count) total", metaColor: .textTertiary)
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { idx, ex in
                    WorkoutExerciseRow(
                        exercise: ex,
                        index: idx,
                        isExpanded: selectedExerciseIndex == idx,
                        onTap: { toggleExercise(idx) }
                    )
                }
            }
        }
        .forgeContentCard(tint: .ember)
    }

    /// Build a pre-workout snapshot purely from the plan (estimated muscle distribution).
    static func plannedSnapshot(_ workout: WorkoutPlan, readiness: ReadinessData) -> ARIASessionSnapshot {
        var mv: [TargetMuscle: Double] = [:]
        var volume = 0
        for ex in workout.exercises {
            let reps = Int(ex.reps) ?? ex.reps.repMidpoint
            volume += ex.sets * reps * (ex.weight ?? 0)
            let setLoad = Double(ex.sets) * (ex.weight.map { Double($0) } ?? 8)
            if let def = ExerciseLibrary.definition(for: ex) {
                for m in def.primary { mv[m, default: 0] += setLoad }
                for m in def.secondary { mv[m, default: 0] += setLoad * 0.4 }
            } else {
                mv[.fullBody, default: 0] += setLoad
            }
        }
        return ARIASessionSnapshot(
            title: workout.name, durationSec: workout.duration * 60, totalVolume: volume,
            totalSets: workout.exercises.reduce(0) { $0 + $1.sets },
            totalReps: workout.exercises.reduce(0) { $0 + $1.sets * (Int($1.reps) ?? $1.reps.repMidpoint) },
            exercisesCompleted: workout.exercises.count, avgHR: 0, peakHR: 0, minO2: 98, avgRPE: 0,
            calories: workout.estimatedCalories, readiness: readiness.overall, muscleVolume: mv,
            zoneSeconds: [0, 0, 0, 0, 0], autoRegLog: [], painFlags: [], personalRecords: [])
    }
}

private struct AdaptiveScalingCard: View {
    let scaling: PlanScaling
    let applied: Bool

    private var volumeLabel: String { "Volume \(Int(scaling.volumeMultiplier * 100))%" }

    private var appliedLine: String {
        applied
            ? "ARIA already scaled this session. Add a set in Train if you feel it."
            : "ARIA scaled this from readiness — it's already on the board."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "ARIA auto-scale", tint: .textTertiary) {
                ForgeChip(label: volumeLabel, energy: .steel, selected: true)
            }
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(scaling.headline)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(scaling.detail)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.steel)
                    .accessibilityHidden(true)
                Text(appliedLine)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
        }
        .forgeContentCard(tint: .steel)
    }
}

/// Static ambient wash. Active workout tints it by heart-rate zone; the
/// color change fades unless Reduce Motion is on. No idle animation.
struct WorkoutBackground: View {
    let accentColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.background
            mesh
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.6), value: accentColor)
    }

    private var mesh: some View {
        Canvas { ctx, size in
            let x1 = size.width  * 0.15
            let y1 = size.height * 0.12
            let r1 = size.width  * 0.55
            var p1 = Path(); p1.addEllipse(in: CGRect(x: x1-r1/2, y: y1-r1/2, width: r1, height: r1))
            ctx.fill(p1, with: .color(accentColor.opacity(0.045)))
            let x2 = size.width  * 0.82
            let y2 = size.height * 0.75
            let r2 = size.width  * 0.48
            var p2 = Path(); p2.addEllipse(in: CGRect(x: x2-r2/2, y: y2-r2/2, width: r2, height: r2))
            ctx.fill(p2, with: .color(Color.steel.opacity(0.028)))
            let x3 = size.width  * 0.5
            let y3 = size.height * 0.45
            let r3 = size.width  * 0.38
            var p3 = Path(); p3.addEllipse(in: CGRect(x: x3-r3/2, y: y3-r3/2, width: r3, height: r3))
            ctx.fill(p3, with: .color(accentColor.opacity(0.025)))
        }
    }
}

struct AgeCompareChip: View {
    let snapshot: AgingSnapshot

    private var line: String {
        snapshot.oneBreathLine.isEmpty ? snapshot.comparisonLine : snapshot.oneBreathLine
    }

    var body: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap, alignment: .center) {
            sentenceBlock
                .frame(maxWidth: .infinity, alignment: .leading)
            ageNumbers
        }
        .padding(.horizontal, ForgeLayout.compactCardPadding)
        .padding(.vertical, ForgeLayout.tilePadding)
        .background(tone.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
                .stroke(tone.opacity(0.28), lineWidth: ForgeUX.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            snapshot.oneBreathLine.isEmpty
                ? "Training age compared with calendar age. \(snapshot.comparisonLine)"
                : snapshot.oneBreathLine
        )
    }

    private var sentenceBlock: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text("Heart")
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                Text(line)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                if AgingNorms.webConfirmed {
                    Text("Public cardio norms")
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var ageNumbers: some View {
        if let chrono = snapshot.chronologicalAge, let bio = snapshot.biologicalAge, snapshot.confidence > 0.25 {
            HStack(alignment: .firstTextBaseline, spacing: ForgeLayout.pairGap) {
                Text("\(Int(bio.rounded()))")
                    .font(HomeType.metric)
                    .foregroundStyle(tone)
                    .forgeSingleLine()
                    .layoutPriority(1)
                Text("/ \(Int(chrono.rounded()))")
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .forgeSingleLine()
                    .layoutPriority(1)
            }
        }
    }

    private var tone: Color {
        switch snapshot.state {
        case .younger: return Color.vitality
        case .older: return Color.amber
        case .matched, .unknown: return Color.steel
        }
    }
}

struct WorkoutExerciseRow: View {
    let exercise: Exercise; let index: Int
    let isExpanded: Bool; let onTap: () -> Void
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var wellSize: CGFloat = 36

    private var def: ExerciseDefinition? { ExerciseLibrary.definition(for: exercise) }
    private var accent: Color { def?.accent ?? Color.ember }

    private var metaLine: String {
        var parts: [String] = ["\(exercise.sets) × \(exercise.reps)"]
        if let w = exercise.weight { parts.append("\(w) lb") }
        if let muscle = def?.primary.first?.label, !muscle.isEmpty { parts.append(muscle) }
        return parts.joined(separator: " · ")
    }

    private var expandTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Button(action: onTap) {
                header
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(index + 1), \(exercise.name), \(metaLine)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Hides details" : "Shows form cues and equipment")

            if isExpanded {
                expandedContent
                    .transition(expandTransition)
            }
        }
        .animation(reduceMotion ? nil : ForgeMotion.smooth, value: isExpanded)
    }

    // MARK: Header (the only part that toggles)

    private var header: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            indexWell
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(exercise.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(isExpanded ? nil : 2)
                Text(metaLine)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .monospacedDigit()
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            }
            .layoutPriority(1)
            Spacer(minLength: FDS.Spacing.xs)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var indexWell: some View {
        let size = ForgeLayout.scaledCap(wellSize, base: 36)
        return ZStack {
            Circle().fill(accent.opacity(0.16))
            Text("\(index + 1)")
                .font(HomeType.label)
                .foregroundStyle(accent)
                .monospacedDigit()
                .forgeGlanceText()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Expanded content (a sibling of the toggle, never inside it)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            if let def {
                mechanics(def)
            }
            if let notes = exercise.notes {
                cueRow(icon: "info.circle.fill", color: Color.steel, text: notes)
            }
            restLine
            ForgeSecondaryButton(title: "Show me how", icon: "play.circle", accent: .ember) {
                store.showHowToPerform(exercise.name)
            }
        }
    }

    @ViewBuilder
    private func mechanics(_ def: ExerciseDefinition) -> some View {
        ForgeFlowLayout {
            ForgeChip(label: def.pattern.label, icon: "arrow.triangle.branch")
            ForgeChip(label: def.equipment.label, icon: def.equipment.icon)
            ForgeChip(label: def.isCompound ? "Compound" : "Isolation", icon: "square.stack.3d.up.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if let cue = def.cues.first {
            cueRow(icon: "checkmark.circle.fill", color: def.accent, text: cue)
        }
        if let fault = def.faults.first {
            cueRow(icon: "exclamationmark.triangle.fill", color: Color.amber, text: "Avoid: \(fault)")
        }
    }

    private var restLine: some View {
        HStack(spacing: FDS.Spacing.sm) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
            Text("\(exercise.restSeconds)s rest between sets")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func cueRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: FDS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }
}

struct WeekSessionPicker: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let onPick: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(WeeklySplit.normalized(store.userProfile.weeklySplit)) { slot in
                    weekRow(slot)
                        .listRowBackground(Color.white.opacity(0.045))
                }
            }
            .scrollContentBackground(.hidden)
            .forgeScreenBackground(accent: .ember)
            .navigationTitle("This week")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func weekRow(_ slot: WeeklySplitSlot) -> some View {
        let isToday = slot.weekday == WeeklySplit.sun0(from: Date())
        let subtitle = slot.isRest ? "Rest · easy core if you want it" : "\(slot.title) · \(slot.exerciseCount) exercises"
        return Button {
            ForgeHaptics.play(.selection)
            onPick(slot.weekday)
        } label: {
            ForgeListRow(
                icon: slot.isRest ? "moon.zzz.fill" : "dumbbell.fill",
                iconColor: slot.isRest ? Color.steel : Color.ember,
                title: WeeklySplit.dayNames[slot.weekday],
                subtitle: subtitle,
                trailing: isToday ? "Today" : nil,
                showChevron: true
            )
        }
        .buttonStyle(.plain)
    }
}

struct WorkoutEmptyState: View {
    @EnvironmentObject var store: AppStore
    @State private var showLibrary = false
    @State private var agingStamp = 0

    private var aging: AgingSnapshot {
        AgingBridge.snapshot(
            age: store.userProfile.age,
            sexFemale: store.userProfile.biologicalSex == .female ? true
                : store.userProfile.biologicalSex == .male ? false : nil,
            stats: HealthKitManager.shared.todayStats
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .sheet(isPresented: $showLibrary) { ExerciseLibraryView() }
        .onAppear {
            Task {
                await AriaAgingNorms.refresh()
                agingStamp += 1
            }
        }
    }

    private var content: some View {
        VStack(spacing: ForgeLayout.sectionGap) {
            ForgeIconWell(systemImage: "dumbbell.fill", tint: .ember, diameter: 72)
            VStack(spacing: FDS.Spacing.md) {
                Text("No session on the board")
                    .font(ForgeType.pageTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
                    .accessibilityAddTraits(.isHeader)
                Text("ARIA writes a session from sleep, readiness, and the week you actually have — preview it here, then start when you’re ready.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
                    .padding(.horizontal, FDS.Spacing.xl)
            }
            if aging.showsOnTrain {
                AgeCompareChip(snapshot: aging)
                    .id(agingStamp)
            }
            VStack(spacing: ForgeLayout.tileGap) {
                ForgePrimaryButton(title: "Write today’s session", icon: "square.and.pencil") {
                    store.rebuildTodayPlanFromLife()
                }
                ForgeSecondaryButton(title: "Browse the library", icon: "books.vertical.fill", accent: .steel) {
                    showLibrary = true
                }
            }
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.vertical, ForgeLayout.sectionGap)
    }
}

/// Rank unused catalog moves that fit gym and gear. Inspectable score.
struct TrainDiscoveryCard: View {
    @EnvironmentObject var store: AppStore
    @State private var memory = ForgeExerciseDiscovery.Memory()
    @State private var ranked: [ForgeExerciseDiscovery.Candidate] = []

    private static let storageKey = "forge.exercise.discovery.v1"

    var body: some View {
        Group {
            if let top = ranked.first {
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(ForgeExerciseDiscovery.suggestLine)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                    Text(top.name)
                        .font(ForgeType.title)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    Text(top.reasons.joined(separator: " · "))
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                        .accessibilityLabel(top.scoreLabel)
                    if !memory.saved.isEmpty {
                        Text("Saved for later: \(memory.saved.count)")
                            .font(HomeType.micro)
                            .foregroundStyle(Color.textTertiary)
                    }
                    ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
                        ForgeSecondaryButton(title: "Tried", accent: .ember) {
                            apply(.tried, id: top.id)
                        }
                        ForgeSecondaryButton(title: "Not interested", accent: .steel) {
                            apply(.notInterested, id: top.id)
                        }
                        ForgeSecondaryButton(title: "Save for later", accent: .steel) {
                            apply(.saved, id: top.id)
                        }
                    }
                }
                .forgePlate(energy: .ember)
                .accessibilityElement(children: .contain)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        if ForgeRuntimeGuard.shouldShed(
            thermal: thermalLabel,
            memoryWarning: false
        ) {
            ranked = []
            return
        }
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(ForgeExerciseDiscovery.Memory.self, from: data) {
            memory = decoded
        }
        memory.gymType = store.userProfile.trainingEquipment.rawValue
        memory.equipmentNotes = store.userProfile.equipmentNotes
        let catalog = catalogFromLibrary()
        ranked = Array(ForgeExerciseDiscovery.rank(
            catalog: catalog,
            memory: memory,
            trainingModel: store.userProfile.coachingPersonality.adaptiveTrainingModel,
            goals: store.userProfile.fitnessGoals.map(\.rawValue) + store.userProfile.fitnessGoals.map(\.label),
            readiness: store.readiness.overall,
            load: min(100, store.workoutHistory.count * 8),
            engagement: min(1, Double(memory.tried.count) / 10.0),
            conditions: store.userProfile.lifestyleProfile.healthConstraints,
            freeform: store.userProfile.lifestyleProfile.healthNote
        ).prefix(8))
    }

    private func catalogFromLibrary() -> [ForgeExerciseDiscovery.Exercise] {
        ExerciseLibrary.all.map {
            ForgeExerciseDiscovery.Exercise(
                id: $0.id,
                name: $0.name,
                equipment: $0.equipment.rawValue,
                triedBefore: memory.tried.contains($0.id)
            )
        }
    }

    private func apply(_ feedback: ForgeExerciseDiscovery.Feedback, id: String) {
        memory = ForgeExerciseDiscovery.applyFeedback(
            memory, id: id, feedback: feedback, catalog: catalogFromLibrary()
        )
        if let data = try? JSONEncoder().encode(memory) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        reload()
    }

    private var thermalLabel: String {
        switch ProcessInfo.processInfo.thermalState {
        case .serious: return "serious"
        case .critical: return "critical"
        default: return "nominal"
        }
    }
}
