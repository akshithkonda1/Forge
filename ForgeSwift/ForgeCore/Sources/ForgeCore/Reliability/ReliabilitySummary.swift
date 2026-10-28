import Foundation

// MARK: - What the Reliability screen and the exported report show

public struct ReliabilityRouteStats: Codable, Equatable, Sendable, Identifiable {
    public var route: AriaReliabilityRoute
    public var counts: AriaOutcomeCounts
    public var successRate: Double?
    public var p50Ms: Int?
    public var p95Ms: Int?

    public var id: String { route.rawValue }
}

public struct AriaReliabilityStats: Codable, Equatable, Sendable {
    /// Turns that count (cancelled excluded).
    public var total: Int
    public var successes: Int
    public var fallbacks: Int
    public var failures: Int
    public var cancelled: Int
    /// successes / total. A cloud turn rescued by the on-device fallback is
    /// not a success here: the person got a reply, the infrastructure failed.
    public var successRate: Double?
    /// Replies the person actually received, fallbacks included.
    public var replyDeliveredRate: Double?
    public var p50Ms: Int?
    public var p95Ms: Int?
    /// How many recent turns the percentiles are computed over.
    public var latencySample: Int
    public var byRoute: [ReliabilityRouteStats]
    public var gate: PhaseGateStatus
}

public struct SessionReliabilityStats: Codable, Equatable, Sendable {
    public var total: Int
    public var abnormal: Int
    public var crashFreeRate: Double?
    public var excludedDebugger: Int
    public var gate: PhaseGateStatus
}

/// The latest view of Apple's MetricKit numbers, summed over every stored
/// payload in the window for exits, latest payload for launch and hangs.
public struct AppleReliabilityStats: Codable, Equatable, Sendable {
    public var payloads: Int
    public var latestPeriodEnd: Date?
    public var launchP50Ms: Double?
    public var resumeP50Ms: Double?
    public var hangSecondsPerHour: Double?
    public var peakMemoryMB: Double?
    public var foregroundExits: ReliabilityExitCounts
    /// 1 − crash-like foreground exits / all foreground exits. Apple's
    /// independent cross-check on the session rate above.
    public var foregroundCrashFreeRate: Double?
    public var diagnosticsByKind: [String: Int]
}

public struct ReliabilityRecentError: Codable, Equatable, Sendable, Identifiable {
    public var at: Date
    public var area: ReliabilityArea
    public var operation: ReliabilityOperation
    public var route: AriaReliabilityRoute?
    public var outcome: AriaReliabilityOutcome?
    public var error: ReliabilityError?

    public var id: String {
        "\(at.timeIntervalSince1970)-\(operation.rawValue)-\(route?.rawValue ?? "")-\(error?.kind.rawValue ?? "")"
    }
}

public struct ReliabilitySummary: Codable, Equatable, Sendable {
    public var windowStartedAt: Date
    public var generatedAt: Date
    public var gateTarget: Double
    public var gateMinimumSample: Int
    public var aria: AriaReliabilityStats
    public var sessions: SessionReliabilityStats
    public var failuresByArea: [String: Int]
    public var recentErrors: [ReliabilityRecentError]
    public var apple: AppleReliabilityStats
}

extension ReliabilityLedger {

    public static let recentErrorLimit = 25

    public func summary(now: Date = Date()) -> ReliabilitySummary {
        let totals = ariaCounts.values.reduce(AriaOutcomeCounts(), +)
        let timed = ariaTurns.filter { $0.outcome != .cancelled }
        let latencies = timed.map(\.latencyMs)

        let byRoute: [ReliabilityRouteStats] = AriaReliabilityRoute.allCases.compactMap { route in
            guard let counts = ariaCounts[route.rawValue], counts.counted + counts.cancelled > 0 else { return nil }
            let routeLatencies = timed.filter { $0.route == route }.map(\.latencyMs)
            return ReliabilityRouteStats(
                route: route,
                counts: counts,
                successRate: ReliabilityMath.rate(counts.success, of: counts.counted),
                p50Ms: ReliabilityMath.percentile(routeLatencies, 0.5),
                p95Ms: ReliabilityMath.percentile(routeLatencies, 0.95)
            )
        }

        let ariaRate = ReliabilityMath.rate(totals.success, of: totals.counted)
        let aria = AriaReliabilityStats(
            total: totals.counted,
            successes: totals.success,
            fallbacks: totals.fallback,
            failures: totals.failure,
            cancelled: totals.cancelled,
            successRate: ariaRate,
            replyDeliveredRate: ReliabilityMath.rate(totals.success + totals.fallback, of: totals.counted),
            p50Ms: ReliabilityMath.percentile(latencies, 0.5),
            p95Ms: ReliabilityMath.percentile(latencies, 0.95),
            latencySample: latencies.count,
            byRoute: byRoute,
            gate: ReliabilityMath.gate(rate: ariaRate, sample: totals.counted)
        )

        let sessionRate = ReliabilityMath.rate(sessionCounts.total - sessionCounts.abnormal, of: sessionCounts.total)
        let sessionStats = SessionReliabilityStats(
            total: sessionCounts.total,
            abnormal: sessionCounts.abnormal,
            crashFreeRate: sessionRate,
            excludedDebugger: sessionCounts.excludedDebugger,
            gate: ReliabilityMath.gate(rate: sessionRate, sample: sessionCounts.total)
        )

        return ReliabilitySummary(
            windowStartedAt: windowStartedAt,
            generatedAt: now,
            gateTarget: ReliabilityMath.phaseGateTarget,
            gateMinimumSample: ReliabilityMath.phaseGateMinimumSample,
            aria: aria,
            sessions: sessionStats,
            failuresByArea: failureCounts,
            recentErrors: recentErrors(limit: Self.recentErrorLimit),
            apple: appleStats()
        )
    }

    func recentErrors(limit: Int) -> [ReliabilityRecentError] {
        let fromAria = ariaTurns
            .filter { $0.outcome == .failure || $0.outcome == .fallback }
            .map {
                ReliabilityRecentError(
                    at: $0.at, area: .aria, operation: .ariaTurn,
                    route: $0.route, outcome: $0.outcome, error: $0.error
                )
            }
        let fromFailures = failures.map {
            ReliabilityRecentError(
                at: $0.at, area: $0.area, operation: $0.operation,
                route: nil, outcome: nil, error: $0.error
            )
        }
        return Array((fromAria + fromFailures).sorted { $0.at > $1.at }.prefix(limit))
    }

    func appleStats() -> AppleReliabilityStats {
        let inWindow = metrics.filter { $0.periodEnd >= windowStartedAt }
        let exits = inWindow.compactMap(\.foregroundExits).reduce(ReliabilityExitCounts(), +)
        let latest = metrics.last
        let latestWithLaunch = metrics.last { !$0.launchBuckets.isEmpty }
        let latestWithHangs = metrics.last { $0.foregroundSeconds != nil }
        var byKind: [String: Int] = [:]
        for diagnostic in diagnostics where diagnostic.at >= windowStartedAt {
            byKind[diagnostic.kind.rawValue, default: 0] += 1
        }
        return AppleReliabilityStats(
            payloads: inWindow.count,
            latestPeriodEnd: latest?.periodEnd,
            launchP50Ms: latestWithLaunch?.launchP50Ms,
            resumeP50Ms: metrics.last { !$0.resumeBuckets.isEmpty }?.resumeP50Ms,
            hangSecondsPerHour: latestWithHangs?.hangSecondsPerHour,
            peakMemoryMB: latest?.peakMemoryMB,
            foregroundExits: exits,
            foregroundCrashFreeRate: ReliabilityMath.rate(exits.total - exits.crashLike, of: exits.total),
            diagnosticsByKind: byKind
        )
    }
}

// MARK: - Exported report

/// What "Export report" shares: the summary plus the raw (already
/// content-free) records, so Akshith can recompute anything.
public struct ReliabilityReport: Codable, Sendable {
    public struct Build: Codable, Sendable {
        public var appVersion: String
        public var appBuild: String
        public var osVersion: String
        public var deviceModel: String
        public var configuration: String

        public init(appVersion: String, appBuild: String, osVersion: String, deviceModel: String, configuration: String) {
            self.appVersion = appVersion
            self.appBuild = appBuild
            self.osVersion = osVersion
            self.deviceModel = deviceModel
            self.configuration = configuration
        }
    }

    public static let format = "forge-reliability-report"
    public static let formatVersion = 1

    public var format = ReliabilityReport.format
    public var formatVersion = ReliabilityReport.formatVersion
    public var build: Build
    public var summary: ReliabilitySummary
    public var ariaTurns: [AriaTurnRecord]
    public var failures: [ReliabilityFailureRecord]
    public var sessions: [ReliabilitySessionRecord]
    public var metrics: [ReliabilityMetricSummary]
    public var diagnostics: [ReliabilityDiagnosticSummary]

    public init(ledger: ReliabilityLedger, build: Build, now: Date = Date()) {
        self.build = build
        self.summary = ledger.summary(now: now)
        self.ariaTurns = ledger.ariaTurns
        self.failures = ledger.failures
        self.sessions = ledger.sessions
        self.metrics = ledger.metrics
        self.diagnostics = ledger.diagnostics
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
