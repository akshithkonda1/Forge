import SwiftUI
import UIKit

@MainActor
struct ActiveWorkoutView: View {
    @EnvironmentObject var store: AppStore
    /// The decorative pulses here redraw ~20x a second for the whole session.
    /// Honouring Reduce Motion turns them off — kinder to watch, kinder to battery.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onWorkoutEnd: (WorkoutSummaryData) -> Void

    // Bio metrics
    @State private var elapsedSecs:    Int    = 0
    @State private var simulatedHR:    Int    = 72
    @State private var peakHR:         Int    = 72
    @State private var hrHistory:      [Int]  = []
    @State private var estimatedCals:  Double = 0
    @State private var simulatedSpO2:  Int    = 98
    @State private var peakSpO2:       Int    = 98
    @State private var minSpO2:        Int    = 98
    @State private var showO2Warning:  Bool   = false

    // Rest
    @State private var isResting:      Bool   = false
    @State private var restTimeLeft:   Int    = 0
    @State private var restTotal:      Int    = 90

    // Coach
    @State private var coachIndex:     Int    = 0

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
    @StateObject private var aria = ARIACoachService()
    @State private var voiceCoach = VoiceCoachManager()
    @State private var autoRegLog:     [String] = []
    @State private var muscleVolume:   [TargetMuscle: Double] = [:]
    @State private var pendingSwap:    ExerciseDefinition? = nil
    @State private var swapReason:     String = ""
    @State private var showSwapBanner: Bool   = false
    @State private var showFormCoach:  Bool   = false

    // End
    @State private var showEndConfirm: Bool   = false

    // Volume
    @State private var totalVolume:    Int    = 0

    // Demo
    @State private var selectedDemoTab: ExerciseDemoTab = .video

    // Music
    @StateObject private var music = MusicControllerFactory.make(for: .appleMusic)

    // Tasks
    @State private var elapsedTask: Task<Void, Never>? = nil
    @State private var hrTask:      Task<Void, Never>? = nil
    @State private var calTask:     Task<Void, Never>? = nil
    @State private var o2Task:      Task<Void, Never>? = nil
    @State private var restTask:    Task<Void, Never>? = nil
    @State private var coachTask:   Task<Void, Never>? = nil

    private var exercises:       [Exercise] { store.todayWorkout?.exercises ?? [] }
    private var currentExercise: Exercise?  { exercises.indices.contains(store.currentExerciseIndex) ? exercises[store.currentExerciseIndex] : nil }
    private var currentZone: WorkoutHRZone { WorkoutHRZone.zone(for: simulatedHR) }
    private var currentDef: ExerciseDefinition? { currentExercise.flatMap { ExerciseLibrary.definition(for: $0) } }

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
            currentHR: simulatedHR, hrZone: currentZone.index, spO2: simulatedSpO2,
            painSeverity: pain, painLocation: painLoc)
    }

    var body: some View {
        ZStack {
            WorkoutBackground(accentColor: currentZone.color).ignoresSafeArea()

            if let exercise = currentExercise {
                VStack(spacing: 0) {
                    cockpitHeader
                    exerciseNavStrip
                    liveMetricsBar
                    MusicControlBar(controller: music, compact: true)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                    mainContent(exercise: exercise)
                    voiceCoachBar
                }
            } else {
                ForgeEmptyStateCard(
                    icon: "figure.strengthtraining.traditional",
                    title: "Today’s session",
                    message: "ARIA writes this from how you live — sleep, cycle, gear, readiness. Not a catalog.",
                    cta: "Write session",
                    action: { store.startLifeShapedSession() }
                )
                .padding(24)
            }

            // Overlays — highest zIndex first
            if showSwapBanner, let swap = pendingSwap {
                SubstitutionBanner(target: swap, reason: swapReason,
                                   onApply: { applySwap(swap) },
                                   onDismiss: { withAnimation { showSwapBanner = false } })
                .transition(.move(edge: .top).combined(with: .opacity)).zIndex(30)
            }
            if showO2Warning {
                O2WarningBanner(spO2: simulatedSpO2) { withAnimation { showO2Warning = false } }
                .transition(.move(edge: .top).combined(with: .opacity)).zIndex(25)
            }
            if showPRBanner {
                PRBannerView(exerciseName: prExerciseName)
                    .transition(.move(edge: .top).combined(with: .opacity)).zIndex(20)
            }
            if showSetLogger, let exercise = currentExercise {
                SetLoggerPanel(
                    exercise: exercise, definition: currentDef, currentSet: store.currentSet,
                    recommendation: recommendation,
                    proposedReps: $loggedReps, proposedWeight: $currentWeight, proposedRPE: $loggedRPE,
                    onConfirm: { confirmSet(exercise: exercise) },
                    onCancel: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showSetLogger = false } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity)).zIndex(15)
            }
            if showPainLogger, let exercise = currentExercise {
                PainLoggerPanel(
                    exerciseName: exercise.name,
                    onLog: { entry in handlePain(entry, exercise: exercise) },
                    onCancel: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showPainLogger = false } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity)).zIndex(15)
            }
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
            startTasks()
            setupCurrentWeight()
            if store.dailyMetrics.restingHR > 0 {
                simulatedHR = max(simulatedHR, store.dailyMetrics.restingHR)
            }
            syncVoiceCoach()
            voiceCoach.announceWorkoutStart()
        }
        .onDisappear { cancelTasks() }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showPRBanner)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showO2Warning)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showSwapBanner)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showSetLogger)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showPainLogger)
    }

    private func liveContext(for exercise: Exercise) -> ARIALiveContext {
        ARIALiveContext(
            exerciseName: exercise.name,
            setLabel: "Set \(store.currentSet) of \(exercise.sets)",
            weight: currentWeight, reps: exercise.reps,
            heartRate: simulatedHR, hrZone: currentZone.index, spO2: simulatedSpO2,
            elapsed: formatTime(elapsedSecs, flashColon: true),
            cues: currentDef?.cues ?? [])
    }

    // MARK: Cockpit Header

    private var cockpitHeader: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(currentZone.color).frame(width: 3, height: 36)
                .shadow(color: currentZone.color.opacity(0.8), radius: 6)
                .animation(.easeInOut(duration: 0.8), value: currentZone.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.todayWorkout?.name ?? "").font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                HStack(spacing: 5) {
                    Text(store.todayWorkout?.type.label ?? "").font(.system(size: 11)).foregroundColor(.textTertiary)
                    Circle().fill(Color.textTertiary.opacity(0.5)).frame(width: 2.5, height: 2.5)
                    Text(store.todayWorkout?.intensity.label ?? "").font(.system(size: 11, weight: .semibold)).foregroundColor(currentZone.color)
                        .animation(.easeInOut(duration: 0.8), value: currentZone.label)
                }
                .lineLimit(1)
            }
            // The title is the only elastic element up here — everything to its right
            // keeps its intrinsic width, so a long workout name truncates instead of
            // crushing the clock and End button into wrapped columns of letters.
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                elapsedChip
                endButton
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }

    private var elapsedChip: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { tl in
            let flash = Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            HStack(spacing: 4) {
                Image(systemName: "clock.fill").font(.system(size: 10)).foregroundColor(.textMuted)
                Text(formatTime(elapsedSecs, flashColon: flash))
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary)
                    .lineLimit(1).contentTransition(.numericText())
            }
            .padding(.horizontal, 10).padding(.vertical, 6).background(Color.surface).cornerRadius(100)
            .overlay(Capsule().stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elapsed time")
        .accessibilityValue(spokenDuration(elapsedSecs))
    }

    private var endButton: some View {
        Button(action: handleEnd) {
            Text(showEndConfirm ? "Confirm?" : "End")
                .font(.system(size: 13, weight: .bold)).foregroundColor(showEndConfirm ? .white : .danger)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(showEndConfirm ? Color.danger : Color.danger.opacity(0.12)).cornerRadius(9)
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: showEndConfirm)
        }
        .accessibilityLabel(showEndConfirm ? "Confirm end workout" : "End workout")
        .accessibilityHint(showEndConfirm ? "Ends and saves this session" : "Activate twice to end and save this session")
    }

    // MARK: Nav Strip

    private var exerciseNavStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { idx, ex in
                        HStack(spacing: 4) {
                            navDot(idx: idx, name: ex.name).id(idx)
                            if idx < exercises.count - 1 {
                                Rectangle().fill(idx < store.currentExerciseIndex ? Color.ember.opacity(0.6) : Color.borderColor.opacity(0.25)).frame(width: 12, height: 1.5)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }
            .scrollEdgeFade()
            .onChange(of: store.currentExerciseIndex) { _, newIdx in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { proxy.scrollTo(newIdx, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func navDot(idx: Int, name: String) -> some View {
        let isCurrent = idx == store.currentExerciseIndex
        let isPast    = idx <  store.currentExerciseIndex
        Group {
            if isCurrent {
                HStack(spacing: 7) {
                    if reduceMotion {
                        Circle().fill(Color.ember).frame(width: 8, height: 8).shadow(color: Color.ember.opacity(0.7), radius: 4)
                    } else {
                        TimelineView(.animation(minimumInterval: 0.05)) { tl in
                            let p = (sin(tl.date.timeIntervalSinceReferenceDate * 2.5) + 1) / 2
                            Circle().fill(Color.ember).frame(width: 8, height: 8).shadow(color: Color.ember.opacity(0.5 + p * 0.4), radius: 3 + p * 3)
                        }
                    }
                    Text(name).font(.system(size: 12, weight: .bold)).foregroundColor(.ember).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 7).background(Color.ember.opacity(0.1)).cornerRadius(100)
                .overlay(Capsule().stroke(Color.ember.opacity(0.35), lineWidth: 1)).shadow(color: Color.ember.opacity(0.2), radius: 6)
            } else if isPast {
                ZStack {
                    Circle().fill(Color.success.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundColor(.success)
                }
            } else {
                ZStack {
                    Circle().fill(Color.surfaceElevated).frame(width: 28, height: 28).overlay(Circle().stroke(Color.borderColor.opacity(0.6), lineWidth: 1))
                    Text("\(idx+1)").font(.system(size: 10, weight: .semibold)).foregroundColor(.textMuted)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: store.currentExerciseIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exercise \(idx + 1) of \(exercises.count), \(name)")
        .accessibilityValue(isPast ? "Completed" : isCurrent ? "In progress" : "Upcoming")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // MARK: Live Metrics Bar

    private var liveMetricsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                heartRateChip
                let o2Color: Color = simulatedSpO2 < 94 ? .danger : simulatedSpO2 < 96 ? .warning : Color(hex: "38BDF8")
                primaryMetricChip(icon: "lungs.fill", iconColor: o2Color, value: "\(simulatedSpO2)%", unit: "O₂", accent: o2Color, glowing: simulatedSpO2 < 95)
                    .accessibilityLabel("Blood oxygen")
                    .accessibilityValue("\(simulatedSpO2) percent")
                liveChip(icon: "flame.fill", iconColor: .ember, value: "\(Int(estimatedCals))", unit: "kcal", accent: .ember)
                    .accessibilityLabel("Energy burned")
                    .accessibilityValue("\(Int(estimatedCals)) calories")
                liveChip(icon: "scalemass.fill", iconColor: .steel, value: "\(totalVolume.formattedVolume)", unit: "vol", accent: .steel)
                    .accessibilityLabel("Session volume")
                    .accessibilityValue("\(totalVolume) pounds")
                if let bpm = music.nowPlaying?.bpm {
                    liveChip(icon: "music.note", iconColor: Color(hex: "1DB954"), value: "\(bpm)", unit: "BPM", accent: Color(hex: "1DB954"))
                        .accessibilityLabel("Track tempo")
                        .accessibilityValue("\(bpm) beats per minute")
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollEdgeFade()
        .padding(.vertical, 6)
    }

    /// Zone is derived from heart rate, so it reads as one fact, not two chips.
    /// Merging them also buys back the width that pushed the row off-screen.
    private var heartRateChip: some View {
        HStack(spacing: 6) {
            if reduceMotion {
                Image(systemName: "heart.fill").font(.system(size: 14)).foregroundColor(currentZone.color)
            } else {
                TimelineView(.animation(minimumInterval: 0.05)) { tl in
                    let p = (sin(tl.date.timeIntervalSinceReferenceDate * 3) + 1) / 2
                    Image(systemName: "heart.fill").font(.system(size: 14)).foregroundColor(currentZone.color)
                        .scaleEffect(1 + p * 0.16)
                        .shadow(color: currentZone.color.opacity(0.5 + p * 0.3), radius: 4)
                }
                .fixedSize()
            }
            Text("\(simulatedHR)").font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.textPrimary).contentTransition(.numericText())
            Text("bpm").font(.system(size: 11, weight: .semibold)).foregroundColor(currentZone.color.opacity(0.8))
            Rectangle().fill(currentZone.color.opacity(0.28)).frame(width: 1, height: 13).padding(.horizontal, 2)
            Text(currentZone.label).font(.system(size: 12, weight: .black)).foregroundColor(currentZone.color)
        }
        .lineLimit(1).fixedSize()
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(ZStack { Color.surface; currentZone.color.opacity(0.08) }).cornerRadius(100)
        .overlay(Capsule().stroke(currentZone.color.opacity(simulatedHR > 140 ? 0.5 : 0.25), lineWidth: simulatedHR > 140 ? 1.5 : 1))
        .shadow(color: simulatedHR > 140 ? currentZone.color.opacity(0.3) : .clear, radius: 8)
        .animation(.easeInOut(duration: 0.7), value: currentZone.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue("\(simulatedHR) beats per minute, \(currentZone.label)")
    }

    @ViewBuilder
    private func primaryMetricChip(icon: String, iconColor: Color, value: String, unit: String, accent: Color, glowing: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(iconColor)
            Text(value).font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.textPrimary).contentTransition(.numericText())
            Text(unit).font(.system(size: 11, weight: .semibold)).foregroundColor(accent.opacity(0.8))
        }
        .lineLimit(1).fixedSize()
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(ZStack { Color.surface; accent.opacity(0.06) }).cornerRadius(100)
        .overlay(Capsule().stroke(accent.opacity(glowing ? 0.5 : 0.2), lineWidth: glowing ? 1.5 : 1))
        .shadow(color: glowing ? accent.opacity(0.3) : .clear, radius: 8)
        .accessibilityElement(children: .ignore)
    }

    @ViewBuilder
    private func liveChip(icon: String, iconColor: Color, value: String, unit: String, accent: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(iconColor)
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary).contentTransition(.numericText())
            Text(unit).font(.system(size: 11)).foregroundColor(.textTertiary)
        }
        .lineLimit(1).fixedSize()
        .padding(.horizontal, 11).padding(.vertical, 8).background(Color.surface).cornerRadius(100)
        .overlay(Capsule().stroke(accent.opacity(0.2), lineWidth: 1))
        .accessibilityElement(children: .ignore)
    }
    // MARK: Main Content

    @ViewBuilder
    private func mainContent(exercise: Exercise) -> some View {
        ScrollView(showsIndicators: false) {
            Group {
                if isResting {
                    RestTimerView(restTimeLeft: restTimeLeft, totalRest: restTotal,
                                  nextLabel: nextLabel(exercise: exercise), onSkip: skipRest)
                        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .scale(scale: 0.9).combined(with: .opacity)))
                } else {
                    exerciseCard(exercise: exercise)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isResting)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: store.currentExerciseIndex)
    }

    // MARK: Exercise Card

    @ViewBuilder
    private func exerciseCard(exercise: Exercise) -> some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                // Set strip
                HStack {
                    HStack(spacing: 8) {
                        Text("Set \(store.currentSet) of \(exercise.sets)").font(.system(size: 13, weight: .bold)).foregroundColor(.ember)
                        HStack(spacing: 4) {
                            ForEach(0..<exercise.sets, id: \.self) { i in
                                Circle()
                                    .fill(i < store.currentSet - 1 ? Color.success : i == store.currentSet - 1 ? Color.ember : Color.borderColor)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: i == store.currentSet - 1 ? Color.ember.opacity(0.6) : .clear, radius: 3)
                                    .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.currentSet)
                            }
                        }
                    }
                    Spacer()
                    Text("\(store.currentExerciseIndex + 1)/\(exercises.count)").font(.system(size: 12)).foregroundColor(.textMuted)
                }
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)

                Divider().background(Color.borderColor.opacity(0.4))

                VStack(alignment: .leading, spacing: 14) {
                    Text(exercise.name).font(.system(size: 26, weight: .bold)).foregroundColor(.textPrimary)
                    Button {
                        FDS.haptic(.medium)
                        store.showHowToPerform(exercise.name)
                    } label: {
                        HStack(spacing: 8) {
                            ARIAIdentityMark(state: .idle, mood: .energized, size: 22, amplitude: 0.3)
                            Text("Show me how")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Image(systemName: "books.vertical")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.ember)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.ember.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    if let def = currentDef {
                        HStack(spacing: 6) {
                            ForEach(def.primary.prefix(3)) { m in
                                Text(m.label).font(.system(size: 10, weight: .bold)).foregroundColor(m.accent)
                                    .padding(.horizontal, 8).padding(.vertical, 4).background(m.accent.opacity(0.12)).cornerRadius(7)
                            }
                            Text("Tempo \(def.tempo)").font(.system(size: 10, weight: .semibold)).foregroundColor(.textMuted)
                                .padding(.horizontal, 8).padding(.vertical, 4).background(Color.surfaceElevated).cornerRadius(7)
                        }
                    }
                    ExerciseDemonstrationView(exercise: exercise, definition: currentDef, selectedTab: $selectedDemoTab,
                                              onLaunchCamera: { showFormCoach = true })
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 18)

                Divider().background(Color.borderColor.opacity(0.4))

                // Weight × Reps hero
                ZStack {
                    currentZone.color.opacity(0.04).animation(.easeInOut(duration: 0.8), value: currentZone.label)
                    HStack(spacing: 0) {
                        if exercise.weight != nil {
                            VStack(spacing: 4) {
                                HStack(spacing: 10) {
                                    Button {
                                        currentWeight = max(0, currentWeight - 5); UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        ZStack {
                                            Circle().fill(Color.surfaceElevated).frame(width: 36, height: 36).overlay(Circle().stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
                                            Image(systemName: "minus").font(.system(size: 14, weight: .bold)).foregroundColor(.textMuted)
                                        }
                                    }
                                    .accessibilityLabel("Decrease weight by 5 pounds")
                                    VStack(spacing: 1) {
                                        Text("\(currentWeight)").font(.system(size: 58, weight: .black, design: .rounded)).foregroundColor(.textPrimary).contentTransition(.numericText())
                                        Text("LBS").font(.system(size: 9, weight: .black)).foregroundColor(currentZone.color.opacity(0.8)).tracking(3).animation(.easeInOut(duration: 0.8), value: currentZone.label)
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Working weight")
                                    .accessibilityValue("\(currentWeight) pounds")
                                    Button {
                                        currentWeight += 5; UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        ZStack {
                                            Circle().fill(Color.ember.opacity(0.12)).frame(width: 36, height: 36).overlay(Circle().stroke(Color.ember.opacity(0.3), lineWidth: 1))
                                            Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundColor(.ember)
                                        }
                                    }
                                    .accessibilityLabel("Increase weight by 5 pounds")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            Rectangle().fill(Color.borderColor.opacity(0.35)).frame(width: 1, height: 60)
                        }
                        VStack(spacing: 1) {
                            Text(exercise.reps).font(.system(size: 58, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
                            Text("REPS").font(.system(size: 9, weight: .black)).foregroundColor(currentZone.color.opacity(0.8)).tracking(3).animation(.easeInOut(duration: 0.8), value: currentZone.label)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 26)
                }

                Divider().background(Color.borderColor.opacity(0.4))

                // Live auto-regulation read
                AutoRegStrip(recommendation: recommendation)
                    .padding(.horizontal, 20).padding(.vertical, 14)

                Divider().background(Color.borderColor.opacity(0.4))

                // Previous sets
                let prevSets = setLog.filter { $0.exerciseName == exercise.name }
                if !prevSets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PREVIOUS SETS").font(.system(size: 9, weight: .black)).foregroundColor(.textMuted).tracking(2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(prevSets) { entry in
                                    VStack(spacing: 3) {
                                        if entry.isPersonalRecord { Image(systemName: "crown.fill").font(.system(size: 9)).foregroundColor(.warning) }
                                        Text("\(entry.repsPerformed)").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(entry.isPersonalRecord ? .warning : .textPrimary)
                                        if entry.weightUsed > 0 { Text("\(entry.weightUsed)lb").font(.system(size: 10)).foregroundColor(.textTertiary) }
                                        Text("RPE \(entry.rpe)").font(.system(size: 9, weight: .bold)).foregroundColor(rpeColor(entry.rpe))
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(entry.isPersonalRecord ? Color.warning.opacity(0.1) : Color.surfaceElevated).cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(entry.isPersonalRecord ? Color.warning.opacity(0.4) : Color.borderColor.opacity(0.4), lineWidth: 1))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    Divider().background(Color.borderColor.opacity(0.4))
                }

                HStack(spacing: 5) {
                    Image(systemName: "clock.fill").font(.system(size: 11)).foregroundColor(.textMuted)
                    Text("\(recommendation.restSeconds)s rest").font(.system(size: 12)).foregroundColor(.textTertiary)
                    if let notes = exercise.notes {
                        Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                        Text(notes).font(.system(size: 12, design: .serif).italic()).foregroundColor(.textTertiary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .background(Color.surface).cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)

            actionButtons(exercise: exercise)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
    }

    // MARK: Action Buttons

    @ViewBuilder
    private func actionButtons(exercise: Exercise) -> some View {
        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx  = store.currentExerciseIndex >= exercises.count - 1
        let isFinish  = isLastSet && isLastEx
        VStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                loggedReps = recommendation.repTarget > 0 ? recommendation.repTarget : (Int(exercise.reps) ?? exercise.reps.repMidpoint)
                loggedRPE  = recommendation.rpeTarget
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { showSetLogger = true }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isFinish ? "checkmark.circle.fill" : "pencil.and.list.clipboard").font(.system(size: 19, weight: .black))
                    Text(isFinish ? "Log & Finish 🎉" : isLastSet ? "Log Set · Next Exercise →" : "Log Set →").font(.system(size: 17, weight: .black))
                    Spacer()
                }
                .foregroundColor(.white).padding(.horizontal, 24).padding(.vertical, 20).frame(maxWidth: .infinity)
                .background(LinearGradient(colors: isFinish ? [Color.success, Color.success.opacity(0.8)] : [Color.ember, Color.ember.opacity(0.82)], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(20).shadow(color: (isFinish ? Color.success : Color.ember).opacity(0.5), radius: 20, y: 8)
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isFinish)
            }
            HStack(spacing: 10) {
                actionMini(icon: "forward.fill", label: "Skip", color: .textSecondary) { skipExercise() }
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { showPainLogger = true }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
                        Text(painLog.isEmpty ? "Pain" : "Pain (\(painLog.count))").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.warning).frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color.warning.opacity(painLog.isEmpty ? 0.1 : 0.2)).cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.warning.opacity(0.3), lineWidth: 1))
                }
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(); showFormCoach = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder").font(.system(size: 13))
                        Text("Form").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.success).frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color.success.opacity(0.12)).cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.success.opacity(0.3), lineWidth: 1))
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.4)) { coachIndex += 1 }
                } label: {
                    Image(systemName: "brain.head.profile").font(.system(size: 14)).foregroundColor(.ember).frame(width: 46, height: 46)
                        .background(Color.ember.opacity(0.1)).cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ember.opacity(0.3), lineWidth: 1))
                }
                .accessibilityLabel("Next coaching cue")
            }
        }
    }

    private func actionMini(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(color).frame(maxWidth: .infinity).frame(height: 46)
            .background(Color.surfaceElevated).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        }
    }

    // MARK: Coach Bar (contextual, data-driven)

    private var liveCoachCues: [String] {
        var cues: [String] = [recommendation.rationale]
        if let def = currentDef { cues.append(contentsOf: def.cues) }
        cues.append(currentZone.index >= 4 ? "HR is climbing — keep technique tight as you fatigue." : "O₂ is solid — you can hold this pace.")
        cues.append("Brace the core and own every rep.")
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
            heartRate: simulatedHR,
            hrZone: currentZone.index,
            calories: Int(estimatedCals),
            restSeconds: currentExercise?.restSeconds ?? 90,
            notes: currentDef?.cues.first ?? liveCoachCues.first ?? ""
        ))
    }

    private var voiceCoachBar: some View {
        VoiceCoachBar(coach: voiceCoach)
            .padding(.horizontal, 16).padding(.bottom, 20).padding(.top, 6)
            .onChange(of: store.currentExerciseIndex) { _, _ in
                syncVoiceCoach()
            }
            .onChange(of: store.currentSet) { _, _ in
                syncVoiceCoach()
            }
    }

    // MARK: Logic

    private func rpeColor(_ rpe: Int) -> Color { rpe <= 4 ? .success : rpe <= 7 ? Color(hex: "F59E0B") : .danger }
    private func setupCurrentWeight() { currentWeight = currentExercise?.weight ?? 0 }

    private func confirmSet(exercise: Exercise) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { showSetLogger = false }
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
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { showPRBanner = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Task { try? await Task.sleep(nanoseconds: 2_500_000_000); withAnimation(.easeOut(duration: 0.4)) { showPRBanner = false } }
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        if loggedRPE >= 9 { withAnimation(.easeInOut(duration: 0.4)) { coachIndex += 1 } }

        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx  = store.currentExerciseIndex >= exercises.count - 1
        if isLastSet && isLastEx { endWorkout(); return }
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showPainLogger = false }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        let def = ExerciseLibrary.definition(for: exercise)
        let contraindicated = def?.painContraindications.contains(entry.location) ?? false
        if entry.severity >= 7 || (entry.severity >= 5 && contraindicated) {
            if let swap = AdaptiveEngine.substitution(for: exercise, painLocation: entry.location) {
                pendingSwap = swap
                swapReason = "\(entry.location) at \(entry.severity)/10"
                withAnimation { showSwapBanner = true }
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
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            store.todayWorkout?.exercises[store.currentExerciseIndex] = new
            store.currentSet = 1
            showSwapBanner = false
        }
        autoRegLog.append("Swapped \(old) → \(def.name) (\(swapReason))")
        setupCurrentWeight()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func endWorkout() {
        cancelTasks()
        let avgHR  = hrHistory.isEmpty ? simulatedHR : hrHistory.reduce(0, +) / hrHistory.count
        let rpes   = setLog.map { Double($0.rpe) }
        let avgRPE = rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
        let prs    = Array(Set(setLog.filter { $0.isPersonalRecord }.map { $0.exerciseName }))
        let painFlags = Array(Set(painLog.map { "\($0.location) (\($0.severity)/10)" }))
        var mvStr: [String: Double] = [:]
        for (m, v) in muscleVolume { mvStr[m.rawValue] = v }
        let data = WorkoutSummaryData(
            duration: elapsedSecs, totalVolume: totalVolume, totalSets: setLog.count,
            totalReps: setLog.reduce(0) { $0 + $1.repsPerformed }, peakHR: peakHR, avgHR: avgHR,
            peakO2: peakSpO2, minO2: minSpO2, caloriesBurned: Int(estimatedCals), personalRecords: prs,
            exercisesCompleted: min(store.currentExerciseIndex + 1, exercises.count), avgRPE: avgRPE, hrHistory: hrHistory,
            muscleVolume: mvStr, autoRegLog: autoRegLog, painFlags: painFlags,
            readiness: store.readiness.overall, workoutName: store.todayWorkout?.name ?? "Workout")
        store.endWorkout()
        onWorkoutEnd(data)
    }

    private func skipExercise() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if store.currentExerciseIndex >= exercises.count - 1 { endWorkout() }
        else { store.nextExercise(); isResting = false; restTimeLeft = 0; restTask?.cancel(); setupCurrentWeight() }
    }
    private func skipRest() {
        restTask?.cancel(); restTask = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { isResting = false }
        restTimeLeft = 0; UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    private func handleEnd() {
        if showEndConfirm { endWorkout() }
        else {
            showEndConfirm = true; UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            Task { try? await Task.sleep(nanoseconds: 3_000_000_000); showEndConfirm = false }
        }
    }
    private func startRest(seconds: Int) {
        restTotal = max(1, seconds); restTimeLeft = seconds
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { isResting = true }
        restTask?.cancel()
        restTask = Task {
            while restTimeLeft > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                if restTimeLeft <= 1 {
                    restTimeLeft = 0
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { isResting = false }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    return
                }
                restTimeLeft -= 1
            }
        }
    }
    private func nextLabel(exercise: Exercise) -> String {
        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx  = store.currentExerciseIndex >= exercises.count - 1
        if isLastSet && isLastEx { return "Workout Complete 🎉" }
        if isLastSet {
            let next = exercises.indices.contains(store.currentExerciseIndex + 1) ? exercises[store.currentExerciseIndex + 1].name : "Done"
            return "Next: \(next)"
        }
        return "Set \(store.currentSet) of \(exercise.sets) done"
    }

    // MARK: Tasks

    private func startTasks() {
        elapsedTask = Task {
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000_000); guard !Task.isCancelled else { return }; elapsedSecs += 1 }
        }
        hrTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000); guard !Task.isCancelled else { return }
                let target = isResting ? (108 + Double.random(in: 0...18)) : (140 + Double.random(in: 0...26))
                simulatedHR = Int((Double(simulatedHR) + (target - Double(simulatedHR)) * 0.12 + Double.random(in: -4...4)).rounded().clamped(to: 55...200))
                hrHistory.append(simulatedHR)
                if simulatedHR > peakHR { peakHR = simulatedHR }
            }
        }
        calTask = Task {
            let weightKg = store.userProfile.weight ?? 80
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000); guard !Task.isCancelled else { return }
                // MET-based expenditure: kcal/sec = MET · 3.5 · kg / 200 / 60, scaled by HR drive.
                let met = isResting ? 1.5 : (currentDef?.met ?? 5.0)
                let hrScale = simulatedHR > 150 ? 1.15 : simulatedHR > 130 ? 1.05 : 1.0
                estimatedCals += (met * 3.5 * weightKg / 200 / 60) * hrScale
            }
        }
        o2Task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000); guard !Task.isCancelled else { return }
                let drop     = simulatedHR > 160 ? Double.random(in: 1...3) : simulatedHR > 140 ? Double.random(in: 0...1.5) : 0.0
                let recovery = isResting ? Double.random(in: 0...1) : 0
                simulatedSpO2 = Int((Double(simulatedSpO2) - drop + recovery).rounded().clamped(to: 90.0...100.0))
                if simulatedSpO2 > peakSpO2 { peakSpO2 = simulatedSpO2 }
                if simulatedSpO2 < minSpO2  { minSpO2  = simulatedSpO2 }
                if simulatedSpO2 < 94 && !showO2Warning {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showO2Warning = true }
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    Task { try? await Task.sleep(nanoseconds: 5_000_000_000); withAnimation { showO2Warning = false } }
                }
            }
        }
        coachTask = Task {
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 9_000_000_000); guard !Task.isCancelled else { return }; withAnimation(.easeInOut(duration: 0.4)) { coachIndex += 1 } }
        }
    }
    private func cancelTasks() {
        [elapsedTask, hrTask, calTask, o2Task, restTask, coachTask].forEach { $0?.cancel() }
        elapsedTask = nil; hrTask = nil; calTask = nil; o2Task = nil; restTask = nil; coachTask = nil
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
