import SwiftUI
import WidgetKit
import ForgeCore

// MARK: - StandBy nest face
//
// Public Apple surface: WidgetKit `WidgetFamily.systemSmall`.
// iPhone StandBy (MagSafe / landscape nightstand) and CarPlay both take the
// small system family and scale it. There is no dedicated StandBy family and
// no MagSafe private API. Low light uses `WidgetRenderingMode.vibrant`.
//
// Actual rendering is `StandByNestFaceView` (ForgeCore) — shared with the
// in-app customization screen's live preview so both are pixel-identical.
// This file only owns what's WidgetKit-specific: the timeline provider and
// the `Widget` configuration.

struct StandByNestProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeWidgetEntry {
        HomeWidgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeWidgetEntry) -> Void) {
        completion(HomeWidgetEntry(date: Date(), snapshot: HomeWidgetSnapshotStore.load() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeWidgetEntry>) -> Void) {
        let snap = HomeWidgetSnapshotStore.load() ?? HomeWidgetSnapshot()
        let now = Date()
        let calendar = Calendar.current
        // Data only changes when the app writes a new snapshot, which already
        // forces an immediate reload via `WidgetCenter.shared.reloadAllTimelines()`.
        // These per-minute entries exist so the clock stays accurate in
        // between — StandBy is a nightstand clock first, a data face second.
        let entries = (0..<20).compactMap { offset -> HomeWidgetEntry? in
            calendar.date(byAdding: .minute, value: offset, to: now)
                .map { HomeWidgetEntry(date: $0, snapshot: snap) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct StandByNestWidgetView: View {
    var entry: HomeWidgetEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        StandByNestFaceView(
            snapshot: entry.snapshot,
            date: entry.date,
            metrics: StandByMetricsStore.load(),
            nightMode: renderingMode == .vibrant
        )
    }
}

struct StandByNestWidget: Widget {
    let kind = AriaNestGeometry.StandBy.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StandByNestProvider()) { entry in
            StandByNestWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(forgeHex: AriaNestGeometry.StandBy.nightstandBackgroundHex)
                }
                .widgetURL(ForgeWidgetLink.standBy)
        }
        .configurationDisplayName("StandBy")
        .description("Readiness, sleep and your hydration goal at a glance — MagSafe landscape StandBy. Customize in Forge Settings.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

#Preview("StandBy nest", as: .systemSmall) {
    StandByNestWidget()
} timeline: {
    HomeWidgetEntry(date: .now, snapshot: .preview)
}
