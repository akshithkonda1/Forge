import WidgetKit
import SwiftUI
import ForgeCore

// MARK: - MindfulnessResetComplication
//
// The proactive nudge on the watch face: shows the currently recommended
// practice + duration ("90s Focus Reset") and deep-links straight into
// the pre-filled session. This is the complication that closes the loop
// on the flagship flow (long desk block → glance → one tap → breathing).

struct MindfulnessResetComplication: Widget {
    let kind = "MindfulnessResetComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            MindfulnessResetComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "forgewatch://mindfulness"))
        }
        .configurationDisplayName("Mindful Reset")
        .description("One tap into the practice that fits this moment of your day.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct MindfulnessResetComplicationView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var practice: PracticeType? { entry.snapshot?.recommendedPractice }
    private var durationLabel: String { entry.snapshot?.recommendedDurationShortLabel ?? "" }
    private var tint: Color { practice?.accentColor ?? ForgePalette.jade }

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
            VStack(spacing: 0) {
                Image(systemName: practice?.symbolName ?? "leaf.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .widgetAccentable()
                if !durationLabel.isEmpty {
                    Text(durationLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var corner: some View {
        Image(systemName: practice?.symbolName ?? "leaf.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .widgetAccentable()
            .widgetLabel {
                Text(practice.map { "\(durationLabel) \($0.displayName)" } ?? "Tap for a reset")
            }
            .accessibilityLabel(accessibilityText)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: practice?.symbolName ?? "leaf.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .widgetAccentable()
                Text(practice.map { "\(durationLabel) \($0.displayName)" } ?? "Mindful reset")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            Text(entry.snapshot?.recommendationReason ?? "A short reset, tuned to your day, is one tap away.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(accessibilityText)
    }

    private var inline: some View {
        Text(practice.map { "\(durationLabel) \($0.displayName) ready" } ?? "Reset ready")
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let practice else { return "A mindful reset is one tap away." }
        return "Recommended: \(practice.displayName), \(durationLabel). \(entry.snapshot?.recommendationReason ?? "")"
    }
}
