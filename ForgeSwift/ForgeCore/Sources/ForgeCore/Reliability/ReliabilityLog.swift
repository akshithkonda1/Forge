import Foundation
#if canImport(os)
import os
#endif

// MARK: - ReliabilityLog
//
// The one writer of the reliability ledger. An actor so ARIA turns,
// HealthKit callbacks and lifecycle notifications can record from any
// thread; the file is JSON in Application Support, excluded from backup,
// protected until first unlock (MetricKit can deliver while locked).
//
// Nothing leaves the device. "Export report" in the Reliability screen is
// the only way the data moves, and only when a tester shares it.
//
// Call sites use the nonisolated statics (`recordAria`, `noteFailure`):
// they classify the error synchronously (so no `Error` crosses an actor)
// and hand a plain record to the actor.

public actor ReliabilityLog {

    public static let shared = ReliabilityLog()

    /// Identifies this process, so the next launch can tell a session it left
    /// open from one this process owns.
    public static let launchID = UUID()

    #if canImport(os)
    static let logger = Logger(subsystem: ForgeReliabilityLogging.subsystem, category: "reliability")
    #endif

    private let fileURL: URL?
    private let saveDelay: Duration
    private var ledger: ReliabilityLedger?
    private var saveScheduled = false

    /// - Parameters:
    ///   - directory: where `reliability.json` lives. Nil keeps it in memory
    ///     (tests). The default is Application Support/Forge/Reliability.
    ///   - saveDelay: how long writes are coalesced.
    public init(directory: URL? = ReliabilityLog.defaultDirectory(), saveDelay: Duration = .seconds(2)) {
        self.fileURL = directory?.appendingPathComponent("reliability.json")
        self.saveDelay = saveDelay
    }

    public static func defaultDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("Forge", isDirectory: true)
            .appendingPathComponent("Reliability", isDirectory: true)
    }

    // MARK: Reads

    public func snapshot() -> ReliabilityLedger {
        loadedLedger()
    }

    public func summary(now: Date = Date()) -> ReliabilitySummary {
        loadedLedger().summary(now: now)
    }

    public func report(build: ReliabilityReport.Build, now: Date = Date()) -> ReliabilityReport {
        ReliabilityReport(ledger: loadedLedger(), build: build, now: now)
    }

    // MARK: Writes

    public func record(_ turn: AriaTurnRecord) {
        mutate { $0.record(turn) }
        #if canImport(os)
        switch turn.outcome {
        case .success, .cancelled:
            break
        case .fallback, .failure:
            Self.logger.error(
                "aria \(turn.outcome.rawValue, privacy: .public) route=\(turn.route.rawValue, privacy: .public) kind=\(turn.error?.kind.rawValue ?? "none", privacy: .public) code=\(turn.error?.code ?? 0, privacy: .public) ms=\(turn.latencyMs, privacy: .public)"
            )
        }
        #endif
    }

    public func record(_ failure: ReliabilityFailureRecord) {
        mutate { $0.record(failure) }
        #if canImport(os)
        Self.logger.error(
            "failure area=\(failure.area.rawValue, privacy: .public) op=\(failure.operation.rawValue, privacy: .public) kind=\(failure.error.kind.rawValue, privacy: .public) domain=\(failure.error.domain ?? "none", privacy: .public) code=\(failure.error.code ?? 0, privacy: .public)"
        )
        #endif
    }

    public func ingest(metrics: [ReliabilityMetricSummary]) {
        guard !metrics.isEmpty else { return }
        mutate { $0.ingest(metrics: metrics) }
    }

    public func ingest(diagnostics: [ReliabilityDiagnosticSummary]) {
        guard !diagnostics.isEmpty else { return }
        mutate { $0.ingest(diagnostics: diagnostics) }
        #if canImport(os)
        for diagnostic in diagnostics {
            Self.logger.error("metrickit \(diagnostic.kind.rawValue, privacy: .public) signal=\(diagnostic.signal ?? 0, privacy: .public)")
        }
        #endif
    }

    // MARK: Sessions

    public func processLaunch(now: Date = Date()) {
        mutate { $0.processLaunch(launchID: Self.launchID, now: now) }
    }

    public func didBecomeActive(now: Date = Date(), debugger: Bool, appVersion: String?) {
        mutate { $0.didBecomeActive(launchID: Self.launchID, now: now, debugger: debugger, appVersion: appVersion) }
    }

    /// Writes immediately: the process may be suspended (and later killed)
    /// any time after this, and a session still marked "on screen" would be
    /// counted as a crash on the next launch.
    public func didEnterBackground(now: Date = Date()) {
        mutate(saveNow: true) { $0.didEnterBackground(launchID: Self.launchID, now: now) }
    }

    public func willTerminate(now: Date = Date()) {
        mutate(saveNow: true) { $0.willTerminate(launchID: Self.launchID, now: now) }
    }

    /// Start a new measurement window (a new rollout phase).
    public func resetWindow(now: Date = Date()) {
        mutate(saveNow: true) { $0.resetWindow(now: now) }
    }

    /// Write any pending change now.
    public func flush() {
        saveScheduled = false
        guard let ledger, let fileURL else { return }
        Self.write(ledger, to: fileURL)
    }

    // MARK: Internals

    private func loadedLedger() -> ReliabilityLedger {
        if let ledger { return ledger }
        let loaded = fileURL.flatMap(Self.read) ?? ReliabilityLedger()
        ledger = loaded
        return loaded
    }

    private func mutate(saveNow: Bool = false, _ change: (inout ReliabilityLedger) -> Void) {
        var current = loadedLedger()
        change(&current)
        ledger = current
        if saveNow {
            flush()
        } else {
            scheduleSave()
        }
    }

    private func scheduleSave() {
        guard fileURL != nil, !saveScheduled else { return }
        saveScheduled = true
        let delay = saveDelay
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            await self?.flushIfScheduled()
        }
    }

    private func flushIfScheduled() {
        guard saveScheduled else { return }
        flush()
    }

    static func read(_ url: URL) -> ReliabilityLedger? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(ReliabilityLedger.self, from: data),
              decoded.version <= ReliabilityLedger.currentVersion else {
            return nil
        }
        return decoded
    }

    static func write(_ ledger: ReliabilityLedger, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(ledger) else { return }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try? mutableDirectory.setResourceValues(values)
            #if canImport(Darwin)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: [.atomic])
            #endif
        } catch {
            // Do not record this failure into the ledger it failed to save.
            #if canImport(os)
            logger.error("reliability ledger write failed code=\((error as NSError).code, privacy: .public)")
            #endif
        }
    }
}

// MARK: - Call-site API

extension ReliabilityLog {

    /// Record one ARIA turn. Safe from any thread; returns immediately.
    public nonisolated static func recordAria(
        route: AriaReliabilityRoute,
        surface: AriaReliabilitySurface,
        outcome: AriaReliabilityOutcome,
        latencyMs: Int,
        error: ReliabilityError? = nil
    ) {
        let turn = AriaTurnRecord(route: route, surface: surface, outcome: outcome, latencyMs: latencyMs, error: error)
        Task { await shared.record(turn) }
    }

    /// Record a critical-path failure. The error is reduced to a kind, a code
    /// and a system domain here, before anything is stored.
    public nonisolated static func noteFailure(
        _ area: ReliabilityArea,
        _ operation: ReliabilityOperation,
        error: Error? = nil,
        kind: ReliabilityErrorKind? = nil
    ) {
        var classified = error.map { ReliabilityError.classify($0) } ?? ReliabilityError(kind: kind ?? .unknown)
        if let kind, error == nil || classified.kind == .unknown {
            classified.kind = kind
        }
        guard classified.kind != .cancelled else { return }
        let failure = ReliabilityFailureRecord(area: area, operation: operation, error: classified)
        Task { await shared.record(failure) }
    }

    /// Milliseconds since `start`, for ARIA latency.
    public nonisolated static func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        let (seconds, attoseconds) = elapsed.components
        return Int(seconds) * 1_000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}

public enum ForgeReliabilityLogging {
    /// Same subsystem as ForgePerf, so Console and Instruments show
    /// reliability events beside the existing signposts.
    public static let subsystem = "com.forge.core"
}
