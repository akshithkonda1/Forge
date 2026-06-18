import SwiftUI

// MARK: - Workout View

struct WorkoutView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if store.isWorkoutActive {
                ActiveWorkoutView()
            } else {
                WorkoutIdleView()
            }
        }
        .background(Color.forgeBackground)
    }
}

// MARK: - Idle State

struct WorkoutIdleView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let workout = store.todayWorkout {
                VStack(spacing: 16) {
                    // Icon
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.ember.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.ember)
                        )

                    Text(workout.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text("\(workout.exercises.count) exercises · \(workout.duration) min · \(workout.intensity.rawValue) intensity")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            WorkoutStatPill(icon: "list.bullet", value: "\(workout.exercises.count)", label: "exercises")
                            WorkoutStatPill(icon: "clock.fill", value: "~\(workout.duration)", label: "min")
                            WorkoutStatPill(icon: "flame.fill", value: "\(workout.estimatedCalories)", label: "cal")
                            WorkoutStatPill(icon: "scalemass.fill", value: "\(workout.exercises.count * 4)", label: "sets")
                        }
                    }
                    .padding(.horizontal, 4)

                    // Exercise list
                    VStack(spacing: 0) {
                        ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { i, ex in
                            HStack {
                                Text("\(i + 1)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.textTertiary)
                                    .frame(width: 20, alignment: .trailing)

                                Text(ex.name)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)

                                Spacer()

                                Text("\(ex.sets) × \(ex.reps)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(.vertical, 10)

                            if i < workout.exercises.count - 1 {
                                Divider().background(Color.forgeBorder)
                            }
                        }
                    }
                    .padding(16)
                    .forgeBorderedCard()
                    .padding(.horizontal, 24)

                    EmberButton(title: "Start Workout", icon: "play.fill") {
                        store.startWorkout()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
            } else {
                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.forgeSurfaceElevated)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "calendar")
                                .font(.system(size: 36))
                                .foregroundColor(.textTertiary)
                        )

                    Text("No Workout Planned")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)

                    Text("Chat with your AI coach to plan one.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
        .padding(.bottom, 80)
    }
}

// MARK: - Active Workout View

struct ActiveWorkoutView: View {
    @EnvironmentObject var store: AppStore
    @State private var pulseSet = 1
    @State private var setPulseScale: CGFloat = 1.0
    @State private var setBurstOpacity: Double = 0
    @State private var elapsed = 0
    @State private var simulatedHR = 72
    @State private var calories = 0.0
    @State private var isResting = false
    @State private var restTimeLeft = 0
    @State private var coachIndex = 0
    @State private var showEndConfirm = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let coachingMessages = [
        "Slow down the eccentric — 3 seconds on the way down",
        "Heart rate elevated. Take extra 30s rest",
        "Last set was easy. Let's bump up 5lbs",
        "You're crushing it. Two more reps.",
        "Keep your core braced through the whole rep.",
        "Control the weight — don't let it control you",
        "Good form. Maintain that bar path.",
    ]

    private var exercises: [Exercise] { store.todayWorkout?.exercises ?? [] }
    private var currentExercise: Exercise? {
        guard store.currentExerciseIndex < exercises.count else { return nil }
        return exercises[store.currentExerciseIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.todayWorkout?.name ?? "Workout")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Text("\(store.todayWorkout?.type.label ?? "") · \(store.todayWorkout?.intensity.rawValue ?? "")")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                    Text(formatTime(elapsed))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }

                Button {
                    if showEndConfirm {
                        store.endWorkout()
                    } else {
                        showEndConfirm = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showEndConfirm = false }
                    }
                } label: {
                    Text(showEndConfirm ? "Confirm" : "End")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(showEndConfirm ? .white : .forgeDanger)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(showEndConfirm ? Color.forgeDanger : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // Exercise dots
            ExerciseNavDots(exercises: exercises, currentIndex: store.currentExerciseIndex)
                .padding(.horizontal, 20)

            // Metrics strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    metricBubble(icon: "heart.fill", value: "\(simulatedHR)", unit: "bpm", color: .forgeDanger)
                    metricBubble(icon: "flame.fill", value: "\(Int(calories))", unit: "cal", color: .ember)
                    metricBubble(icon: "clock", value: formatTime(elapsed), unit: "", color: .steel)

                    let zone = hrZone(simulatedHR)
                    metricBubble(icon: "bolt.fill", value: zone.label, unit: "", color: zone.color)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            // Main content
            ScrollView {
                if isResting {
                    restTimerView
                } else if let ex = currentExercise {
                    exerciseCard(ex)
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            // Coach bar
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.ember.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "cpu")
                            .font(.system(size: 14))
                            .foregroundColor(.ember)
                    )

                Text(coachingMessages[coachIndex])
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)
                    .animation(.easeInOut, value: coachIndex)
            }
            .padding(14)
            .forgeBorderedCard()
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onReceive(timer) { _ in
            elapsed += 1
            calories += simulatedHR > 140 ? 0.18 : 0.1

            // Simulate HR
            if isResting {
                simulatedHR = max(100, simulatedHR + Int.random(in: -3...1))
            } else {
                simulatedHR = min(180, simulatedHR + Int.random(in: -1...3))
            }

            // Rest countdown
            if isResting && restTimeLeft > 0 {
                restTimeLeft -= 1
                if restTimeLeft == 0 { isResting = false }
            }

            // Coach rotation
            if elapsed % 8 == 0 {
                coachIndex = (coachIndex + 1) % coachingMessages.count
            }
        }
    }

    // MARK: - Exercise Card

    private func exerciseCard(_ ex: Exercise) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Set \(store.currentSet) of \(ex.sets)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ember)
                    Spacer()
                    Text("Exercise \(store.currentExerciseIndex + 1)/\(exercises.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }

                SetIndicatorDots(totalSets: ex.sets, activeSet: store.currentSet, pulseSet: pulseSet, scale: setPulseScale, burstOpacity: setBurstOpacity)

                Text(ex.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let weight = ex.weight {
                        Text("\(weight)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("lbs")
                            .font(.system(size: 16))
                            .foregroundColor(.textSecondary)
                        Text("×")
                            .font(.system(size: 22))
                            .foregroundColor(.textTertiary)
                    }
                    Text(ex.reps)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("reps")
                        .font(.system(size: 16))
                        .foregroundColor(.textSecondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text("\(ex.restSeconds)s rest between sets")
                        .font(.system(size: 12))
                }
                .foregroundColor(.textTertiary)

                if let notes = ex.notes {
                    Text(""\(notes)"")
                        .font(.system(size: 13))
                        .italic()
                        .foregroundColor(.textSecondary)
                        .padding(.top, 8)
                }
            }
            .padding(20)
            .forgeBorderedCard()

            // Complete button
            EmberButton(
                title: store.currentSet >= ex.sets && store.currentExerciseIndex >= exercises.count - 1
                    ? "Finish Workout"
                    : store.currentSet >= ex.sets
                        ? "Complete · Next Exercise"
                        : "Complete Set",
                icon: "chevron.right"
            ) {
                handleCompleteSet(ex)
            }

            // Secondary actions
            HStack(spacing: 12) {
                Button {
                    handleSkipExercise()
                } label: {
                    Text("Skip Exercise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)

                Button { } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12))
                        Text("Log Pain")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Rest Timer

    private var restTimerView: some View {
        VStack(spacing: 20) {
            Text("REST")
                .font(.system(size: 12, weight: .semibold))
                .tracking(2)
                .foregroundColor(.textSecondary)
                .padding(.top, 24)

            // Ring timer
            ZStack {
                Circle()
                    .stroke(Color.forgeBorder, lineWidth: 6)

                if let ex = currentExercise, ex.restSeconds > 0 {
                    Circle()
                        .trim(from: 0, to: CGFloat(restTimeLeft) / CGFloat(ex.restSeconds))
                        .stroke(Color.ember, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: .ember.opacity(0.5), radius: 6)
                        .animation(.linear(duration: 1), value: restTimeLeft)
                }

                Text("\(restTimeLeft)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(width: 140, height: 140)

            Button {
                isResting = false
                restTimeLeft = 0
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                    Text("Skip Rest")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.forgeSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.forgeBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func handleCompleteSet(_ ex: Exercise) {
        let isLastSet = store.currentSet >= ex.sets
        let isLastExercise = store.currentExerciseIndex >= exercises.count - 1

        if isLastSet && isLastExercise {
            store.endWorkout()
            return
        }

        if isLastSet {
            store.nextExercise()
        } else {
            store.nextSet()
            triggerSetPulse()
        }

        isResting = true
        restTimeLeft = ex.restSeconds
    }

    private func handleSkipExercise() {
        if store.currentExerciseIndex >= exercises.count - 1 {
            store.endWorkout()
        } else {
            store.nextExercise()
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func hrZone(_ hr: Int) -> (label: String, color: Color) {
        if hr < 110 { return ("Zone 1", .textTertiary) }
        if hr < 130 { return ("Zone 2", .steel) }
        if hr < 150 { return ("Zone 3", .forgeSuccess) }
        if hr < 165 { return ("Zone 4", .ember) }
        return ("Zone 5", .forgeDanger)
    }

    private func triggerSetPulse() {
        pulseSet = store.currentSet
        withAnimation(FDS.Spring.snap) {
            setPulseScale = 1.35
        }
        if !UIAccessibility.isReduceMotionEnabled {
            setBurstOpacity = 0.85
            withAnimation(.easeOut(duration: 0.4)) {
                setBurstOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(FDS.Spring.snap) {
                setPulseScale = 1.0
            }
        }
    }

    private func metricBubble(icon: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.forgeSurface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.forgeBorder, lineWidth: 1))
    }
}

// MARK: - Exercise Nav Dots

struct WorkoutStatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.ember)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.forgeSurfaceElevated)
        .clipShape(Capsule())
    }
}

struct SetIndicatorDots: View {
    let totalSets: Int
    let activeSet: Int
    let pulseSet: Int
    let scale: CGFloat
    let burstOpacity: Double

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...max(totalSets, 1), id: \.self) { set in
                Circle()
                    .fill(set <= activeSet ? Color.ember : Color.forgeSurfaceElevated)
                    .frame(width: 10, height: 10)
                    .scaleEffect(set == pulseSet ? scale : 1.0)
                    .shadow(color: set == pulseSet ? Color.ember.opacity(burstOpacity) : .clear, radius: 10)
                    .animation(FDS.Spring.snap, value: scale)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ExerciseNavDots: View {
    let exercises: [Exercise]
    let currentIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { i, _ in
                    ZStack {
                        Circle()
                            .fill(
                                i == currentIndex ? Color.ember
                                : i < currentIndex ? Color.ember.opacity(0.2)
                                : Color.forgeSurfaceElevated
                            )
                            .frame(width: 32, height: 32)
                            .shadow(color: i == currentIndex ? .ember.opacity(0.4) : .clear, radius: 6)

                        if i < currentIndex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.ember)
                        } else {
                            Text("\(i + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(i == currentIndex ? .white : .textTertiary)
                        }
                    }

                    if i < exercises.count - 1 {
                        Capsule()
                            .fill(i < currentIndex ? Color.ember.opacity(0.4) : Color.forgeBorder)
                            .frame(width: 16, height: 2)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}
