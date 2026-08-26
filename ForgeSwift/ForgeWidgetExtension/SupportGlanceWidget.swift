import WidgetKit
import SwiftUI
import ForgeCore

// MARK: - SupportGlanceWidget
//
// Supporter Lock Screen + Home Screen. Lock Screen families use the
// lock-safe line only. The Home Screen widget (behind the lock) may show
// the digest headline — still never flow, fertility, or logs.

struct SupportGlanceWidget: Widget {
    let kind = "SupportGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SupportHomeGlanceProvider()) { entry in
            SupportGlanceWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetChrome.background(accent: ForgePalette.ember)
                }
                .widgetURL(ForgeWidgetLink.support)
        }
        .configurationDisplayName("Support today")
        .description("How to show up for someone who invited you. Never their log.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private struct SupportHomeGlanceEntry: TimelineEntry {
    let date: Date
    let glance: PartnerSupportGlance?
}

private struct SupportHomeGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> SupportHomeGlanceEntry {
        SupportHomeGlanceEntry(date: Date(), glance: .gallerySample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SupportHomeGlanceEntry) -> Void) {
        let glance = context.isPreview ? PartnerSupportGlance.gallerySample : PartnerSupportGlanceStore.load()
        completion(SupportHomeGlanceEntry(date: Date(), glance: glance))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SupportHomeGlanceEntry>) -> Void) {
        let entry = SupportHomeGlanceEntry(date: Date(), glance: PartnerSupportGlanceStore.load())
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

private struct SupportGlanceWidgetView: View {
    let entry: SupportHomeGlanceEntry
    @Environment(\.widgetFamily) private var family

    private var glance: PartnerSupportGlance? { entry.glance }
    private var tint: Color {
        guard let glance, !glance.isPaused, !glance.isStale else { return ForgePalette.textTertiary }
        return glance.extraThoughtfulnessHelps ? ForgePalette.jade : ForgePalette.indigo
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 2) {
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(glance?.circularLabel ?? "—")
                    .font(.caption2)
            }
            .accessibilityLabel(lockSafe)
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(glance.map { $0.firstName.isEmpty ? "Support" : $0.firstName } ?? "Support")
                        .font(.caption).fontWeight(.semibold)
                    Text(glance?.lockScreenLine ?? "Waiting on an invite")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .accessibilityLabel(lockSafe)
        default:
            homeCard
        }
    }

    private var homeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetChrome.eyebrow("Support today", color: tint)
            if let glance {
                Text(glance.firstName.isEmpty ? "Someone you support" : glance.firstName)
                    .font(.headline)
                    .foregroundStyle(ForgePalette.textPrimary)
                Text(glance.isPaused || glance.isStale ? glance.lockScreenLine : glance.headline)
                    .font(.caption)
                    .foregroundStyle(ForgePalette.textSecondary)
                    .lineLimit(family == .systemMedium ? 4 : 3)
            } else {
                WidgetChrome.empty("After they invite you, this is how to show up.")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityLabel(glance?.headline ?? "Support glance is empty")
    }

    private var lockSafe: String {
        glance?.lockScreenLine ?? "Support glance is empty. Open Forge after they invite you."
    }
}
