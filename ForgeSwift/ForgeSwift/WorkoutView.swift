import SwiftUI
import UIKit

struct WorkoutView: View {
    @EnvironmentObject var store: AppStore
    @State private var summaryData: WorkoutSummaryData? = nil
    @State private var showSummary = false

    var body: some View {
        ZStack {
            if showSummary, let summary = summaryData {
                WorkoutSummaryView(data: summary, onDismiss: {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                        showSummary = false; summaryData = nil
                    }
                })
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94).combined(with: .opacity),
                    removal:   .scale(scale: 1.04).combined(with: .opacity)
                ))
                .zIndex(10)
            } else if store.isWorkoutActive {
                ActiveWorkoutView { data in
                    summaryData = data
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { showSummary = true }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                    removal:   .scale(scale: 1.04).combined(with: .opacity)
                ))
                .zIndex(5)
            } else {
                WorkoutIdleView()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal:   .scale(scale: 0.96).combined(with: .opacity)
                    ))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: store.isWorkoutActive)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: showSummary)
    }
}

struct WorkoutIdleView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var music = MusicControllerFactory.make(for: .appleMusic)
    @State private var appeared = false
    @State private var pulseOrb = false
    @State private var selectedExerciseIndex: Int? = nil
    @State private var showLibrary = false
    @State private var showDashboard = false
    @State private var scalingApplied = false

    private var scaling: PlanScaling { AdaptiveEngine.scaling(readiness: store.readiness, experience: store.userProfile.experienceLevel) }

    var body: some View {
        ZStack {
            WorkoutBackground(accentColor: .ember).ignoresSafeArea()
            if let workout = store.todayWorkout {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        idleHeader(workout: workout)
                            .padding(.horizontal, 20).padding(.top, 60)

                        quickActions
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.22), value: appeared)

                        AdaptiveScalingCard(scaling: scaling, applied: scalingApplied) { applyScaling(workout: workout) }
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: appeared)

                        MusicControlBar(controller: music, compact: false)
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.36), value: appeared)

                        exerciseList(workout: workout).padding(.horizontal, 16)

                        WorkoutInsightsView(workout: workout)
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 18)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.48), value: appeared)

                        startButton(workout: workout)
                            .padding(.horizontal, 16).padding(.bottom, 110)
                    }
                }
            } else {
                WorkoutEmptyState()
            }
        }
        .sheet(isPresented: $showLibrary) { ExerciseLibraryView() }
        .sheet(isPresented: $showDashboard) {
            if let workout = store.todayWorkout {
                ARIADashboardView(snapshot: Self.plannedSnapshot(workout, readiness: store.readiness),
                                  isPreWorkout: true)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.8).delay(0.08)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulseOrb = true }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            idleActionTile(icon: "figure.stand", title: "Library", subtitle: "Tap a muscle", accent: Color(hex: "38BDF8")) { showLibrary = true }
            idleActionTile(icon: "brain.head.profile", title: "ARIA Brief", subtitle: "Plan readout", accent: .ember) { showDashboard = true }
        }
    }

    private func idleActionTile(icon: String, title: String, subtitle: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(); action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(accent.opacity(0.14)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                    Text(subtitle).font(.system(size: 11)).foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.surface).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func applyScaling(workout: WorkoutPlan) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            store.todayWorkout?.exercises = workout.exercises.map { AdaptiveEngine.scaled($0, by: scaling) }
            scalingApplied = true
        }
    }

    private func idleHeader(workout: WorkoutPlan) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.ember.opacity(0.18))
                    .frame(width: 90, height: 90).blur(radius: 22)
                    .scaleEffect(pulseOrb ? 1.45 : 0.85)
                    .opacity(pulseOrb ? 0.15 : 0.9)
                Circle()
                    .fill(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.75)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.ember.opacity(0.5), radius: 20, y: 6)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 36, weight: .black)).foregroundColor(.white)
            }
            .scaleEffect(appeared ? 1 : 0.7).opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.65, dampingFraction: 0.7).delay(0.1), value: appeared)

            VStack(spacing: 6) {
                Text(workout.name)
                    .font(.system(size: 32, weight: .bold, design: .rounded)).foregroundColor(.textPrimary).multilineTextAlignment(.center)
                Text(workout.type.label.uppercased())
                    .forgeSectionLabel()
                    .foregroundColor(.ember)
            }
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.18), value: appeared)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    WorkoutStatPill(icon: "list.bullet",    value: "\(workout.exercises.count)",   label: "exercises")
                    WorkoutStatPill(icon: "clock.fill",     value: "~\(workout.duration)",         label: "min")
                    WorkoutStatPill(icon: "flame.fill",     value: "\(workout.estimatedCalories)", label: "cal",  color: workout.intensity.color)
                    WorkoutStatPill(icon: "scalemass.fill", value: totalVolumeStr(workout),        label: "vol",  color: .steel)
                }
            }
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)
            .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.26), value: appeared)

            ReadinessIntensityArc(readiness: store.readiness.overall, intensity: workout.intensity)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.34), value: appeared)
        }
    }

    private func totalVolumeStr(_ w: WorkoutPlan) -> String {
        let v = w.exercises.reduce(0) { $0 + ($1.sets * (Int($1.reps) ?? $1.reps.repMidpoint) * ($1.weight ?? 0)) }
        return v > 0 ? v.formattedVolume : "—"
    }

    private func exerciseList(workout: WorkoutPlan) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("EXERCISES").forgeSectionLabel()
                Spacer()
                Text("\(workout.exercises.count) total").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundColor(.textMuted)
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { idx, ex in
                WorkoutExerciseRow(exercise: ex, index: idx, isExpanded: selectedExerciseIndex == idx, onTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        selectedExerciseIndex = selectedExerciseIndex == idx ? nil : idx
                    }
                })
                .opacity(appeared ? 1 : 0).offset(x: appeared ? 0 : -22)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.32 + Double(idx) * 0.055), value: appeared)
                if idx < workout.exercises.count - 1 {
                    Divider().background(Color.borderColor.opacity(0.5)).padding(.leading, 72)
                }
            }
        }
        .padding(.vertical, 20)
        .forgeGlassCard(accent: .ember)
    }

    private func startButton(workout: WorkoutPlan) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            if music.nowPlaying?.isPlaying == false { music.togglePlayPause() }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { store.startWorkout() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill").font(.system(size: 20, weight: .black))
                Text("Start Workout").font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 18, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 28).padding(.vertical, 22)
            .background {
                ZStack {
                    FDS.Gradient.ember
                    LinearGradient.premiumChrome
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.ember.opacity(0.4), radius: 20, y: 8)
        }
        .opacity(appeared ? 1 : 0).scaleEffect(appeared ? 1 : 0.92)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.52), value: appeared)
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
    let onApply: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(scaling.tone.opacity(0.15)).frame(width: 30, height: 30)
                    Image(systemName: "wand.and.stars").font(.system(size: 13)).foregroundColor(scaling.tone)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("ARIA AUTO-SCALE").font(.system(size: 10, weight: .black)).tracking(2).foregroundColor(.textTertiary)
                    Text(scaling.headline).font(.system(size: 15, weight: .bold)).foregroundColor(.textPrimary)
                }
                Spacer()
                if scaling.isModified {
                    VStack(spacing: 1) {
                        Text("\(Int(scaling.volumeMultiplier * 100))%").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(scaling.tone)
                        Text("volume").font(.system(size: 8, weight: .semibold)).foregroundColor(.textMuted)
                    }
                }
            }
            Text(scaling.detail).font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)

            if scaling.isModified {
                Button(action: onApply) {
                    HStack(spacing: 8) {
                        Image(systemName: applied ? "checkmark.circle.fill" : "slider.horizontal.3").font(.system(size: 14, weight: .bold))
                        Text(applied ? "Auto-scaling applied" : "Apply to today's plan").font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .foregroundColor(applied ? scaling.tone : .white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(applied ? scaling.tone.opacity(0.12) : scaling.tone)
                    .cornerRadius(13)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(scaling.tone.opacity(applied ? 0.4 : 0), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(applied)
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(scaling.tone.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
    }
}

struct WorkoutBackground: View {
    let accentColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.background
            Group {
                if reduceMotion {
                    mesh(at: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1/30)) { tl in
                        mesh(at: tl.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 1.6), value: accentColor)
    }

    private func mesh(at t: TimeInterval) -> some View {
        Canvas { ctx, size in
            let x1 = size.width  * (0.15 + 0.12 * sin(t * 0.17))
            let y1 = size.height * (0.12 + 0.10 * cos(t * 0.13))
            let r1 = size.width  * 0.55
            var p1 = Path(); p1.addEllipse(in: CGRect(x: x1-r1/2, y: y1-r1/2, width: r1, height: r1))
            ctx.fill(p1, with: .color(accentColor.opacity(0.045)))
            let x2 = size.width  * (0.82 + 0.10 * cos(t * 0.11))
            let y2 = size.height * (0.75 + 0.12 * sin(t * 0.14))
            let r2 = size.width  * 0.48
            var p2 = Path(); p2.addEllipse(in: CGRect(x: x2-r2/2, y: y2-r2/2, width: r2, height: r2))
            ctx.fill(p2, with: .color(Color(hex: "38BDF8").opacity(0.028)))
            let x3 = size.width  * (0.5 + 0.18 * sin(t * 0.09 + 1.0))
            let y3 = size.height * (0.45 + 0.14 * cos(t * 0.12 + 0.5))
            let r3 = size.width  * 0.38
            var p3 = Path(); p3.addEllipse(in: CGRect(x: x3-r3/2, y: y3-r3/2, width: r3, height: r3))
            ctx.fill(p3, with: .color(accentColor.opacity(0.025)))
        }
    }
}

private struct ReadinessIntensityArc: View {
    let readiness: Int
    let intensity: WorkoutIntensity
    @State private var appeared = false

    private var readinessFraction: CGFloat { CGFloat(readiness) / 100 }
    private var intensityFraction: CGFloat {
        switch intensity {
        case .low: return 0.25
        case .moderate: return 0.50
        case .high: return 0.75
        case .max: return 1.0
        }
    }
    private var matchColor: Color {
        let diff = abs(readinessFraction - intensityFraction)
        return diff < 0.15 ? .success : diff < 0.35 ? Color(hex: "F59E0B") : .danger
    }
    private var matchLabel: String {
        let diff = abs(readinessFraction - intensityFraction)
        return diff < 0.15 ? "Well matched" : diff < 0.35 ? "Manageable" : "Intensity mismatch"
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.borderColor.opacity(0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 56, height: 56)
                Circle().trim(from: 0, to: appeared ? readinessFraction : 0)
                    .stroke(Color.success.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 56, height: 56).rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.1), value: appeared)
                Circle().trim(from: 0, to: appeared ? intensityFraction : 0)
                    .stroke(Color.ember.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 44, height: 44).rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.22), value: appeared)
                Text("\(readiness)").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(matchColor).frame(width: 6, height: 6).shadow(color: matchColor.opacity(0.5), radius: 3)
                    Text(matchLabel).font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                }
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.success.opacity(0.7)).frame(width: 6, height: 6)
                        Text("Readiness \(readiness)%").font(.system(size: 11)).foregroundColor(.textTertiary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.ember.opacity(0.8)).frame(width: 6, height: 6)
                        Text(intensity.label).font(.system(size: 11)).foregroundColor(.textTertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(16).background(Color.surface).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(matchColor.opacity(0.2), lineWidth: 1))
        .onAppear { appeared = true }
    }
}

struct WorkoutStatPill: View {
    let icon: String; let value: String; let label: String
    var color: Color = .textSecondary
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(color)
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.textPrimary)
            Text(label).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(.textSecondary).lineLimit(1)

        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

struct WorkoutExerciseRow: View {
    let exercise: Exercise; let index: Int
    let isExpanded: Bool; let onTap: () -> Void
    private var def: ExerciseDefinition? { ExerciseLibrary.definition(for: exercise) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [(def?.accent ?? .ember).opacity(0.18), (def?.accent ?? .ember).opacity(0.07)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 42, height: 42)
                        Text("\(index + 1)").font(.system(size: 16, weight: .bold)).foregroundColor(def?.accent ?? .ember)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary).lineLimit(isExpanded ? nil : 1)
                        HStack(spacing: 8) {
                            Label("\(exercise.sets) × \(exercise.reps)", systemImage: "repeat")
                                .font(.system(size: 12)).foregroundColor(.textSecondary)
                            if let w = exercise.weight {
                                Circle().fill(Color.textMuted).frame(width: 3, height: 3)
                                Text("\(w) lbs").font(.system(size: 12)).foregroundColor(.textSecondary)
                            }
                            if let def {
                                Circle().fill(Color.textMuted).frame(width: 3, height: 3)
                                Text(def.primary.first?.label ?? "").font(.system(size: 12, weight: .semibold)).foregroundColor(def.accent)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider().background(Color.borderColor.opacity(0.5)).padding(.horizontal, 20)
                        if let def {
                            // Muscle map + mechanics chips
                            HStack(spacing: 6) {
                                metaChip(def.pattern.label, "arrow.triangle.branch", def.accent)
                                metaChip(def.equipment.label, def.equipment.icon, .steel)
                                metaChip(def.isCompound ? "Compound" : "Isolation", "square.stack.3d.up.fill", .textTertiary)
                            }
                            .padding(.horizontal, 20)
                            if let cue = def.cues.first {
                                cueRow(icon: "checkmark.circle.fill", color: def.accent, text: cue)
                            }
                            if let fault = def.faults.first {
                                cueRow(icon: "exclamationmark.triangle.fill", color: .warning, text: "Avoid: \(fault)")
                            }
                        }
                        if let notes = exercise.notes {
                            cueRow(icon: "info.circle.fill", color: .steel, text: notes)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill").font(.system(size: 12)).foregroundColor(.textMuted)
                            Text("\(exercise.restSeconds)s rest between sets").font(.system(size: 12)).foregroundColor(.textTertiary)
                        }
                        .padding(.horizontal, 20).padding(.bottom, 14)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isExpanded)
    }

    private func cueRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
            Text(text).font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }
    private func metaChip(_ text: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color).padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.1)).cornerRadius(7)
    }
}

struct WorkoutInsightsView: View {
    let workout: WorkoutPlan
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    private var insights: [(icon: String, text: String, color: Color)] {
        var r: [(String, String, Color)] = []
        if store.readiness.overall >= 80 { r.append(("bolt.fill", "Readiness \(store.readiness.overall)% — primed for heavy top sets today.", .ember)) }
        else if store.readiness.overall < 65 { r.append(("bed.double.fill", "Recovery \(store.readiness.overall)% — ARIA trimmed volume to protect tomorrow.", .steel)) }
        // Balance read across the plan
        if let lean = planRegionLean() { r.append(("scale.3d", lean, Color(hex: "A855F7"))) }
        if workout.intensity == .high || workout.intensity == .max {
            r.append(("exclamationmark.triangle.fill", "High intensity — run the mobility warm-up before loading.", .warning))
        }
        r.append(("flame.fill", "≈\(workout.estimatedCalories) kcal projected at this output.", .success))
        return r
    }

    private func planRegionLean() -> String? {
        var counts: [TargetMuscle.Region: Int] = [:]
        for ex in workout.exercises {
            if let def = ExerciseLibrary.definition(for: ex) { counts[def.region, default: 0] += ex.sets }
        }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return "Session emphasis: \(top.key.rawValue) (\(top.value) working sets)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "brain.head.profile").font(.system(size: 14)).foregroundColor(.ember)
                Text("ARIA INSIGHTS").font(.system(size: 10, weight: .black)).foregroundColor(.textTertiary).tracking(2.5)
            }
            VStack(spacing: 10) {
                ForEach(Array(insights.enumerated()), id: \.offset) { idx, insight in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(insight.color.opacity(0.12)).frame(width: 32, height: 32)
                            Image(systemName: insight.icon).font(.system(size: 13)).foregroundColor(insight.color)
                        }
                        Text(insight.text).font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)
                        Spacer()
                    }
                    .padding(12).background(Color.surfaceElevated).cornerRadius(13)
                    .opacity(appeared ? 1 : 0).offset(x: appeared ? 0 : -14)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(idx) * 0.1), value: appeared)
                }
            }
        }
        .padding(20).background(Color.surface).cornerRadius(22)
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
        .onAppear { appeared = true }
        .task { store.shareWorkoutInsightsIfNeeded(insights.map(\.text)) }
    }
}

struct WorkoutEmptyState: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false
    @State private var showLibrary = false
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(Color.ember.opacity(0.08)).frame(width: 130, height: 130).blur(radius: 24)
                Image(systemName: "dumbbell.fill").font(.system(size: 58)).foregroundColor(.ember.opacity(0.5))
            }
            .scaleEffect(appeared ? 1 : 0.8).opacity(appeared ? 1 : 0)
            VStack(spacing: 10) {
                Text("No Workout Planned").font(.system(size: 24, weight: .bold)).foregroundColor(.textPrimary)
                Text("Chat with ARIA to generate a plan tailored to your readiness and goals — or explore the movement library.")
                    .font(.system(size: 15)).foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center).lineSpacing(5).padding(.horizontal, 44)
            }
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 18)
            VStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.activeTab = .chat
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill").font(.system(size: 16))
                        Text("Chat with ARIA").font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 32).padding(.vertical, 17)
                    .background(Color.ember).cornerRadius(18)
                    .shadow(color: Color.ember.opacity(0.45), radius: 18, y: 8)
                }
                Button { showLibrary = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.stand").font(.system(size: 14))
                        Text("Browse by muscle").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.steel).padding(.horizontal, 24).padding(.vertical, 13)
                    .background(Color.steel.opacity(0.1)).cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.steel.opacity(0.3), lineWidth: 1))
                }
            }
            .opacity(appeared ? 1 : 0).scaleEffect(appeared ? 1 : 0.92)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showLibrary) { ExerciseLibraryView() }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.18)) { appeared = true } }
    }
}

struct FeatureBadge: View {
    let icon: String; let label: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(label).font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color).padding(.horizontal, 9).padding(.vertical, 5)
        .background(color.opacity(0.1)).cornerRadius(7)
    }
}
