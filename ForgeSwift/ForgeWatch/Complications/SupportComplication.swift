import WidgetKit
import SwiftUI
import ForgeCore

// MARK: - SupportComplication
//
// A supporter's wrist glance. "Be kind" / "OK" — never a phase, day count,
// or the word period. Data is PartnerSupportGlance in the App Group, written
// by the iPhone after a CloudKit digest lands.

struct SupportComplication: Widget {
    let kind = "SupportComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SupportGlanceProvider()) { entry in
            SupportComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "forgewatch://home"))
        }
        .configurationDisplayName("Support today")
        .description("A kind/OK glance for someone you support. Never their log.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct SupportGlanceEntry: TimelineEntry {
    let date: Date
    let glance: PartnerSupportGlance?
}

struct SupportGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> SupportGlanceEntry {
        SupportGlanceEntry(date: Date(), glance: .gallerySample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SupportGlanceEntry) -> Void) {
        let glance = context.isPreview ? PartnerSupportGlance.gallerySample : PartnerSupportGlanceStore.load()
        completion(SupportGlanceEntry(date: Date(), glance: glance))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SupportGlanceEntry>) -> Void) {
        let entry = SupportGlanceEntry(date: Date(), glance: PartnerSupportGlanceStore.load())
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

private struct SupportComplicationView: View {
    let entry: SupportGlanceEntry
    @Environment(\.widgetFamily) private var family

    private var glance: PartnerSupportGlance? { entry.glance }
    private var tint: Color {
        guard let glance, !glance.isPaused, !glance.isStale else { return ForgePalette.textTertiary }
        return glance.extraThoughtfulnessHelps ? ForgePalette.jade : ForgePalette.indigo
    }

    var body: some View {
        switch family {
        case .accessoryCircular:   circular
        case .accessoryCorner:     corner
        case .accessoryRectangular: rectangular
        default:                   inline
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .widgetAccentable()
                Text(glance?.circularLabel ?? "—")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var corner: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .widgetAccentable()
            .widgetLabel {
                Text(glance?.circularLabel ?? "Support")
            }
            .accessibilityLabel(accessibilityText)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .widgetAccentable()
                Text(glance.map { $0.firstName.isEmpty ? "Support today" : $0.firstName } ?? "Support")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .widgetAccentable()
            }
            Text(glance?.lockScreenLine ?? "Open Forge after they invite you.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(accessibilityText)
    }

    private var inline: some View {
        Text(inlineText)
            .accessibilityLabel(accessibilityText)
    }

    private var inlineText: String {
        guard let glance else { return "Support today" }
        if glance.firstName.isEmpty { return glance.lockScreenLine }
        return "\(glance.firstName) · \(glance.circularLabel)"
    }

    private var accessibilityText: String {
        glance?.lockScreenLine ?? "Support glance is empty. Open Forge after they invite you."
    }
}
