import SwiftUI

// MARK: - Workout Tab Root (World-Class Edition)

struct WorkoutView: View {
    @EnvironmentObject var store: AppStore
    @State private var showTransition = false

    var body: some View {
        ZStack {
            if store.isWorkoutActive {
                ActiveWorkoutView()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 1.05).combined(with: .opacity)
                    ))
            } else {
                WorkoutIdleView()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: store.isWorkoutActive)
    }
}

// MARK: - Idle View (Enhanced)

struct WorkoutIdleView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    @State private var pulseAnimation = false
    @State private var selectedExerciseIndex: Int? = nil

    var body: some View {
        ZStack {
            // Dynamic gradient background
            WorkoutGradientBackground()
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                if let workout = store.todayWorkout {
                    VStack(spacing: 28) {
                        // Enhanced Header
                        VStack(spacing: 16) {
                            // Animated icon
                            ZStack {
                                Circle()
                                    .fill(Color.ember.opacity(0.15))
                                    .frame(width: 80, height: 80)
                                    .blur(radius: 20)
                                    .scaleEffect(pulseAnimation ? 1.4 : 1.0)
                                    .opacity(pulseAnimation ? 0.0 : 0.8)
                                
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.ember, Color.ember.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)
                                    .shadow(color: Color.ember.opacity(0.4), radius: 16)
                                
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .scaleEffect(appear ? 1 : 0.8)
                            .opacity(appear ? 1 : 0)
                            
                            VStack(spacing: 8) {
                                Text(workout.name)
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                    .multilineTextAlignment(.center)
                                
                                Text(workout.type.label.uppercased())
                                    .font(.system(size: 12, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundColor(.ember)
                            }
                            
                            // Workout stats pills
                            HStack(spacing: 12) {
                                WorkoutStatPill(
                                    icon: "list.bullet",
                                    value: "\(workout.exercises.count)",
                                    label: "exercises"
                                )
                                
                                WorkoutStatPill(
                                    icon: "clock.fill",
                                    value: "~\(workout.duration)",
                                    label: "min"
                                )
                                
                                WorkoutStatPill(
                                    icon: "flame.fill",
                                    value: "\(workout.estimatedCalories)",
                                    label: "cal",
                                    color: workout.intensity.color
                                )
                            }
                        }
                        .padding(.top, 60)
                        .padding(.horizontal, 20)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : -20)

                        // Exercise List with expandable details
                        VStack(spacing: 0) {
                            HStack {
                                Text("EXERCISES")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.textTertiary)
                                    .tracking(1.5)
                                
                                Spacer()
                                
                                Text("\(workout.exercises.count) Total")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textSecondary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                            
                            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { idx, ex in
                                WorkoutExerciseRow(
                                    exercise: ex,
                                    index: idx,
                                    isExpanded: selectedExerciseIndex == idx,
                                    onTap: {
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                            selectedExerciseIndex = selectedExerciseIndex == idx ? nil : idx
                                        }
                                    }
                                )
                                .opacity(appear ? 1 : 0)
                                .offset(x: appear ? 0 : -20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3 + Double(idx) * 0.05), value: appear)
                                
                                if idx < workout.exercises.count - 1 {
                                    Divider()
                                        .background(Color.borderColor)
                                        .padding(.leading, 70)
                                }
                            }
                        }
                        .padding(.vertical, 20)
                        .background(Color.surface)
                        .cornerRadius(24)
                        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
                        .padding(.horizontal, 16)

                        // Workout insights
                        WorkoutInsightsView(workout: workout)
                            .padding(.horizontal, 16)
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 20)

                        // Start button with gradient
                        Button(action: startWorkout) {
                            HStack(spacing: 12) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 20, weight: .bold))
                                
                                Text("Start Workout")
                                    .font(.system(size: 20, weight: .bold))
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 20)
                            .background(
                                LinearGradient(
                                    colors: [Color.ember, Color.ember.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(20)
                            .shadow(color: Color.ember.opacity(0.5), radius: 20, y: 10)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                        .opacity(appear ? 1 : 0)
                        .scaleEffect(appear ? 1 : 0.9)
                    }
                } else {
                    WorkoutEmptyState()
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) {
                appear = true
            }
            
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
                pulseAnimation = true
            }
        }
    }
    
    func startWorkout() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            store.startWorkout()
        }
        
        // Success haptic after transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
        }
    }
}

// MARK: - Workout Gradient Background

struct WorkoutGradientBackground: View {
    @State private var animateGradient = false
    
    var body: some View {
        ZStack {
            Color.background
            
            LinearGradient(
                colors: [
                    Color.background,
                    Color.ember.opacity(0.04),
                    Color.background,
                    Color.steel.opacity(0.03)
                ],
                startPoint: animateGradient ? .topLeading : .bottomLeading,
                endPoint: animateGradient ? .bottomTrailing : .topTrailing
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
    }
}

// MARK: - Workout Stat Pill

struct WorkoutStatPill: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .textSecondary
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.textPrimary)
            
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.surface)
        .cornerRadius(100)
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
    }
}

// MARK: - Workout Exercise Row

struct WorkoutExerciseRow: View {
    let exercise: Exercise
    let index: Int
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    // Exercise number badge
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.ember.opacity(0.15), Color.ember.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        
                        Text("\(index + 1)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.ember)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(isExpanded ? nil : 1)
                        
                        HStack(spacing: 10) {
                            Label("\(exercise.sets) × \(exercise.reps)", systemImage: "repeat")
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                            
                            if let weight = exercise.weight {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.textMuted)
                                        .frame(width: 3, height: 3)
                                    
                                    Text("\(weight) lbs")
                                        .font(.system(size: 13))
                                        .foregroundColor(.textSecondary)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                // Expanded details
                if isExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                            .background(Color.borderColor)
                            .padding(.horizontal, 20)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            if let notes = exercise.notes {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.steel)
                                    
                                    Text(notes)
                                        .font(.system(size: 14))
                                        .foregroundColor(.textSecondary)
                                        .lineSpacing(3)
                                }
                            }
                            
                            HStack(spacing: 8) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.textTertiary)
                                
                                Text("\(exercise.restSeconds)s rest between sets")
                                    .font(.system(size: 13))
                                    .foregroundColor(.textTertiary)
                            }
                            
                            if exercise.has3DModel || exercise.videoURL != nil {
                                HStack(spacing: 12) {
                                    if exercise.videoURL != nil {
                                        FeatureBadge(icon: "play.circle.fill", label: "Video Demo", color: .ember)
                                    }
                                    if exercise.has3DModel {
                                        FeatureBadge(icon: "cube.fill", label: "3D Model", color: .steel)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
                    ))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct FeatureBadge: View {
    let icon: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Workout Insights

struct WorkoutInsightsView: View {
    let workout: WorkoutPlan
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    
    var insights: [String] {
        var result: [String] = []
        
        if store.readiness.overall >= 80 {
            result.append("Your readiness is excellent — perfect time for high intensity")
        } else if store.readiness.overall < 65 {
            result.append("Recovery is lower today — consider reducing volume or intensity")
        }
        
        if workout.intensity == .high || workout.intensity == .max {
            result.append("High intensity workout — ensure you're properly warmed up")
        }
        
        result.append("Estimated \(workout.estimatedCalories) calories burned")
        
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.warning)
                
                Text("INSIGHTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .tracking(1.5)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(insights.enumerated()), id: \.offset) { idx, insight in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.ember)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        
                        Text(insight)
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(3)
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(x: appear ? 0 : -10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6 + Double(idx) * 0.1), value: appear)
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5)) {
                appear = true
            }
        }
    }
}

// MARK: - Empty State

struct WorkoutEmptyState: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.ember.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.ember.opacity(0.6))
            }
            .scaleEffect(appear ? 1 : 0.8)
            .opacity(appear ? 1 : 0)
            
            VStack(spacing: 12) {
                Text("No Workout Planned")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                
                Text("Chat with Forge to get a personalized workout plan based on your readiness and goals.")
                    .font(.system(size: 15))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 20)
            
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                store.activeTab = .chat
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 16))
                    
                    Text("Chat with Forge")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(Color.ember)
                .cornerRadius(16)
                .shadow(color: Color.ember.opacity(0.4), radius: 16, y: 8)
            }
            .opacity(appear ? 1 : 0)
            .scaleEffect(appear ? 1 : 0.9)
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.2)) {
                appear = true
            }
        }
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
                
                // 3D Model / Video Preview
                ExerciseDemonstrationView(exercise: exercise)
                    .padding(.bottom, 16)

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
                    Text(notes)
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

// MARK: - Exercise Demonstration View (Videos, Camera)

struct ExerciseDemonstrationView: View {
    let exercise: Exercise
    @State private var selectedTab: DemoTab = .video
    
    enum DemoTab {
        case video, formCheck
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Tab selector
            HStack(spacing: 8) {
                DemoTabButton(
                    icon: "play.circle.fill",
                    label: "Video",
                    isSelected: selectedTab == .video,
                    action: { selectedTab = .video }
                )
                
                DemoTabButton(
                    icon: "camera.fill",
                    label: "Form Check",
                    isSelected: selectedTab == .formCheck,
                    action: { selectedTab = .formCheck }
                )
            }
            
            // Content area
            Group {
                switch selectedTab {
                case .video:
                    ExerciseVideoPlayer(exercise: exercise)
                case .formCheck:
                    ExerciseFormCheckView(exercise: exercise)
                }
            }
            .frame(height: 220)
            .background(Color.black.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderColor, lineWidth: 1)
            )
        }
    }
}

struct DemoTabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.ember : Color.surfaceElevated)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct ExerciseVideoPlayer: View {
    let exercise: Exercise
    @State private var isPlaying = false
    
    var body: some View {
        ZStack {
            // Placeholder for video - in production would use AVPlayer or VideoPlayer
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.ember.opacity(0.1), Color.emberLight.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 48))
                    .foregroundColor(.ember.opacity(0.6))
                
                Text(exercise.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                
                // Play/Pause button
                Button(action: { isPlaying.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                        Text(isPlaying ? "Pause" : "Play Demo")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.ember)
                    .cornerRadius(20)
                }
            }
        }
        .onAppear {
            // In production, load video from exercise.videoURL
        }
    }
}

struct ExerciseFormCheckView: View {
    let exercise: Exercise
    @State private var isAnalyzing = false
    @State private var showCameraView = false
    
    var body: some View {
        ZStack {
            // Placeholder for camera feed - in production would use AVCaptureSession
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.success.opacity(0.1), Color.success.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.success.opacity(0.6))
                
                Text("AI Form Analysis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textPrimary)
                
                Text("Use your camera to check your form in real-time")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button(action: { showCameraView = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                        Text("Start Form Check")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.success)
                    .cornerRadius(20)
                }
            }
        }
        .sheet(isPresented: $showCameraView) {
            FormCheckCameraView(exercise: exercise)
        }
    }
}

struct SmallIconButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.textPrimary)
                .frame(width: 32, height: 32)
                .background(Color.surfaceElevated)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct FormCheckCameraView: View {
    @Environment(\.dismiss) var dismiss
    let exercise: Exercise
    @State private var isAnalyzing = false
    @State private var formScore: Int = 0
    @State private var feedback: [String] = []
    
    var body: some View {
        NavigationView {
            ZStack {
                // Camera preview would go here - in production use AVCaptureVideoPreviewLayer
                Color.black
                
                VStack {
                    Spacer()
                    
                    // Overlay feedback
                    if isAnalyzing {
                        VStack(spacing: 12) {
                            HStack {
                                Circle()
                                    .fill(Color.success)
                                    .frame(width: 12, height: 12)
                                    .opacity(0.8)
                                Text("Analyzing your form...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(12)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(20)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    if formScore > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Form Score: \(formScore)%")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(formScore >= 80 ? .success : formScore >= 60 ? .warning : .danger)
                                Spacer()
                            }
                            
                            ForEach(feedback, id: \.self) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.success)
                                    Text(item)
                                        .font(.system(size: 12))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(16)
                        .padding()
                    }
                    
                    // Controls
                    HStack(spacing: 20) {
                        Button(action: { dismiss() }) {
                            Text("Cancel")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.danger)
                                .cornerRadius(20)
                        }
                        
                        Button(action: analyzeForm) {
                            Text(isAnalyzing ? "Analyzing..." : "Analyze Form")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.success)
                                .cornerRadius(20)
                        }
                        .disabled(isAnalyzing)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    func analyzeForm() {
        isAnalyzing = true
        
        // Simulate AI analysis - in production would use Vision/CoreML
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            formScore = Int.random(in: 75...95)
            feedback = [
                "✓ Good bar path",
                "✓ Proper depth achieved",
                "⚠️ Try keeping elbows slightly more tucked"
            ]
            isAnalyzing = false
        }
    }
}
