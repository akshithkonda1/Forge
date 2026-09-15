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
}
