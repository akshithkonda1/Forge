import SwiftUI
import WidgetKit
import ForgeCore

// Shared chrome so every Home Screen widget reads as Forge, not as five
// different apps that happen to share a bundle.

enum WidgetChrome {
    static func background(accent: Color) -> some View {
        ZStack {
            ForgePalette.background
            LinearGradient(
                colors: [accent.opacity(0.22), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func eyebrow(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(text.uppercased())
                .font(ForgeType.Compact.caption)
                .tracking(ForgeType.eyebrowTracking)
                .foregroundStyle(color)
            Spacer(minLength: 0)
        }
    }

    static func empty(_ message: String) -> some View {
        Text(message)
            .font(ForgeType.Compact.body)
            .foregroundStyle(ForgePalette.textSecondary)
    }
}

struct HomeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: HomeWidgetSnapshot
}

struct HomeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeWidgetEntry {
        HomeWidgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeWidgetEntry) -> Void) {
        let now = Date()
        completion(HomeWidgetEntry(date: now, snapshot: HomeWidgetSnapshotStore.load()?.asOf(now) ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeWidgetEntry>) -> Void) {
        let now = Date()
        let snap = HomeWidgetSnapshotStore.load() ?? HomeWidgetSnapshot()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        var entries = [HomeWidgetEntry(date: now, snapshot: snap.asOf(now))]
        // Roll over at midnight even if the 30-minute refresh is late.
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)),
           midnight < next {
            entries.append(HomeWidgetEntry(date: midnight, snapshot: snap.asOf(midnight)))
        }
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

func widgetDeepLink(for kind: String) -> URL {
    switch kind {
    case "ReadinessWidget": return ForgeWidgetLink.readiness
    case "HydrationWidget": return ForgeWidgetLink.hydration
    case "SleepWidget":     return ForgeWidgetLink.sleep
    case "CyclePhaseWidget": return ForgeWidgetLink.cycle
    case "SupportGlanceWidget": return ForgeWidgetLink.support
    case "LifestyleWidget": return ForgeWidgetLink.lifestyle
    case "StandByNestWidget": return ForgeWidgetLink.standBy
    default:                return ForgeWidgetLink.today
    }
}
