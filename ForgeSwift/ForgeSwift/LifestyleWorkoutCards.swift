import SwiftUI
import ForgeCore

struct AIWorkoutSuggestionsCard: View {
    let workouts: [AIWorkoutSuggestion]
    @EnvironmentObject var store: AppStore
    @State private var selectedWorkout: CustomWorkoutPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Train suggestions", meta: "\(workouts.count) ready")

            VStack(spacing: ForgeLayout.rowGap) {
                ForEach(workouts, id: \.id) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        }
        .forgeContentCard(tint: .ember)
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(workout: workout)
                .environmentObject(store)
        }
    }

    private func suggestionRow(_ suggestion: AIWorkoutSuggestion) -> some View {
        Button {
            selectedWorkout = suggestion.workout
        } label: {
            AIWorkoutCard(suggestion: suggestion)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens workout details")
    }
}

/// One suggestion row: the Home agenda-row anatomy (36 pt well, status title,
/// meta, chevron). The reason sentence wraps instead of truncating.
struct AIWorkoutCard: View {
    let suggestion: AIWorkoutSuggestion

    private var meta: String {
        "\(suggestion.workout.duration) min · \(suggestion.workout.exercises.count) exercises"
    }

    var body: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: "dumbbell.fill", tint: .ember)

            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(suggestion.title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(meta)
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                Text(suggestion.reason)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            .layoutPriority(1)

            Spacer(minLength: FDS.Spacing.xs)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct WorkoutDetailSheet: View {
    let workout: CustomWorkoutPlan
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    ForgePageHeader(title: workout.name, accent: .ember)
                    factStrip
                    exerciseCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeScreenInsets()
            }
            .forgeScreenBackground(accent: .ember)
            .safeAreaInset(edge: .bottom) { startBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var factStrip: some View {
        ForgeStatGrid(columns: 3) {
            ForgeStatTile(label: "Duration", value: "\(workout.duration)", unit: "min", energy: .ember, icon: "clock.fill")
            ForgeStatTile(label: "Calories", value: "~\(workout.caloriesBurn)", unit: "cal", energy: .ember, icon: "flame.fill")
            ForgeStatTile(label: "Exercises", value: "\(workout.exercises.count)", energy: .ember, icon: "list.bullet")
        }
    }

    private var exerciseCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Exercises")

            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { i, exercise in
                    ExerciseRow(index: i + 1, exercise: exercise)
                }
            }
        }
        .forgeContentCard(tint: .ember)
    }

    /// The sheet's one primary action, pinned above the home indicator.
    private var startBar: some View {
        ForgePrimaryButton(title: "Start session", icon: "play.fill", accent: .ember) {
            store.adoptCustomWorkoutPlan(workout)
            store.startExistingWorkout()
            dismiss()
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.vertical, FDS.Spacing.sm)
        .frame(maxWidth: .infinity)
        .forgeBarChrome(edge: .bottom)
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: FDS.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(value)
                .font(HomeType.label)
                .foregroundStyle(Color.textPrimary)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
        }
        .padding(.horizontal, FDS.Spacing.sm)
        .padding(.vertical, FDS.Spacing.sm)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: ForgeUX.hairline))
        .accessibilityElement(children: .combine)
    }
}

/// A plain exercise row. The caller supplies the card, so the row carries
/// no chrome of its own.
struct ExerciseRow: View {
    let index: Int
    let exercise: WorkoutExercise

    @ScaledMetric(relativeTo: .subheadline) private var indexSize: CGFloat = 36

    private var meta: String {
        "\(exercise.sets) sets · \(exercise.reps) reps · \(exercise.restSeconds)s rest"
    }

    var body: some View {
        let diameter = ForgeLayout.scaledCap(indexSize, base: 36)
        HStack(spacing: ForgeLayout.rowGap) {
            ZStack {
                Circle().fill(Color.ember.opacity(0.16))
                Text("\(index)")
                    .font(HomeType.label)
                    .monospacedDigit()
                    .foregroundStyle(Color.ember)
                    .hudInArcText()
            }
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(exercise.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(meta)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(ForgeLayout.labelMinScale)
                ForgeChip(label: exercise.muscleGroup.rawValue.capitalized)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(index). \(exercise.name), \(meta), \(exercise.muscleGroup.rawValue.capitalized)")
    }
}
