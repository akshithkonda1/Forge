import SwiftUI
import WidgetKit
import ForgeCore

struct ReadinessWidgetView: View {
    var entry: HomeWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var score: Int { entry.snapshot.readiness }
    private var band: ReadinessBand { ReadinessBand(score: score) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(score), in: 0...100) {
                Image(systemName: "bolt.heart.fill")
            } currentValueLabel: {
                Text("\(score)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular, .accessoryInline:
            HStack(spacing: 6) {
                Image(systemName: "bolt.heart.fill")
                Text("\(score) · \(band.label)")
                    .font(.caption.weight(.semibold))
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                WidgetChrome.eyebrow("Readiness", color: band.color)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(ForgePalette.textPrimary)
                        .contentTransition(.numericText())
                    Text(band.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(band.color)
                }
                Text(band.supportiveDescriptor)
                    .font(.caption2)
                    .foregroundStyle(ForgePalette.textSecondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

struct ReadinessWidget: Widget {
    let kind = "ReadinessWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeWidgetProvider()) { entry in
            ReadinessWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetChrome.background(accent: ReadinessBand(score: entry.snapshot.readiness).color)
                }
                .widgetURL(ForgeWidgetLink.readiness)
        }
        .configurationDisplayName("Readiness")
        .description("Today's readiness score on your Home Screen or Lock Screen.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
        .contentMarginsDisabled()
    }
}
