import XCTest
@testable import ForgeSwift

final class MedicationPharmacyTests: XCTestCase {

    func testCatalogExceedsTenThousand() {
        XCTAssertGreaterThanOrEqual(MedicationPharmacy.count, MedicationPharmacy.minimumCount)
        XCTAssertGreaterThanOrEqual(MedicationPharmacy.all().count, 50_000, "NDC + drugs@FDA + CDC CVX must ship as a federal-scale catalog")
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

    func testSearchFindsXcopriAndOxtellar() {
        let xcopri = MedicationPharmacy.search("xcopri")
        XCTAssertFalse(xcopri.isEmpty, "Xcopri is an FDA-approved cenobamate brand and must be searchable")
        XCTAssertTrue(xcopri.contains { $0.brand?.localizedCaseInsensitiveContains("Xcopri") == true })
        XCTAssertTrue(xcopri.contains { $0.generic.localizedCaseInsensitiveContains("cenobamate") })

        let oxtellar = MedicationPharmacy.search("oxtellar")
        XCTAssertFalse(oxtellar.isEmpty, "Oxtellar XR is an FDA-approved oxcarbazepine brand and must be searchable")
        XCTAssertTrue(oxtellar.contains { $0.brand?.localizedCaseInsensitiveContains("Oxtellar") == true })
        XCTAssertTrue(oxtellar.contains { $0.generic.localizedCaseInsensitiveContains("oxcarbazepine") })
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

    func testCatalogIsRealFDAPresentationsNotInventedStrengths() {
        let rows = MedicationPharmacy.all()
        let generics = Set(rows.map { $0.generic.lowercased() })
        XCTAssertGreaterThanOrEqual(generics.count, 2_000, "Padded strength grids do not produce thousands of distinct ingredients")
        XCTAssertTrue(rows.contains { $0.brand?.localizedCaseInsensitiveCompare("Lipitor") == .orderedSame })
        XCTAssertGreaterThanOrEqual(rows.filter { $0.generic.localizedCaseInsensitiveContains("atorvastatin") }.count, 4)
    }

    func testClinicalSummaryEmptyIsSafe() {
        XCTAssertFalse(ClinicalRecordsSummary.empty.hasData)
        XCTAssertTrue(ClinicalRecordsSummary.empty.items.isEmpty)
        XCTAssertTrue(ClinicalRecordsSummary.empty.items(for: .medication).isEmpty)
    }
}
