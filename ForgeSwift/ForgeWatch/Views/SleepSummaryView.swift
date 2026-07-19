import SwiftUI
import ForgeCore

// MARK: - SleepSummaryView
//
// The morning glance: duration + quality header, a lite stage timeline
// (one Canvas, colored segments — no charting framework), last night's
// story, tonight's plan with a one-tap wind-down reminder, and
// zero-judgment factor chips. Deep-linked from the SleepQuality
// complication (forgewatch://sleep).

struct SleepSummaryView: View {
    @Environment(WatchHealthKitManager.self) private var health
    @Environment(ContextEngine.self) private var contextEngine
    @Environment(ARIAWatchService.self) private var aria
    @Environment(MindfulnessSessionManager.self) private var session

    @State private var reminderScheduled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeDS.Spacing.md) {
                header

                if let night = health.sleepSummary, !night.segments.isEmpty {
                    SleepTimelineCanvas(night: night)
                        .frame(height: 34)
                    legend
                }

                ContextCard(
                    systemImage: "text.book.closed.fill",
                    title: "Last night's story",
                    body_: story,
                    accent: ForgePalette.indigo
                )

                ContextCard(
                    systemImage: "moon.stars.fill",
                    title: "Tonight's plan",
                    body_: tonightPlan,
                    accent: ForgePalette.violet
                )

                if let plan = health.windDownPlan {
                    reminderButton(plan: plan)
                }

                factorChips
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Sleep")
    }

    // MARK: Pieces

    private var story: String {
        SleepStoryEngine.story(
            night: health.sleepSummary,
            readiness: health.readiness,
            factors: contextEngine.todaySleepFactors
        )
    }

    private var tonightPlan: String {
        SleepStoryEngine.tonightPlan(
            plan: health.windDownPlan,
            night: health.sleepSummary,
            highCognitiveLoadDay: contextEngine.isHighCognitiveLoadDay
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: ForgeDS.Spacing.sm) {
            Text(health.sleepSummary?.durationLabel ?? "—")
                .font(ForgeType.metric(28))
                .foregroundStyle(ForgePalette.textPrimary)
            if let quality = health.readiness?.sleepQuality, quality > 0 {
                Text("quality \(quality)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ForgePalette.indigo)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerAccessibility)
    }

    private var headerAccessibility: String {
        guard let night = health.sleepSummary else {
            return "No sleep data yet for last night."
        }
        var text = "Slept \(night.durationLabel)"
        if let quality = health.readiness?.sleepQuality, quality > 0 {
            text += ", quality \(quality) out of 100"
        }
        return text
    }

    private var legend: some View {
        HStack(spacing: ForgeDS.Spacing.sm) {
            ForEach(SleepStage.allCases, id: \.self) { stage in
                HStack(spacing: 3) {
                    Circle().fill(stage.color).frame(width: 5, height: 5)
                    Text(stage.displayName)
                        .font(.system(size: 9))
                        .foregroundStyle(ForgePalette.textTertiary)
                }
            }
        }
        .accessibilityHidden(true) // stage minutes are in the story text
    }

    private func reminderButton(plan: WindDownPlan) -> some View {
        ForgeActionButton(
            title: reminderScheduled ? "Reminder set ✓" : "Remind me at wind-down",
            systemImage: reminderScheduled ? "bell.fill" : "bell",
            tint: ForgePalette.violet,
            accessibilityHint: "Schedules one gentle reminder at tonight's suggested wind-down time."
        ) {
            Task {
                reminderScheduled = await WindDownScheduler.schedule(plan: plan)
            }
        }
        .disabled(reminderScheduled)
    }

    private var factorChips: some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            Text("Anything shape last night? (just context, never judged)")
                .font(.system(size: 11))
                .foregroundStyle(ForgePalette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ForgeDS.Spacing.sm) {
                    ForEach(SleepFactor.allCases) { factor in
                        let selected = contextEngine.todaySleepFactors.contains(factor)
                        HapticButton(haptic: .click) {
                            contextEngine.toggleSleepFactor(factor)
                        } label: {
                            Label(factor.label, systemImage: factor.symbolName)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, ForgeDS.Spacing.sm)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(selected
                                        ? ForgePalette.indigo.opacity(0.45)
                                        : ForgePalette.surface)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(factor.label)
                        .accessibilityValue(selected ? "Logged" : "Not logged")
                        .accessibilityHint("Adds context to your sleep story. Tap again to remove.")
                    }
                }
            }
        }
    }
}

// MARK: - Timeline canvas

private struct SleepTimelineCanvas: View {
    let night: SleepNight

    var body: some View {
        Canvas { context, size in
            guard
                let start = night.start,
                let end = night.end,
                end > start
            else { return }
            let total = end.timeIntervalSince(start)
            let barHeight = size.height * 0.62

            for segment in night.segments {
                let x = segment.start.timeIntervalSince(start) / total * size.width
                let width = max(1, segment.end.timeIntervalSince(segment.start) / total * size.width)
                // Awake pops above the baseline band, sleep sits in it —
                // reads like a night at a glance.
                let y = segment.stage == .awake ? 0 : size.height - barHeight
                let height = segment.stage == .awake ? size.height * 0.3 : barHeight
                let rect = CGRect(x: x, y: y, width: width, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1.5),
                    with: .color(segment.stage.color.opacity(segment.stage == .awake ? 0.7 : 0.9))
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timelineAccessibility)
    }

    private var timelineAccessibility: String {
        "Sleep stages: \(Int(night.deepMinutes)) minutes deep, \(Int(night.remMinutes)) minutes REM, \(Int(night.coreMinutes)) minutes core, \(Int(night.awakeMinutes)) minutes awake."
    }
}
