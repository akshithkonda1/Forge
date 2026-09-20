import XCTest
@testable import ForgeCore

/// Apple Watch-derived metabolic estimates: labeling honesty, the two-signal
/// minimum, CGM-wins gating, and the Metabolic Health toggle.
final class MetabolicWatchSignalsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func fullInputs() -> MetabolicWatchInputs {
        MetabolicWatchInputs(
            restingHRBpm: 58,
            hrvMs: 52,
            hrvBaselineMs: 48,
            vo2Max: 42,
            activeCalories: 420,
            exerciseMinutes: 35,
            sleepHours: 6.2,
            sleepBaselineHours: 7.4
        )
    }

    // MARK: - Estimate construction

    func testEmptyInputsProduceNoEstimate() {
        let estimate = MetabolicWatchEstimate.evaluate(MetabolicWatchInputs())
        XCTAssertFalse(estimate.hasSignals)
        XCTAssertTrue(estimate.signals.isEmpty)
        XCTAssertTrue(estimate.summaryLine.isEmpty)
    }

    func testSingleSignalIsNotEnoughForAnEstimate() {
        // One data point is not a metabolic picture — it must not surface.
        var inputs = MetabolicWatchInputs()
        inputs.vo2Max = 42
        let estimate = MetabolicWatchEstimate.evaluate(inputs)
        XCTAssertFalse(estimate.hasSignals)
        XCTAssertNil(MetabolicHealthSnapshot.evaluate(
            meals: [], glucose: [], watchEstimate: estimate, now: now
        ).watchEstimate)
    }

    func testFullInputsProduceFiveLabeledSignals() {
        let estimate = MetabolicWatchEstimate.evaluate(fullInputs())
        XCTAssertTrue(estimate.hasSignals)
        XCTAssertEqual(estimate.signals.count, 5)
        XCTAssertEqual(
            estimate.signals.map(\.id),
            ["cardio-fitness", "resting-hr", "hrv", "movement", "sleep"]
        )
    }

    func testEverySignalNamesItsSource() {
        let estimate = MetabolicWatchEstimate.evaluate(fullInputs())
        XCTAssertTrue(estimate.hasSignals)
        for signal in estimate.signals {
            XCTAssertTrue(signal.line.contains("Apple Watch"), signal.id)
        }
        XCTAssertTrue(estimate.summaryLine.contains("Apple Watch"))
    }

    func testInterpretiveSignalsSayEstimate() {
        // Lines that interpret data (vs. merely reporting it) must say so.
        let estimate = MetabolicWatchEstimate.evaluate(fullInputs())
        let byID = Dictionary(uniqueKeysWithValues: estimate.signals.map { ($0.id, $0.line) })
        XCTAssertTrue(byID["cardio-fitness"]?.contains("estimat") == true)
        XCTAssertTrue(byID["hrv"]?.contains("estimat") == true)
        XCTAssertTrue(byID["sleep"]?.contains("estimat") == true)
        XCTAssertTrue(estimate.summaryLine.contains("estimat"))
        XCTAssertTrue(estimate.summaryLine.contains("not medical advice"))
    }

    func testImplausibleValuesAreDroppedNotShown() {
        var inputs = fullInputs()
        inputs.restingHRBpm = 400 // corrupt sample — must not appear
        inputs.hrvMs = 0 // missing — must not appear
        let estimate = MetabolicWatchEstimate.evaluate(inputs)
        XCTAssertTrue(estimate.hasSignals)
        XCTAssertNil(estimate.signals.first(where: { $0.id == "resting-hr" }))
        XCTAssertNil(estimate.signals.first(where: { $0.id == "hrv" }))
        XCTAssertNotNil(estimate.signals.first(where: { $0.id == "cardio-fitness" }))
        XCTAssertNotNil(estimate.signals.first(where: { $0.id == "sleep" }))
    }

    func testBaselineComparisonFallsBackToTodayOnly() {
        var inputs = MetabolicWatchInputs()
        inputs.hrvMs = 52
        inputs.sleepHours = 6.2
        inputs.vo2Max = 42
        let estimate = MetabolicWatchEstimate.evaluate(inputs)
        XCTAssertTrue(estimate.hasSignals)
        let byID = Dictionary(uniqueKeysWithValues: estimate.signals.map { ($0.id, $0.line) })
        XCTAssertEqual(byID["hrv"], "52 ms today — Apple Watch")
        XCTAssertEqual(byID["sleep"], "6.2 h last night — Apple Watch")
    }

    // MARK: - Honesty firewall

    func testCopyNeverDiagnosesScoresOrGrades() {
        let estimate = MetabolicWatchEstimate.evaluate(fullInputs())
        XCTAssertTrue(estimate.hasSignals)
        let blob = (estimate.signals.map(\.line).joined(separator: " ") + " " + estimate.summaryLine).lowercased()
        for banned in ["diagnos", "diabet", "disease", "patient", "insulin", "a1c",
                       "hypergly", "hypogly", "score", "grade", "risk",
                       "healthy", "unhealthy", "normal", "abnormal"] {
            XCTAssertFalse(blob.contains(banned), banned)
        }
    }

    // MARK: - Snapshot wiring: toggle + CGM truth

    func testToggleOffReturnsEmptySnapshot() {
        let estimate = MetabolicWatchEstimate.evaluate(fullInputs())
        let snap = MetabolicHealthSnapshot.evaluate(
            meals: [MetabolicMealEvent(name: "Lunch", date: now.addingTimeInterval(-60 * 60), calories: 500, carbs: 50)],
            glucose: [],
            watchEstimate: estimate,
            isEnabled: false,
            now: now
        )
        XCTAssertEqual(snap, .empty)
        XCTAssertNil(snap.watchEstimate)
        XCTAssertFalse(snap.hasWatchEstimate)
    }

    func testWatchEstimateSurfacesWhenNoGlucose() {
        let estimate = MetabolicWatchEstimate.evaluate(fullInputs())
        let snap = MetabolicHealthSnapshot.evaluate(
            meals: [], glucose: [], watchEstimate: estimate, now: now
        )
        XCTAssertFalse(snap.hasGlucose)
        XCTAssertTrue(snap.hasWatchEstimate)
        XCTAssertEqual(snap.watchEstimate?.displayLines.count, 5)
    }

    func testGlucoseBeatsWatchEstimates() {
        // CGM is the source of truth: with glucose present, estimates never surface.
        let estimate = MetabolicWatchEstimate.evaluate(fullInputs())
        let snap = MetabolicHealthSnapshot.evaluate(
            meals: [],
            glucose: [GlucosePoint(date: now.addingTimeInterval(-20 * 60), mgdl: 102, sourceName: "Dexcom Stelo")],
            watchEstimate: estimate,
            now: now
        )
        XCTAssertTrue(snap.hasGlucose)
        XCTAssertNil(snap.watchEstimate)
        XCTAssertFalse(snap.hasWatchEstimate)
    }

    func testEmptyWatchEstimateIsDropped() {
        let snap = MetabolicHealthSnapshot.evaluate(
            meals: [], glucose: [], watchEstimate: .empty, now: now
        )
        XCTAssertNil(snap.watchEstimate)
        XCTAssertFalse(snap.hasWatchEstimate)
    }
}
