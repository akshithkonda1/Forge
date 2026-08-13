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
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(color)
            Spacer(minLength: 0)
        }
    }

    static func empty(_ message: String) -> some View {
        Text(message)
            .font(.caption)
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
        completion(HomeWidgetEntry(date: Date(), snapshot: HomeWidgetSnapshotStore.load() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeWidgetEntry>) -> Void) {
        let snap = HomeWidgetSnapshotStore.load() ?? HomeWidgetSnapshot()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [HomeWidgetEntry(date: Date(), snapshot: snap)], policy: .after(next)))
    }
}

func widgetDeepLink(for kind: String) -> URL {
    switch kind {
    case "ReadinessWidget": return ForgeWidgetLink.readiness
    case "HydrationWidget": return ForgeWidgetLink.hydration
    case "SleepWidget":     return ForgeWidgetLink.sleep
    case "CyclePhaseWidget": return ForgeWidgetLink.cycle
    case "LifestyleWidget": return ForgeWidgetLink.lifestyle
    default:                return ForgeWidgetLink.today
    }
}
