import XCTest
@testable import ForgeCore

final class TranslationCatalogTests: XCTestCase {

    func testEveryPillarHasExactlyFourBullets() {
        XCTAssertEqual(TranslationCatalog.all.count, 6)
        for pillar in TranslationCatalog.all {
            XCTAssertEqual(pillar.bullets.count, 4, pillar.id)
            XCTAssertFalse(pillar.title.isEmpty, pillar.id)
            XCTAssertFalse(pillar.symbolName.isEmpty, pillar.id)
        }
    }

    func testMetabolicIsHonestAboutSoldSeparately() {
        let note = TranslationCatalog.metabolic.accessoryNote ?? ""
        XCTAssertTrue(note.localizedCaseInsensitiveContains("sold separately"))
        XCTAssertTrue(note.localizedCaseInsensitiveContains("stelo"))
        XCTAssertTrue(note.localizedCaseInsensitiveContains("apple health"))
        XCTAssertEqual(
            HealthDeviceCatalog.device(matching: "dexcom-stelo")?.soldSeparatelyNote,
            TranslationCatalog.metabolicAccessoryNote
        )
        XCTAssertNil(HealthDeviceCatalog.device(matching: "oura-ring-4")?.soldSeparatelyNote)
        for id in ["dexcom", "dexcom-stelo", "abbott-lingo", "abbott-libre"] {
            let summary = HealthDeviceCatalog.device(matching: id)?.summary ?? ""
            XCTAssertTrue(summary.localizedCaseInsensitiveContains("sold separately"), id)
        }
    }

    func testCycleDoesNotShrinkToPeriodPrediction() {
        let text = TranslationCatalog.cycle.bullets.joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("range"))
        XCTAssertTrue(text.contains("support"))
        XCTAssertTrue(text.contains("phase"))
        XCTAssertFalse(text.contains("natural cycles"))
        XCTAssertFalse(text.contains("predict"))
    }

    func testCopyNeverSellsAMembershipOrDiagnoses() {
        let blob = (
            TranslationCatalog.tagline + " " +
            TranslationCatalog.all.flatMap(\.bullets).joined(separator: " ") + " " +
            (TranslationCatalog.metabolic.accessoryNote ?? "")
        ).lowercased()
        for banned in ["$5.99", "membership", "diagnos", "disease", "paywall"] {
            XCTAssertFalse(blob.contains(banned), banned)
        }
        XCTAssertTrue(TranslationCatalog.tagline.contains("Forge translates"))
    }

    func testLookupByID() {
        XCTAssertEqual(TranslationCatalog.pillar(id: "heart")?.title, "Heart")
        XCTAssertNil(TranslationCatalog.pillar(id: "oura"))
    }
}
