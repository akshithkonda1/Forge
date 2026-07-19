import Foundation
import ActivityKit
import ForgeCore

// MARK: - ForgeWorkoutActivityAttributes
//
// Shared between the iOS app target (which requests/updates the activity
// from watch state) and the ForgeWidgetExtension target (which renders
// it). The content state IS the shared WorkoutLiveState — the wrist, the
// lock screen, and the Dynamic Island can never disagree.

struct ForgeWorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var live: WorkoutLiveState
    }

    /// Fixed for the activity's lifetime.
    var startedAt: Date
}
