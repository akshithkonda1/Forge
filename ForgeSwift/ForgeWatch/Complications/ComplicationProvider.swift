import WidgetKit
import SwiftUI
import ForgeCore

// MARK: - Shared complication plumbing
//
// All three complications render from the same WatchSnapshot the app
// maintains in the App Group. Providers do NO HealthKit work — reading a
// cached struct keeps timeline generation ~instant and battery-free, and
// the app's WatchSnapshotStore.save() → reloadAllTimelines() path is what
// delivers the "< 2s from data change to wrist" behavior.

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?
    /// Drives Smart Stack ordering. See `SmartStackRelevance`.
    var relevance: TimelineEntryRelevance?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .gallerySample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot: WatchSnapshot? = context.isPreview ? WatchSnapshot.gallerySample : WatchSnapshotStore.load()
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WatchSnapshotStore.load()
        let entry = SnapshotEntry(
            date: Date(),
            snapshot: snapshot,
            relevance: SmartStackRelevance.score(for: snapshot)?.timelineRelevance
        )
        // The app reloads timelines on every meaningful change; this
        // .after policy is just a slow safety refresh, not the mechanism.
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Smart Stack relevance
//
// The decision lives in ForgeCore.SmartStackRelevance, where it is tested
// without WidgetKit. This is the conversion and nothing else.

private extension SmartStackRelevance.Relevance {
    var timelineRelevance: TimelineEntryRelevance {
        if let duration {
            return TimelineEntryRelevance(score: score, duration: duration)
        }
        return TimelineEntryRelevance(score: score)
    }
}

extension WatchSnapshot {
    /// Friendly example data for the complication gallery.
    static var gallerySample: WatchSnapshot {
        var snapshot = WatchSnapshot()
        snapshot.readinessOverall = 82
        snapshot.readinessBand = .ready
        snapshot.readinessConfidence = 0.9
        snapshot.sleepQualityScore = 84
        snapshot.sleepMinutes = 7 * 60 + 32
        snapshot.recommendedPractice = .focusReset
        snapshot.recommendedDuration = 90
        snapshot.recommendationReason = "A short reset keeps your focus sustainable."
        snapshot.mindfulMinutesToday = 6
        snapshot.hydrationMilliliters = 1_400
        snapshot.hydrationTargetMilliliters = 2_300
        return snapshot
    }

    var recommendedDurationShortLabel: String {
        guard let duration = recommendedDuration else { return "" }
        return duration < 120 ? "\(Int(duration))s" : "\(Int(duration / 60))m"
    }
}
