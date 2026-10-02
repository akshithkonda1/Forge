import XCTest
@testable import ForgeCore

/// Same fixtures as backend/ai/simrunner/tests/test_web_research.py.
final class AriaWebEvidenceTests: XCTestCase {

    private let medline = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <nlmSearchResult><term>creatine</term><count>1</count>
    <list num="1" start="0" per="2">
    <document rank="0" url="https://medlineplus.gov/dietarysupplements.html">
    <content name="title">Dietary &lt;span class="qt0"&gt;Supplements&lt;/span&gt;</content>
    <content name="FullSummary">&lt;p&gt;Dietary supplements are vitamins, minerals, herbs and other substances.&lt;/p&gt;&lt;p&gt;Talk with your health care provider first.&lt;/p&gt;</content>
    </document>
    <document rank="1" url="http://insecure.example/x"><content name="title">X</content><content name="FullSummary">Y</content></document>
    </list></nlmSearchResult>
    """.utf8)

    func testMedlinePlus() {
        let rows = AriaWebParsers.medlinePlus(medline)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "Dietary Supplements")
        XCTAssertFalse(rows.first?.summary.contains("<p>") ?? true)
        XCTAssertTrue(AriaWebParsers.medlinePlus(Data("<not xml".utf8)).isEmpty)
    }

    func testPubMed() {
        let ids = Data(#"{"header":{},"esearchresult":{"count":"2","idlist":["111","222"]}}"#.utf8)
        XCTAssertEqual(AriaWebParsers.pubmedIDs(ids), ["111", "222"])
        let summary = Data(#"{"result":{"uids":["111"],"111":{"title":"Creatine and sleep deprivation.","source":"Sci Rep","pubdate":"2024 Feb 1"}}}"#.utf8)
        let rows = AriaWebParsers.pubmedSummaries(summary)
        XCTAssertEqual(rows.first?.url, "https://pubmed.ncbi.nlm.nih.gov/111/")
        XCTAssertEqual(rows.first?.year, "2024")
        XCTAssertTrue(AriaWebParsers.pubmedIDs(Data("{}".utf8)).isEmpty)
    }

    func testOpenFDA() {
        let label = Data(#"{"results":[{"indications_and_usage":["Temporarily relieves minor aches."],"warnings":["Stomach bleeding warning."],"openfda":{"generic_name":["IBUPROFEN"]}}]}"#.utf8)
        let parsed = AriaWebParsers.openFDALabel(label)
        XCTAssertEqual(parsed?.name, "IBUPROFEN")
        XCTAssertTrue(parsed?.warnings.contains("bleeding") ?? false)
        XCTAssertNil(AriaWebParsers.openFDALabel(Data(#"{"results":[]}"#.utf8)))
    }

    func testEnvironment() {
        let forecast = Data(#"{"current":{"time":"2026-09-30T14:00","temperature_2m":33.1,"apparent_temperature":37.4,"precipitation":0.0,"uv_index":8.5,"is_day":1}}"#.utf8)
        let air = Data(#"{"current":{"time":"2026-09-30T14:00","us_aqi":112,"pm2_5":40.2}}"#.utf8)
        let env = AriaWebParsers.environment(forecast: forecast, air: air)
        XCTAssertEqual(env?.apparentTempC, 37.4)
        XCTAssertEqual(env?.usAQI, 112)
        XCTAssertEqual(env?.isDay, true)
        XCTAssertTrue((env?.hot ?? false) && (env?.smoky ?? false) && (env?.harshSun ?? false))
        XCTAssertNil(AriaWebParsers.environment(forecast: nil, air: Data("junk".utf8)))
    }

    func testScoutBrief() {
        let brief = Data(#"{"answer":"Most adults need seven or more hours.","confidence":0.8,"sources":[{"title":"CDC","url":"https://www.cdc.gov/sleep"},{"url":"http://bad"}]}"#.utf8)
        let evidence = AriaWebParsers.scoutBrief(brief)
        XCTAssertEqual(evidence?.via, .scout)
        XCTAssertEqual(evidence?.sources.count, 1)
        XCTAssertTrue(evidence?.cite.hasPrefix("From cdc.gov:") ?? false)
        XCTAssertNil(AriaWebParsers.scoutBrief(Data(#"{"answer":"x","sources":[]}"#.utf8)))
        XCTAssertNil(AriaWebParsers.scoutBrief(Data(#"{"answer":""}"#.utf8)))
    }
}
