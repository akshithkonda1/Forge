import SwiftUI
import WidgetKit
import ForgeCore

struct SleepWidgetView: View {
    var entry: HomeWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var snap: HomeWidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "moon.stars.fill")
                    .font(.caption)
                Text(String(format: "%.1fh", snap.sleepHours))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
            }
        case .accessoryRectangular, .accessoryInline:
            HStack(spacing: 6) {
                Image(systemName: "moon.stars.fill")
                Text(String(format: "%.1f h last night", snap.sleepHours))
                    .font(.caption.weight(.semibold))
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                WidgetChrome.eyebrow("Sleep", color: ForgePalette.violet)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", snap.sleepHours))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(ForgePalette.textPrimary)
                    Text("hours")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ForgePalette.textSecondary)
                }
                if let score = snap.sleepScore {
                    Text("Score \(score)")
                        .font(.caption)
                        .foregroundStyle(ForgePalette.violet)
                }
                if let window = snap.sleepWindowTitle, family != .systemSmall {
                    Text(window)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ForgePalette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

struct SleepWidget: Widget {
    let kind = "SleepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeWidgetProvider()) { entry in
            SleepWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetChrome.background(accent: ForgePalette.violet)
                }
                .widgetURL(ForgeWidgetLink.sleep)
        }
        .configurationDisplayName("Sleep")
        .description("Last night's sleep and the energy window you are in.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
        .contentMarginsDisabled()
    }
}
