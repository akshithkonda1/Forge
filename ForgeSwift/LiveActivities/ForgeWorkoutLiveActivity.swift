import WidgetKit
import SwiftUI
import ForgeCore

// MARK: - ForgeWorkoutLiveActivity (ForgeWidgetExtension target only)
//
// Lock-screen banner + Dynamic Island for a workout running on the
// watch. Forge palette on black, zone color as the live accent, calm
// copy. Tapping opens the iOS app (full review lives in WorkoutView).

struct ForgeWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ForgeWorkoutActivityAttributes.self) { context in
            LockScreenWorkoutView(state: context.state.live)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let live = context.state.live
            let accent = zoneColor(live)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(live.workoutType.displayName, systemImage: live.workoutType.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(live.elapsedLabel)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        if let bpm = live.heartRate {
                            Label("\(Int(bpm))", systemImage: "heart.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(accent)
                        }
                        if let zone = live.zoneNumber {
                            Text("Zone \(zone)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if let exercise = live.currentExerciseName {
                            Text(exercise)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            } compactLeading: {
                Image(systemName: live.workoutType.symbolName)
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text(live.elapsedLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: live.workoutType.symbolName)
                    .foregroundStyle(accent)
            }
        }
    }

    private func zoneColor(_ live: WorkoutLiveState) -> Color {
        guard let zone = live.zoneNumber else { return live.workoutType.accentColor }
        return ForgeHRZones.zone(number: zone).color
    }
}

private struct LockScreenWorkoutView: View {
    let state: WorkoutLiveState

    private var accent: Color {
        guard let zone = state.zoneNumber else { return state.workoutType.accentColor }
        return ForgeHRZones.zone(number: zone).color
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.workoutType.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(state.elapsedLabel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if let bpm = state.heartRate {
                    Label("\(Int(bpm))", systemImage: "heart.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                }
            }
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var title: String {
        switch state.phase {
        case .paused:  return "\(state.workoutType.displayName) · Paused"
        case .resting: return "\(state.workoutType.displayName) · Resting"
        default:       return "\(state.workoutType.displayName) on Watch"
        }
    }

    private var subtitle: String {
        if let exercise = state.currentExerciseName,
           let setIndex = state.currentSetIndex,
           let totalSets = state.totalSetsInExercise {
            return "\(exercise) · set \(setIndex + 1)/\(totalSets)"
        }
        if let zone = state.zoneNumber {
            return "Zone \(zone) · steady as you like"
        }
        return "Live from your wrist"
    }

    private var accessibilityText: String {
        var parts = ["\(state.workoutType.displayName) workout, \(state.elapsedLabel) elapsed"]
        if let bpm = state.heartRate { parts.append("heart rate \(Int(bpm))") }
        if state.phase == .paused { parts.append("paused") }
        return parts.joined(separator: ", ")
    }
}
