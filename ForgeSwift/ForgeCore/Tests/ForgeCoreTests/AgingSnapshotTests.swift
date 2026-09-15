import XCTest
@testable import ForgeCore

final class AgingSnapshotTests: XCTestCase {

    func testStrongVO2DoesNotCollapseToTeenFloor() {
        let snap = AgingSnapshot.evaluate(
            chronologicalAge: 38,
            sexFemale: false,
            vo2Max: 52
        )
        XCTAssertEqual(snap.state, .younger)
        XCTAssertGreaterThanOrEqual(snap.fitnessAge ?? 0, 26)
        XCTAssertLessThan(snap.fitnessAge ?? 99, 38)
        XCTAssertGreaterThanOrEqual(snap.biologicalAge ?? 0, 26)
    }

    func testStrongVO2ReadsYoungerThanCalendar() {
        let snap = AgingSnapshot.evaluate(
            chronologicalAge: 40,
            sexFemale: false,
            vo2Max: 52,
            hrv: 70,
            restingHR: 52,
            sleepHours: 8.0
        )
        XCTAssertEqual(snap.chronologicalAge, 40)
        XCTAssertNotNil(snap.biologicalAge)
        XCTAssertLessThan(snap.biologicalAge ?? 99, 40)
        XCTAssertEqual(snap.state, .younger)
        XCTAssertTrue(snap.comparisonLine.contains("younger"))
        XCTAssertFalse(snap.trainingHint.lowercased().contains("diagnos"))
    }

    func testSuppressedSignalsReadOlder() {
        let snap = AgingSnapshot.evaluate(
            chronologicalAge: 35,
            sexFemale: true,
            vo2Max: 28,
            hrv: 22,
            restingHR: 78,
            sleepHours: 5.5
        )
        XCTAssertEqual(snap.state, .older)
        XCTAssertGreaterThan(snap.biologicalAge ?? 0, 35)
        XCTAssertTrue(snap.trainingHint.localizedCaseInsensitiveContains("recovery"))
    }

    func testCalendarOnlyDoesNotInventAGap() {
        let snap = AgingSnapshot.evaluate(chronologicalAge: 29)
        XCTAssertEqual(snap.chronologicalAge, 29)
        XCTAssertEqual(snap.biologicalAge, 29)
        XCTAssertEqual(snap.deltaYears, 0)
        XCTAssertEqual(snap.state, .matched)
        XCTAssertLessThanOrEqual(snap.confidence, 0.25)
        XCTAssertTrue(snap.comparisonLine.contains("calendar"))
    }

    func testVendorBiologicalAgeIsCaptured() {
        let snap = AgingSnapshot.evaluate(
            chronologicalAge: 38,
            vendorAges: [
                AgingVendorAge(kind: .fitness, years: 32, confidence: 0.9, source: "garmin"),
                AgingVendorAge(kind: .inner, years: 33, confidence: 0.8, source: "ultrahuman")
            ]
        )
        XCTAssertLessThan(snap.biologicalAge ?? 99, 38)
        XCTAssertTrue(snap.sources.contains { $0.contains("garmin") })
        XCTAssertTrue(snap.sources.contains { $0.contains("ultrahuman") })
    }

    func testHealthMetricTypesMapToVendorAges() {
        XCTAssertEqual(AgingVendorAge(metricType: "garmin-fitness-age", years: 32, source: "garmin")?.kind, .fitness)
        XCTAssertEqual(AgingVendorAge(metricType: "inner_age", years: 33, source: "ultrahuman")?.kind, .inner)
        XCTAssertEqual(AgingVendorAge(metricType: "true-age", years: 41, source: "manual")?.kind, .biological)
        XCTAssertNil(AgingVendorAge(metricType: "chronological-age", years: 38, source: "apple-health"))
        XCTAssertNil(AgingVendorAge(metricType: "vo2-max", years: 52, source: "apple-health"))
    }

    func testMissingAgeDoesNotFabricate() {
        let snap = AgingSnapshot.evaluate(
            chronologicalAge: nil,
            vo2Max: 50,
            hrv: 60,
            restingHR: 55
        )
        XCTAssertNil(snap.chronologicalAge)
        XCTAssertNil(snap.biologicalAge)
        XCTAssertEqual(snap.state, .unknown)
        XCTAssertFalse(snap.showsOnTrain)
    }

    func testCopyNeverClaimsDiagnosis() {
        let snap = AgingSnapshot.evaluate(
            chronologicalAge: 50,
            vo2Max: 30,
            hrv: 25,
            restingHR: 80,
            sleepHours: 5
        )
        let blob = (snap.comparisonLine + " " + snap.trainingHint).lowercased()
        for banned in ["diagnos", "disease", "patient", "mortality", "dying"] {
            XCTAssertFalse(blob.contains(banned), banned)
        }
    }

    func testFriendExpectedVO2At38Male() {
        AgingNorms.resetForTests()
        XCTAssertEqual(AgingSnapshot.expectedVO2(age: 38, sexFemale: false), 38.8, accuracy: 0.05)
        XCTAssertEqual(AgingNorms.fitnessConfidence, 0.58, accuracy: 0.001)
    }

    func testWebConfirmedBumpsFitnessConfidenceAndSource() {
        AgingNorms.resetForTests()
        defer { AgingNorms.resetForTests() }
        let before = AgingSnapshot.evaluate(chronologicalAge: 38, sexFemale: false, vo2Max: 48)
        XCTAssertEqual(before.sources.contains { $0 == "vo2" }, true)
        AgingNorms.markWebConfirmed(sourceTitle: "MedlinePlus: Exercise Stress Test / VO2")
        XCTAssertEqual(AgingNorms.fitnessConfidence, 0.72, accuracy: 0.001)
        XCTAssertEqual(AgingNorms.webSourceTitle, "MedlinePlus: Exercise Stress Test / VO2")
        let after = AgingSnapshot.evaluate(chronologicalAge: 38, sexFemale: false, vo2Max: 48)
        XCTAssertTrue(after.sources.contains { $0 == "vo2+web" })
        XCTAssertFalse(after.sources.contains { $0 == "vo2" })
        // Fused snapshot confidence is clamped to ≥0.2, same as backend
        // fuse_biological_age. A VO2-only estimate stays on that floor;
        // the live confirm is the source tag and AgingNorms.fitnessConfidence.
        XCTAssertEqual(before.confidence, 0.2, accuracy: 0.001)
        XCTAssertEqual(after.confidence, 0.2, accuracy: 0.001)
    }
}
