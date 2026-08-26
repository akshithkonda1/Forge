import Foundation

// MARK: - SessionClock
//
// Pause-aware elapsed time for a practice session, extracted from
// MindfulnessSessionManager so the bookkeeping can be tested without a watch,
// a Task, or a haptic engine.
//
// The manager kept this as two mutable fields — `accumulated` and
// `segmentStartedAt` — updated from five places (start, pause, resume, endEarly,
// the runner's completion). Every one of them had to get the arithmetic right,
// and nothing checked that they did. A pause that forgets to fold the running
// segment into the total silently shortens the session the user is credited
// with; one that folds it in twice silently lengthens it.

public struct SessionClock: Equatable, Sendable {

    /// Practice time banked by segments that have already ended.
    public private(set) var accumulated: TimeInterval
    /// When the current running segment began, or nil while paused.
    public private(set) var segmentStartedAt: Date?

    public init(accumulated: TimeInterval = 0, segmentStartedAt: Date? = nil) {
        self.accumulated = accumulated
        self.segmentStartedAt = segmentStartedAt
    }

    public var isRunning: Bool { segmentStartedAt != nil }

    /// Seconds of actual practice at `date`.
    ///
    /// Clamped at zero on the running segment: a backwards clock adjustment
    /// must not subtract from time the user really spent.
    public func elapsed(at date: Date) -> TimeInterval {
        guard let segmentStartedAt else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(segmentStartedAt))
    }

    public func remaining(at date: Date, of planned: TimeInterval) -> TimeInterval {
        max(0, planned - elapsed(at: date))
    }

    public func isComplete(at date: Date, of planned: TimeInterval) -> Bool {
        elapsed(at: date) >= planned
    }

    // MARK: Transitions
    //
    // Each returns a new clock rather than mutating in place, so a caller
    // cannot half-apply one.

    public static func started(at date: Date) -> SessionClock {
        SessionClock(accumulated: 0, segmentStartedAt: date)
    }

    /// Folds the running segment into the total and stops the clock.
    /// Pausing an already-paused clock changes nothing.
    public func paused(at date: Date) -> SessionClock {
        guard isRunning else { return self }
        return SessionClock(accumulated: elapsed(at: date), segmentStartedAt: nil)
    }

    /// Restarts the clock without touching what was already banked.
    /// Resuming a running clock changes nothing — in particular it does not
    /// discard the segment in flight.
    public func resumed(at date: Date) -> SessionClock {
        guard !isRunning else { return self }
        return SessionClock(accumulated: accumulated, segmentStartedAt: date)
    }

    /// Stops the clock, banking whatever was running.
    public func stopped(at date: Date) -> SessionClock {
        SessionClock(accumulated: elapsed(at: date), segmentStartedAt: nil)
    }

    /// Stops at exactly the planned duration — the natural-completion case,
    /// where the runner has already decided the session is over and the credited
    /// time should be the plan rather than however late the last tick landed.
    public func completed(of planned: TimeInterval) -> SessionClock {
        SessionClock(accumulated: planned, segmentStartedAt: nil)
    }
}
