import Foundation

// MARK: - Reliability ledger
//
// The whole on-device record as one value type: recent ARIA turns,
// critical-path failures, foreground sessions, and Apple's MetricKit
// summaries. Pure and synchronous so every rule here is unit-tested
// without a device; `ReliabilityLog` owns persistence and threading.
//
// Two kinds of number live here:
//   • counters since the window started (the last reset). Rates come from
//     these, so a phase that runs past the recent-event caps stays exact.
//   • recent events (capped). Latency percentiles and the error list come
//     from these.

public struct ReliabilityLedger: Codable, Equatable, Sendable {

    /// Bump when the stored shape changes incompatibly; an unreadable or
    /// newer file starts a fresh ledger instead of crashing.
    public static let currentVersion = 1

    public enum Limits {
        public static let ariaTurns = 2_000
        public static let failures = 300
        public static let sessions = 300
        public static let metrics = 60
        public static let diagnostics = 40
    }

    /// Return to the foreground within this long and it is the same session.
    public static let sessionResumeWindow: TimeInterval = 30 * 60

    public var version: Int = ReliabilityLedger.currentVersion
    public var windowStartedAt: Date

    /// ARIA outcomes since the window started, keyed by route raw value.
    public var ariaCounts: [String: AriaOutcomeCounts] = [:]
    /// Closed foreground sessions since the window started.
    public var sessionCounts = SessionCounts()
    /// Non-ARIA failures since the window started, keyed by area raw value.
    public var failureCounts: [String: Int] = [:]

    public var ariaTurns: [AriaTurnRecord] = []
    public var failures: [ReliabilityFailureRecord] = []
    public var sessions: [ReliabilitySessionRecord] = []
    public var metrics: [ReliabilityMetricSummary] = []
    public var diagnostics: [ReliabilityDiagnosticSummary] = []

    public init(windowStartedAt: Date = Date()) {
        self.windowStartedAt = windowStartedAt
    }

    // MARK: ARIA

    public mutating func record(_ turn: AriaTurnRecord) {
        ariaCounts[turn.route.rawValue, default: AriaOutcomeCounts()].add(turn.outcome)
        ariaTurns.append(turn)
        if ariaTurns.count > Limits.ariaTurns {
            ariaTurns.removeFirst(ariaTurns.count - Limits.ariaTurns)
        }
        touchOpenSession(at: turn.at)
    }

    // MARK: Failures

    public mutating func record(_ failure: ReliabilityFailureRecord) {
        guard failure.error.kind != .cancelled else { return }
        failureCounts[failure.area.rawValue, default: 0] += 1
        failures.append(failure)
        if failures.count > Limits.failures {
            failures.removeFirst(failures.count - Limits.failures)
        }
    }

    // MARK: Sessions
    //
    // A session is time on screen. It opens when Forge becomes active, goes
    // quiet when it enters the background, and resumes if it comes back
    // within `sessionResumeWindow`. On the next launch, a session that was
    // still on screen when its process ended is `abnormal` (crash, watchdog,
    // foreground memory kill); one that was in the background is `clean`,
    // because iOS reclaiming a suspended app is not a failure anyone sees.

    /// Close every session left open by an earlier process.
    public mutating func processLaunch(launchID: UUID, now: Date) {
        for index in sessions.indices where sessions[index].isOpen && sessions[index].launchID != launchID {
            if let backgrounded = sessions[index].backgroundedAt {
                close(at: index, end: .clean, time: backgrounded)
            } else {
                close(at: index, end: .abnormal, time: sessions[index].lastActiveAt)
            }
        }
        trimSessions()
    }

    public mutating func didBecomeActive(
        launchID: UUID,
        now: Date,
        debugger: Bool = false,
        appVersion: String? = nil
    ) {
        processLaunch(launchID: launchID, now: now)
        if let index = openSessionIndex(launchID: launchID) {
            if let backgrounded = sessions[index].backgroundedAt {
                if now.timeIntervalSince(backgrounded) > Self.sessionResumeWindow {
                    close(at: index, end: .clean, time: backgrounded)
                } else {
                    sessions[index].backgroundedAt = nil
                    sessions[index].lastActiveAt = now
                    return
                }
            } else {
                sessions[index].lastActiveAt = now
                return
            }
        }
        sessions.append(ReliabilitySessionRecord(
            launchID: launchID,
            startedAt: now,
            debugger: debugger,
            appVersion: appVersion
        ))
        trimSessions()
    }

    public mutating func didEnterBackground(launchID: UUID, now: Date) {
        guard let index = openSessionIndex(launchID: launchID) else { return }
        if sessions[index].backgroundedAt == nil {
            sessions[index].backgroundedAt = now
            sessions[index].lastActiveAt = now
        }
    }

    public mutating func willTerminate(launchID: UUID, now: Date) {
        guard let index = openSessionIndex(launchID: launchID) else { return }
        close(at: index, end: .clean, time: now)
    }

    private func openSessionIndex(launchID: UUID) -> Int? {
        sessions.lastIndex { $0.isOpen && $0.launchID == launchID }
    }

    private mutating func touchOpenSession(at date: Date) {
        if let index = sessions.lastIndex(where: { $0.isInForeground }),
           date > sessions[index].lastActiveAt {
            sessions[index].lastActiveAt = date
        }
    }

    private mutating func close(at index: Int, end: ReliabilitySessionEnd, time: Date) {
        guard sessions[index].isOpen else { return }
        sessions[index].end = end
        sessions[index].endedAt = max(time, sessions[index].startedAt)
        // A session that began before the window (reset mid-session) still
        // ends inside it; count it, since its end is what the window saw.
        sessionCounts.add(end, debugger: sessions[index].debugger)
    }

    private mutating func trimSessions() {
        guard sessions.count > Limits.sessions else { return }
        // Never drop an open session; drop the oldest closed ones.
        var overflow = sessions.count - Limits.sessions
        sessions.removeAll { session in
            guard overflow > 0, !session.isOpen else { return false }
            overflow -= 1
            return true
        }
    }

    // MARK: MetricKit

    /// Add Apple's daily metric summaries, ignoring ones already stored
    /// (MetricKit can hand the same payload to `pastPayloads` and the
    /// subscriber).
    public mutating func ingest(metrics incoming: [ReliabilityMetricSummary]) {
        for summary in incoming where !metrics.contains(where: { $0.identity == summary.identity }) {
            metrics.append(summary)
        }
        metrics.sort { $0.periodEnd < $1.periodEnd }
        if metrics.count > Limits.metrics {
            metrics.removeFirst(metrics.count - Limits.metrics)
        }
    }

    public mutating func ingest(diagnostics incoming: [ReliabilityDiagnosticSummary]) {
        for diagnostic in incoming where !diagnostics.contains(where: { $0.identity == diagnostic.identity }) {
            diagnostics.append(diagnostic)
        }
        diagnostics.sort { $0.at < $1.at }
        if diagnostics.count > Limits.diagnostics {
            diagnostics.removeFirst(diagnostics.count - Limits.diagnostics)
        }
    }

    // MARK: Reset

    /// Start a new measurement window (a new phase). Apple's MetricKit
    /// history is kept: it is Apple's record, not this window's.
    /// An open session is carried over so the current run is not lost.
    public mutating func resetWindow(now: Date) {
        windowStartedAt = now
        ariaCounts = [:]
        sessionCounts = SessionCounts()
        failureCounts = [:]
        ariaTurns = []
        failures = []
        sessions = sessions.filter(\.isOpen)
    }
}

// MARK: - Counters

public struct AriaOutcomeCounts: Codable, Equatable, Sendable {
    public var success = 0
    public var fallback = 0
    public var failure = 0
    public var cancelled = 0

    public init(success: Int = 0, fallback: Int = 0, failure: Int = 0, cancelled: Int = 0) {
        self.success = success
        self.fallback = fallback
        self.failure = failure
        self.cancelled = cancelled
    }

    /// Turns that count toward the success rate (cancelled excluded).
    public var counted: Int { success + fallback + failure }

    public mutating func add(_ outcome: AriaReliabilityOutcome) {
        switch outcome {
        case .success: success += 1
        case .fallback: fallback += 1
        case .failure: failure += 1
        case .cancelled: cancelled += 1
        }
    }

    public static func + (lhs: AriaOutcomeCounts, rhs: AriaOutcomeCounts) -> AriaOutcomeCounts {
        AriaOutcomeCounts(
            success: lhs.success + rhs.success,
            fallback: lhs.fallback + rhs.fallback,
            failure: lhs.failure + rhs.failure,
            cancelled: lhs.cancelled + rhs.cancelled
        )
    }
}

public struct SessionCounts: Codable, Equatable, Sendable {
    /// Closed sessions that count (no debugger attached).
    public var total = 0
    /// Of those, how many ended on screen.
    public var abnormal = 0
    /// Closed sessions left out because a debugger was attached.
    public var excludedDebugger = 0

    public init(total: Int = 0, abnormal: Int = 0, excludedDebugger: Int = 0) {
        self.total = total
        self.abnormal = abnormal
        self.excludedDebugger = excludedDebugger
    }

    public mutating func add(_ end: ReliabilitySessionEnd, debugger: Bool) {
        if debugger {
            excludedDebugger += 1
            return
        }
        total += 1
        if end == .abnormal { abnormal += 1 }
    }
}

// MARK: - Math

public enum ReliabilityMath {

    /// The gate Akshith set for moving between rollout phases.
    public static let phaseGateTarget = 0.999

    /// Below this many events a 99.9% rate cannot be told apart from 99%:
    /// one failure in fewer than 1,000 already misses the gate, and zero
    /// failures in 100 says almost nothing.
    public static let phaseGateMinimumSample = 1_000

    /// `part / whole`, or nil when there is nothing to divide.
    public static func rate(_ part: Int, of whole: Int) -> Double? {
        guard whole > 0 else { return nil }
        return Double(part) / Double(whole)
    }

    /// Nearest-rank percentile (`p` in 0...1) of `values`. Nil when empty.
    /// p50 of [10, 20, 30, 40] is 20; p95 of 1...100 is 95.
    public static func percentile(_ values: [Int], _ p: Double) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clamped = min(max(p, 0), 1)
        let rank = Int((clamped * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    public static func gate(rate: Double?, sample: Int) -> PhaseGateStatus {
        guard let rate, sample > 0 else { return .noData }
        if rate < phaseGateTarget { return .below }
        if sample < phaseGateMinimumSample { return .tooFewToJudge }
        return .meets
    }
}

/// Where one metric stands against the 99.9% gate.
public enum PhaseGateStatus: String, Codable, Sendable {
    case noData = "no_data"
    /// At or above 99.9% so far, but fewer than 1,000 events.
    case tooFewToJudge = "too_few_to_judge"
    case meets
    case below

    public var label: String {
        switch self {
        case .noData: return "No data yet"
        case .tooFewToJudge: return "On track, too few to judge"
        case .meets: return "Meets 99.9%"
        case .below: return "Below 99.9%"
        }
    }
}
