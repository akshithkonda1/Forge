import SwiftUI
import ForgeCore

// MARK: - WorkoutCoordinatorView
//
// The wrist workout experience: readiness-aware start screen → 3-2-1
// countdown → in-session vertical pages (Controls / Metrics / Exercise,
// the watchOS Workout-app idiom) → summary that hands off into a
// mindfulness reset. Effort guidance is informational, never bossy.

struct WorkoutCoordinatorView: View {
    @Environment(WorkoutSessionManager.self) private var workout
    @Environment(WatchHealthKitManager.self) private var health
    @Environment(ARIAWatchService.self) private var aria
    @Environment(MindfulnessSessionManager.self) private var mindfulness
    @Binding var path: [WatchRoute]

    var body: some View {
        switch workout.phase {
        case .idle:
            WorkoutStartView()
        case .countdown:
            CountdownView()
        case .active, .resting, .paused:
            InSessionView()
        case .summary:
            WorkoutSummaryView(path: $path)
        }
    }
}

// MARK: - Start

private struct WorkoutStartView: View {
    @Environment(WorkoutSessionManager.self) private var workout
    @Environment(ARIAWatchService.self) private var aria

    private var suggestion: WorkoutSuggestion {
        WorkoutSuggestionEngine.suggest(for: aria.lastContext ?? WatchARIAContext())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeDS.Spacing.md) {
                let suggested = suggestion
                ContextCard(
                    systemImage: suggested.type.symbolName,
                    title: "Today: \(suggested.type.displayName) · Zone \(suggested.targetZone)",
                    body_: suggested.reason,
                    accent: suggested.type.accentColor,
                    accessibilityHint: "Starts the suggested session."
                ) {
                    workout.start(type: suggested.type)
                }

                if suggested.type == .strength || suggested.type == .hiit {
                    ForgeActionButton(
                        title: "Guided: \(StructuredWorkout.starterStrength.name)",
                        systemImage: "list.bullet.rectangle",
                        tint: ForgePalette.ember,
                        accessibilityHint: "Starts the structured plan with sets, reps, and rest timers."
                    ) {
                        workout.start(type: .strength, plan: .starterStrength)
                    }
                }

                Text("Or pick your own — every option is a good one.")
                    .font(.system(size: 11))
                    .foregroundStyle(ForgePalette.textTertiary)

                ForEach(ForgeWorkoutType.allCases) { type in
                    HapticButton(haptic: .click) {
                        workout.start(type: type)
                    } label: {
                        HStack {
                            Image(systemName: type.symbolName)
                                .foregroundStyle(type.accentColor)
                                .frame(width: 24)
                            Text(type.displayName)
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Start \(type.displayName) workout")
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Workout")
    }
}

// MARK: - Countdown

private struct CountdownView: View {
    @Environment(WorkoutSessionManager.self) private var workout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The manager owns the countdown. This view used to run a second, parallel
    /// timer, so the number shown and the session's actual start agreed only by
    /// coincidence — and any re-render restarted the display from 3 while the
    /// manager kept counting down underneath it.
    private var count: Int {
        workout.countdownRemaining ?? WorkoutSessionManager.countdownSeconds
    }

    var body: some View {
        Text("\(count)")
            .font(ForgeType.metric(64))
            .foregroundStyle(ForgePalette.ember)
            .scaleEffect(reduceMotion ? 1 : 1 + CGFloat(WorkoutSessionManager.countdownSeconds - count) * 0.06)
            .animation(reduceMotion ? nil : ForgeDS.Spring.snap, value: count)
            .navigationBarBackButtonHidden(true)
            .accessibilityLabel("Starting in \(count)")
    }
}

// MARK: - In session

private struct InSessionView: View {
    @Environment(WorkoutSessionManager.self) private var workout

    var body: some View {
        TabView {
            SessionControlsPage()
            SessionMetricsPage()
            if workout.plan != nil {
                SessionExercisePage()
            }
        }
        .tabViewStyle(.verticalPage)
        .navigationBarBackButtonHidden(true)
    }
}

private struct SessionControlsPage: View {
    @Environment(WorkoutSessionManager.self) private var workout

    var body: some View {
        VStack(spacing: ForgeDS.Spacing.md) {
            HapticButton(haptic: .click) {
                if workout.phase == .paused {
                    workout.resume()
                } else {
                    workout.pause()
                }
            } label: {
                Label(
                    workout.phase == .paused ? "Resume" : "Pause",
                    systemImage: workout.phase == .paused ? "play.fill" : "pause.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(ForgePalette.amber)
            .accessibilityLabel(workout.phase == .paused ? "Resume workout" : "Pause workout")

            HapticButton(haptic: .stop) {
                Task { await workout.end() }
            } label: {
                Label("End", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ForgePalette.jade.opacity(0.85))
            .foregroundStyle(.black)
            .accessibilityLabel("End workout")
            .accessibilityHint("Saves the session to Health and shows your summary.")
        }
        .padding(.horizontal, 4)
    }
}

private struct SessionMetricsPage: View {
    @Environment(WorkoutSessionManager.self) private var workout
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(elapsedLabel)
                    .font(ForgeType.metric(30))
                    .foregroundStyle(ForgePalette.textPrimary)
                    .monospacedDigit()
                    .accessibilityLabel("Elapsed \(elapsedLabel)")
            }

            HStack(spacing: ForgeDS.Spacing.sm) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(workout.currentZone?.color ?? ForgePalette.textTertiary)
                    .opacity(luminanceReduced ? 0.6 : 1)
                Text(workout.heartRate.map { "\(Int($0))" } ?? "—")
                    .font(ForgeType.metric(24))
                    .monospacedDigit()
                if let zone = workout.currentZone {
                    Text(zone.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(zone.color)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heartAccessibility)

            zoneBar

            if let calories = workout.activeCalories {
                Label("\(Int(calories)) cal", systemImage: "flame.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(ForgePalette.amber)
            }

            if let cue = workout.coachingCue {
                Text(cue)
                    .font(.system(size: 11))
                    .foregroundStyle(ForgePalette.textSecondary)
                    .lineLimit(3)
                    .accessibilityLabel("Coach: \(cue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var elapsedLabel: String {
        let total = Int(workout.elapsed.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var heartAccessibility: String {
        guard let bpm = workout.heartRate else { return "Heart rate reading" }
        let zoneText = workout.currentZone.map { ", \($0.label)" } ?? ""
        return "Heart rate \(Int(bpm)) beats per minute\(zoneText)"
    }

    /// Five-segment zone bar; the active zone is lit. Epilepsy-safe: the
    /// bar only changes when the zone changes (breath-slow at most).
    private var zoneBar: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { number in
                let zone = ForgeHRZones.zone(number: number)
                RoundedRectangle(cornerRadius: 2)
                    .fill(zone.color.opacity(workout.currentZone?.zone == number ? 1 : 0.25))
                    .frame(height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SessionExercisePage: View {
    @Environment(WorkoutSessionManager.self) private var workout

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            if workout.phase == .resting, let rest = workout.restRemaining {
                restView(rest)
            } else if let exercise = workout.currentExercise {
                exerciseView(exercise)
            } else if workout.planIsComplete {
                VStack(spacing: ForgeDS.Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(ForgePalette.success)
                    Text("Plan complete — end whenever you're ready.")
                        .font(.system(size: 12.5))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(ForgePalette.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }

    private func exerciseView(_ exercise: WorkoutExercise) -> some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            Text(exercise.name)
                .font(ForgeType.title(17))
                .foregroundStyle(ForgePalette.textPrimary)
                .lineLimit(2)
            Text("Set \(workout.setIndex + 1) of \(exercise.sets.count) · \(exercise.sets[min(workout.setIndex, exercise.sets.count - 1)].reps) reps")
                .font(.system(size: 12.5))
                .foregroundStyle(ForgePalette.textSecondary)

            HapticButton(haptic: .click) {
                workout.completeSet()
            } label: {
                Label("Done", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ForgePalette.steel.opacity(0.85))
            .accessibilityLabel("Set done")
            .accessibilityHint("Logs this set and starts the rest timer.")
        }
        .accessibilityElement(children: .contain)
    }

    private func restView(_ remaining: Int) -> some View {
        VStack(spacing: ForgeDS.Spacing.sm) {
            Text("Rest")
                .font(ForgeType.caption(13))
                .foregroundStyle(ForgePalette.textSecondary)
            Text("\(remaining)")
                .font(ForgeType.metric(44))
                .foregroundStyle(ForgePalette.steelLight)
                .monospacedDigit()
                .accessibilityLabel("\(remaining) seconds of rest left. Wrist taps count the last three.")
            HapticButton(haptic: .click) {
                workout.skipRest()
            } label: {
                Text("Skip rest").font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Ends the rest early.")
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Summary → mindfulness handoff

private struct WorkoutSummaryView: View {
    @Environment(WorkoutSessionManager.self) private var workout
    @Environment(WatchHealthKitManager.self) private var health
    @Environment(MindfulnessSessionManager.self) private var mindfulness
    @Binding var path: [WatchRoute]

    var body: some View {
        ScrollView {
            if let summary = workout.summary {
                VStack(alignment: .leading, spacing: ForgeDS.Spacing.md) {
                    ContextCard(
                        systemImage: summary.workoutType.symbolName,
                        title: summaryTitle(summary),
                        body_: summary.debrief,
                        accent: summary.workoutType.accentColor
                    )

                    HStack(spacing: ForgeDS.Spacing.lg) {
                        if let avg = summary.averageHeartRate {
                            statView(value: "\(Int(avg))", label: "avg bpm")
                        }
                        if let calories = summary.activeCalories {
                            statView(value: "\(Int(calories))", label: "cal")
                        }
                        if let zone = summary.dominantZone {
                            statView(value: "Z\(zone)", label: "mostly")
                        }
                    }

                    if !summary.savedToHealth {
                        Text("Couldn't save to Health just now — the effort still counted.")
                            .font(.system(size: 11))
                            .foregroundStyle(ForgePalette.textTertiary)
                    }

                    // The seamless handoff: effort → ease, one tap.
                    ForgeActionButton(
                        title: "3-min Body Scan reset",
                        systemImage: "figure.mind.and.body",
                        tint: ForgePalette.violet,
                        haptic: .start,
                        accessibilityHint: "Starts a short recovery reset. Skipping is completely fine too."
                    ) {
                        mindfulness.start(practice: .bodyScan, duration: 180, health: health)
                        workout.dismissSummary()
                        path.append(.mindfulness)
                    }

                    Button("Done for now") {
                        workout.dismissSummary()
                        path.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(ForgePalette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Closes the summary. Full review is on your iPhone.")
                }
                .padding(.horizontal, 2)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func summaryTitle(_ summary: WorkoutSessionManager.Summary) -> String {
        let minutes = max(1, Int(summary.duration / 60))
        return "\(summary.workoutType.displayName) · \(minutes) min"
    }

    private func statView(value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(ForgeType.metric(18))
                .foregroundStyle(ForgePalette.textPrimary)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(ForgePalette.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}
