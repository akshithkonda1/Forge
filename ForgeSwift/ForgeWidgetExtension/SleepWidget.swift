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
                Text(HomeWidgetSleepDisplay.hoursText(snap, style: .compact))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
            }
        case .accessoryRectangular, .accessoryInline:
            HStack(spacing: 6) {
                Image(systemName: "moon.stars.fill")
                Text(HomeWidgetSleepDisplay.hoursText(snap, style: .lastNight))
                    .font(.caption.weight(.semibold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                WidgetChrome.eyebrow("Sleep", color: ForgePalette.violet)
                if HomeWidgetSleepDisplay.hasHoursToShow(snap.sleepHours) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(HomeWidgetSleepDisplay.hoursText(snap, style: .number))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(ForgePalette.textPrimary)
                        Text("hours")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ForgePalette.textSecondary)
                    }
                } else {
                    WidgetChrome.empty(HomeWidgetSleepDisplay.emptyCopy)
                }
                if let score = snap.sleepScore {
                    Text("Score \(score)")
                        .font(.caption)
                        .foregroundStyle(ForgePalette.violet)
                }
                if HomeWidgetSleepDisplay.hasHoursToShow(snap.sleepHours),
                   let window = snap.sleepWindowTitle, family != .systemSmall {
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
