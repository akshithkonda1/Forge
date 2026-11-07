import Foundation

// MARK: - Apple's own numbers (MetricKit), reduced to Codable summaries
//
// `ReliabilityMetricKit` (iOS only) turns MXMetricPayload and
// MXDiagnosticPayload into these. They hold durations, counts and system
// codes. Call stacks are addresses and binary names (what Xcode's Organizer
// symbolicates), never memory contents.

/// One histogram bucket, in milliseconds.
public struct ReliabilityHistogramBucket: Codable, Equatable, Sendable {
    public var startMs: Double
    public var endMs: Double
    public var count: Int

    public init(startMs: Double, endMs: Double, count: Int) {
        self.startMs = startMs
        self.endMs = endMs
        self.count = count
    }

    public var midpointMs: Double { (startMs + endMs) / 2 }
}

public enum ReliabilityHistogram {

    /// Approximate percentile from buckets: the midpoint of the bucket that
    /// holds the nearest-rank sample. MetricKit only gives buckets, so this
    /// is as precise as Apple's data allows.
    public static func percentile(_ buckets: [ReliabilityHistogramBucket], _ p: Double) -> Double? {
        let ordered = buckets.filter { $0.count > 0 }.sorted { $0.startMs < $1.startMs }
        let total = ordered.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        let clamped = min(max(p, 0), 1)
        let rank = max(1, Int((clamped * Double(total)).rounded(.up)))
        var seen = 0
        for bucket in ordered {
            seen += bucket.count
            if seen >= rank { return bucket.midpointMs }
        }
        return ordered.last?.midpointMs
    }

    /// Sum of bucket midpoints × counts, in milliseconds.
    public static func approximateTotalMs(_ buckets: [ReliabilityHistogramBucket]) -> Double {
        buckets.reduce(0) { $0 + $1.midpointMs * Double($1.count) }
    }

    public static func count(_ buckets: [ReliabilityHistogramBucket]) -> Int {
        buckets.reduce(0) { $0 + $1.count }
    }

    /// Hang rate the way Xcode's Organizer reports it: seconds of hang per
    /// hour of foreground time. Nil without foreground time.
    public static func hangSecondsPerHour(hangs: [ReliabilityHistogramBucket], foregroundSeconds: Double?) -> Double? {
        guard let foregroundSeconds, foregroundSeconds > 0 else { return nil }
        let hangSeconds = approximateTotalMs(hangs) / 1_000
        return hangSeconds / (foregroundSeconds / 3_600)
    }
}

/// App exits MetricKit counted over one period.
public struct ReliabilityExitCounts: Codable, Equatable, Sendable {
    public var normal = 0
    public var abnormal = 0
    public var badAccess = 0
    public var illegalInstruction = 0
    public var watchdog = 0
    public var memoryLimit = 0
    public var memoryPressure = 0
    public var cpuLimit = 0
    public var suspendedWithLockedFile = 0
    public var backgroundTaskTimeout = 0

    public init() {}

    /// Exits a person would experience as a crash.
    public var crashLike: Int { abnormal + badAccess + illegalInstruction + watchdog + memoryLimit }

    public var total: Int {
        normal + abnormal + badAccess + illegalInstruction + watchdog + memoryLimit
            + memoryPressure + cpuLimit + suspendedWithLockedFile + backgroundTaskTimeout
    }

    public static func + (lhs: ReliabilityExitCounts, rhs: ReliabilityExitCounts) -> ReliabilityExitCounts {
        var sum = ReliabilityExitCounts()
        sum.normal = lhs.normal + rhs.normal
        sum.abnormal = lhs.abnormal + rhs.abnormal
        sum.badAccess = lhs.badAccess + rhs.badAccess
        sum.illegalInstruction = lhs.illegalInstruction + rhs.illegalInstruction
        sum.watchdog = lhs.watchdog + rhs.watchdog
        sum.memoryLimit = lhs.memoryLimit + rhs.memoryLimit
        sum.memoryPressure = lhs.memoryPressure + rhs.memoryPressure
        sum.cpuLimit = lhs.cpuLimit + rhs.cpuLimit
        sum.suspendedWithLockedFile = lhs.suspendedWithLockedFile + rhs.suspendedWithLockedFile
        sum.backgroundTaskTimeout = lhs.backgroundTaskTimeout + rhs.backgroundTaskTimeout
        return sum
    }
}

/// One MXMetricPayload (usually a day), summarized.
public struct ReliabilityMetricSummary: Codable, Equatable, Sendable {
    public var periodStart: Date
    public var periodEnd: Date
    public var appVersion: String?
    public var appBuild: String?
    public var osVersion: String?
    public var launchBuckets: [ReliabilityHistogramBucket] = []
    public var resumeBuckets: [ReliabilityHistogramBucket] = []
    public var hangBuckets: [ReliabilityHistogramBucket] = []
    public var foregroundSeconds: Double?
    public var peakMemoryMB: Double?
    public var foregroundExits: ReliabilityExitCounts?
    public var backgroundExits: ReliabilityExitCounts?

    public init(periodStart: Date, periodEnd: Date) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
    }

    var identity: String {
        "\(periodStart.timeIntervalSince1970)-\(periodEnd.timeIntervalSince1970)-\(appBuild ?? "")"
    }

    public var launchP50Ms: Double? { ReliabilityHistogram.percentile(launchBuckets, 0.5) }
    public var launchP95Ms: Double? { ReliabilityHistogram.percentile(launchBuckets, 0.95) }
    public var resumeP50Ms: Double? { ReliabilityHistogram.percentile(resumeBuckets, 0.5) }
    public var hangSecondsPerHour: Double? {
        ReliabilityHistogram.hangSecondsPerHour(hangs: hangBuckets, foregroundSeconds: foregroundSeconds)
    }
}

public enum ReliabilityDiagnosticKind: String, Codable, CaseIterable, Sendable {
    case crash
    case hang
    case cpuException = "cpu_exception"
    case diskWriteException = "disk_write_exception"
    case slowLaunch = "slow_launch"

    public var label: String {
        switch self {
        case .crash: return "Crash"
        case .hang: return "Hang"
        case .cpuException: return "CPU exception"
        case .diskWriteException: return "Disk-write exception"
        case .slowLaunch: return "Slow launch"
        }
    }
}

/// One MetricKit diagnostic (crash, hang, CPU, disk write, slow launch).
public struct ReliabilityDiagnosticSummary: Codable, Equatable, Sendable {
    /// Largest call-stack JSON kept per diagnostic. Bigger trees are dropped
    /// (marked `callStackTruncated`) so the ledger stays small.
    public static let maxCallStackBytes = 48 * 1_024

    public var kind: ReliabilityDiagnosticKind
    /// When the payload's period ended (MetricKit does not date a single
    /// diagnostic more precisely than its payload).
    public var at: Date
    public var appBuild: String?
    public var osVersion: String?
    public var exceptionType: Int?
    public var exceptionCode: Int?
    public var signal: Int?
    /// System termination text ("Namespace SIGNAL, Code 11"). Written by the
    /// OS, never by Forge or the user.
    public var terminationReason: String?
    /// ObjC exception class name only (NSRangeException), never its message.
    public var exceptionName: String?
    public var durationMs: Double?
    public var callStackJSON: String?
    public var callStackTruncated = false

    public init(kind: ReliabilityDiagnosticKind, at: Date) {
        self.kind = kind
        self.at = at
    }

    var identity: String {
        "\(kind.rawValue)-\(at.timeIntervalSince1970)-\(signal ?? -1)-\(exceptionType ?? -1)-\(durationMs ?? -1)-\(callStackJSON?.count ?? 0)"
    }

    /// Keep a call stack only if it fits.
    public mutating func attachCallStack(_ data: Data) {
        guard data.count <= Self.maxCallStackBytes else {
            callStackJSON = nil
            callStackTruncated = true
            return
        }
        callStackJSON = String(data: data, encoding: .utf8)
    }
}
