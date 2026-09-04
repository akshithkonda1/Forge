import WidgetKit
import SwiftUI
import ForgeCore

// MARK: - HydrationComplication
//
// Water at a glance: how many glasses are in, against the target
// HydrationEngine computed. Tapping opens Forge, where one tap logs a glass.
//
// The better version of this is an interactive `Button(intent: LogWaterIntent())`
// on the rectangular family — logging from the watch face without opening
// anything. It is not here, and the reason is structural rather than a
// preference: `Button(intent:)` needs the intent type visible inside the
// widgets extension's module, and the intents live in the watch app target.
// Making that work means either a file compiled into two targets — hand-built
// pbxproj surgery, which has broken this project's build three times — or
// moving AppIntent conformances into the ForgeCore package, where App Intents
// metadata extraction has a known discovery wrinkle that cannot be verified
// without Xcode. Both are worth doing deliberately, on their own, with a build
// to check them against. Neither is worth guessing at inside a batch of
// features.

struct HydrationComplication: Widget {
    let kind = "HydrationComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            HydrationComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Water")
        .description("Today's hydration, with one tap to log a glass.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct HydrationComplicationView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var consumed: Double { entry.snapshot?.hydrationMilliliters ?? 0 }
    private var target: Double {
        let stored = entry.snapshot?.hydrationTargetMilliliters ?? 0
        return stored > 0 ? stored : HydrationEngine.minimumTargetMilliliters
    }
    private var progress: Double { min(1, target > 0 ? consumed / target : 0) }
    private var glasses: Int { Int(HydrationEngine.glasses(fromMilliliters: consumed).rounded()) }
    private var targetGlasses: Int { Int(HydrationEngine.glasses(fromMilliliters: target).rounded()) }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryRectangular: rectangular
        default: inline
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Gauge(value: progress) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text("\(glasses)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(ForgePalette.steel)
            .widgetAccentable()
        }
        .widgetURL(URL(string: "forgewatch://home"))
        .accessibilityLabel(accessibilityText)
    }

    private var corner: some View {
        Text("\(glasses)")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(ForgePalette.steel)
            .widgetAccentable()
            .widgetLabel {
                Gauge(value: progress) { EmptyView() }
                    .tint(ForgePalette.steel)
            }
            .widgetURL(URL(string: "forgewatch://home"))
            .accessibilityLabel(accessibilityText)
    }

    /// The one family with room to name the target as well as the count.
    private var rectangular: some View {
        HStack(spacing: 6) {
            Gauge(value: progress) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(ForgePalette.steel)
                .scaleEffect(0.62)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(glasses) of \(targetGlasses)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .widgetAccentable()
                Text("glasses today")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "forgewatch://home"))
        .accessibilityLabel(accessibilityText)
    }

    private var inline: some View {
        Text("Water \(glasses)/\(targetGlasses)")
            .widgetURL(URL(string: "forgewatch://home"))
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        "\(glasses) of \(targetGlasses) glasses of water today."
    }
}
