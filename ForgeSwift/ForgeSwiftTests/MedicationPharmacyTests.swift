import XCTest
@testable import ForgeSwift

final class MedicationPharmacyTests: XCTestCase {

    override func setUp() async throws {
        await MedicationPharmacy.prepare()
    }

    func testCatalogExceedsTenThousand() {
        XCTAssertGreaterThanOrEqual(MedicationPharmacy.count, MedicationPharmacy.minimumCount)
        XCTAssertGreaterThanOrEqual(MedicationPharmacy.all().count, 50_000, "NDC + drugs@FDA + CDC CVX must ship as a federal-scale catalog")
    }

    func testSearchFindsKnownFDADrugs() {
        let atorva = MedicationPharmacy.search("atorvastatin").items
        XCTAssertFalse(atorva.isEmpty)
        XCTAssertTrue(atorva.contains { $0.generic.localizedCaseInsensitiveContains("atorvastatin") })

        let lipitor = MedicationPharmacy.search("lipitor").items
        XCTAssertFalse(lipitor.isEmpty)
        XCTAssertTrue(lipitor.contains { $0.brand?.localizedCaseInsensitiveContains("Lipitor") == true })

        let metformin = MedicationPharmacy.search("metformin").items
        XCTAssertFalse(metformin.isEmpty)
    }

    func testSearchFindsXcopriAndOxtellarByBrandAndGeneric() {
        let xcopri = MedicationPharmacy.search("xcopri")
        XCTAssertGreaterThan(xcopri.total, 0)
        XCTAssertTrue(xcopri.items.contains { $0.brand?.localizedCaseInsensitiveContains("Xcopri") == true })
        XCTAssertTrue(xcopri.items.contains { $0.generic.localizedCaseInsensitiveContains("cenobamate") })
        XCTAssertTrue(xcopri.items.contains { $0.disease == "Epilepsy" })

        let generic = MedicationPharmacy.search("cenobamate")
        XCTAssertTrue(generic.items.contains { $0.brand?.localizedCaseInsensitiveContains("Xcopri") == true })

        let oxtellar = MedicationPharmacy.search("oxtellar")
        XCTAssertGreaterThan(oxtellar.total, 0)
        XCTAssertTrue(oxtellar.items.contains { $0.brand?.localizedCaseInsensitiveContains("Oxtellar") == true })
        XCTAssertTrue(oxtellar.items.contains { $0.generic.localizedCaseInsensitiveContains("oxcarbazepine") })

        let oxc = MedicationPharmacy.search("oxcarbazepine")
        XCTAssertTrue(oxc.items.contains { $0.brand?.localizedCaseInsensitiveContains("Oxtellar") == true })
    }

    func testSearchFindsByDiseaseAndArchetype() {
        let epilepsy = MedicationPharmacy.search("epilepsy", sort: .disease, limit: 80)
        XCTAssertGreaterThan(epilepsy.total, 0)
        XCTAssertTrue(epilepsy.items.contains { $0.disease.localizedCaseInsensitiveCompare("Epilepsy") == .orderedSame })

        let filtered = MedicationPharmacy.search("xcopri", sort: .disease, disease: "Epilepsy")
        XCTAssertTrue(filtered.items.contains { $0.generic.localizedCaseInsensitiveContains("cenobamate") })

        let neuro = MedicationPharmacy.search("", sort: .archetype, limit: 20, archetype: "Neurology")
        XCTAssertFalse(neuro.items.isEmpty)
        XCTAssertTrue(neuro.items.allSatisfy { $0.archetype == "Neurology" })
    }

    func testSearchIsCappedAndReportsFullTotal() {
        let hits = MedicationPharmacy.search("tablet", limit: 12)
        XCTAssertLessThanOrEqual(hits.items.count, 12)
        XCTAssertGreaterThan(hits.total, hits.items.count)
        XCTAssertFalse(hits.items.isEmpty)
    }

    func testEntriesHaveStableIdsAndBothNames() {
        let rows = MedicationPharmacy.all()
        let ids = Set(rows.map(\.id))
        XCTAssertEqual(ids.count, rows.count)
        XCTAssertTrue(rows.allSatisfy { !$0.name.isEmpty && !$0.generic.isEmpty && !$0.archetype.isEmpty && !$0.disease.isEmpty })
    }

    func testCatalogIsRealFDAPresentationsNotInventedStrengths() {
        let rows = MedicationPharmacy.all()
        let generics = Set(rows.map { $0.generic.lowercased() })
        XCTAssertGreaterThanOrEqual(generics.count, 2_000, "Padded strength grids do not produce thousands of distinct ingredients")
        XCTAssertTrue(rows.contains { $0.brand?.localizedCaseInsensitiveCompare("Lipitor") == .orderedSame })
        XCTAssertGreaterThanOrEqual(rows.filter { $0.generic.localizedCaseInsensitiveContains("atorvastatin") }.count, 4)
    }

    func testGroupsByArchetypeAndDisease() {
        let page = MedicationPharmacy.search("", sort: .archetype, limit: 40)
        XCTAssertFalse(page.groups.isEmpty)
        XCTAssertEqual(Set(page.groups.map(\.title)).count, page.groups.count)
        let disease = MedicationPharmacy.search("xcopri", sort: .disease, limit: 20)
        XCTAssertTrue(disease.groups.contains { $0.title == "Epilepsy" })
    }

    func testResultIdsAreUniqueForForEach() {
        let page = MedicationPharmacy.search("metformin", limit: 40)
        XCTAssertEqual(Set(page.items.map(\.id)).count, page.items.count)
    }

    func testClinicalSummaryEmptyIsSafe() {
        XCTAssertFalse(ClinicalRecordsSummary.empty.hasData)
        XCTAssertTrue(ClinicalRecordsSummary.empty.items.isEmpty)
        XCTAssertTrue(ClinicalRecordsSummary.empty.items(for: .medication).isEmpty)
    }
}
