import SwiftUI
import MediaPlayer
import Combine

// MARK: - HR Zone

fileprivate struct WorkoutHRZone: Equatable {
    let label: String
    let color: Color
    let range: ClosedRange<Int>
    static func == (l: WorkoutHRZone, r: WorkoutHRZone) -> Bool { l.label == r.label }
}

fileprivate let workoutHRZones: [WorkoutHRZone] = [
    WorkoutHRZone(label: "Rest",   color: .steel,               range: 0...99),
    WorkoutHRZone(label: "Zone 1", color: Color(hex: "38BDF8"),  range: 100...114),
    WorkoutHRZone(label: "Zone 2", color: .success,              range: 115...133),
    WorkoutHRZone(label: "Zone 3", color: Color(hex: "F59E0B"),  range: 134...152),
    WorkoutHRZone(label: "Zone 4", color: .ember,                range: 153...171),
    WorkoutHRZone(label: "Zone 5", color: .danger,               range: 172...220),
]
fileprivate func workoutHRZone(for bpm: Int) -> WorkoutHRZone {
    workoutHRZones.first { $0.range.contains(bpm) } ?? workoutHRZones[0]
}

// MARK: - Music
// Note: NowPlayingTrack, MusicService, and MusicControllerFactory are defined in MusicControllerFactory.swift
// MARK: - Data Models

fileprivate struct SetLogEntry: Identifiable {
    let id = UUID()
    let exerciseName: String
    let setNumber:    Int
    var repsPerformed: Int
    var weightUsed:   Int
    var rpe:          Int        // 1–10
    var isPersonalRecord: Bool = false
    var timestamp: Date = Date()
    var volume: Int { repsPerformed * weightUsed }
}

fileprivate struct PainEntry: Identifiable {
    let id = UUID()
    let location:     String
    let severity:     Int
    let exerciseName: String
}

struct WorkoutSummaryData {
    let duration:           Int
    let totalVolume:        Int
    let totalSets:          Int
    let totalReps:          Int
    let peakHR:             Int
    let avgHR:              Int
    let peakO2:             Int
    let minO2:              Int
    let caloriesBurned:     Int
    let personalRecords:    [String]
    let exercisesCompleted: Int
    let avgRPE:             Double
    let hrHistory:          [Int]
}

// MARK: - Tab Root

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

// MARK: - Idle View

struct WorkoutIdleView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var music = MusicControllerFactory.make(for: .appleMusic)
    @State private var appeared = false
    @State private var pulseOrb = false
    @State private var selectedExerciseIndex: Int? = nil

    var body: some View {
        ZStack {
            WorkoutBackground(accentColor: .ember).ignoresSafeArea()
            if let workout = store.todayWorkout {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        idleHeader(workout: workout)
                            .padding(.horizontal, 20).padding(.top, 60)

                        MusicControlBar(controller: music, compact: false)
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.28), value: appeared)

                        exerciseList(workout: workout).padding(.horizontal, 16)

                        WorkoutInsightsView(workout: workout)
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 18)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.44), value: appeared)

                        startButton(workout: workout)
                            .padding(.horizontal, 16).padding(.bottom, 110)
                    }
                }
            } else {
                WorkoutEmptyState()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.8).delay(0.08)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulseOrb = true }
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
                    .font(.system(size: 32, weight: .bold)).foregroundColor(.textPrimary).multilineTextAlignment(.center)
                Text(workout.type.label.uppercased())
                    .font(.system(size: 11, weight: .black)).tracking(2.5).foregroundColor(.ember)
            }
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.18), value: appeared)

            HStack(spacing: 8) {
                WorkoutStatPill(icon: "list.bullet",    value: "\(workout.exercises.count)",   label: "exercises")
                WorkoutStatPill(icon: "clock.fill",     value: "~\(workout.duration)",         label: "min")
                WorkoutStatPill(icon: "flame.fill",     value: "\(workout.estimatedCalories)", label: "cal",  color: workout.intensity.color)
                WorkoutStatPill(icon: "scalemass.fill", value: totalVolumeStr(workout),        label: "vol",  color: .steel)
            }
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)
            .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.26), value: appeared)

            // Readiness intensity arc
            ReadinessIntensityArc(readiness: store.readiness.overall, intensity: workout.intensity)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.34), value: appeared)
        }
    }

    private func totalVolumeStr(_ w: WorkoutPlan) -> String {
        let v = w.exercises.reduce(0) { $0 + ($1.sets * (Int($1.reps) ?? 0) * ($1.weight ?? 0)) }
        return v > 0 ? "\(v)" : "—"
    }

    private func exerciseList(workout: WorkoutPlan) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("EXERCISES").font(.system(size: 10, weight: .black)).foregroundColor(.textTertiary).tracking(2.5)
                Spacer()
                Text("\(workout.exercises.count) total").font(.system(size: 12, weight: .medium)).foregroundColor(.textMuted)
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
        .padding(.vertical, 20).background(Color.surface).cornerRadius(24)
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
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
                Text("Start Workout").font(.system(size: 20, weight: .black))
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 18, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 28).padding(.vertical, 22)
            .background(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.82)],
                                       startPoint: .leading, endPoint: .trailing))
            .cornerRadius(22).shadow(color: Color.ember.opacity(0.55), radius: 24, y: 10)
        }
        .opacity(appeared ? 1 : 0).scaleEffect(appeared ? 1 : 0.92)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.52), value: appeared)
    }
}

// MARK: - Music Control Bar

struct MusicControlBar: View {
    @ObservedObject var controller: AnyMusicController
    var compact: Bool = true

    private var accent: Color { controller.service.accentColor }

    var body: some View {
        Group {
            if let track = controller.nowPlaying {
                playingView(track: track)
            } else if controller.isAuthorized {
                emptyView
            } else {
                unauthorizedView
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: controller.nowPlaying?.isPlaying)
    }

    // MARK: Playing state

    private func playingView(track: NowPlayingTrack) -> some View {
        HStack(spacing: 14) {
            // Album art / service badge
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [accent, accent.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .shadow(color: accent.opacity(0.4), radius: 8, y: 3)

                if track.isPlaying {
                    // Animated waveform bars
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { i in
                            TimelineView(.animation(minimumInterval: 0.1)) { tl in
                                let t = tl.date.timeIntervalSinceReferenceDate + Double(i) * 0.3
                                let h = 6.0 + abs(sin(t * 3.0 + Double(i))) * 10.0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white)
                                    .frame(width: 3, height: h)
                            }
                        }
                    }
                } else {
                    Image(systemName: controller.service.iconName)
                        .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    // Service label pill
                    Text(controller.service.rawValue)
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(accent)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(accent.opacity(0.12))
                        .cornerRadius(4)
                    Text(track.artist)
                        .font(.system(size: 12)).foregroundColor(.textTertiary).lineLimit(1)
                    if let bpm = track.bpm {
                        Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                        Text("\(bpm) BPM")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.steel)
                    }
                }
            }
            Spacer()

            HStack(spacing: 4) {
                Button(action: controller.skipBack) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 15)).foregroundColor(.textSecondary)
                        .frame(width: 36, height: 36)
                }
                Button(action: controller.togglePlayPause) {
                    ZStack {
                        Circle().fill(accent).frame(width: 36, height: 36)
                            .shadow(color: accent.opacity(0.45), radius: 6, y: 2)
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    }
                }
                Button(action: controller.skipForward) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15)).foregroundColor(.textSecondary)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, compact ? 9 : 14)
        .background(Color.surface)
        .cornerRadius(compact ? 16 : 20)
        .overlay(RoundedRectangle(cornerRadius: compact ? 16 : 20)
            .stroke(accent.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    // MARK: Empty state (authorized, nothing playing)

    private var emptyView: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 18)).foregroundColor(.textMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing playing")
                    .font(.system(size: 14)).foregroundColor(.textMuted)
                Text(controller.service.rawValue)
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(accent.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.surface).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
    }

    // MARK: Unauthorized state (needs connect)

    private var unauthorizedView: some View {
        Button {
            Task {
                await controller.requestAccess()
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(accent.opacity(0.12)).frame(width: 34, height: 34)
                    Image(systemName: controller.service.iconName)
                        .font(.system(size: 14)).foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connect \(controller.service.rawValue)")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                    Text("Tap to authorize")
                        .font(.system(size: 11)).foregroundColor(.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12)).foregroundColor(.textMuted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.surface).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Background (Bevel-tier animated mesh)

private struct WorkoutBackground: View {
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.background
            // Slow-moving multi-blob mesh using TimelineView
            TimelineView(.animation(minimumInterval: 1/30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    // Blob 1 — top-left, accent color
                    let x1 = size.width  * (0.15 + 0.12 * sin(t * 0.17))
                    let y1 = size.height * (0.12 + 0.10 * cos(t * 0.13))
                    let r1 = size.width  * 0.55
                    var p1 = Path(); p1.addEllipse(in: CGRect(x: x1-r1/2, y: y1-r1/2, width: r1, height: r1))
                    ctx.fill(p1, with: .color(accentColor.opacity(0.045)))

                    // Blob 2 — bottom-right, steel tint
                    let x2 = size.width  * (0.82 + 0.10 * cos(t * 0.11))
                    let y2 = size.height * (0.75 + 0.12 * sin(t * 0.14))
                    let r2 = size.width  * 0.48
                    var p2 = Path(); p2.addEllipse(in: CGRect(x: x2-r2/2, y: y2-r2/2, width: r2, height: r2))
                    ctx.fill(p2, with: .color(Color(hex: "38BDF8").opacity(0.028)))

                    // Blob 3 — center drift, accent echo
                    let x3 = size.width  * (0.5 + 0.18 * sin(t * 0.09 + 1.0))
                    let y3 = size.height * (0.45 + 0.14 * cos(t * 0.12 + 0.5))
                    let r3 = size.width  * 0.38
                    var p3 = Path(); p3.addEllipse(in: CGRect(x: x3-r3/2, y: y3-r3/2, width: r3, height: r3))
                    ctx.fill(p3, with: .color(accentColor.opacity(0.025)))
                }
            }
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 1.6), value: accentColor)
    }
}

// MARK: - Readiness Intensity Arc (idle screen)

private struct ReadinessIntensityArc: View {
    let readiness: Int
    let intensity: WorkoutIntensity
    @State private var appeared = false

    private var readinessFraction: CGFloat { CGFloat(readiness) / 100 }
    private var intensityFraction: CGFloat {
        switch intensity {
        case .low:      return 0.25
        case .moderate: return 0.50
        case .high:     return 0.75
        case .max:      return 1.0
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
                // Track
                Circle()
                    .stroke(Color.borderColor.opacity(0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 56, height: 56)
                // Readiness arc — green
                Circle()
                    .trim(from: 0, to: appeared ? readinessFraction : 0)
                    .stroke(Color.success.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.1), value: appeared)
                // Intensity arc — ember (slightly smaller radius so both visible)
                Circle()
                    .trim(from: 0, to: appeared ? intensityFraction : 0)
                    .stroke(Color.ember.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.22), value: appeared)

                Text("\(readiness)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(matchColor).frame(width: 6, height: 6)
                        .shadow(color: matchColor.opacity(0.5), radius: 3)
                    Text(matchLabel)
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
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
        .padding(16)
        .background(Color.surface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(matchColor.opacity(0.2), lineWidth: 1))
        .onAppear { appeared = true }
    }
}

// MARK: - Shared Components

struct WorkoutStatPill: View {
    let icon: String; let value: String; let label: String
    var color: Color = .textSecondary
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(color)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundColor(.textPrimary)
            Text(label).font(.system(size: 11)).foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.surface).cornerRadius(100)
        .overlay(Capsule().stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 5, y: 2)
    }
}

struct WorkoutExerciseRow: View {
    let exercise: Exercise; let index: Int
    let isExpanded: Bool; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.ember.opacity(0.18), Color.ember.opacity(0.07)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 42, height: 42)
                        Text("\(index + 1)").font(.system(size: 16, weight: .bold)).foregroundColor(.ember)
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
                        if let notes = exercise.notes {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle.fill").font(.system(size: 13)).foregroundColor(.steel)
                                Text(notes).font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)
                            }
                            .padding(.horizontal, 20)
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
}

struct WorkoutInsightsView: View {
    let workout: WorkoutPlan
    @EnvironmentObject var store: AppStore
    @State private var appeared = false
    private var insights: [(icon: String, text: String, color: Color)] {
        var r: [(String, String, Color)] = []
        if store.readiness.overall >= 80   { r.append(("bolt.fill",       "Readiness excellent — go heavy today.", .ember)) }
        else if store.readiness.overall < 65 { r.append(("bed.double.fill","Recovery low — reduce volume by 20%.", .steel)) }
        if workout.intensity == .high || workout.intensity == .max {
            r.append(("exclamationmark.triangle.fill", "High intensity — warm up before starting.", .warning))
        }
        r.append(("flame.fill", "Estimated \(workout.estimatedCalories) kcal at this intensity.", .success))
        return r
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "brain.head.profile").font(.system(size: 14)).foregroundColor(.ember)
                Text("AI INSIGHTS").font(.system(size: 10, weight: .black)).foregroundColor(.textTertiary).tracking(2.5)
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
    }
}

struct WorkoutEmptyState: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().fill(Color.ember.opacity(0.08)).frame(width: 130, height: 130).blur(radius: 24)
                Image(systemName: "dumbbell.fill").font(.system(size: 58)).foregroundColor(.ember.opacity(0.5))
            }
            .scaleEffect(appeared ? 1 : 0.8).opacity(appeared ? 1 : 0)
            VStack(spacing: 10) {
                Text("No Workout Planned").font(.system(size: 24, weight: .bold)).foregroundColor(.textPrimary)
                Text("Chat with ARIA to generate a plan tailored to your readiness and goals.")
                    .font(.system(size: 15)).foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center).lineSpacing(5).padding(.horizontal, 44)
            }
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 18)
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
            .opacity(appeared ? 1 : 0).scaleEffect(appeared ? 1 : 0.92)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
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

// MARK: - Coach Messages

private let coachMessages = [
    "Slow the eccentric — 3 seconds on the way down.",
    "HR is elevated. Take an extra 30 seconds rest.",
    "Last set felt easy — bump the weight 5 lbs.",
    "Two more reps. You've got this.",
    "Core braced through every single rep.",
    "Control the weight. Don't let it control you.",
    "Breathe out on exertion. Stay in rhythm.",
    "Back straight, chest up. Own the position.",
    "Short rest = more growth hormone. Keep it tight.",
    "Mind-muscle connection. Feel every rep.",
    "O₂ is solid — you can push the pace.",
    "That track is matching your HR zone perfectly.",
]

// MARK: - Active Workout

@MainActor
struct ActiveWorkoutView: View {
    @EnvironmentObject var store: AppStore
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

    // Voice coach
    @State private var voiceCoach = VoiceCoachManager()

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
    private var exercises:       [Exercise] { store.todayWorkout?.exercises ?? [] }
    private var currentExercise: Exercise?  { exercises.indices.contains(store.currentExerciseIndex) ? exercises[store.currentExerciseIndex] : nil }
    private var currentZone: WorkoutHRZone { workoutHRZone(for: simulatedHR) }

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
                    VoiceCoachBar(coach: voiceCoach)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                        .padding(.top, 6)
                }
            }

            // Overlays — highest zIndex first
            if showO2Warning {
                O2WarningBanner(spO2: simulatedSpO2) {
                    withAnimation { showO2Warning = false }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(25)
            }

            if showPRBanner {
                PRBannerView(exerciseName: prExerciseName)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }

            if showSetLogger, let exercise = currentExercise {
                SetLoggerPanel(
                    exercise: exercise,
                    currentSet: store.currentSet,
                    proposedReps: $loggedReps,
                    proposedWeight: $currentWeight,
                    proposedRPE: $loggedRPE,
                    onConfirm: { confirmSet(exercise: exercise) },
                    onCancel: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showSetLogger = false } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(15)
            }

            if showPainLogger, let exercise = currentExercise {
                PainLoggerPanel(
                    exerciseName: exercise.name,
                    onLog: { entry in
                        painLog.append(entry)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showPainLogger = false }
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    },
                    onCancel: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showPainLogger = false } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(15)
            }
        }
        .onAppear {
            startTasks()
            setupCurrentWeight()
            syncVoiceCoachContext()
            if currentExercise != nil {
                voiceCoach.announceWorkoutStart()
            }
        }
        .onDisappear {
            cancelTasks()
            voiceCoach.stopListening()
        }
        .onChange(of: store.currentExerciseIndex) { _, _ in syncVoiceCoachContext() }
        .onChange(of: store.currentSet) { _, _ in syncVoiceCoachContext() }
        .onChange(of: elapsedSecs) { _, _ in syncVoiceCoachContext() }
        .onChange(of: simulatedHR) { _, _ in syncVoiceCoachContext() }
        .onChange(of: isResting) { _, _ in syncVoiceCoachContext() }
        .onChange(of: restTimeLeft) { _, _ in syncVoiceCoachContext() }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showPRBanner)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showO2Warning)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showSetLogger)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showPainLogger)
    }

    // MARK: Cockpit Header

    private var cockpitHeader: some View {
        HStack(spacing: 12) {
            // Zone-reactive left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(currentZone.color)
                .frame(width: 3, height: 36)
                .shadow(color: currentZone.color.opacity(0.8), radius: 6, x: 0, y: 0)
                .animation(.easeInOut(duration: 0.8), value: currentZone.label)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.todayWorkout?.name ?? "")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                HStack(spacing: 5) {
                    Text(store.todayWorkout?.type.label ?? "")
                        .font(.system(size: 11)).foregroundColor(.textTertiary)
                    Circle().fill(Color.textTertiary.opacity(0.5)).frame(width: 2.5, height: 2.5)
                    Text(store.todayWorkout?.intensity.label ?? "")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(currentZone.color)
                        .animation(.easeInOut(duration: 0.8), value: currentZone.label)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                headerBadge(icon: "scalemass.fill", iconColor: .steel,
                            value: "\(totalVolume)", unit: "vol")
                // Elapsed with flashing colon
                TimelineView(.animation(minimumInterval: 0.5)) { tl in
                    let flash = Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill").font(.system(size: 10)).foregroundColor(.textMuted)
                        Text(formatTime(elapsedSecs, flashColon: flash))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color.surface).cornerRadius(100)
                    .overlay(Capsule().stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
                }

                Button(action: handleEnd) {
                    Text(showEndConfirm ? "Confirm?" : "End")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(showEndConfirm ? .white : .danger)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(showEndConfirm ? Color.danger : Color.danger.opacity(0.12))
                        .cornerRadius(9)
                        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: showEndConfirm)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }

    @ViewBuilder
    private func headerBadge(icon: String, iconColor: Color, value: String, unit: String?, mono: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(iconColor)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: mono ? .monospaced : .default))
                .foregroundColor(.textPrimary).contentTransition(.numericText())
            if let u = unit { Text(u).font(.system(size: 10)).foregroundColor(.textTertiary) }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.surface).cornerRadius(100)
        .overlay(Capsule().stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
    }

    // MARK: Nav Strip — exercise names visible on current

    private var exerciseNavStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { idx, ex in
                        HStack(spacing: 4) {
                            navDot(idx: idx, name: ex.name).id(idx)
                            if idx < exercises.count - 1 {
                                Rectangle()
                                    .fill(idx < store.currentExerciseIndex ? Color.ember.opacity(0.6) : Color.borderColor.opacity(0.25))
                                    .frame(width: 12, height: 1.5)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }
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
                // Current: shows name label
                HStack(spacing: 7) {
                    TimelineView(.animation(minimumInterval: 0.05)) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let p = (sin(t * 2.5) + 1) / 2
                        Circle()
                            .fill(Color.ember)
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.ember.opacity(0.5 + p * 0.4), radius: 3 + p * 3)
                    }
                    Text(name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.ember)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.ember.opacity(0.1))
                .cornerRadius(100)
                .overlay(Capsule().stroke(Color.ember.opacity(0.35), lineWidth: 1))
                .shadow(color: Color.ember.opacity(0.2), radius: 6)
            } else if isPast {
                ZStack {
                    Circle().fill(Color.success.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundColor(.success)
                }
            } else {
                ZStack {
                    Circle().fill(Color.surfaceElevated).frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.borderColor.opacity(0.6), lineWidth: 1))
                    Text("\(idx+1)").font(.system(size: 10, weight: .semibold)).foregroundColor(.textMuted)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: store.currentExerciseIndex)
    }

    // MARK: Live Metrics Bar — primary (HR, O2) large; secondary smaller

    private var liveMetricsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // PRIMARY: HR — largest chip, zone-colored
                primaryMetricChip(
                    icon: "heart.fill", iconColor: currentZone.color,
                    value: "\(simulatedHR)", unit: "bpm",
                    accent: currentZone.color, glowing: simulatedHR > 140
                )

                // Zone label
                HStack(spacing: 5) {
                    TimelineView(.animation(minimumInterval: 0.05)) { tl in
                        let t  = tl.date.timeIntervalSinceReferenceDate
                        let p  = (sin(t * 3) + 1) / 2
                        Circle()
                            .fill(currentZone.color)
                            .frame(width: 7, height: 7)
                            .scaleEffect(1 + p * 0.3)
                            .shadow(color: currentZone.color.opacity(0.6 + p * 0.3), radius: 4)
                    }
                    Text(currentZone.label)
                        .font(.system(size: 12, weight: .black)).foregroundColor(currentZone.color)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(currentZone.color.opacity(0.13)).cornerRadius(100)
                .overlay(Capsule().stroke(currentZone.color.opacity(0.35), lineWidth: 1))
                .animation(.easeInOut(duration: 0.7), value: currentZone.label)

                // PRIMARY: SpO2 — large, color-coded
                let o2Color: Color = simulatedSpO2 < 94 ? .danger : simulatedSpO2 < 96 ? .warning : Color(hex: "38BDF8")
                primaryMetricChip(
                    icon: "lungs.fill", iconColor: o2Color,
                    value: "\(simulatedSpO2)%", unit: "O₂",
                    accent: o2Color, glowing: simulatedSpO2 < 95
                )

                // SECONDARY chips
                liveChip(icon: "flame.fill", iconColor: .ember,
                         value: "\(Int(estimatedCals))", unit: "kcal", accent: .ember)
                liveChip(icon: "repeat", iconColor: .steel,
                         value: "\(store.currentSet)/\(currentExercise?.sets ?? 0)", unit: "sets", accent: .steel)
                liveChip(icon: "scalemass.fill", iconColor: .steel,
                         value: "\(totalVolume)", unit: "vol", accent: .steel)

                if let bpm = music.nowPlaying?.bpm {
                    liveChip(icon: "music.note", iconColor: Color(hex: "1DB954"),
                             value: "\(bpm)", unit: "BPM", accent: Color(hex: "1DB954"))
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 6)
    }

    // Primary chip — taller, more prominent
    @ViewBuilder
    private func primaryMetricChip(icon: String, iconColor: Color, value: String, unit: String, accent: Color, glowing: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(iconColor)
            Text(value)
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(.textPrimary)
                .contentTransition(.numericText())
            Text(unit).font(.system(size: 11, weight: .semibold)).foregroundColor(accent.opacity(0.8))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            ZStack {
                Color.surface
                accent.opacity(0.06)
            }
        )
        .cornerRadius(100)
        .overlay(Capsule().stroke(accent.opacity(glowing ? 0.5 : 0.2), lineWidth: glowing ? 1.5 : 1))
        .shadow(color: glowing ? accent.opacity(0.3) : .clear, radius: 8, y: 0)
    }

    @ViewBuilder
    private func liveChip(icon: String, iconColor: Color, value: String, unit: String, accent: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(iconColor)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary).contentTransition(.numericText())
            Text(unit).font(.system(size: 11)).foregroundColor(.textTertiary)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(Color.surface).cornerRadius(100)
        .overlay(Capsule().stroke(accent.opacity(0.2), lineWidth: 1))
    }

    // MARK: Main Content

    @ViewBuilder
    private func mainContent(exercise: Exercise) -> some View {
        ScrollView(showsIndicators: false) {
            Group {
                if isResting {
                    RestTimerView(
                        restTimeLeft: restTimeLeft,
                        totalRest: exercise.restSeconds,
                        nextLabel: nextLabel(exercise: exercise),
                        onSkip: skipRest
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal:   .scale(scale: 0.9).combined(with: .opacity)
                    ))
                } else {
                    exerciseCard(exercise: exercise)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)
                        ))
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
                        Text("Set \(store.currentSet) of \(exercise.sets)")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.ember)
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
                    Text("\(store.currentExerciseIndex + 1)/\(exercises.count)")
                        .font(.system(size: 12)).foregroundColor(.textMuted)
                }
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)

                Divider().background(Color.borderColor.opacity(0.4))

                // Name + demo
                VStack(alignment: .leading, spacing: 14) {
                    Text(exercise.name)
                        .font(.system(size: 26, weight: .bold)).foregroundColor(.textPrimary)
                    ExerciseDemonstrationView(exercise: exercise, selectedTab: $selectedDemoTab)
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 18)

                Divider().background(Color.borderColor.opacity(0.4))

                // Weight × Reps — Bevel-tier full-bleed hero zone
                ZStack {
                    // Zone-reactive background wash
                    currentZone.color.opacity(0.04)
                        .animation(.easeInOut(duration: 0.8), value: currentZone.label)

                    HStack(spacing: 0) {
                        if exercise.weight != nil {
                            VStack(spacing: 4) {
                                HStack(spacing: 10) {
                                    Button {
                                        currentWeight = max(0, currentWeight - 5)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        ZStack {
                                            Circle().fill(Color.surfaceElevated).frame(width: 36, height: 36)
                                                .overlay(Circle().stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
                                            Image(systemName: "minus").font(.system(size: 14, weight: .bold)).foregroundColor(.textMuted)
                                        }
                                    }
                                    VStack(spacing: 1) {
                                        Text("\(currentWeight)")
                                            .font(.system(size: 58, weight: .black, design: .rounded))
                                            .foregroundColor(.textPrimary)
                                            .contentTransition(.numericText())
                                        Text("LBS")
                                            .font(.system(size: 9, weight: .black))
                                            .foregroundColor(currentZone.color.opacity(0.8))
                                            .tracking(3)
                                            .animation(.easeInOut(duration: 0.8), value: currentZone.label)
                                    }
                                    Button {
                                        currentWeight += 5
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        ZStack {
                                            Circle().fill(Color.ember.opacity(0.12)).frame(width: 36, height: 36)
                                                .overlay(Circle().stroke(Color.ember.opacity(0.3), lineWidth: 1))
                                            Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundColor(.ember)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)

                            // Divider between weight and reps
                            Rectangle()
                                .fill(Color.borderColor.opacity(0.35))
                                .frame(width: 1, height: 60)

                        }
                        VStack(spacing: 1) {
                            Text(exercise.reps)
                                .font(.system(size: 58, weight: .black, design: .rounded))
                                .foregroundColor(.textPrimary)
                            Text("REPS")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(currentZone.color.opacity(0.8))
                                .tracking(3)
                                .animation(.easeInOut(duration: 0.8), value: currentZone.label)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 26)
                }

                Divider().background(Color.borderColor.opacity(0.4))

                // Previous sets with RPE badges
                let prevSets = setLog.filter { $0.exerciseName == exercise.name }
                if !prevSets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PREVIOUS SETS")
                            .font(.system(size: 9, weight: .black)).foregroundColor(.textMuted).tracking(2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(prevSets) { entry in
                                    VStack(spacing: 3) {
                                        if entry.isPersonalRecord {
                                            Image(systemName: "crown.fill")
                                                .font(.system(size: 9)).foregroundColor(.warning)
                                        }
                                        Text("\(entry.repsPerformed)")
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                            .foregroundColor(entry.isPersonalRecord ? .warning : .textPrimary)
                                        if entry.weightUsed > 0 {
                                            Text("\(entry.weightUsed)lb")
                                                .font(.system(size: 10)).foregroundColor(.textTertiary)
                                        }
                                        Text("RPE \(entry.rpe)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(rpeColor(entry.rpe))
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(entry.isPersonalRecord ? Color.warning.opacity(0.1) : Color.surfaceElevated)
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(entry.isPersonalRecord ? Color.warning.opacity(0.4) : Color.borderColor.opacity(0.4), lineWidth: 1))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    Divider().background(Color.borderColor.opacity(0.4))
                }

                // Footer
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill").font(.system(size: 11)).foregroundColor(.textMuted)
                    Text("\(exercise.restSeconds)s rest").font(.system(size: 12)).foregroundColor(.textTertiary)
                    if let notes = exercise.notes {
                        Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                        Text(notes).font(.system(size: 12, design: .serif).italic()).foregroundColor(.textTertiary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .background(Color.surface)
            .cornerRadius(24)
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
                loggedReps = Int(exercise.reps) ?? 0
                loggedRPE  = 7
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { showSetLogger = true }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isFinish ? "checkmark.circle.fill" : "pencil.and.list.clipboard")
                        .font(.system(size: 19, weight: .black))
                    Text(isFinish ? "Log & Finish 🎉" : isLastSet ? "Log Set · Next Exercise →" : "Log Set →")
                        .font(.system(size: 17, weight: .black))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24).padding(.vertical, 20).frame(maxWidth: .infinity)
                .background(LinearGradient(
                    colors: isFinish ? [Color.success, Color.success.opacity(0.8)] : [Color.ember, Color.ember.opacity(0.82)],
                    startPoint: .leading, endPoint: .trailing
                ))
                .cornerRadius(20)
                .shadow(color: (isFinish ? Color.success : Color.ember).opacity(0.5), radius: 20, y: 8)
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isFinish)
            }

            HStack(spacing: 10) {
                Button(action: skipExercise) {
                    HStack(spacing: 5) {
                        Image(systemName: "forward.fill").font(.system(size: 12))
                        Text("Skip").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color.surfaceElevated).cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { showPainLogger = true }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
                        Text(painLog.isEmpty ? "Pain" : "Pain (\(painLog.count))")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.warning)
                    .frame(height: 46).padding(.horizontal, 16)
                    .background(Color.warning.opacity(painLog.isEmpty ? 0.1 : 0.2)).cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.warning.opacity(0.3), lineWidth: 1))
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if voiceCoach.isListening {
                        voiceCoach.stopListening()
                    } else {
                        voiceCoach.startListening()
                    }
                } label: {
                    Image(systemName: voiceCoach.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.ember).frame(width: 46, height: 46)
                        .background(Color.ember.opacity(0.1)).cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ember.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }

    // MARK: Logic Helpers

    private func syncVoiceCoachContext() {
        guard let exercise = currentExercise else { return }
        voiceCoach.updateContext(
            WorkoutContext(
                workoutName: store.todayWorkout?.name ?? "",
                exerciseName: exercise.name,
                currentSet: store.currentSet,
                sets: exercise.sets,
                reps: exercise.reps,
                weight: exercise.weight.map { "\($0) lbs" } ?? "BW",
                elapsedTime: formatTime(elapsedSecs, flashColon: false),
                heartRate: simulatedHR,
                hrZone: workoutHRZones.firstIndex(where: { $0.label == currentZone.label }) ?? 0 + 1,
                calories: Int(estimatedCals),
                restSeconds: exercise.restSeconds,
                notes: exercise.notes ?? ""
            )
        )
        WorkoutLiveActivityManager.update(
            WorkoutActivityAttributes.ContentState(
                exerciseName: exercise.name,
                currentSet: store.currentSet,
                totalSets: exercise.sets,
                restSecondsRemaining: restTimeLeft,
                isResting: isResting,
                elapsedSeconds: elapsedSecs,
                heartRate: simulatedHR,
                hrZoneLabel: currentZone.label
            )
        )
    }

    private func rpeColor(_ rpe: Int) -> Color {
        rpe <= 4 ? .success : rpe <= 7 ? Color(hex: "F59E0B") : .danger
    }

    private func setupCurrentWeight() {
        currentWeight = currentExercise?.weight ?? 0
    }

    private func confirmSet(exercise: Exercise) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { showSetLogger = false }

        let existingMax = setLog.filter { $0.exerciseName == exercise.name }.map { $0.weightUsed }.max() ?? 0
        let isPR = currentWeight > existingMax && currentWeight > 0

        let entry = SetLogEntry(exerciseName: exercise.name, setNumber: store.currentSet,
                                repsPerformed: loggedReps, weightUsed: currentWeight,
                                rpe: loggedRPE, isPersonalRecord: isPR)
        setLog.append(entry)
        totalVolume += entry.volume

        if isPR {
            prExerciseName = exercise.name
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { showPRBanner = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeOut(duration: 0.4)) { showPRBanner = false }
            }
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        voiceCoach.announceSetComplete(
            setNumber: store.currentSet,
            totalSets: exercise.sets,
            restSeconds: exercise.restSeconds
        )

        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx  = store.currentExerciseIndex >= exercises.count - 1
        if isLastSet && isLastEx { endWorkout(); return }
        if isLastSet { store.nextExercise(); setupCurrentWeight() } else { store.nextSet() }
        startRest(seconds: exercise.restSeconds)
    }

    private func endWorkout() {
        cancelTasks()
        let avgHR  = hrHistory.isEmpty ? simulatedHR : hrHistory.reduce(0, +) / hrHistory.count
        let rpes   = setLog.map { Double($0.rpe) }
        let avgRPE = rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
        let prs    = Array(Set(setLog.filter { $0.isPersonalRecord }.map { $0.exerciseName }))
        let data   = WorkoutSummaryData(
            duration: elapsedSecs, totalVolume: totalVolume,
            totalSets: setLog.count, totalReps: setLog.reduce(0) { $0 + $1.repsPerformed },
            peakHR: peakHR, avgHR: avgHR,
            peakO2: peakSpO2, minO2: minSpO2,
            caloriesBurned: Int(estimatedCals),
            personalRecords: prs,
            exercisesCompleted: min(store.currentExerciseIndex + 1, exercises.count),
            avgRPE: avgRPE, hrHistory: hrHistory
        )
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
        restTimeLeft = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func handleEnd() {
        if showEndConfirm { endWorkout() }
        else {
            showEndConfirm = true
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                showEndConfirm = false
            }
        }
    }

    private func startRest(seconds: Int) {
        restTimeLeft = seconds
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
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                elapsedSecs += 1
            }
        }
        hrTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                let target = isResting ? (108 + Double.random(in: 0...18)) : (140 + Double.random(in: 0...26))
                let current = Double(simulatedHR)
                let drift = (target - current) * 0.12
                let noise = Double.random(in: -4...4)
                let nextHR = (current + drift + noise).rounded().clamped(to: 55.0...200.0)
                simulatedHR = Int(nextHR)
                hrHistory.append(simulatedHR)
                if simulatedHR > peakHR { peakHR = simulatedHR }
            }
        }
        calTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                estimatedCals += simulatedHR > 150 ? 0.21 : simulatedHR > 130 ? 0.16 : 0.11
            }
        }
        o2Task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                let drop     = simulatedHR > 160 ? Double.random(in: 1...3) : simulatedHR > 140 ? Double.random(in: 0...1.5) : 0.0
                let recovery = isResting ? Double.random(in: 0...1) : 0
                simulatedSpO2 = Int((Double(simulatedSpO2) - drop + recovery).rounded().clamped(to: 90.0...100.0))
                if simulatedSpO2 > peakSpO2 { peakSpO2 = simulatedSpO2 }
                if simulatedSpO2 < minSpO2  { minSpO2  = simulatedSpO2 }
                if simulatedSpO2 < 94 && !showO2Warning {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showO2Warning = true }
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        withAnimation { showO2Warning = false }
                    }
                }
            }
        }
    }

    private func cancelTasks() {
        [elapsedTask, hrTask, calTask, o2Task, restTask].forEach { $0?.cancel() }
        elapsedTask = nil; hrTask = nil; calTask = nil; o2Task = nil; restTask = nil
    }

    private func formatTime(_ s: Int, flashColon: Bool = true) -> String {
        let sep = flashColon ? ":" : " "
        return String(format: "%02d\(sep)%02d", s / 60, s % 60)
    }
}

// MARK: - O2 Warning Banner

private struct O2WarningBanner: View {
    let spO2: Int
    let onDismiss: () -> Void
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.danger.opacity(0.2)).frame(width: 40, height: 40)
                    Image(systemName: "lungs.fill").font(.system(size: 18)).foregroundColor(.danger)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOW O₂ SATURATION")
                        .font(.system(size: 11, weight: .black)).foregroundColor(.danger).tracking(1.5)
                    Text("\(spO2)% — Slow down and breathe deeply")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.textMuted)
                        .frame(width: 28, height: 28).background(Color.surfaceElevated).clipShape(Circle())
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(ZStack {
                Color.surface
                LinearGradient(colors: [Color.danger.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing)
            })
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.danger.opacity(0.45), lineWidth: 1.5))
            .shadow(color: Color.danger.opacity(0.25), radius: 20, y: 6)
            .padding(.horizontal, 16).padding(.top, 56)
            Spacer()
        }
    }
}

// MARK: - Set Logger Panel — Bevel dark glass modal

private struct SetLoggerPanel: View {
    let exercise: Exercise
    let currentSet: Int
    @Binding var proposedReps: Int
    @Binding var proposedWeight: Int
    @Binding var proposedRPE: Int
    let onConfirm: () -> Void
    let onCancel:  () -> Void
    @State private var rpePulsing: Int? = nil

    private func rpeLabel(_ r: Int) -> String {
        switch r {
        case 1...3: return "Easy"
        case 4...5: return "Moderate"
        case 6...7: return "Hard"
        case 8:     return "Very Hard"
        case 9:     return "Max Effort"
        default:    return "All Out 🔥"
        }
    }
    private func rpeColor(_ r: Int) -> Color {
        r <= 4 ? .success : r <= 7 ? Color(hex: "F59E0B") : .danger
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { onCancel() }
            VStack {
                Spacer()
                VStack(spacing: 0) {
                    VStack(spacing: 14) {
                        Capsule().fill(Color.white.opacity(0.18)).frame(width: 36, height: 4)
                        Text("SET \(currentSet) — \(exercise.name.uppercased())")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white.opacity(0.45)).tracking(2.5)
                    }
                    .padding(.top, 16).padding(.bottom, 18)
                    Divider().background(Color.white.opacity(0.08))
                    VStack(spacing: 20) {
                        // Reps
                        VStack(spacing: 10) {
                            Text("REPS PERFORMED")
                                .font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                            HStack(spacing: 32) {
                                Button {
                                    if proposedReps > 1 { proposedReps -= 1 }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    ZStack {
                                        Circle().fill(Color.white.opacity(0.08)).frame(width: 44, height: 44)
                                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                        Image(systemName: "minus").font(.system(size: 18, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                Text("\(proposedReps)")
                                    .font(.system(size: 72, weight: .black, design: .rounded))
                                    .foregroundColor(.white).frame(minWidth: 90).contentTransition(.numericText())
                                Button {
                                    proposedReps += 1
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    ZStack {
                                        Circle().fill(Color.ember.opacity(0.22)).frame(width: 44, height: 44)
                                            .overlay(Circle().stroke(Color.ember.opacity(0.4), lineWidth: 1))
                                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundColor(.ember)
                                    }
                                }
                            }
                        }
                        // Weight
                        if exercise.weight != nil && proposedWeight > 0 {
                            VStack(spacing: 10) {
                                Text("WEIGHT (LBS)")
                                    .font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                                HStack(spacing: 7) {
                                    ForEach([(-10, "-10"), (-5, "-5"), (5, "+5"), (10, "+10")], id: \.0) { delta, lbl in
                                        Button {
                                            proposedWeight = max(0, proposedWeight + delta)
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        } label: {
                                            Text(lbl).font(.system(size: 14, weight: .bold))
                                                .foregroundColor(delta > 0 ? .ember : .white.opacity(0.6))
                                                .frame(maxWidth: .infinity).frame(height: 40)
                                                .background(delta > 0 ? Color.ember.opacity(0.15) : Color.white.opacity(0.07))
                                                .cornerRadius(10)
                                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(delta > 0 ? Color.ember.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1))
                                        }
                                    }
                                    Text("\(proposedWeight)")
                                        .font(.system(size: 18, weight: .black, design: .rounded))
                                        .foregroundColor(.white).contentTransition(.numericText()).frame(minWidth: 52)
                                }
                            }
                        }
                        // RPE
                        VStack(spacing: 10) {
                            HStack {
                                Text("EFFORT")
                                    .font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                                Spacer()
                                Text("RPE \(proposedRPE) — \(rpeLabel(proposedRPE))")
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(rpeColor(proposedRPE))
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: proposedRPE)
                            }
                            HStack(spacing: 3) {
                                ForEach(1...10, id: \.self) { level in
                                    Button {
                                        proposedRPE = level
                                        rpePulsing = level
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        Task {
                                            try? await Task.sleep(nanoseconds: 180_000_000)
                                            rpePulsing = nil
                                        }
                                    } label: {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(level <= proposedRPE ? rpeColor(level) : Color.white.opacity(0.07))
                                            .frame(maxWidth: .infinity).frame(height: 36)
                                            .overlay(Text("\(level)").font(.system(size: 11, weight: .black))
                                                .foregroundColor(level <= proposedRPE ? .white : .white.opacity(0.25)))
                                            .scaleEffect(rpePulsing == level ? 1.18 : 1.0)
                                            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: rpePulsing)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        // Confirm
                        Button(action: onConfirm) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                                Text("Log Set").font(.system(size: 20, weight: .black))
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 60)
                            .background(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.82)],
                                                       startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(20).shadow(color: Color.ember.opacity(0.55), radius: 20, y: 6)
                        }
                        Button(action: onCancel) {
                            Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.bottom, 8)
                    }
                    .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 28)
                }
                .background(ZStack {
                    Color(hex: "0E0E0E")
                    LinearGradient(colors: [Color.ember.opacity(0.07), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                })
                .roundedCorners(32, corners: [.topLeft, .topRight])
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                        .mask(Rectangle().padding(.bottom, -40))
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Pain Logger Panel

private struct PainLoggerPanel: View {
    let exerciseName: String
    let onLog:    (PainEntry) -> Void
    let onCancel: () -> Void

    @State private var selectedLocation = "Knee"
    @State private var severity = 5
    private let locations = ["Shoulder", "Elbow", "Wrist", "Lower Back", "Hip", "Knee", "Ankle", "Neck", "Other"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Capsule().fill(Color.textTertiary.opacity(0.4)).frame(width: 36, height: 4).padding(.top, 12)

                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15)).foregroundColor(.warning)
                    Text("LOG PAIN / DISCOMFORT")
                        .font(.system(size: 11, weight: .black)).foregroundColor(.textTertiary).tracking(2)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("LOCATION").font(.system(size: 10, weight: .black)).foregroundColor(.textMuted).tracking(2)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(locations, id: \.self) { loc in
                            Button {
                                selectedLocation = loc
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                Text(loc).font(.system(size: 13, weight: .medium))
                                    .foregroundColor(selectedLocation == loc ? .white : .textSecondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(selectedLocation == loc ? Color.warning : Color.surfaceElevated)
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(selectedLocation == loc ? Color.warning.opacity(0.5) : Color.borderColor.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("SEVERITY").font(.system(size: 10, weight: .black)).foregroundColor(.textMuted).tracking(2)
                        Spacer()
                        Text("\(severity)/10").font(.system(size: 13, weight: .bold))
                            .foregroundColor(severity >= 7 ? .danger : .warning)
                    }
                    HStack(spacing: 3) {
                        ForEach(1...10, id: \.self) { level in
                            Button {
                                severity = level
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(level <= severity ? (severity >= 7 ? Color.danger : Color.warning) : Color.surfaceElevated)
                                    .frame(maxWidth: .infinity).frame(height: 32)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.borderColor.opacity(0.3), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    onLog(PainEntry(location: selectedLocation, severity: severity, exerciseName: exerciseName))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18))
                        Text("Log Pain").font(.system(size: 18, weight: .black))
                    }
                    .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 56)
                    .background(LinearGradient(colors: [Color.warning, Color.warning.opacity(0.82)],
                                               startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(18).shadow(color: Color.warning.opacity(0.5), radius: 16, y: 6)
                }
                .padding(.horizontal, 4)

                Button(action: onCancel) {
                    Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundColor(.textSecondary)
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
            .background(Color.surface)
            .roundedCorners(28, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.22), radius: 40, y: -10)
        }
        .ignoresSafeArea()
    }
}

// MARK: - PR Banner

private struct PRBannerView: View {
    let exerciseName: String
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.warning.opacity(0.2)).frame(width: 40, height: 40)
                    Image(systemName: "trophy.fill").font(.system(size: 18)).foregroundColor(.warning)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("PERSONAL RECORD 🏆")
                        .font(.system(size: 12, weight: .black)).foregroundColor(.warning).tracking(1.5)
                    Text(exerciseName)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(ZStack {
                Color.surface
                LinearGradient(colors: [Color.warning.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing)
            })
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.warning.opacity(0.4), lineWidth: 1.5))
            .shadow(color: Color.warning.opacity(0.25), radius: 20, y: 6)
            .padding(.horizontal, 16).padding(.top, 56)
            Spacer()
        }
    }
}

// MARK: - Rest Timer — Bevel-tier layered rings + breath pacer

struct RestTimerView: View {
    let restTimeLeft: Int
    let totalRest:    Int
    let nextLabel:    String
    let onSkip:       () -> Void

    @State private var breathPhase = false

    private var progress:  CGFloat { totalRest > 0 ? CGFloat(restTimeLeft) / CGFloat(totalRest) : 0 }
    private var urgency:   Bool    { restTimeLeft <= 5 && restTimeLeft > 0 }
    private var ringColor: Color   { urgency ? .danger : Color(hex: "38BDF8") }
    private var breathLabel: String { breathPhase ? "Exhale slowly" : "Breathe in" }

    var body: some View {
        VStack(spacing: 20) {
            // Label
            Text("REST")
                .font(.system(size: 11, weight: .black)).foregroundColor(.textMuted).tracking(4)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color.surfaceElevated).cornerRadius(100)
                .overlay(Capsule().stroke(Color.borderColor.opacity(0.4), lineWidth: 1))

            // Layered ring system
            ZStack {
                // Outer ambient glow (wide, soft)
                Circle()
                    .fill(ringColor.opacity(0.06))
                    .frame(width: 220, height: 220)
                    .animation(.easeInOut(duration: 1.0), value: ringColor)

                // Track ring
                Circle()
                    .stroke(Color.borderColor.opacity(0.25), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 170, height: 170)

                // Glow progress ring (blurred — creates halo)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor.opacity(0.5), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 170, height: 170)
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 6)
                    .animation(.linear(duration: 1), value: progress)

                // Main progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [ringColor, ringColor.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 170, height: 170)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                    .animation(.easeInOut(duration: 0.6), value: ringColor)

                // Breath pacer — concentric expanding rings
                ZStack {
                    // Outer breath ring
                    Circle()
                        .stroke(Color(hex: "38BDF8").opacity(breathPhase ? 0.15 : 0.0), lineWidth: 1.5)
                        .frame(width: breathPhase ? 130 : 80, height: breathPhase ? 130 : 80)
                        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathPhase)

                    // Middle breath ring
                    Circle()
                        .stroke(Color(hex: "38BDF8").opacity(breathPhase ? 0.25 : 0.08), lineWidth: 2)
                        .frame(width: breathPhase ? 100 : 60, height: breathPhase ? 100 : 60)
                        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathPhase)

                    // Inner fill
                    Circle()
                        .fill(Color(hex: "38BDF8").opacity(breathPhase ? 0.15 : 0.04))
                        .frame(width: breathPhase ? 80 : 50, height: breathPhase ? 80 : 50)
                        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathPhase)
                }
                .opacity(urgency ? 0 : 1) // Hide pacer when urgency kicks in

                // Countdown
                VStack(spacing: 3) {
                    Text("\(restTimeLeft)")
                        .font(.system(size: 62, weight: .black, design: .rounded))
                        .foregroundColor(urgency ? .danger : .textPrimary)
                        .contentTransition(.numericText())
                        .scaleEffect(urgency ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: urgency)
                    Text("sec").font(.system(size: 12, weight: .semibold)).foregroundColor(.textMuted)
                }
            }
            .frame(width: 220, height: 220)

            // Breath label
            if !urgency {
                Text(breathLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "38BDF8").opacity(0.8))
                    .animation(.easeInOut(duration: 0.5), value: breathPhase)
            }

            Text(nextLabel)
                .font(.system(size: 14, weight: .medium)).foregroundColor(.textTertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)

            Button(action: onSkip) {
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill").font(.system(size: 13))
                    Text("Skip Rest").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 28).padding(.vertical, 14)
                .background(Color.surfaceElevated).cornerRadius(100)
                .overlay(Capsule().stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breathPhase = true }
        }
    }
}

// MARK: - Workout Summary

struct WorkoutSummaryView: View {
    let data: WorkoutSummaryData
    let onDismiss: () -> Void
    @State private var appeared = false
    @State private var scoreAppeared = false

    // Computed overall workout score 0–100
    private var workoutScore: Int {
        var s = 60
        if data.personalRecords.count > 0 { s += min(20, data.personalRecords.count * 7) }
        if data.avgRPE >= 6 && data.avgRPE <= 8.5 { s += 10 }
        if data.minO2 >= 95 { s += 5 }
        if data.totalSets >= 12 { s += 5 }
        return min(100, s)
    }

    private var scoreLabel: String {
        switch workoutScore {
        case 90...: return "Elite"
        case 80...: return "Excellent"
        case 70...: return "Strong"
        case 60...: return "Solid"
        default:    return "Good"
        }
    }

    private var scoreColor: Color {
        switch workoutScore {
        case 90...: return Color(hex: "F59E0B")
        case 80...: return .success
        case 70...: return .ember
        default:    return .steel
        }
    }

    var body: some View {
        ZStack {
            // Dark editorial background
            Color(hex: "0A0A0A").ignoresSafeArea()

            // Ambient color wash matching score
            RadialGradient(
                colors: [scoreColor.opacity(appeared ? 0.12 : 0), .clear],
                center: .top, startRadius: 0, endRadius: 400
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.5).delay(0.5), value: appeared)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── HERO: Score Ring ──────────────────────────────────
                    VStack(spacing: 24) {
                        ZStack {
                            // Outer glow ring
                            Circle()
                                .stroke(scoreColor.opacity(appeared ? 0.12 : 0), lineWidth: 1)
                                .frame(width: 220, height: 220)
                                .animation(.easeInOut(duration: 1.0).delay(0.4), value: appeared)

                            // Track
                            Circle()
                                .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 180, height: 180)

                            // Score arc
                            Circle()
                                .trim(from: 0, to: scoreAppeared ? CGFloat(workoutScore) / 100 : 0)
                                .stroke(
                                    LinearGradient(
                                        colors: [scoreColor.opacity(0.7), scoreColor, scoreColor.opacity(0.9)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .frame(width: 180, height: 180)
                                .rotationEffect(.degrees(-90))
                                .shadow(color: scoreColor.opacity(0.5), radius: 12)
                                .animation(.spring(response: 1.4, dampingFraction: 0.75).delay(0.5), value: scoreAppeared)

                            // Inner content
                            VStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 22, weight: .black))
                                    .foregroundColor(scoreColor)
                                    .scaleEffect(appeared ? 1 : 0.4)
                                    .opacity(appeared ? 1 : 0)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.3), value: appeared)

                                Text("\(workoutScore)")
                                    .font(.system(size: 52, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                    .scaleEffect(appeared ? 1 : 0.6)
                                    .opacity(appeared ? 1 : 0)
                                    .animation(.spring(response: 0.65, dampingFraction: 0.7).delay(0.2), value: appeared)

                                Text(scoreLabel.uppercased())
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(scoreColor)
                                    .tracking(2.5)
                                    .opacity(appeared ? 1 : 0)
                                    .animation(.easeOut(duration: 0.5).delay(0.55), value: appeared)
                            }
                        }
                        .frame(width: 220, height: 220)

                        VStack(spacing: 8) {
                            Text("Workout Complete")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                            HStack(spacing: 16) {
                                HStack(spacing: 5) {
                                    Image(systemName: "clock.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                                    Text(formatDuration(data.duration))
                                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                                }
                                if !data.personalRecords.isEmpty {
                                    HStack(spacing: 5) {
                                        Image(systemName: "crown.fill").font(.system(size: 12)).foregroundColor(.warning)
                                        Text("\(data.personalRecords.count) PR\(data.personalRecords.count == 1 ? "" : "s")")
                                            .font(.system(size: 14, weight: .bold)).foregroundColor(.warning)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.warning.opacity(0.15)).cornerRadius(100)
                                    .overlay(Capsule().stroke(Color.warning.opacity(0.3), lineWidth: 1))
                                }
                            }
                        }
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: appeared)
                    }
                    .padding(.top, 64).padding(.bottom, 36)

                    // ── HR SPARKLINE ──────────────────────────────────────
                    if !data.hrHistory.isEmpty {
                        HRSparklineCard(hrHistory: data.hrHistory, peakHR: data.peakHR, avgHR: data.avgHR)
                            .padding(.horizontal, 16).padding(.bottom, 20)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.35), value: appeared)
                    }

                    // ── STATS GRID ────────────────────────────────────────
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach([
                            ("scalemass.fill",    "\(data.totalVolume)",                   "Volume",       Color.steel),
                            ("flame.fill",         "\(data.caloriesBurned)",                "Kcal",         Color.ember),
                            ("repeat",             "\(data.totalSets)",                     "Sets",         Color.success),
                            ("hand.raised.fill",   "\(data.totalReps)",                     "Reps",         Color(hex: "F59E0B")),
                            ("heart.fill",         "\(data.peakHR)",                        "Peak HR",      Color.danger),
                            ("waveform.path.ecg",  "\(data.avgHR)",                         "Avg HR",       Color.steel),
                            ("lungs.fill",         "\(data.minO2)%",                        "Min O₂",       data.minO2 < 94 ? Color.danger : Color(hex: "38BDF8")),
                            ("bolt.fill",          String(format: "%.1f", data.avgRPE),     "Avg RPE",      rpeColor(data.avgRPE)),
                            ("dumbbell.fill",      "\(data.exercisesCompleted)",             "Exercises",    Color.ember),
                        ], id: \.0) { icon, value, label, color in
                            darkStatCard(icon, value, label, color)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.45), value: appeared)

                    // ── HR ZONE BREAKDOWN ─────────────────────────────────
                    ZoneBreakdownCard(hrHistory: data.hrHistory)
                        .padding(.horizontal, 16).padding(.bottom, 20)
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.55), value: appeared)

                    // ── PRs ───────────────────────────────────────────────
                    if !data.personalRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Image(systemName: "crown.fill").font(.system(size: 14)).foregroundColor(.warning)
                                Text("PERSONAL RECORDS")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(.white.opacity(0.4)).tracking(2.5)
                            }
                            ForEach(data.personalRecords, id: \.self) { pr in
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.warning.opacity(0.15)).frame(width: 38, height: 38)
                                        Image(systemName: "crown.fill").font(.system(size: 15)).foregroundColor(.warning)
                                    }
                                    Text(pr).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                                    Spacer()
                                    Text("NEW PR")
                                        .font(.system(size: 10, weight: .black)).foregroundColor(.warning).tracking(1)
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(Color.warning.opacity(0.15)).cornerRadius(100)
                                        .overlay(Capsule().stroke(Color.warning.opacity(0.3), lineWidth: 1))
                                }
                                .padding(16)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.warning.opacity(0.2), lineWidth: 1))
                            }
                        }
                        .padding(20)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(22)
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07), lineWidth: 1))
                        .padding(.horizontal, 16).padding(.bottom, 20)
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.6), value: appeared)
                    }

                    // ── ACTIONS ───────────────────────────────────────────
                    VStack(spacing: 12) {
                        Button(action: onDismiss) {
                            HStack(spacing: 10) {
                                Image(systemName: "house.fill").font(.system(size: 16))
                                Text("Back to Dashboard").font(.system(size: 17, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 58)
                            .background(LinearGradient(
                                colors: [Color.ember, Color.ember.opacity(0.82)],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .cornerRadius(18)
                            .shadow(color: Color.ember.opacity(0.5), radius: 18, y: 6)
                        }
                        Button { UIImpactFeedbackGenerator(style: .light).impactOccurred() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up").font(.system(size: 15))
                                Text("Share Workout").font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Color.white.opacity(0.07)).cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 60)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.7), value: appeared)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.8).delay(0.1)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scoreAppeared = true }
        }
    }

    private func darkStatCard(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
            }
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func rpeColor(_ rpe: Double) -> Color {
        rpe <= 4 ? .success : rpe <= 7 ? Color(hex: "F59E0B") : .danger
    }

    private func formatDuration(_ s: Int) -> String {
        let m = s / 60; let sec = s % 60
        return m > 0 ? "\(m)m \(sec)s" : "\(sec)s"
    }
}

// MARK: - Zone Breakdown Card

private struct ZoneBreakdownCard: View {
    let hrHistory: [Int]
    @State private var barsAppeared = false

    private struct ZoneBar {
        let zone: String
        let color: Color
        let range: ClosedRange<Int>
        var count: Int = 0
    }

    private var zoneBars: [ZoneBar] {
        var bars = [
            ZoneBar(zone: "Z1", color: Color(hex: "38BDF8"), range: 100...114),
            ZoneBar(zone: "Z2", color: .success,             range: 115...133),
            ZoneBar(zone: "Z3", color: Color(hex: "F59E0B"), range: 134...152),
            ZoneBar(zone: "Z4", color: .ember,               range: 153...171),
            ZoneBar(zone: "Z5", color: .danger,              range: 172...220),
        ]
        for hr in hrHistory {
            for i in bars.indices where bars[i].range.contains(hr) {
                bars[i].count += 1
            }
        }
        return bars
    }

    var body: some View {
        let bars = zoneBars
        let maxCount = max(1, bars.map { $0.count }.max() ?? 1)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 13)).foregroundColor(.danger)
                Text("HEART RATE ZONES")
                    .font(.system(size: 10, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                Spacer()
                Text("\(hrHistory.count) samples")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(bars.enumerated()), id: \.element.zone) { idx, bar in
                    VStack(spacing: 8) {
                        let fraction = barsAppeared ? CGFloat(bar.count) / CGFloat(maxCount) : 0
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.06))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(
                                    colors: [bar.color, bar.color.opacity(0.6)],
                                    startPoint: .top, endPoint: .bottom
                                ))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(4, 80 * fraction))
                                .shadow(color: bar.color.opacity(0.4), radius: 4)
                        }
                        .frame(height: 80)
                        // Fixed: use enumerated idx instead of O(n) firstIndex lookup
                        .animation(.spring(response: 0.9, dampingFraction: 0.75)
                                    .delay(Double(idx) * 0.08), value: barsAppeared)

                        Text(formatZoneTime(bar.count))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(bar.count > 0 ? bar.color : .white.opacity(0.2))

                        Text(bar.zone)
                            .font(.system(size: 10, weight: .black)).foregroundColor(.white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.04))
        .cornerRadius(22)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { barsAppeared = true }
        }
    }

    // Convert sample count to approx time (assumes ~1.5s per HR sample)
    private func formatZoneTime(_ count: Int) -> String {
        let secs = count * 2
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m"
    }
}

// MARK: - HR Sparkline Card (dark glass edition)

private struct HRSparklineCard: View {
    let hrHistory: [Int]
    let peakHR: Int
    let avgHR:  Int
    @State private var lineAppeared = false

    private var smoothed: [Int] {
        guard hrHistory.count > 4 else { return hrHistory }
        let step = max(1, hrHistory.count / 60)
        return stride(from: 0, to: hrHistory.count, by: step).map { hrHistory[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.system(size: 13)).foregroundColor(.danger)
                    Text("HEART RATE")
                        .font(.system(size: 10, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                }
                Spacer()
                HStack(spacing: 18) {
                    VStack(spacing: 1) {
                        Text("\(peakHR)").font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.danger)
                        Text("peak").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.35))
                    }
                    VStack(spacing: 1) {
                        Text("\(avgHR)").font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.white)
                        Text("avg").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.35))
                    }
                }
            }

            GeometryReader { geo in
                Canvas { ctx, size in
                    let pts = smoothed
                    guard pts.count > 1 else { return }
                    let minV = Double(pts.min() ?? 60)
                    let maxV = Double(pts.max() ?? 200)
                    let rng  = max(maxV - minV, 1)
                    let xStep = size.width / Double(pts.count - 1)

                    func y(_ v: Int) -> Double { size.height - (Double(v) - minV) / rng * size.height }
                    func pt(_ i: Int) -> CGPoint { CGPoint(x: Double(i) * xStep, y: y(pts[i])) }

                    // Zone band fills
                    let zoneDefs: [(min: Int, max: Int, col: Color)] = [
                        (100, 114, Color(hex: "38BDF8")),
                        (115, 133, .success),
                        (134, 152, Color(hex: "F59E0B")),
                        (153, 171, .ember),
                        (172, 220, .danger),
                    ]
                    for z in zoneDefs {
                        let yT = max(0.0, size.height - (Double(z.max) - minV) / rng * size.height)
                        let yB = min(size.height, size.height - (Double(z.min) - minV) / rng * size.height)
                        if yB > yT {
                            ctx.fill(Path(CGRect(x: 0, y: yT, width: size.width, height: yB - yT)),
                                     with: .color(z.col.opacity(0.09)))
                        }
                    }

                    // Filled area
                    var area = Path()
                    area.move(to: CGPoint(x: 0, y: size.height))
                    for i in pts.indices {
                        i == 0 ? area.move(to: pt(0)) : area.addLine(to: pt(i))
                    }
                    area.addLine(to: CGPoint(x: size.width, y: size.height))
                    area.closeSubpath()
                    ctx.fill(area, with: .color(Color.danger.opacity(0.10)))

                    // Line stroke
                    var line = Path()
                    for i in pts.indices { i == 0 ? line.move(to: pt(0)) : line.addLine(to: pt(i)) }
                    ctx.stroke(line, with: .color(Color.danger.opacity(0.85)), lineWidth: 2)
                }
                .opacity(lineAppeared ? 1 : 0)
                .animation(.easeInOut(duration: 0.8), value: lineAppeared)
            }
            .frame(height: 88)
        }
        .padding(20)
        .background(Color.white.opacity(0.04))
        .cornerRadius(22)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { lineAppeared = true }
        }
    }
}

// MARK: - Exercise Demonstration

enum ExerciseDemoTab: CaseIterable { case video, formCheck }

struct ExerciseDemonstrationView: View {
    let exercise: Exercise
    @Binding var selectedTab: ExerciseDemoTab

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ExerciseDemoTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) { selectedTab = tab }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab == .video ? "play.circle.fill" : "camera.fill").font(.system(size: 12))
                            Text(tab == .video ? "Video" : "Form Check").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(selectedTab == tab ? .white : .textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.ember : Color.surfaceElevated)
                        .cornerRadius(10)
                        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: selectedTab)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Group {
                switch selectedTab {
                case .video:     ExerciseVideoPlayer(exercise: exercise)
                case .formCheck: ExerciseFormCheckView(exercise: exercise)
                }
            }
            .id(selectedTab)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
            .frame(height: 190)
            .background(Color.background.opacity(0.5))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: selectedTab)
        }
    }
}

struct ExerciseVideoPlayer: View {
    let exercise: Exercise
    @State private var isPlaying = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.ember.opacity(0.09), Color.ember.opacity(0.03)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 42)).foregroundColor(.ember.opacity(0.45))
                Text(exercise.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                Button { isPlaying.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13))
                        Text(isPlaying ? "Pause" : "Play Demo").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.ember).cornerRadius(20).shadow(color: Color.ember.opacity(0.35), radius: 8, y: 3)
                }
            }
        }
    }
}

struct ExerciseFormCheckView: View {
    let exercise: Exercise
    @State private var showCamera = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.success.opacity(0.08), Color.success.opacity(0.03)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: "camera.viewfinder").font(.system(size: 42)).foregroundColor(.success.opacity(0.45))
                Text("AI Form Analysis").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                Text("Real-time feedback via camera").font(.system(size: 12)).foregroundColor(.textTertiary)
                Button { showCamera = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.system(size: 13))
                        Text("Start Form Check").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.success).cornerRadius(20).shadow(color: Color.success.opacity(0.35), radius: 8, y: 3)
                }
            }
        }
        .sheet(isPresented: $showCamera) { FormCheckCameraView(exercise: exercise) }
    }
}

struct FormCheckCameraView: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    @State private var isAnalyzing = false
    @State private var formScore: Int = 0
    @State private var feedback: [String] = []
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    Spacer()
                    if isAnalyzing {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Analyzing form…").font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                        }
                        .padding(14).background(Color.black.opacity(0.7)).cornerRadius(22)
                        .transition(.scale.combined(with: .opacity))
                    }
                    if formScore > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Form Score: \(formScore)%")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(formScore >= 80 ? .success : formScore >= 60 ? .warning : .danger)
                            ForEach(feedback, id: \.self) { f in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(.success)
                                    Text(f).font(.system(size: 13)).foregroundColor(.white)
                                }
                            }
                        }
                        .padding(18).background(Color.black.opacity(0.82)).cornerRadius(18)
                        .padding(.horizontal, 20).transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    HStack(spacing: 16) {
                        Button { dismiss() } label: {
                            Text("Cancel").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                                .padding(.horizontal, 24).padding(.vertical, 13).background(Color.danger).cornerRadius(22)
                        }
                        Button(action: analyzeForm) {
                            HStack(spacing: 6) {
                                if isAnalyzing { ProgressView().tint(.white) }
                                Text(isAnalyzing ? "Analyzing…" : "Analyze Form")
                                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            }
                            .padding(.horizontal, 24).padding(.vertical, 13).background(Color.success).cornerRadius(22)
                        }
                        .disabled(isAnalyzing)
                    }
                    .padding(.bottom, 44)
                }
            }
            .navigationTitle(exercise.name).navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.white).fontWeight(.semibold)
                }
            }
        }
    }
    private func analyzeForm() {
        withAnimation { isAnalyzing = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                formScore = Int.random(in: 76...96)
                feedback  = ["Good bar path maintained", "Proper depth achieved", "Keep elbows slightly more tucked"]
                isAnalyzing = false
            }
        }
    }
}

// MARK: - Corner Radius Helper

private extension View {
    func roundedCorners(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(WorkoutRoundedCorner(radius: radius, corners: corners))
    }
}

private struct WorkoutRoundedCorner: Shape {
    let radius: CGFloat; let corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

// MARK: - Comparable clamp

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
