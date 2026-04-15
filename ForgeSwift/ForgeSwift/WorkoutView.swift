import SwiftUI

// MARK: - Workout Tab root (mirrors workout-page.tsx)

struct WorkoutView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if store.isWorkoutActive {
            ActiveWorkoutView()
        } else {
            WorkoutIdleView()
        }
    }
}

// MARK: - Idle View (workout not started)

struct WorkoutIdleView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            if let workout = store.todayWorkout {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.ember.opacity(0.15))
                                .frame(width: 72, height: 72)
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.ember)
                        }
                        Text(workout.name)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.textPrimary)
                        HStack(spacing: 16) {
                            Label("\(workout.exercises.count) exercises", systemImage: "list.bullet")
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                            Label("~\(workout.duration) min", systemImage: "clock.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                            Label(workout.intensity.label, systemImage: "bolt.fill")
                                .font(.system(size: 13))
                                .foregroundColor(workout.intensity.color)
                        }
                    }
                    .padding(.top, 56)

                    // Exercise list
                    VStack(spacing: 0) {
                        ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { idx, ex in
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle().fill(Color.surfaceElevated).frame(width: 32, height: 32)
                                    Text("\(idx+1)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.textTertiary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                    HStack(spacing: 8) {
                                        Text("\(ex.sets) sets × \(ex.reps) reps")
                                            .font(.system(size: 12))
                                            .foregroundColor(.textTertiary)
                                        if let w = ex.weight {
                                            Text("· \(w) lbs")
                                                .font(.system(size: 12))
                                                .foregroundColor(.textMuted)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            if idx < workout.exercises.count - 1 {
                                Divider().background(Color.borderColor).padding(.leading, 66)
                            }
                        }
                    }
                    .background(Color.surface)
                    .cornerRadius(16)
                    .padding(.horizontal, 16)

                    // Start button
                    Button(action: { store.startWorkout() }) {
                        HStack(spacing: 8) {
                            Text("Start Workout")
                                .font(.system(size: 18, weight: .bold))
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(Color.ember)
                        .cornerRadius(16)
                        .shadow(color: Color.ember.opacity(0.4), radius: 18, x: 0, y: 6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.textMuted)
                    Text("No workout planned")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Text("Chat with Forge to get a personalized plan.")
                        .font(.system(size: 14))
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 120)
            }
        }
        .background(Color.background.ignoresSafeArea())
    }
}

// MARK: - Active Workout View (mirrors active-workout-view.tsx)

private let coachMsgs = [
    "Slow down the eccentric — 3 seconds on the way down",
    "Heart rate is elevated. Take an extra 30 seconds rest",
    "Last set was easy. Let's bump up 5lbs",
    "You're crushing it. Two more reps.",
    "Keep your core braced. Tight through the whole rep.",
    "Control the weight — don't let it control you",
    "Good form. Maintain that bar path.",
    "Breathe out on the exertion. Stay in rhythm.",
]

struct ActiveWorkoutView: View {
    @EnvironmentObject var store: AppStore

    @State private var elapsedTime: Int = 0
    @State private var simulatedHR: Int = 72
    @State private var estimatedCals: Double = 0
    @State private var isResting: Bool = false
    @State private var restTimeLeft: Int = 0
    @State private var coachIndex: Int = 0
    @State private var showEndConfirm: Bool = false

    // Timers
    @State private var elapsedTimer: Timer? = nil
    @State private var hrTimer: Timer? = nil
    @State private var calTimer: Timer? = nil
    @State private var restTimer: Timer? = nil
    @State private var coachTimer: Timer? = nil

    var exercises: [Exercise] { store.todayWorkout?.exercises ?? [] }
    var currentExercise: Exercise? { exercises.indices.contains(store.currentExerciseIndex) ? exercises[store.currentExerciseIndex] : nil }

    var body: some View {
        VStack(spacing: 0) {
            if let exercise = currentExercise {
                workoutContent(exercise: exercise)
            }
        }
        .background(Color.background.ignoresSafeArea())
        .onAppear { startTimers() }
        .onDisappear { stopTimers() }
    }

    @ViewBuilder
    func workoutContent(exercise: Exercise) -> some View {
        // Header
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.todayWorkout?.name ?? "")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                Text("\(store.todayWorkout?.type.label ?? "") · \(store.todayWorkout?.intensity.label ?? "")")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
            Spacer()
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                    Text(formatTime(elapsedTime))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.textPrimary)
                }
                Button(action: handleEnd) {
                    Text(showEndConfirm ? "Confirm" : "End")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(showEndConfirm ? .white : .danger)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(showEndConfirm ? Color.danger : Color.danger.opacity(0.12))
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)

        // Exercise navigation dots
        ExerciseNavView(exercises: exercises, currentIndex: store.currentExerciseIndex)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

        // Live metrics strip
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                let zone = hrZone(for: simulatedHR)

                // HR
                liveMetricPill {
                    Image(systemName: "heart.fill").font(.system(size: 14)).foregroundColor(.danger)
                    Text("\(simulatedHR)").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.white)
                    Text("bpm").font(.system(size: 11)).foregroundColor(.textTertiary)
                }
                .scaleEffect(1.0)

                // Cals
                liveMetricPill {
                    Image(systemName: "flame.fill").font(.system(size: 14)).foregroundColor(.ember)
                    Text("\(Int(estimatedCals))").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.white)
                    Text("cal").font(.system(size: 11)).foregroundColor(.textTertiary)
                }

                // Time
                liveMetricPill {
                    Image(systemName: "clock.fill").font(.system(size: 14)).foregroundColor(.steel)
                    Text(formatTime(elapsedTime)).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.white)
                }

                // Zone
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill").font(.system(size: 13)).foregroundColor(zone.color)
                    Text(zone.label).font(.system(size: 13, weight: .bold)).foregroundColor(zone.color)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(zone.color.opacity(0.12))
                .cornerRadius(100)
                .overlay(Capsule().stroke(zone.color.opacity(0.35), lineWidth: 1))
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)

        // Main content
        ScrollView(showsIndicators: false) {
            if isResting {
                RestTimerView(
                    restTimeLeft: restTimeLeft,
                    totalRest: exercise.restSeconds,
                    nextLabel: nextLabel(exercise: exercise),
                    onSkip: skipRest
                )
                .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .scale(scale: 0.9).combined(with: .opacity)))
            } else {
                exerciseCard(exercise: exercise)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isResting)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.currentExerciseIndex)

        // AI coach bar
        CoachBarView(message: coachMsgs[coachIndex % coachMsgs.count])
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 8)
    }

    @ViewBuilder
    func liveMetricPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 5) { content() }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.surface)
            .cornerRadius(100)
            .overlay(Capsule().stroke(Color.borderColor, lineWidth: 1))
    }

    @ViewBuilder
    func exerciseCard(exercise: Exercise) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Set indicator
                HStack {
                    Text("Set \(store.currentSet) of \(exercise.sets)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.ember)
                    Spacer()
                    Text("Exercise \(store.currentExerciseIndex + 1)/\(exercises.count)")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(.bottom, 8)

                // Exercise name
                Text(exercise.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 12)

                // Weight × reps
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let weight = exercise.weight {
                        Text("\(weight)")
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                        Text("lbs")
                            .font(.system(size: 20))
                            .foregroundColor(.textSecondary)
                        Text("×")
                            .font(.system(size: 28))
                            .foregroundColor(.textMuted)
                    }
                    Text(exercise.reps)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                    Text("reps")
                        .font(.system(size: 20))
                        .foregroundColor(.textSecondary)
                }
                .padding(.bottom, 10)

                // Rest info
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                    Text("\(exercise.restSeconds)s rest between sets")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(.bottom, 8)

                // Notes
                if let notes = exercise.notes {
                    Divider().background(Color.borderColor).padding(.vertical, 10)
                    Text(""\(notes)"")
                        .font(.system(size: 13).italic())
                        .foregroundColor(.textSecondary)
                        .lineSpacing(3)
                }
            }
            .padding(24)
            .background(Color.surface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor, lineWidth: 1))

            // Action buttons
            VStack(spacing: 12) {
                let isLastSet = store.currentSet >= exercise.sets
                let isLastEx = store.currentExerciseIndex >= exercises.count - 1
                let label = isLastSet && isLastEx ? "Finish Workout" : isLastSet ? "Complete · Next Exercise" : "Complete Set"

                Button(action: completeSet) {
                    HStack(spacing: 8) {
                        Text(label)
                            .font(.system(size: 18, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.ember)
                    .cornerRadius(14)
                    .shadow(color: Color.ember.opacity(0.35), radius: 16)
                }

                HStack(spacing: 12) {
                    Button(action: skipExercise) {
                        Text("Skip Exercise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.surfaceElevated)
                            .cornerRadius(12)
                    }
                    Button(action: {}) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13))
                            Text("Log Pain")
                                .font(.system(size: 13))
                        }
                        .foregroundColor(.warning)
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                        .background(Color.surfaceElevated)
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: Actions

    func completeSet() {
        guard let exercise = currentExercise else { return }
        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx = store.currentExerciseIndex >= exercises.count - 1

        if isLastSet && isLastEx {
            store.endWorkout()
            return
        }
        if isLastSet {
            store.nextExercise()
        } else {
            store.nextSet()
        }
        startRest(seconds: exercise.restSeconds)
    }

    func skipExercise() {
        if store.currentExerciseIndex >= exercises.count - 1 {
            store.endWorkout()
        } else {
            store.nextExercise()
            isResting = false
            restTimeLeft = 0
        }
    }

    func skipRest() {
        restTimer?.invalidate()
        restTimer = nil
        withAnimation { isResting = false }
        restTimeLeft = 0
    }

    func handleEnd() {
        if showEndConfirm {
            store.endWorkout()
        } else {
            showEndConfirm = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showEndConfirm = false }
        }
    }

    func startRest(seconds: Int) {
        restTimeLeft = seconds
        withAnimation { isResting = true }
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if restTimeLeft <= 1 {
                restTimer?.invalidate()
                restTimer = nil
                withAnimation { isResting = false }
                restTimeLeft = 0
            } else {
                restTimeLeft -= 1
            }
        }
    }

    func nextLabel(exercise: Exercise) -> String {
        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx = store.currentExerciseIndex >= exercises.count - 1
        if isLastSet && isLastEx { return "Workout Complete" }
        if isLastSet {
            let next = exercises.indices.contains(store.currentExerciseIndex + 1) ? exercises[store.currentExerciseIndex + 1].name : "Done"
            return "Next: \(next)"
        }
        return "Set \(store.currentSet) of \(exercise.sets)"
    }

    // MARK: Timers

    func startTimers() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in elapsedTime += 1 }

        hrTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            let target: Double = isResting ? (110 + Double.random(in: 0...20)) : (135 + Double.random(in: 0...30))
            let noise = Double.random(in: -5...5)
            simulatedHR = Int((Double(simulatedHR) + (target - Double(simulatedHR)) * 0.1 + noise).rounded())
        }

        calTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let rate: Double = simulatedHR > 140 ? 0.18 : simulatedHR > 120 ? 0.14 : 0.10
            estimatedCals += rate
        }

        coachTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) { coachIndex += 1 }
        }
    }

    func stopTimers() {
        elapsedTimer?.invalidate(); elapsedTimer = nil
        hrTimer?.invalidate(); hrTimer = nil
        calTimer?.invalidate(); calTimer = nil
        restTimer?.invalidate(); restTimer = nil
        coachTimer?.invalidate(); coachTimer = nil
    }

    func formatTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Exercise Navigation (mirrors exercise-nav.tsx)

struct ExerciseNavView: View {
    let exercises: [Exercise]
    let currentIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(exercises.enumerated()), id: \.offset) { idx, _ in
                    HStack(spacing: 0) {
                        navDot(idx: idx)
                        if idx < exercises.count - 1 {
                            Rectangle()
                                .fill(idx < currentIndex ? Color.ember.opacity(0.4) : Color.borderColor)
                                .frame(width: 20, height: 1.5)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    func navDot(idx: Int) -> some View {
        if idx < currentIndex {
            // Completed
            ZStack {
                Circle().fill(Color.ember.opacity(0.25)).frame(width: 28, height: 28)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.ember)
            }
        } else if idx == currentIndex {
            // Current — pulsing
            ZStack {
                Circle().fill(Color.ember).frame(width: 28, height: 28)
                Text("\(idx+1)").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            }
            .overlay(
                Circle().stroke(Color.ember.opacity(0.4), lineWidth: 3)
                    .frame(width: 36, height: 36)
                    .opacity(0.6)
            )
        } else {
            // Upcoming
            ZStack {
                Circle().fill(Color.surfaceElevated).frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.borderColor, lineWidth: 1))
                Text("\(idx+1)").font(.system(size: 11)).foregroundColor(.textTertiary)
            }
        }
    }
}

// MARK: - Rest Timer View (mirrors rest timer in active-workout-view.tsx)

struct RestTimerView: View {
    let restTimeLeft: Int
    let totalRest: Int
    let nextLabel: String
    let onSkip: () -> Void

    var progress: CGFloat { totalRest > 0 ? CGFloat(restTimeLeft) / CGFloat(totalRest) : 0 }

    var body: some View {
        VStack(spacing: 24) {
            Text("REST")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
                .tracking(2)

            // Circular timer
            ZStack {
                Circle()
                    .stroke(Color.borderColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.ember, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.ember.opacity(0.5), radius: 8)
                    .animation(.linear(duration: 1), value: progress)

                Text("\(restTimeLeft)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
            }

            Text(nextLabel)
                .font(.system(size: 14))
                .foregroundColor(.textTertiary)

            Button(action: onSkip) {
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill").font(.system(size: 15))
                    Text("Skip Rest").font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.textPrimary)
                .frame(width: 160, height: 52)
                .background(Color.surfaceElevated)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - AI Coach Bar (mirrors AI coach bar in active-workout-view.tsx)

struct CoachBarView: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.ember.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "cpu.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.ember)
            }
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .id(message)
        }
        .padding(16)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
        .animation(.easeInOut(duration: 0.4), value: message)
    }
}
