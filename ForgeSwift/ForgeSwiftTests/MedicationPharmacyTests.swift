import XCTest
@testable import ForgeSwift

final class MedicationPharmacyTests: XCTestCase {

    func testCatalogExceedsTenThousand() {
        XCTAssertGreaterThanOrEqual(MedicationPharmacy.count, MedicationPharmacy.minimumCount)
        XCTAssertGreaterThanOrEqual(MedicationPharmacy.all().count, 10_000)
    }

    func testSearchFindsKnownFDADrugs() {
        let atorva = MedicationPharmacy.search("atorvastatin")
        XCTAssertFalse(atorva.isEmpty)
        XCTAssertTrue(atorva.contains { $0.generic.localizedCaseInsensitiveContains("atorvastatin") })

        let lipitor = MedicationPharmacy.search("lipitor")
        XCTAssertFalse(lipitor.isEmpty)

        let metformin = MedicationPharmacy.search("metformin")
        XCTAssertFalse(metformin.isEmpty)
    }

    func testSearchIsCappedAndCaseInsensitive() {
        let hits = MedicationPharmacy.search("tablet", limit: 12)
        XCTAssertLessThanOrEqual(hits.count, 12)
        XCTAssertFalse(hits.isEmpty)
    }

    func testEntriesHaveStableIds() {
        let rows = MedicationPharmacy.all()
        let ids = Set(rows.map(\.id))
        XCTAssertEqual(ids.count, rows.count)
        XCTAssertTrue(rows.allSatisfy { !$0.name.isEmpty && !$0.generic.isEmpty })
    }

    func testClinicalSummaryEmptyIsSafe() {
        XCTAssertFalse(ClinicalRecordsSummary.empty.hasData)
        XCTAssertTrue(ClinicalRecordsSummary.empty.items.isEmpty)
        XCTAssertTrue(ClinicalRecordsSummary.empty.items(for: .medication).isEmpty)
    }
}
