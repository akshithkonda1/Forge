import SwiftUI

struct AIWorkoutSuggestionsCard: View {
    let workouts: [AIWorkoutSuggestion]
    @EnvironmentObject var store: AppStore
    @State private var appeared = false
    @State private var selectedWorkout: CustomWorkoutPlan?
    
    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            HStack(spacing: FDS.Spacing.md) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.ember)
                Text("Train suggestions")
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(workouts.count) ready")
                    .font(FDS.TypeScale.Dynamic.micro)
                    .foregroundColor(.ember)
                    .padding(.horizontal, FDS.Spacing.sm).padding(.vertical, FDS.Spacing.xs)
                    .background(Color.ember.opacity(0.12))
                    .cornerRadius(FDS.Radius.sm)
            }
            
            VStack(spacing: FDS.Spacing.md) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { i, suggestion in
                    AIWorkoutCard(suggestion: suggestion)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(Double(i) * 0.1), value: appeared)
                        .onTapGesture {
                            selectedWorkout = suggestion.workout
                        }
                }
            }
        }
        .padding(FDS.Spacing.xl)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: .ember)
        .onAppear { appeared = true }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(workout: workout)
                .environmentObject(store)
        }
    }
}

struct AIWorkoutCard: View {
    let suggestion: AIWorkoutSuggestion
    
    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            HStack(spacing: FDS.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: FDS.Radius.sm)
                        .fill(Color.ember.opacity(0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(LinearGradient.emberGradient)
                }
                
                VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                    Text(suggestion.title)
                        .font(FDS.TypeScale.Dynamic.headline)
                        .foregroundColor(.textPrimary)
                    HStack(spacing: FDS.Spacing.sm) {
                        Label("\(suggestion.workout.duration) min", systemImage: "clock.fill")
                        Label("\(suggestion.workout.exercises.count) exercises", systemImage: "list.bullet")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.ember)
            }
            
            Divider().background(Color.borderColor.opacity(0.4))
            
            HStack(spacing: FDS.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundColor(.ember)
                Text(suggestion.reason)
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(FDS.Spacing.lg)
        .forgeInsetTile(radius: FDS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg)
                .stroke(Color.ember.opacity(0.2), lineWidth: 1)
        )
    }
}

struct WorkoutDetailSheet: View {
    let workout: CustomWorkoutPlan
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: FDS.Spacing.xl) {
                    // Header stats
                    VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                        Text(workout.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        HStack(spacing: FDS.Spacing.lg) {
                            StatPill(icon: "clock.fill", value: "\(workout.duration) min", color: .steel)
                            StatPill(icon: "flame.fill", value: "~\(workout.caloriesBurn) cal", color: .ember)
                            StatPill(icon: "list.bullet", value: "\(workout.exercises.count) exercises", color: .success)
                        }
                    }
                    .padding(.horizontal, FDS.Spacing.lg)
                    
                    // Exercise list
                    VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
                        Text("Exercises")
                            .font(FDS.TypeScale.Dynamic.title)
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, FDS.Spacing.lg)
                        
                        ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { i, exercise in
                            ExerciseRow(index: i + 1, exercise: exercise)
                                .padding(.horizontal, FDS.Spacing.lg)
                        }
                    }
                    
                    Button {
                        store.adoptCustomWorkoutPlan(workout)
                        store.startExistingWorkout()
                        dismiss()
                    } label: {
                        HStack(spacing: FDS.Spacing.md) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Start session")
                                .font(FDS.TypeScale.Dynamic.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FDS.Spacing.lg)
                        .background(LinearGradient.emberGradient)
                        .cornerRadius(FDS.Radius.lg)
                        .shadow(color: Color.ember.opacity(0.4), radius: 12, y: 6)
                    }
                    .padding(.horizontal, FDS.Spacing.lg)
                    .padding(.top, FDS.Spacing.sm)
                }
                .padding(.vertical, FDS.Spacing.xl)
            }
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: FDS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(value)
                .font(FDS.TypeScale.Dynamic.caption)
        }
        .foregroundColor(color)
        .padding(.horizontal, FDS.Spacing.md)
        .padding(.vertical, FDS.Spacing.sm)
        .background(color.opacity(0.12))
        .cornerRadius(FDS.Radius.sm)
    }
}

struct ExerciseRow: View {
    let index: Int
    let exercise: WorkoutExercise
    
    var body: some View {
        HStack(spacing: FDS.Spacing.lg) {
            ZStack {
                Circle().fill(Color.ember.opacity(0.12)).frame(width: 40, height: 40)
                Text("\(index)")
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundColor(.ember)
            }
            
            VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                Text(exercise.name)
                    .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: FDS.Spacing.sm) {
                    Text("\(exercise.sets) sets")
                    Text("·")
                    Text("\(exercise.reps) reps")
                    Text("·")
                    Text("\(exercise.restSeconds)s rest")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            Text(exercise.muscleGroup.rawValue.capitalized)
                .font(FDS.TypeScale.Dynamic.micro)
                .foregroundColor(.textTertiary)
                .padding(.horizontal, FDS.Spacing.sm)
                .padding(.vertical, FDS.Spacing.xs)
                .forgeInsetTile(radius: FDS.Radius.xs)
        }
        .padding(FDS.Spacing.lg)
        .forgeGlassCard(cornerRadius: FDS.Radius.md, accent: .ember)
    }
}
