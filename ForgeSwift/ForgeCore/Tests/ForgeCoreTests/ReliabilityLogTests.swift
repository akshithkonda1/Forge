import XCTest
@testable import ForgeCore

/// The math behind the phase gate. If these move, the number Akshith reads
/// on the Reliability screen moves with them, so each rule is pinned here:
/// what counts as a success, what a percentile means, and when a session is
/// a crash.
final class ReliabilityLogTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func turn(
        _ outcome: AriaReliabilityOutcome,
        route: AriaReliabilityRoute = .onDeviceModel,
        ms: Int = 100,
        at offset: TimeInterval = 0
    ) -> AriaTurnRecord {
        AriaTurnRecord(
            at: t0.addingTimeInterval(offset),
            route: route,
            outcome: outcome,
            latencyMs: ms,
            error: outcome == .success ? nil : ReliabilityError(kind: .serverError, code: 500)
        )
    }

    // MARK: Percentiles

    func testPercentileIsNearestRank() {
        XCTAssertNil(ReliabilityMath.percentile([], 0.5))
        XCTAssertEqual(ReliabilityMath.percentile([42], 0.5), 42)
        XCTAssertEqual(ReliabilityMath.percentile([42], 0.95), 42)
        XCTAssertEqual(ReliabilityMath.percentile([40, 10, 30, 20], 0.5), 20)
        XCTAssertEqual(ReliabilityMath.percentile(Array(1...100), 0.5), 50)
        XCTAssertEqual(ReliabilityMath.percentile(Array(1...100), 0.95), 95)
        XCTAssertEqual(ReliabilityMath.percentile(Array(1...100).reversed(), 0.95), 95)
        XCTAssertEqual(ReliabilityMath.percentile(Array(1...20), 0.95), 19)
        XCTAssertEqual(ReliabilityMath.percentile([5, 1, 9], 0), 1)
        XCTAssertEqual(ReliabilityMath.percentile([5, 1, 9], 1), 9)
    }

    func testRate() {
        XCTAssertNil(ReliabilityMath.rate(0, of: 0))
        XCTAssertEqual(ReliabilityMath.rate(999, of: 1_000), 0.999)
        XCTAssertEqual(ReliabilityMath.rate(3, of: 4), 0.75)
    }

    // MARK: ARIA success rate

    func testFallbackAndFailureAreNotSuccessesAndCancelledIsExcluded() throws {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        for _ in 0..<7 { ledger.record(turn(.success)) }
        ledger.record(turn(.fallback, route: .cloud))
        ledger.record(turn(.failure, route: .cloud))
        ledger.record(turn(.failure))
        ledger.record(turn(.cancelled))

        let aria = ledger.summary(now: t0).aria
        XCTAssertEqual(aria.total, 10, "cancelled turns are not counted")
        XCTAssertEqual(aria.successes, 7)
        XCTAssertEqual(aria.fallbacks, 1)
        XCTAssertEqual(aria.failures, 2)
        XCTAssertEqual(aria.cancelled, 1)
        XCTAssertEqual(try XCTUnwrap(aria.successRate), 0.7, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(aria.replyDeliveredRate), 0.8, accuracy: 1e-9)
    }

    func testRatesComeFromCountersSoTheyStayExactPastTheEventCap() throws {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        let extra = 500
        for i in 0..<(ReliabilityLedger.Limits.ariaTurns + extra) {
            ledger.record(turn(i == 0 ? .failure : .success, at: TimeInterval(i)))
        }
        XCTAssertEqual(ledger.ariaTurns.count, ReliabilityLedger.Limits.ariaTurns)
        let aria = ledger.summary(now: t0).aria
        XCTAssertEqual(aria.total, ReliabilityLedger.Limits.ariaTurns + extra)
        XCTAssertEqual(aria.failures, 1, "the dropped event's failure still counts")
        XCTAssertEqual(aria.latencySample, ReliabilityLedger.Limits.ariaTurns)
    }

    func testLatencyPercentilesSkipCancelledTurnsAndSplitByRoute() {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        for ms in [100, 200, 300, 400] { ledger.record(turn(.success, route: .onDeviceModel, ms: ms)) }
        for ms in [1_000, 2_000] { ledger.record(turn(.success, route: .cloud, ms: ms)) }
        ledger.record(turn(.cancelled, ms: 99_999))

        let aria = ledger.summary(now: t0).aria
        XCTAssertEqual(aria.latencySample, 6)
        XCTAssertEqual(aria.p50Ms, 300)
        XCTAssertEqual(aria.p95Ms, 2_000)

        let model = aria.byRoute.first { $0.route == .onDeviceModel }
        XCTAssertEqual(model?.p50Ms, 200)
        XCTAssertEqual(model?.p95Ms, 400)
        XCTAssertEqual(model?.counts.cancelled, 1)
        let cloud = aria.byRoute.first { $0.route == .cloud }
        XCTAssertEqual(cloud?.p50Ms, 1_000)
        XCTAssertEqual(cloud?.successRate, 1)
    }

    // MARK: Gate

    func testGateNeedsTheTargetAndEnoughData() {
        XCTAssertEqual(ReliabilityMath.gate(rate: nil, sample: 0), .noData)
        XCTAssertEqual(ReliabilityMath.gate(rate: 1, sample: 300), .tooFewToJudge)
        XCTAssertEqual(ReliabilityMath.gate(rate: 0.998, sample: 500), .below)
        XCTAssertEqual(ReliabilityMath.gate(rate: 0.999, sample: 1_000), .meets)
        XCTAssertEqual(ReliabilityMath.gate(rate: 0.9989, sample: 10_000), .below)
    }

    // MARK: Sessions

    func testSessionLeftOnScreenIsAbnormalOnNextLaunch() throws {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        let first = UUID()
        ledger.didBecomeActive(launchID: first, now: t0)
        // Process dies while on screen. Next launch:
        let second = UUID()
        ledger.processLaunch(launchID: second, now: t0.addingTimeInterval(60))

        let sessions = ledger.summary(now: t0).sessions
        XCTAssertEqual(sessions.total, 1)
        XCTAssertEqual(sessions.abnormal, 1)
        XCTAssertEqual(try XCTUnwrap(sessions.crashFreeRate), 0, accuracy: 1e-9)
        XCTAssertEqual(ledger.sessions.first?.end, .abnormal)
    }

    func testKilledWhileInBackgroundIsClean() {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        let first = UUID()
        ledger.didBecomeActive(launchID: first, now: t0)
        ledger.didEnterBackground(launchID: first, now: t0.addingTimeInterval(30))
        // iOS reclaims the suspended process; next launch:
        ledger.processLaunch(launchID: UUID(), now: t0.addingTimeInterval(3_600))

        let sessions = ledger.summary(now: t0).sessions
        XCTAssertEqual(sessions.total, 1)
        XCTAssertEqual(sessions.abnormal, 0)
        XCTAssertEqual(sessions.crashFreeRate, 1)
        XCTAssertEqual(ledger.sessions.first?.endedAt, t0.addingTimeInterval(30))
    }

    func testShortTripToTheBackgroundResumesTheSameSession() {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        let launch = UUID()
        ledger.didBecomeActive(launchID: launch, now: t0)
        ledger.didEnterBackground(launchID: launch, now: t0.addingTimeInterval(10))
        ledger.didBecomeActive(launchID: launch, now: t0.addingTimeInterval(10 + 60))
        XCTAssertEqual(ledger.sessions.count, 1)
        XCTAssertTrue(ledger.sessions[0].isInForeground)
        XCTAssertEqual(ledger.sessionCounts.total, 0, "an open session is not counted yet")
    }

    func testLongTripToTheBackgroundStartsANewSession() {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        let launch = UUID()
        ledger.didBecomeActive(launchID: launch, now: t0)
        ledger.didEnterBackground(launchID: launch, now: t0.addingTimeInterval(10))
        ledger.didBecomeActive(
            launchID: launch,
            now: t0.addingTimeInterval(10 + ReliabilityLedger.sessionResumeWindow + 1)
        )
        XCTAssertEqual(ledger.sessions.count, 2)
        XCTAssertEqual(ledger.sessions[0].end, .clean)
        XCTAssertEqual(ledger.sessionCounts.total, 1)
        XCTAssertEqual(ledger.sessionCounts.abnormal, 0)
    }

    func testActivationWithoutBackgroundIsNotANewSession() {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        let launch = UUID()
        // Control Center, a call banner: inactive → active, no background.
        ledger.didBecomeActive(launchID: launch, now: t0)
        ledger.didBecomeActive(launchID: launch, now: t0.addingTimeInterval(5))
        XCTAssertEqual(ledger.sessions.count, 1)
    }

    func testTerminateClosesClean() {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        let launch = UUID()
        ledger.didBecomeActive(launchID: launch, now: t0)
        ledger.willTerminate(launchID: launch, now: t0.addingTimeInterval(5))
        ledger.processLaunch(launchID: UUID(), now: t0.addingTimeInterval(50))
        XCTAssertEqual(ledger.sessionCounts.total, 1)
        XCTAssertEqual(ledger.sessionCounts.abnormal, 0)
    }

    func testDebuggerSessionsNeverCount() {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        ledger.didBecomeActive(launchID: UUID(), now: t0, debugger: true)
        // Xcode's Stop button kills it on screen.
        ledger.processLaunch(launchID: UUID(), now: t0.addingTimeInterval(20))
        let sessions = ledger.summary(now: t0).sessions
        XCTAssertEqual(sessions.total, 0)
        XCTAssertEqual(sessions.excludedDebugger, 1)
        XCTAssertNil(sessions.crashFreeRate)
        XCTAssertEqual(sessions.gate, .noData)
    }

    func testCrashFreeRateOverManySessions() throws {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        var clock = t0
        for i in 0..<1_000 {
            let launch = UUID()
            ledger.didBecomeActive(launchID: launch, now: clock)
            if i != 500 {
                ledger.didEnterBackground(launchID: launch, now: clock.addingTimeInterval(60))
            }
            clock = clock.addingTimeInterval(3_600)
            ledger.processLaunch(launchID: UUID(), now: clock)
        }
        let sessions = ledger.summary(now: clock).sessions
        XCTAssertEqual(sessions.total, 1_000)
        XCTAssertEqual(sessions.abnormal, 1)
        XCTAssertEqual(try XCTUnwrap(sessions.crashFreeRate), 0.999, accuracy: 1e-9)
        XCTAssertEqual(sessions.gate, .meets)
        XCTAssertLessThanOrEqual(ledger.sessions.count, ReliabilityLedger.Limits.sessions)
    }

    func testAriaTurnKeepsTheOpenSessionsLastActiveTimeFresh() {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        let launch = UUID()
        ledger.didBecomeActive(launchID: launch, now: t0)
        ledger.record(turn(.success, at: 120))
        XCTAssertEqual(ledger.sessions[0].lastActiveAt, t0.addingTimeInterval(120))
    }

    // MARK: Reset

    func testResetStartsANewWindowAndKeepsTheOpenSession() {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        let old = UUID()
        ledger.didBecomeActive(launchID: old, now: t0)
        ledger.processLaunch(launchID: UUID(), now: t0.addingTimeInterval(1))
        let live = UUID()
        ledger.didBecomeActive(launchID: live, now: t0.addingTimeInterval(2))
        ledger.record(turn(.failure))
        ledger.record(ReliabilityFailureRecord(area: .healthKit, operation: .quantityQuery, error: ReliabilityError(kind: .healthKit, code: 6)))

        let later = t0.addingTimeInterval(100)
        ledger.resetWindow(now: later)
        let summary = ledger.summary(now: later)
        XCTAssertEqual(summary.windowStartedAt, later)
        XCTAssertEqual(summary.aria.total, 0)
        XCTAssertEqual(summary.sessions.total, 0)
        XCTAssertTrue(summary.recentErrors.isEmpty)
        XCTAssertEqual(ledger.sessions.count, 1)
        XCTAssertEqual(ledger.sessions.first?.launchID, live)
    }

    // MARK: Errors and failures

    func testRecentErrorsMergeAriaAndCriticalPathFailuresNewestFirst() {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        ledger.record(turn(.failure, route: .cloud, at: 10))
        ledger.record(turn(.success, at: 20))
        ledger.record(ReliabilityFailureRecord(
            at: t0.addingTimeInterval(30), area: .persistence, operation: .chatSessionSave,
            error: ReliabilityError(kind: .encoding)
        ))
        ledger.record(turn(.fallback, route: .cloud, at: 40))
        let errors = ledger.summary(now: t0).recentErrors
        XCTAssertEqual(errors.map(\.operation), [.ariaTurn, .chatSessionSave, .ariaTurn])
        XCTAssertEqual(errors.first?.outcome, .fallback)
        XCTAssertEqual(ledger.summary(now: t0).failuresByArea["persistence"], 1)
    }

    func testCancelledFailuresAreDropped() {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        ledger.record(ReliabilityFailureRecord(area: .healthKit, operation: .quantityQuery, error: ReliabilityError(kind: .cancelled)))
        XCTAssertTrue(ledger.failures.isEmpty)
    }

    func testHTTPStatusMapping() {
        XCTAssertEqual(ReliabilityError.http(status: 401).kind, .unauthorized)
        XCTAssertEqual(ReliabilityError.http(status: 429).kind, .rateLimited)
        XCTAssertEqual(ReliabilityError.http(status: 503).kind, .serverError)
        XCTAssertEqual(ReliabilityError.http(status: 404).kind, .clientError)
        XCTAssertEqual(ReliabilityError.http(status: 503).code, 503)
    }

    func testClassifyByTypeAndDomain() {
        XCTAssertEqual(ReliabilityError.classify(CancellationError()).kind, .cancelled)
        XCTAssertEqual(ReliabilityError.classify(URLError(.notConnectedToInternet)).kind, .offline)
        XCTAssertEqual(ReliabilityError.classify(URLError(.timedOut)).kind, .timeout)
        let hk = ReliabilityError.classify(NSError(domain: "com.apple.healthkit", code: 6))
        XCTAssertEqual(hk.kind, .healthKit)
        XCTAssertEqual(hk.code, 6)
        XCTAssertEqual(ReliabilityError.classify(NSError(domain: NSCocoaErrorDomain, code: 640)).kind, .fileSystem)
    }

    // MARK: MetricKit summaries

    func testHistogramPercentileAndHangRate() throws {
        let buckets = [
            ReliabilityHistogramBucket(startMs: 0, endMs: 100, count: 50),
            ReliabilityHistogramBucket(startMs: 100, endMs: 200, count: 45),
            ReliabilityHistogramBucket(startMs: 900, endMs: 1_100, count: 5),
        ]
        XCTAssertEqual(ReliabilityHistogram.percentile(buckets, 0.5), 50)
        XCTAssertEqual(ReliabilityHistogram.percentile(buckets, 0.95), 150)
        XCTAssertEqual(ReliabilityHistogram.percentile(buckets, 0.96), 1_000)
        XCTAssertNil(ReliabilityHistogram.percentile([], 0.5))

        // 2 hangs of ~1.5 s in 2 h of foreground = 1.5 s per hour.
        let hangs = [ReliabilityHistogramBucket(startMs: 1_000, endMs: 2_000, count: 2)]
        let rate = try XCTUnwrap(ReliabilityHistogram.hangSecondsPerHour(hangs: hangs, foregroundSeconds: 7_200))
        XCTAssertEqual(rate, 1.5, accuracy: 1e-9)
        XCTAssertNil(ReliabilityHistogram.hangSecondsPerHour(hangs: hangs, foregroundSeconds: 0))
    }

    func testMetricPayloadsDeduplicateAndSumExitsForAppleCrossCheck() throws {
        var ledger = ReliabilityLedger(windowStartedAt: t0)
        var day = ReliabilityMetricSummary(periodStart: t0, periodEnd: t0.addingTimeInterval(86_400))
        var exits = ReliabilityExitCounts()
        exits.normal = 990
        exits.badAccess = 1
        exits.watchdog = 1
        day.foregroundExits = exits
        ledger.ingest(metrics: [day])
        ledger.ingest(metrics: [day])
        XCTAssertEqual(ledger.metrics.count, 1)

        let apple = ledger.summary(now: t0).apple
        XCTAssertEqual(apple.foregroundExits.crashLike, 2)
        XCTAssertEqual(try XCTUnwrap(apple.foregroundCrashFreeRate), 990.0 / 992.0, accuracy: 1e-9)
    }

    func testOversizedCallStacksAreDropped() {
        var diagnostic = ReliabilityDiagnosticSummary(kind: .crash, at: t0)
        diagnostic.attachCallStack(Data(repeating: 0x41, count: ReliabilityDiagnosticSummary.maxCallStackBytes + 1))
        XCTAssertNil(diagnostic.callStackJSON)
        XCTAssertTrue(diagnostic.callStackTruncated)
        diagnostic.attachCallStack(Data("{}".utf8))
        XCTAssertEqual(diagnostic.callStackJSON, "{}")
    }

    // MARK: Persistence

    func testLedgerSurvivesARoundTripThroughDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reliability-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = ReliabilityLog(directory: directory)
        await log.record(turn(.success, ms: 321))
        await log.record(turn(.failure, route: .cloud))
        await log.flush()

        let reopened = ReliabilityLog(directory: directory)
        let summary = await reopened.summary(now: t0)
        XCTAssertEqual(summary.aria.total, 2)
        XCTAssertEqual(summary.aria.failures, 1)
        XCTAssertEqual(summary.aria.byRoute.first { $0.route == .onDeviceModel }?.p50Ms, 321)
    }

    func testUnreadableFileStartsFresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reliability-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("reliability.json"))

        let log = ReliabilityLog(directory: directory)
        let summary = await log.summary(now: t0)
        XCTAssertEqual(summary.aria.total, 0)
    }
}
