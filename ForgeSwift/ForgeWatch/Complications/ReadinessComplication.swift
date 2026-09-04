import WidgetKit
import SwiftUI
import ForgeCore

// MARK: - ReadinessComplication
//
// The one-glance answer to "how am I doing today?". Gauge ring tinted by
// band; honest empty state when data hasn't synced. Tapping opens Home.

struct ReadinessComplication: Widget {
    let kind = "ReadinessComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            ReadinessComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "forgewatch://home"))
        }
        .configurationDisplayName("Readiness")
        .description("Today's readiness at a glance — a guide, not a grade.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct ReadinessComplicationView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var score: Int? { entry.snapshot?.readinessOverall }
    private var band: ReadinessBand? { entry.snapshot?.readinessBand ?? score.map(ReadinessBand.init(score:)) }
    private var tint: Color { band?.color ?? ForgePalette.textTertiary }

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
            if let score {
                Gauge(value: Double(score), in: 0...100) {
                    Text("RDY")
                } currentValueLabel: {
                    Text("\(score)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(tint)
                .widgetAccentable()
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var corner: some View {
        Text(score.map(String.init) ?? "–")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .widgetAccentable()
            .widgetLabel {
                if let score {
                    Gauge(value: Double(score), in: 0...100) { EmptyView() }
                        .tint(tint)
                } else {
                    Text("Open Forge")
                }
            }
            .accessibilityLabel(accessibilityText)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(score.map { "Readiness \($0)" } ?? "Readiness")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .widgetAccentable()
                if let band {
                    Text("· \(band.label)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(band?.supportiveDescriptor ?? "Wear your watch a little and Forge will catch up.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(accessibilityText)
    }

    private var inline: some View {
        Text(score.flatMap { s in band.map { "Readiness \(s) · \($0.label)" } } ?? "Readiness syncing…")
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let score, let band else { return "Readiness is still syncing. Open Forge to update." }
        return "Readiness \(score) out of 100, \(band.label). \(band.supportiveDescriptor)"
    }
}
