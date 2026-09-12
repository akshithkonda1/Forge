import XCTest
@testable import ForgeCore

final class AriaReferenceCatalogTests: XCTestCase {

    func testFeverQuestionOverridesTrainingDomain() {
        let topic = AriaReferenceCatalog.resolvedTopic(
            domainRawValue: "training",
            question: "is a 100.8 temperature too high to lift"
        )
        XCTAssertEqual(topic, .fever)
    }

    func testSameQuestionDifferentSaltRotatesPrimarySource() {
        let urls = [UInt64]([1, 2, 3, 7, 11, 42, 99]).compactMap {
            AriaReferenceCatalog.picks(topic: .fever, question: "is a fever dangerous", salt: $0)
                .first?.source.url
        }
        XCTAssertGreaterThan(Set(urls).count, 1, "session salt must rotate the first page")
    }

    func testDifferentQuestionsGetDifferentExcerptWindows() {
        let starts = [
            "how much sleep do I need",
            "why do I wake at 3am",
            "is melatonin safe",
            "what is a sleep debt",
        ].map {
            AriaReferenceCatalog.picks(topic: .sleep, question: $0, salt: 7).first?.excerptStart
        }
        XCTAssertGreaterThan(Set(starts.compactMap { $0 }).count, 1)
    }

    func testProteinKeywordOverlaysNutritionOntoTraining() {
        let picks = AriaReferenceCatalog.picks(
            topic: .training,
            question: "how much protein should I eat to recomp",
            salt: 3,
            limit: 8
        )
        XCTAssertTrue(picks.contains { $0.source.url.contains("ods.od.nih.gov") })
    }

    func testHighBitSaltDoesNotTrapWhenPickingWindows() {
        let picks = AriaReferenceCatalog.picks(
            topic: .sleep,
            question: "why do I wake at 3am",
            salt: .max
        )
        XCTAssertFalse(picks.isEmpty)
        XCTAssertTrue([0, 180, 360, 540].contains(picks[0].excerptStart))
    }

    func testStableMixIsDeterministic() {
        XCTAssertEqual(
            AriaReferenceCatalog.stableMix("Hello", salt: 42),
            AriaReferenceCatalog.stableMix("hello", salt: 42)
        )
        XCTAssertNotEqual(
            AriaReferenceCatalog.stableMix("hello", salt: 1),
            AriaReferenceCatalog.stableMix("hello", salt: 2)
        )
    }

    func testEveryTopicHasAtLeastOneHTTPSGovOrMedlinePlusURL() {
        for topic in AriaReferenceTopic.allCases {
            let sources = AriaReferenceCatalog.sources[topic] ?? []
            XCTAssertFalse(sources.isEmpty, "\(topic) has no sources")
            for source in sources {
                XCTAssertTrue(source.url.hasPrefix("https://"), source.url)
                let host = source.pageURL?.host ?? ""
                XCTAssertTrue(
                    host.contains("cdc.gov")
                        || host.contains("nih.gov")
                        || host.contains("medlineplus.gov")
                        || host.contains("womenshealth.gov")
                        || host.contains("nhlbi.nih.gov")
                        || host.contains("ods.od.nih.gov"),
                    "unexpected host \(host) for \(source.title)"
                )
            }
        }
    }

    func testTuxedoQuestionOverlaysLifestylePublicHealthPages() {
        XCTAssertTrue(
            AriaReferenceCatalog.questionSuggestsEventPrep(
                "what tuxedo should I wear to a wedding"
            )
        )
        XCTAssertFalse(AriaReferenceCatalog.questionSuggestsEventPrep("what should I train today"))
        let picks = AriaReferenceCatalog.picks(
            topic: .training,
            question: "what tuxedo should I wear to a wedding",
            salt: 3,
            limit: 8
        )
        XCTAssertTrue(picks.contains {
            $0.source.url.contains("medlineplus.gov") || $0.source.url.contains("cdc.gov")
        })
    }
}
