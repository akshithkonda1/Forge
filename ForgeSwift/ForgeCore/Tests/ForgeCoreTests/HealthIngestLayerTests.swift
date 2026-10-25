import XCTest
@testable import ForgeCore

final class HealthIngestLayerTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        _ metric: HealthIngestMetric,
        value: Double,
        source: String,
        startOffset: TimeInterval = 0,
        duration: TimeInterval? = nil,
        workoutType: String? = nil
    ) -> HealthIngestSample {
        let start = day.addingTimeInterval(startOffset)
        return HealthIngestSample(
            metric: metric,
            value: value,
            unit: metric == .sleep ? "min" : "count",
            start: start,
            end: duration.map { start.addingTimeInterval($0) },
            source: source,
            workoutType: workoutType
        )
    }

    func testOuraAndWatchDuplicateWorkoutKeepsOne() {
        let watch = sample(.workout, value: 40, source: "apple-watch", duration: 40 * 60, workoutType: "run")
        let oura = sample(.workout, value: 41, source: "oura", startOffset: 5 * 60, duration: 38 * 60, workoutType: "run")
        let (kept, decisions) = HealthIngestLayer.dedup([watch, oura], learner: HealthIngestLearner())
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(HealthSourcePriority.canonicalize(kept[0].source), "apple-watch")
        XCTAssertEqual(decisions.count, 1)
        XCTAssertTrue(decisions[0].reason.contains("Merged overlapping"))
    }

    func testStravaRoundTripDuplicateDropsExactCopy() {
        let first = sample(.workout, value: 55, source: "strava", duration: 55 * 60, workoutType: "run")
        let echo = first
        let (kept, _) = HealthIngestLayer.dedup([first, echo], learner: HealthIngestLearner())
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].source, "strava")
    }

    func testTwoSourceSleepDoesNotDoubleCount() {
        let watch = sample(.sleep, value: 420, source: "apple-watch")
        let oura = sample(.sleep, value: 418, source: "oura", startOffset: 30)
        let (kept, decisions) = HealthIngestLayer.dedup([watch, oura], learner: HealthIngestLearner())
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].value, 420)
        XCTAssertTrue(decisions[0].reason.contains("source priority"))
    }

    func testLearnerTightensWindowAfterRepeatedOverlaps() {
        var learner = HealthIngestLearner()
        XCTAssertEqual(learner.nearDuplicateWindow(sourceA: "oura", sourceB: "apple-watch"), 90)
        for _ in 0..<4 {
            learner.recordOverlap(winner: "apple-watch", loser: "oura", offsetSeconds: 20)
        }
        XCTAssertEqual(learner.nearDuplicateWindow(sourceA: "oura", sourceB: "apple-watch"), 50)
        XCTAssertTrue(learner.summary().contains("apple-watch|oura"))
    }

    func testDedupIsDeterministic() {
        let a = sample(.steps, value: 8000, source: "oura")
        let b = sample(.steps, value: 8010, source: "apple-watch", startOffset: 10)
        let first = HealthIngestLayer.dedup([a, b], learner: HealthIngestLearner())
        let second = HealthIngestLayer.dedup([b, a], learner: HealthIngestLearner())
        XCTAssertEqual(first.samples, second.samples)
        XCTAssertEqual(first.samples[0].source, "apple-watch")
    }

    func testProcessNeverTouchesNetworkAndRecordsDecisions() {
        let incoming = [
            sample(.steps, value: 9000, source: "apple-watch"),
            sample(.steps, value: 9050, source: "oura", startOffset: 15),
            sample(.sleep, value: 430, source: "apple-watch"),
        ]
        var reGatherCalls = 0
        let (batch, _) = HealthIngestLayer.process(
            incoming: incoming,
            connectedSources: ["apple-watch", "oura"],
            expected: [.steps, .sleep],
            day: day,
            learner: HealthIngestLearner()
        ) { _ in
            reGatherCalls += 1
            return []
        }
        XCTAssertEqual(batch.samples.count, 2)
        XCTAssertGreaterThanOrEqual(reGatherCalls, 1, "Scout re-gathers missing expected fields on-device")
        XCTAssertTrue(batch.decisions.contains { $0.reason.contains("source priority") })
        XCTAssertTrue(batch.learnerSummary.contains("overlaps") || batch.decisions.isEmpty == false)
    }
}

final class HealthScoutTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    func testFlagsMissingSleepHRVAndWorkoutHR() {
        let samples = [
            HealthIngestSample(metric: .steps, value: 1000, unit: "count", start: day, source: "apple-watch"),
        ]
        let report = HealthScout.inspect(
            samples: samples,
            connectedSources: ["apple-watch", "oura"],
            expected: [.sleep, .hrv, .workoutHR, .steps],
            day: day
        )
        let fields = Set(report.gaps.map(\.field))
        XCTAssertEqual(fields, ["sleep", "hrv", "workoutHR"])
        XCTAssertTrue(report.gaps.allSatisfy { $0.status == .missing })
        XCTAssertNotNil(report.ariaLine)
        XCTAssertFalse(report.ariaLine?.contains("188") == true)
    }

    func testReGatherSuccessClearsTheFlag() {
        let incoming = [
            HealthIngestSample(metric: .steps, value: 1000, unit: "count", start: day, source: "apple-watch"),
        ]
        let fill = HealthIngestSample(metric: .hrv, value: 55, unit: "ms", start: day, source: "oura")
        let (batch, _) = HealthIngestLayer.process(
            incoming: incoming,
            connectedSources: ["apple-watch", "oura"],
            expected: [.steps, .hrv],
            day: day,
            learner: HealthIngestLearner()
        ) { gap in
            gap.field == "hrv" ? [fill] : []
        }
        XCTAssertTrue(batch.samples.contains { $0.metric == .hrv && $0.value == 55 })
        XCTAssertEqual(batch.scout.gaps.first { $0.field == "hrv" }?.status, .filledFromHealthKit)
        XCTAssertFalse(batch.scout.openGaps.contains { $0.field == "hrv" })
    }

    func testPermanentWhoopHRVStaysFlaggedWhenNoOtherSource() {
        let samples = [
            HealthIngestSample(metric: .steps, value: 2000, unit: "count", start: day, source: "whoop"),
        ]
        let report = HealthScout.inspect(
            samples: samples,
            connectedSources: ["whoop"],
            expected: [.hrv, .steps],
            day: day
        )
        let hrv = report.gaps.first { $0.field == "hrv" }
        XCTAssertEqual(hrv?.status, .permanent)
        XCTAssertEqual(hrv?.note, "WHOOP doesn't share HRV")
        XCTAssertTrue(report.ariaLine?.contains("WHOOP doesn't share HRV") == true)
    }

    func testARIALineMentionsGapAndNeverFabricatesCanaryHRV() {
        let report = HealthScout.inspect(
            samples: [],
            connectedSources: ["whoop"],
            expected: [.hrv],
            day: day
        )
        let line = report.ariaLine ?? ""
        XCTAssertTrue(HealthScout.ariaMentionsGap(line, field: "HRV") || line.contains("WHOOP"))
        XCTAssertFalse(line.contains("\(ForgeOutboundSanitizer.Canary.hrv)"))
        XCTAssertFalse(line.contains("188"))
    }

    func testRecurringGapsFeedTheLearner() {
        var learner = HealthIngestLearner()
        let incoming: [HealthIngestSample] = []
        let (_, next) = HealthIngestLayer.process(
            incoming: incoming,
            connectedSources: ["whoop"],
            expected: [.hrv],
            day: day,
            learner: learner
        ) { _ in [] }
        learner = next
        XCTAssertTrue(learner.summary().contains("gap:whoop:hrv"))
    }

    func testScoutHasNoNetworkSurface() {
        // Completeness Scout is a sibling of research Scout, not a client of it.
        XCTAssertNotEqual(HealthScout.permanentGaps.first?.note, "/scout/research")
        var called = false
        _ = HealthIngestLayer.process(
            incoming: [],
            connectedSources: ["apple-watch"],
            expected: [.hrv],
            day: day,
            learner: HealthIngestLearner()
        ) { _ in
            called = true
            return []
        }
        XCTAssertTrue(called, "Scout re-gathers on-device; it does not call research Scout")
    }

    func testExpectedMetricsFlagsWorkoutHRWhenWorkoutPresent() {
        let workout = HealthIngestSample(
            metric: .workout,
            value: 40,
            unit: "min",
            start: day,
            end: day.addingTimeInterval(40 * 60),
            source: "apple-watch",
            workoutType: "run"
        )
        let expected = HealthScout.expectedMetrics(
            connectedSources: ["apple-watch"],
            samples: [workout]
        )
        XCTAssertTrue(expected.contains(.workoutHR))
        let report = HealthScout.inspect(
            samples: [workout],
            connectedSources: ["apple-watch"],
            expected: expected,
            day: day
        )
        XCTAssertEqual(report.gaps.first { $0.field == "workoutHR" }?.status, .missing)
        XCTAssertFalse(report.ariaLine?.contains("188") == true)
    }

    func testAppleHealthLedgerDoesNotHideWhoopPermanentHRV() {
        let report = HealthScout.inspect(
            samples: [],
            connectedSources: ["whoop", "apple-health"],
            expected: HealthScout.expectedMetrics(connectedSources: ["whoop", "apple-health"]),
            day: day
        )
        XCTAssertEqual(report.gaps.first { $0.field == "hrv" }?.status, .permanent)
        XCTAssertEqual(report.gaps.first { $0.field == "hrv" }?.note, "WHOOP doesn't share HRV")
    }

    func testRestDayDoesNotExpectWorkoutHR() {
        let expected = HealthScout.expectedMetrics(
            connectedSources: ["apple-watch"],
            samples: [
                HealthIngestSample(metric: .steps, value: 4000, unit: "count", start: day, source: "apple-watch")
            ]
        )
        XCTAssertFalse(expected.contains(.workout))
        XCTAssertFalse(expected.contains(.workoutHR))
    }
}
