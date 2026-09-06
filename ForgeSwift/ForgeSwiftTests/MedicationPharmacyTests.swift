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

    func testBottleOCRAdmitsXcopriAndIgnoresDose() {
        let scan = MedicationBottleScanner.match(ocrText: """
        NDC 72078-101-03
        XCOPRI
        cenobamate tablets
        100 mg
        Rx only
        Store at 20-25 C
        """)
        XCTAssertEqual(scan.admitted?.brand?.localizedCaseInsensitiveCompare("Xcopri"), .orderedSame)
        XCTAssertTrue(scan.admitted?.generic.localizedCaseInsensitiveContains("cenobamate") == true)
        XCTAssertEqual(scan.admitted?.disease, "Epilepsy")
        XCTAssertFalse(scan.tokensUsed.contains { $0.lowercased() == "mg" || $0 == "100" })
        XCTAssertTrue(scan.headline.contains("never names a dose"))
    }

    func testBottleOCRAdmitsOxtellarXR() {
        let scan = MedicationBottleScanner.match(ocrText: "Oxtellar XR oxcarbazepine 150 mg extended release tablets")
        XCTAssertTrue(scan.admitted?.brand?.localizedCaseInsensitiveContains("Oxtellar") == true)
        XCTAssertTrue(scan.admitted?.generic.localizedCaseInsensitiveContains("oxcarbazepine") == true)
    }

    func testBottleOCRAdmitsLipitorWithoutInventingADose() {
        let scan = MedicationBottleScanner.match(ocrText: "Lipitor atorvastatin calcium 10 mg tablets Rx only")
        XCTAssertTrue(scan.admitted?.brand?.localizedCaseInsensitiveCompare("Lipitor") == .orderedSame)
        XCTAssertTrue(scan.admitted?.generic.localizedCaseInsensitiveContains("atorvastatin") == true)
        XCTAssertFalse(scan.headline.contains("10 mg"))
    }

    func testBottleOCRIgnoresLabelNoise() {
        let scan = MedicationBottleScanner.match(ocrText: "Rx only Store at room temperature Keep out of reach of children")
        XCTAssertNil(scan.admitted)
        XCTAssertTrue(scan.candidates.isEmpty)
    }

    func testEnsureSavedDoesNotToggleOff() {
        let name = "Xcopri 100 mg Tablet"
        MedicationPharmacy.ensureSaved(name: name)
        MedicationPharmacy.ensureSaved(name: name)
        let names = MedicationPharmacy.savedNames()
        XCTAssertEqual(names.filter { $0.caseInsensitiveCompare(name) == .orderedSame }.count, 1)
    }

    func testClinicalSummaryEmptyIsSafe() {
        XCTAssertFalse(ClinicalRecordsSummary.empty.hasData)
        XCTAssertTrue(ClinicalRecordsSummary.empty.items.isEmpty)
        XCTAssertTrue(ClinicalRecordsSummary.empty.items(for: .medication).isEmpty)
    }

    func testEveryDiseaseArchetypeIsKnown() {
        XCTAssertEqual(MedicationArchetype.allCases.count, 34)
        XCTAssertEqual(Set(MedicationTaxonomy.allArchetypes).count, 34)
        XCTAssertTrue(MedicationArchetype.allCases.contains(.neurology))
        XCTAssertTrue(MedicationArchetype.allCases.contains(.rareDisease))
        XCTAssertTrue(MedicationArchetype.allCases.contains(.obstetrics))
        XCTAssertTrue(MedicationArchetype.allCases.contains(.rehabilitation))
    }

    func testContextLayerResolvesXcopriAndLipitor() {
        let mentioned = MedicationContext.resolve(query: "I take xcopri and cenobamate")
        XCTAssertTrue(mentioned.mentioned.contains { $0.archetype == "Neurology" && $0.disease == "Epilepsy" })
        XCTAssertTrue(mentioned.mentioned.contains { $0.generic.localizedCaseInsensitiveContains("cenobamate") })
        XCTAssertFalse(mentioned.mentioned.contains { $0.generic.localizedCaseInsensitiveContains("levonorgestrel") })

        let onFile = MedicationContext.resolve(savedNames: ["Lipitor"])
        XCTAssertTrue(onFile.onFile.contains { $0.generic.localizedCaseInsensitiveContains("atorvastatin") })
        XCTAssertTrue(onFile.onFile.contains { $0.archetype == "Cardiovascular" })
        XCTAssertTrue(onFile.constraintLines.contains { $0.hasPrefix("med:saved:") })
        XCTAssertTrue(onFile.tags.contains { $0.hasPrefix("med_onfile:") })
    }

    func testMedicationLayerNeverPrescribesAndMutatesLifestyleForYou() {
        let layer = MedicationContext.resolve(query: "xcopri", savedNames: ["Lipitor"])
        XCTAssertTrue(layer.inferredNeeds.contains("Epilepsy"))
        XCTAssertTrue(layer.inferredNeeds.contains("High cholesterol"))
        XCTAssertTrue(layer.shouldSoftenTraining)
        XCTAssertTrue(layer.lifestyleMutations.contains { $0.contains("Neurology") })
        XCTAssertTrue(layer.lifestyleMutations.contains { $0.contains("Cardiovascular") })
        let block = layer.promptBlock.lowercased()
        XCTAssertTrue(block.contains("never prescribes"))
        XCTAssertTrue(block.contains("never names a dose"))
        XCTAssertTrue(block.contains("for you, not for everyone"))
        XCTAssertFalse(block.contains(" mg"))
        XCTAssertFalse(block.contains("take 1"))
        XCTAssertTrue(layer.planNote.lowercased().contains("no prescription"))
        XCTAssertTrue(layer.planNote.lowercased().contains("no dose"))
        XCTAssertTrue(MedicationContextLayer.hardRules.lowercased().contains("never starts, stops, or changes"))
    }

    func testContextLayerTaxonomyCoversEachArchetypeFamily() {
        let samples: [(String, String, String)] = [
            ("atorvastatin", "Cardiovascular", "High cholesterol"),
            ("metformin", "Metabolic", "Diabetes"),
            ("levothyroxine", "Endocrine", "Hypothyroidism"),
            ("cenobamate", "Neurology", "Epilepsy"),
            ("sertraline", "Psychiatry", "Depression"),
            ("amoxicillin", "Infectious disease", "Bacterial infection"),
            ("imatinib", "Oncology", "Cancer"),
            ("adalimumab", "Immunology", "Autoimmune disease"),
            ("albuterol", "Respiratory", "Asthma"),
            ("omeprazole", "Gastroenterology", "Acid reflux"),
            ("sofosbuvir", "Hepatology", "Hepatitis"),
            ("sevelamer", "Nephrology", "Chronic kidney disease"),
            ("warfarin", "Hematology", "Clot prevention"),
            ("methotrexate", "Rheumatology", "Autoimmune disease"),
            ("tretinoin", "Dermatology", "Acne"),
            ("latanoprost", "Ophthalmology", "Glaucoma"),
            ("oxymetazoline", "Otolaryngology", "Nasal congestion"),
            ("tamsulosin", "Urology", "Benign prostatic hyperplasia"),
            ("estradiol", "Women's health", "Hormone therapy"),
            ("finasteride", "Men's health", "Benign prostatic hyperplasia"),
            ("oxytocin", "Obstetrics", "Labor"),
            ("palivizumab", "Pediatrics", "RSV prevention"),
            ("ibuprofen", "Pain", "Pain and inflammation"),
            ("zolpidem", "Sleep medicine", "Insomnia"),
            ("cetirizine", "Allergy", "Allergy"),
            ("cholecalciferol", "Nutrition", "Vitamin deficiency"),
            ("naloxone", "Toxicology", "Overdose reversal"),
            ("alendronate", "Musculoskeletal", "Osteoporosis"),
            ("baclofen", "Rehabilitation", "Spasticity"),
            ("ivacaftor", "Rare disease", "Cystic fibrosis"),
        ]
        for (name, arch, disease) in samples {
            let inferred = MedicationTaxonomy.infer(generic: name, brand: "", form: "")
            XCTAssertEqual(inferred.0, arch, "\(name) archetype")
            XCTAssertEqual(inferred.1, disease, "\(name) disease")
        }
    }

    func testRemoteStripDropsOnFileKeepsMentioned() {
        let onFile = MedicationContextEntry(
            id: "health:lipitor",
            name: "Lipitor",
            generic: "atorvastatin",
            brand: "Lipitor",
            archetype: "Cardiovascular",
            disease: "High cholesterol",
            source: "health"
        )
        let mentioned = MedicationContextEntry(
            id: "mentioned:xcopri",
            name: "Xcopri",
            generic: "cenobamate",
            brand: "Xcopri",
            archetype: "Neurology",
            disease: "Epilepsy",
            source: "mentioned"
        )
        var payload = ARIAContextPayload(
            timestamp: "2026-09-06T00:00:00Z",
            sleep: .init(),
            readiness: .init(),
            training: .init(),
            activity: .init(),
            chronotype: .init(),
            body: .init(),
            nutrition: .init(),
            profile: .init(constraints: [
                "med:health:Cardiovascular:High cholesterol:atorvastatin",
                "med:mentioned:Neurology:Epilepsy:cenobamate",
            ]),
            progress: .init(),
            lifestyle: .init(tags: ["med_onfile:atorvastatin", "med_archetype:Neurology"]),
            medicationLayer: MedicationContextLayer(
                onFile: [onFile],
                mentioned: [mentioned],
                archetypes: ["Cardiovascular", "Neurology"],
                diseases: ["Epilepsy", "High cholesterol"]
            )
        )
        payload = AriaOnDeviceHealthPolicy.strippedForRemoteInference(payload)
        XCTAssertEqual(payload.medicationLayer?.onFile.count, 0)
        XCTAssertEqual(payload.medicationLayer?.mentioned.count, 1)
        XCTAssertEqual(payload.medicationLayer?.mentioned.first?.generic, "cenobamate")
        XCTAssertFalse(payload.profile.constraints.contains { $0.hasPrefix("med:health:") })
        XCTAssertTrue(payload.profile.constraints.contains { $0.hasPrefix("med:mentioned:") })
        XCTAssertFalse(payload.lifestyle.tags.contains { $0.hasPrefix("med_onfile:") })
        XCTAssertTrue(payload.lifestyle.tags.contains("med_archetype:Neurology"))
    }
}
