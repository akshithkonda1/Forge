import WidgetKit
import SwiftUI
import ForgeCore

// MARK: - SleepQualityComplication
//
// Last night, honestly and kindly: quality ring + duration. Deep-links to
// Home's sleep glance (SleepSummaryView takes over in Phase 4).

struct SleepQualityComplication: Widget {
    let kind = "SleepQualityComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            SleepQualityComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "forgewatch://sleep"))
        }
        .configurationDisplayName("Sleep Quality")
        .description("Last night's rest and what it gives you today.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct SleepQualityComplicationView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var quality: Int? { entry.snapshot?.sleepQualityScore }
    private var durationText: String? {
        guard let minutes = entry.snapshot?.sleepMinutes else { return nil }
        return "\(Int(minutes) / 60)h \(Int(minutes) % 60)m"
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
            if let quality {
                Gauge(value: Double(quality), in: 0...100) {
                    Image(systemName: "bed.double.fill")
                } currentValueLabel: {
                    Text("\(quality)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(ForgePalette.indigo)
                .widgetAccentable()
            } else {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 15))
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var corner: some View {
        Image(systemName: "bed.double.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(ForgePalette.indigo)
            .widgetAccentable()
            .widgetLabel {
                Text(cornerLabel)
            }
            .accessibilityLabel(accessibilityText)
    }

    private var cornerLabel: String {
        switch (durationText, quality) {
        case let (duration?, quality?): return "\(duration) · \(quality)"
        case let (duration?, nil):      return duration
        default:                        return "No sleep data yet"
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ForgePalette.indigo)
                    .widgetAccentable()
                Text(durationText.map { "Slept \($0)" } ?? "Sleep")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if let quality {
                    Text("· \(quality)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(accessibilityText)
    }

    private var subtitle: String {
        // Evening: pivot to tonight's plan once a wind-down is predicted.
        if let windDown = entry.snapshot?.tonightWindDown, windDown > entry.date {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "Tonight: wind down ~\(formatter.string(from: windDown))"
        }
        guard let quality else { return "Last night will appear after your watch syncs." }
        switch quality {
        case 80...: return "Solid recharge — it's fueling today's readiness."
        case 60..<80: return "A decent night. Today can still be a good one."
        default: return "A short night, not a lost day — pace kindly."
        }
    }

    private var inline: some View {
        Text(cornerLabel == "No sleep data yet" ? "Sleep: syncing…" : "Sleep \(cornerLabel)")
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let durationText, let quality else {
            return "Sleep data hasn't synced yet."
        }
        return "Slept \(durationText), quality \(quality) out of 100. \(subtitle)"
    }
}
