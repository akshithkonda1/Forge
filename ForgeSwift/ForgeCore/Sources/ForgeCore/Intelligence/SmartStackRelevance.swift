import Foundation

// MARK: - SmartStackRelevance
//
// How much Forge is worth showing right now.
//
// The watch complications existed and never surfaced themselves. The Smart
// Stack ranks what it shows by the relevance each timeline entry declares, and
// every entry declared none — so Forge appeared only when the user scrolled to
// it, which is the opposite of what a proactive app is for. Meanwhile
// ContextEngine was already computing the moments that matter and discarding
// every one of them.
//
// Returns plain numbers rather than a TimelineEntryRelevance so the decision is
// testable without WidgetKit; the widgets extension does the one-line
// conversion.

public enum SmartStackRelevance {

    public struct Relevance: Equatable, Sendable {
        /// Higher wins a place further up the stack.
        public var score: Float
        /// How long the score holds. Nil means until the next timeline reload.
        public var duration: TimeInterval?

        public init(score: Float, duration: TimeInterval? = nil) {
            self.score = score
            self.duration = duration
        }
    }

    /// A workout in progress. Nothing outranks the thing happening now.
    public static let liveSession: Float = 100
    /// A moment the context engine actively flagged.
    public static let flagged: Float = 60
    /// Worth showing, no particular urgency.
    public static let ambient: Float = 20

    /// How close to the wind-down time counts as "now".
    public static let windDownWindowMinutes: Double = 90

    /// The scores are relative, not absolute. What matters is the ordering — a
    /// live workout above a wind-down prompt above an ambient glance — so that
    /// nothing can push a running session down the stack.
    public static func score(for snapshot: WatchSnapshot?, now: Date = Date()) -> Relevance? {
        guard let snapshot else { return nil }

        if let workout = snapshot.activeWorkout, workout.phase != .ended {
            // No duration: the app reloads timelines on every phase change, so
            // the score is replaced rather than expiring on a guess about how
            // long somebody trains.
            return Relevance(score: liveSession)
        }

        if let windDown = snapshot.tonightWindDown,
           isWithin(windDown, of: now, minutes: windDownWindowMinutes) {
            return Relevance(score: flagged, duration: windDownWindowMinutes * 60)
        }

        // A recommendation exists whenever the suggestion engine has something
        // to say — which, after a 90-minute desk block, is the reset it wants
        // to offer. Below wind-down because a reset keeps; a bedtime does not.
        if snapshot.recommendedPractice != nil {
            return Relevance(score: flagged * 0.7)
        }

        return Relevance(score: ambient)
    }

    /// Symmetric on purpose: the half hour after the wind-down window opened is
    /// at least as relevant as the half hour before it.
    private static func isWithin(_ date: Date, of now: Date, minutes: Double) -> Bool {
        abs(date.timeIntervalSince(now)) <= minutes * 60
    }
}
