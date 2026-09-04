import WidgetKit
import SwiftUI
import ForgeCore

// MARK: - ActiveWorkoutComplication
//
// Live session state on the watch face: elapsed + zone while a workout
// runs, a calm one-tap "start" affordance otherwise. Reads the same
// WatchSnapshot.activeWorkout the session manager publishes at 1 Hz
// (timeline reloads happen on phase changes + once a minute).

struct ActiveWorkoutComplication: Widget {
    let kind = "ActiveWorkoutComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            ActiveWorkoutComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "forgewatch://workout"))
        }
        .configurationDisplayName("Workout")
        .description("Your live session at a glance — or one tap to start moving.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct ActiveWorkoutComplicationView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var workout: WorkoutLiveState? {
        guard let state = entry.snapshot?.activeWorkout, state.phase != .ended else { return nil }
        return state
    }

    private var tint: Color {
        workout?.workoutType.accentColor ?? ForgePalette.ember
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            corner
        case .accessoryRectangular:
            rectangular
        default:
            inline
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let workout {
                VStack(spacing: 0) {
                    Image(systemName: workout.workoutType.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .widgetAccentable()
                    Text(workout.elapsedLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            } else {
                Image(systemName: "figure.run")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ForgePalette.textSecondary)
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var corner: some View {
        Image(systemName: workout?.workoutType.symbolName ?? "figure.run")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .widgetAccentable()
            .widgetLabel {
                Text(cornerLabel)
            }
            .accessibilityLabel(accessibilityText)
    }

    private var cornerLabel: String {
        guard let workout else { return "Start a workout" }
        if let zone = workout.zoneNumber {
            return "\(workout.elapsedLabel) · Z\(zone)"
        }
        return workout.elapsedLabel
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let workout {
                HStack(spacing: 4) {
                    Image(systemName: workout.workoutType.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .widgetAccentable()
                    Text("\(workout.workoutType.displayName) · \(workout.elapsedLabel)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    if let bpm = workout.heartRate {
                        Label("\(Int(bpm))", systemImage: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if let zoneNumber = workout.zoneNumber {
                        Text(ForgeHRZones.zone(number: zoneNumber).label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ForgeHRZones.zone(number: zoneNumber).color)
                    }
                    if let exercise = workout.currentExerciseName {
                        Text(exercise)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ForgePalette.textSecondary)
                    Text("No session running")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                Text("One tap starts the workout that fits today.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(accessibilityText)
    }

    private var inline: some View {
        Text(workout.map { "\($0.workoutType.displayName) \($0.elapsedLabel)" } ?? "Tap to work out")
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let workout else { return "No workout running. Tap to start one." }
        var parts = ["\(workout.workoutType.displayName) in progress, \(workout.elapsedLabel) elapsed"]
        if let bpm = workout.heartRate { parts.append("heart rate \(Int(bpm))") }
        if let zone = workout.zoneNumber { parts.append("zone \(zone)") }
        return parts.joined(separator: ", ")
    }
}
