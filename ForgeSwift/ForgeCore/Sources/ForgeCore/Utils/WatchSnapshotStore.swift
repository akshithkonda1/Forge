import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - WatchSnapshotStore
//
// The single source of truth complications render from. The watch app
// writes a compact snapshot to the shared App Group whenever meaningful
// data changes and asks WidgetKit to reload — this is what makes the
// "< 2 seconds from data change to complication update" target real:
// providers never run queries, they just read this struct.

public struct WatchSnapshot: Codable, Sendable, Equatable {
    public var readinessOverall: Int?
    public var readinessBand: ReadinessBand?
    public var readinessConfidence: Double?

    public var sleepQualityScore: Int?
    public var sleepMinutes: Double?

    public var recommendedPractice: PracticeType?
    public var recommendedDuration: TimeInterval?
    public var recommendationReason: String?

    public var lifestyleMode: LifestyleMode?
    public var mindfulMinutesToday: Double?
    /// Present only while a workout session is running (drives the
    /// ActiveWorkoutComplication). Optional so old snapshots still decode.
    public var activeWorkout: WorkoutLiveState?
    public var updatedAt: Date

    public init(updatedAt: Date = Date()) {
        self.updatedAt = updatedAt
    }
}

public enum WatchSnapshotStore {
    /// Matches the group already used by ForgeWidget on iOS.
    public static let appGroupID = "group.com.forge.ForgeSwift"
    private static let key = "forge.watch.snapshot.v1"

    public static func load() -> WatchSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: key)
        else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    /// Persists the snapshot and nudges WidgetKit so complications refresh
    /// promptly. `reloadWidgets` exists so unit tests can skip WidgetKit.
    public static func save(_ snapshot: WatchSnapshot, reloadWidgets: Bool = true) {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: key)
        #if canImport(WidgetKit)
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    /// Read-modify-write convenience used by managers that each own a few
    /// fields of the snapshot.
    public static func update(reloadWidgets: Bool = true, _ mutate: (inout WatchSnapshot) -> Void) {
        var snapshot = load() ?? WatchSnapshot()
        mutate(&snapshot)
        snapshot.updatedAt = Date()
        save(snapshot, reloadWidgets: reloadWidgets)
    }
}
