import SwiftUI
import WorkoutKit
import ForgeCore

struct AIWorkoutSuggestionsCard: View {
    let workouts: [AIWorkoutSuggestion]
    @State private var appeared = false
    @State private var selectedWorkout: CustomWorkoutPlan?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.ember)
                Text("AI Workout Suggestions")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(workouts.count) ready")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ember)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.ember.opacity(0.12))
                    .cornerRadius(8)
            }
            
            VStack(spacing: 12) {
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
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(workout: workout)
        }
    }
}

struct AIWorkoutCard: View {
    let suggestion: AIWorkoutSuggestion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.ember.opacity(0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(LinearGradient.emberGradient)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 8) {
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
            
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundColor(.ember)
                Text(suggestion.reason)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(Color.surfaceElevated)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.ember.opacity(0.2), lineWidth: 1)
        )
    }
}

struct WorkoutDetailSheet: View {
    let workout: CustomWorkoutPlan
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text(workout.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        HStack(spacing: 16) {
                            StatPill(icon: "clock.fill", value: "\(workout.duration) min", color: .steel)
                            StatPill(icon: "flame.fill", value: "~\(workout.caloriesBurn) cal", color: .ember)
                            StatPill(icon: "list.bullet", value: "\(workout.exercises.count) exercises", color: .success)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Exercise list
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Exercises")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 20)
                        
                        ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { i, exercise in
                            ExerciseRow(index: i + 1, exercise: exercise)
                                .padding(.horizontal, 20)
                        }
                    }
                    
                    // Start workout button
                    Button {
                        // Integration with WorkoutKit would go here
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Start Workout")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.emberGradient)
                        .cornerRadius(16)
                        .shadow(color: Color.ember.opacity(0.4), radius: 12, y: 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .padding(.vertical, 24)
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
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .cornerRadius(10)
    }
}

struct ExerciseRow: View {
    let index: Int
    let exercise: WorkoutExercise
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.ember.opacity(0.12)).frame(width: 40, height: 40)
                Text("\(index)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.ember)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 8) {
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.surfaceElevated)
                .cornerRadius(6)
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(14)
    }
}
