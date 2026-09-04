import SwiftUI
import WidgetKit
import AppIntents
import ForgeCore

struct HydrationWidgetView: View {
    var entry: HomeWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var snap: HomeWidgetSnapshot { entry.snapshot }
    private var tint: Color { Color(forgeHex: "4A9EFF") }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: snap.hydrationFraction) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text("\(Int((snap.hydrationFraction * 100).rounded()))")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular, .accessoryInline:
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                Text("\(Int(snap.hydrationMl.rounded())) ml")
                    .font(.caption.weight(.semibold))
            }
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetChrome.eyebrow("Hydration", color: tint)
            Text(format(snap.hydrationMl))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(ForgePalette.textPrimary)
                .contentTransition(.numericText())
            Text("of \(format(snap.hydrationTargetMl))")
                .font(.caption)
                .foregroundStyle(ForgePalette.textSecondary)
            Gauge(value: snap.hydrationFraction) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .tint(tint)
            Spacer(minLength: 0)
            Button(intent: LogWaterGlassIntent()) {
                Label("Log a glass", systemImage: "plus")
                    .font(.caption.weight(.semibold))
            }
            .tint(tint)
        }
        .padding(16)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetChrome.eyebrow("Hydration", color: tint)
                Text(format(snap.hydrationMl))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(ForgePalette.textPrimary)
                Text("of \(format(snap.hydrationTargetMl)) · \(Int((snap.hydrationFraction * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(ForgePalette.textSecondary)
                Gauge(value: snap.hydrationFraction) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(tint)
                Spacer(minLength: 0)
            }
            VStack {
                Spacer()
                Button(intent: LogWaterGlassIntent()) {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.bold))
                        Text("Glass")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(width: 64, height: 64)
                }
                .tint(tint)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private func format(_ ml: Double) -> String {
        ml >= 1_000 ? String(format: "%.2f L", ml / 1_000) : "\(Int(ml.rounded())) ml"
    }
}

struct HydrationWidget: Widget {
    let kind = "HydrationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeWidgetProvider()) { entry in
            HydrationWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetChrome.background(accent: Color(forgeHex: "4A9EFF"))
                }
                .widgetURL(ForgeWidgetLink.hydration)
        }
        .configurationDisplayName("Hydration")
        .description("Today's water against your need. Log a glass without opening Forge.")
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
