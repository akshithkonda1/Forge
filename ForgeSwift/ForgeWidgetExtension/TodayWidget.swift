import SwiftUI
import WidgetKit
import ForgeCore

struct TodayWidgetView: View {
    var entry: HomeWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var snap: HomeWidgetSnapshot { entry.snapshot }

    var body: some View {
        if family == .systemLarge {
            large
        } else {
            medium
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetChrome.eyebrow("Today", color: ForgePalette.ember)
            HStack(spacing: 14) {
                metric("Readiness", value: "\(snap.readiness)", tint: ReadinessBand(score: snap.readiness).color)
                metric("Sleep", value: String(format: "%.1fh", snap.sleepHours), tint: ForgePalette.violet)
                metric("Water", value: "\(Int((snap.hydrationFraction * 100).rounded()))%", tint: Color(forgeHex: "4A9EFF"))
            }
            if let rec = snap.topRecommendation {
                Text(rec)
                    .font(.caption)
                    .foregroundStyle(ForgePalette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 14) {
            WidgetChrome.eyebrow("Today", color: ForgePalette.ember)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snap.readiness)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(ForgePalette.textPrimary)
                    Text(snap.readinessLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ReadinessBand(score: snap.readiness).color)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    row(icon: "moon.stars.fill", tint: ForgePalette.violet,
                        title: String(format: "%.1f h sleep", snap.sleepHours),
                        detail: snap.sleepWindowTitle)
                    row(icon: "drop.fill", tint: Color(forgeHex: "4A9EFF"),
                        title: "\(Int(snap.hydrationMl.rounded())) ml",
                        detail: "\(Int((snap.hydrationFraction * 100).rounded()))% of need")
                    if let phase = snap.cyclePhase {
                        row(icon: "heart.circle.fill", tint: Color(forgeHex: "EC4899"),
                            title: phase.capitalized,
                            detail: snap.cycleDay.map { "Day \($0)" })
                    }
                }
            }
            if let workout = snap.workoutName {
                Label(workout, systemImage: "dumbbell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForgePalette.ember)
            }
            if let rec = snap.topRecommendation {
                Text(rec)
                    .font(.caption)
                    .foregroundStyle(ForgePalette.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func metric(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ForgePalette.textTertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(icon: String, tint: Color, title: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(ForgePalette.textPrimary)
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(ForgePalette.textSecondary)
                }
            }
        }
    }
}

struct TodayWidget: Widget {
    let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeWidgetProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetChrome.background(accent: ForgePalette.ember)
                }
                .widgetURL(ForgeWidgetLink.today)
        }
        .configurationDisplayName("Forge Today")
        .description("Readiness, sleep, water and today's note — one glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
