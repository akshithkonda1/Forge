#if os(iOS) && canImport(MetricKit)
import Foundation
import MetricKit

// MARK: - MetricKit (iOS)
//
// Apple delivers MXMetricPayload (launch time, hangs, memory, app exits)
// about once a day, and MXDiagnosticPayload (crash, hang, CPU and disk-write
// exceptions, slow launch) on the next launch after one happens. Both
// arrive on a background queue, are reduced here to the Codable summaries in
// ReliabilityAppleMetrics, and are stored on device by ReliabilityLog.
//
// No third-party SDK, no network. The app calls `ReliabilityMetricKit.start()`
// from its launch path (ReliabilityMonitor in the app target, which also owns
// the UIApplication lifecycle half, since UIApplication.shared is not
// available to the extensions that link ForgeCore).

public enum ReliabilityMetricKit {

    private static let subscriber = ReliabilityMetricKitSubscriber()

    /// Subscribe, then backfill anything Apple delivered earlier. Returns at
    /// once; MetricKit's disk reads happen off the calling thread.
    public static func start() {
        MXMetricManager.shared.add(subscriber)
        // Payloads delivered before this launch (or before this subscriber
        // existed); the ledger ignores ones it already has.
        Task.detached(priority: .utility) {
            let manager = MXMetricManager.shared
            let pastMetrics = manager.pastPayloads.map(ReliabilityMetricKitMapper.summary)
            let pastDiagnostics = manager.pastDiagnosticPayloads.flatMap(ReliabilityMetricKitMapper.diagnostics)
            await ReliabilityLog.shared.ingest(metrics: pastMetrics)
            await ReliabilityLog.shared.ingest(diagnostics: pastDiagnostics)
        }
    }
}

/// MetricKit calls back on its own queue. No state; everything goes to the
/// ReliabilityLog actor as plain summaries.
final class ReliabilityMetricKitSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    func didReceive(_ payloads: [MXMetricPayload]) {
        let summaries = payloads.map(ReliabilityMetricKitMapper.summary)
        Task { await ReliabilityLog.shared.ingest(metrics: summaries) }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let diagnostics = payloads.flatMap(ReliabilityMetricKitMapper.diagnostics)
        Task { await ReliabilityLog.shared.ingest(diagnostics: diagnostics) }
    }
}

enum ReliabilityMetricKitMapper {

    static func summary(_ payload: MXMetricPayload) -> ReliabilityMetricSummary {
        var summary = ReliabilityMetricSummary(periodStart: payload.timeStampBegin, periodEnd: payload.timeStampEnd)
        summary.appVersion = payload.latestApplicationVersion
        summary.appBuild = payload.metaData?.applicationBuildVersion
        summary.osVersion = payload.metaData?.osVersion

        if let launch = payload.applicationLaunchMetrics {
            summary.launchBuckets = buckets(launch.histogrammedTimeToFirstDraw)
            summary.resumeBuckets = buckets(launch.histogrammedApplicationResumeTime)
        }
        if let responsiveness = payload.applicationResponsivenessMetrics {
            summary.hangBuckets = buckets(responsiveness.histogrammedApplicationHangTime)
        }
        if let time = payload.applicationTimeMetrics {
            summary.foregroundSeconds = time.cumulativeForegroundTime.converted(to: .seconds).value
        }
        if let memory = payload.memoryMetrics {
            summary.peakMemoryMB = memory.peakMemoryUsage.converted(to: .megabytes).value
        }
        if let exits = payload.applicationExitMetrics {
            let foreground = exits.foregroundExitData
            var fg = ReliabilityExitCounts()
            fg.normal = foreground.cumulativeNormalAppExitCount
            fg.abnormal = foreground.cumulativeAbnormalExitCount
            fg.badAccess = foreground.cumulativeBadAccessExitCount
            fg.illegalInstruction = foreground.cumulativeIllegalInstructionExitCount
            fg.watchdog = foreground.cumulativeAppWatchdogExitCount
            fg.memoryLimit = foreground.cumulativeMemoryResourceLimitExitCount
            summary.foregroundExits = fg

            let background = exits.backgroundExitData
            var bg = ReliabilityExitCounts()
            bg.normal = background.cumulativeNormalAppExitCount
            bg.abnormal = background.cumulativeAbnormalExitCount
            bg.badAccess = background.cumulativeBadAccessExitCount
            bg.illegalInstruction = background.cumulativeIllegalInstructionExitCount
            bg.watchdog = background.cumulativeAppWatchdogExitCount
            bg.memoryLimit = background.cumulativeMemoryResourceLimitExitCount
            bg.memoryPressure = background.cumulativeMemoryPressureExitCount
            bg.cpuLimit = background.cumulativeCPUResourceLimitExitCount
            bg.suspendedWithLockedFile = background.cumulativeSuspendedWithLockedFileExitCount
            bg.backgroundTaskTimeout = background.cumulativeBackgroundTaskAssertionTimeoutExitCount
            summary.backgroundExits = bg
        }
        return summary
    }

    static func diagnostics(_ payload: MXDiagnosticPayload) -> [ReliabilityDiagnosticSummary] {
        let at = payload.timeStampEnd
        var out: [ReliabilityDiagnosticSummary] = []

        for crash in payload.crashDiagnostics ?? [] {
            var item = base(.crash, at: at, meta: crash.metaData)
            item.exceptionType = crash.exceptionType?.intValue
            item.exceptionCode = crash.exceptionCode?.intValue
            item.signal = crash.signal?.intValue
            item.terminationReason = crash.terminationReason.map { String($0.prefix(200)) }
            item.exceptionName = crash.exceptionReason?.exceptionName
            item.attachCallStack(crash.callStackTree.jsonRepresentation())
            out.append(item)
        }
        for hang in payload.hangDiagnostics ?? [] {
            var item = base(.hang, at: at, meta: hang.metaData)
            item.durationMs = hang.hangDuration.converted(to: .milliseconds).value
            item.attachCallStack(hang.callStackTree.jsonRepresentation())
            out.append(item)
        }
        for cpu in payload.cpuExceptionDiagnostics ?? [] {
            var item = base(.cpuException, at: at, meta: cpu.metaData)
            item.durationMs = cpu.totalCPUTime.converted(to: .milliseconds).value
            item.attachCallStack(cpu.callStackTree.jsonRepresentation())
            out.append(item)
        }
        for disk in payload.diskWriteExceptionDiagnostics ?? [] {
            var item = base(.diskWriteException, at: at, meta: disk.metaData)
            item.attachCallStack(disk.callStackTree.jsonRepresentation())
            out.append(item)
        }
        for launch in payload.appLaunchDiagnostics ?? [] {
            var item = base(.slowLaunch, at: at, meta: launch.metaData)
            item.durationMs = launch.launchDuration.converted(to: .milliseconds).value
            item.attachCallStack(launch.callStackTree.jsonRepresentation())
            out.append(item)
        }
        return out
    }

    private static func base(_ kind: ReliabilityDiagnosticKind, at: Date, meta: MXMetaData) -> ReliabilityDiagnosticSummary {
        var item = ReliabilityDiagnosticSummary(kind: kind, at: at)
        item.appBuild = meta.applicationBuildVersion
        item.osVersion = meta.osVersion
        return item
    }

    private static func buckets(_ histogram: MXHistogram<UnitDuration>) -> [ReliabilityHistogramBucket] {
        histogram.bucketEnumerator.allObjects.compactMap { object in
            guard let bucket = object as? MXHistogramBucket<UnitDuration> else { return nil }
            return ReliabilityHistogramBucket(
                startMs: bucket.bucketStart.converted(to: .milliseconds).value,
                endMs: bucket.bucketEnd.converted(to: .milliseconds).value,
                count: bucket.bucketCount
            )
        }
    }
}

#endif

#if os(iOS) || os(macOS)
import Darwin
import Foundation

// MARK: - Process facts

public enum ReliabilityProcess {

    /// True under an Xcode run. Stopping a run in Xcode kills the process in
    /// the foreground, which would otherwise count as a crash.
    public static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    public static var appVersion: String? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return nil }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}
#endif
