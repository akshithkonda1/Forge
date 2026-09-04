import Foundation

// MARK: - WorkoutCoaching
//
// The zone-boundary coaching decision as a pure function, extracted from
// WorkoutSessionManager.maybeCoach so the throttle and the copy selection can
// be tested without an HKWorkoutSession.
//
// Two properties matter and neither was checked anywhere: a cue fires only on a
// genuine zone change and no more than once per throttle window (a cue on every
// sample would buzz the wrist continuously through a boundary), and the wording
// never instructs. The user owns the effort; this reports where they are
// against the session's target.

public enum WorkoutCoaching {

    /// A cue at every zone flicker would mean near-continuous haptics for
    /// anyone training on a boundary.
    public static let throttle: TimeInterval = 45

    public struct Decision: Equatable, Sendable {
        public var cue: String
        /// When this cue fired, to be carried forward as the next `lastCueAt`.
        public var firedAt: Date

        public init(cue: String, firedAt: Date) {
            self.cue = cue
            self.firedAt = firedAt
        }
    }

    /// The cue to show, or nil to stay quiet.
    ///
    /// - Parameters:
    ///   - zone: the zone the heart rate just entered.
    ///   - previousZone: the zone before it, nil at the first reading.
    ///   - target: the zone this workout type is aimed at.
    ///   - lastCueAt: when a cue last fired; `.distantPast` if none has.
    ///   - now: the current instant.
    ///   - allowsBuildingUp: false for workouts where "you could go harder" is
    ///     the wrong thing to say at all — mobility and yoga are not efforts to
    ///     escalate.
    public static func cue(
        zone: ForgeHRZone,
        previousZone: Int?,
        target: Int,
        lastCueAt: Date,
        now: Date = Date(),
        allowsBuildingUp: Bool = true,
        throttle: TimeInterval = WorkoutCoaching.throttle
    ) -> Decision? {
        guard zone.zone != previousZone else { return nil }
        guard now.timeIntervalSince(lastCueAt) > throttle else { return nil }

        let line: String
        if zone.zone > target + 1 {
            line = "Running above the day's plan — easing off a touch keeps this sustainable. Your call."
        } else if zone.zone < target - 1, allowsBuildingUp {
            line = "Plenty in reserve if you want to build toward Zone \(target). No rush."
        } else {
            line = zone.coachingLine
        }
        return Decision(cue: line, firedAt: now)
    }
}
