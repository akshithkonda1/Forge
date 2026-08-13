import WidgetKit
import SwiftUI

// MARK: - Shared snapshot
//
// Mirror of `LifestyleWidgetSnapshot` in the app target. The app writes this
// into the shared App Group (see `LifestyleWidgetBridge`); the widget reads it
// back. Keep the field list + the App Group id + the storage key in sync with
// the app side.

struct LifestyleWidgetSnapshot: Codable {
    var qol: Int
    var topTitle: String?
    var topCategory: String?
    var updatedAt: Date

    static let preview = LifestyleWidgetSnapshot(
        qol: 82,
        topTitle: "Add 30g protein before dinner",
        topCategory: "Nutrition",
        updatedAt: Date()
    )
}

// MARK: - Timeline

struct LifestyleEntry: TimelineEntry {
    let date: Date
    let snapshot: LifestyleWidgetSnapshot?
}

struct LifestyleProvider: TimelineProvider {
    /// Must match `LifestyleWidgetBridge.appGroup` / `.snapshotKey` in the app.
    static let appGroup = "group.com.forge.ForgeSwift"
    static let snapshotKey = "lifestyle.widget.snapshot"

    func placeholder(in context: Context) -> LifestyleEntry {
        LifestyleEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (LifestyleEntry) -> Void) {
        completion(LifestyleEntry(date: Date(), snapshot: Self.load() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LifestyleEntry>) -> Void) {
        let entry = LifestyleEntry(date: Date(), snapshot: Self.load())
        // Hourly safety refresh; the app also pokes us via WidgetCenter.reloadTimelines.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    static func load() -> LifestyleWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(LifestyleWidgetSnapshot.self, from: data)
    }
}

// MARK: - View

struct LifestyleWidgetView: View {
    var entry: LifestyleProvider.Entry
    @Environment(\.widgetFamily) private var family

    private var qol: Int { entry.snapshot?.qol ?? 0 }

    private var qolColor: Color {
        switch qol {
        case 80...:   return .green
        case 60..<80: return .yellow
        default:      return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.caption2).foregroundStyle(.orange)
                Text("Lifestyle").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(qol)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(qolColor)
                    .contentTransition(.numericText())
                Text("QOL").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }

            if let title = entry.snapshot?.topTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text((entry.snapshot?.topCategory ?? "ARIA").uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                    Text(title)
                        .font(family == .systemSmall ? .caption2 : .caption)
                        .foregroundStyle(.primary)
                        .lineLimit(family == .systemSmall ? 2 : 3)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget

struct LifestyleWidget: Widget {
    let kind = "LifestyleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LifestyleProvider()) { entry in
            LifestyleWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "forge://lifestyle"))
        }
        .configurationDisplayName("Lifestyle")
        .description("Your quality-of-life score and ARIA's top recommendation.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
