import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Readiness Widget

struct ReadinessEntry: TimelineEntry {
    let date: Date
    let readiness: Int
    let workoutName: String
    let hrv: Int
    let streak: Int
    let strain: Int
    let recovery: Int
    let sleep: Int
    let sleepNeed: Int
    let briefHeadline: String
}

struct ReadinessProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadinessEntry {
        ReadinessEntry(date: Date(), readiness: 82, workoutName: "Upper Body Power", hrv: 52, streak: 5, strain: 58, recovery: 79, sleep: 88, sleepNeed: 45, briefHeadline: "Trilogy green light — strain 58, recovery 79, sleep 88.")
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadinessEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadinessEntry>) -> Void) {
        let entry = currentEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> ReadinessEntry {
        ReadinessEntry(
            date: Date(),
            readiness: ForgeSharedData.readinessScore,
            workoutName: ForgeSharedData.workoutName,
            hrv: ForgeSharedData.hrv,
            streak: ForgeSharedData.streak,
            strain: ForgeSharedData.strainScore,
            recovery: ForgeSharedData.recoveryScore,
            sleep: ForgeSharedData.sleepScore,
            sleepNeed: ForgeSharedData.sleepNeedMinutes,
            briefHeadline: ForgeSharedData.briefHeadline
        )
    }
}

struct ReadinessWidgetView: View {
    let entry: ReadinessEntry

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(Color(red: 0.04, green: 0.04, blue: 0.04))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("FORGE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 1, green: 0.3, blue: 0))
                    Spacer()
                    Text("\(entry.streak)d")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                HStack(spacing: 10) {
                    TrilogyWidgetStat(label: "Strain", value: entry.strain, color: Color(red: 0.98, green: 0.45, blue: 0.09))
                    TrilogyWidgetStat(label: "Recovery", value: entry.recovery, color: Color(red: 0.13, green: 0.77, blue: 0.37))
                    TrilogyWidgetStat(label: "Sleep", value: entry.sleep, color: Color(red: 0.39, green: 0.4, blue: 0.95))
                }
                Text(entry.workoutName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                if !entry.briefHeadline.isEmpty {
                    Text(entry.briefHeadline)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                } else if entry.sleepNeed > 0 {
                    Text("Sleep need \(entry.sleepNeed)m")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    Text("HRV \(entry.hrv)ms · Ready \(entry.readiness)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(14)
        }
    }
}

struct ReadinessWidget: Widget {
    let kind = "ForgeReadinessWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReadinessProvider()) { entry in
            ReadinessWidgetView(entry: entry)
        }
        .configurationDisplayName("Forge Readiness")
        .description("Strain, recovery, sleep trilogy and today's workout.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Workout Live Activity

struct WorkoutLiveActivityView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.workoutName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                Text(context.state.exerciseName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                if context.state.isResting {
                    Text("Rest \(context.state.restSecondsRemaining)s")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 1, green: 0.3, blue: 0))
                } else {
                    Text("Set \(context.state.currentSet)/\(context.state.totalSets)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatElapsed(context.state.elapsedSeconds))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("\(context.state.heartRate) bpm")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Text(context.state.hrZoneLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 1, green: 0.3, blue: 0))
            }
        }
        .padding(14)
        .activityBackgroundTint(Color(red: 0.08, green: 0.08, blue: 0.08))
    }

    private func formatElapsed(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct TrilogyWidgetStat: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
        }
    }
}

@main
struct ForgeWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadinessWidget()
        if #available(iOS 16.1, *) {
            WorkoutLiveActivityWidget()
        }
    }
}

@available(iOS 16.1, *)
struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.exerciseName)
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.heartRate)")
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.workoutName)
                        .font(.caption2)
                }
            } compactLeading: {
                Text("\(context.state.currentSet)")
            } compactTrailing: {
                Image(systemName: "dumbbell.fill")
            } minimal: {
                Image(systemName: "flame.fill")
            }
        }
    }
}
