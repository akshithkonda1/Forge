import XCTest
@testable import ForgeCore

final class LifestyleAssetTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 1
        return cal
    }

    private var pinnedNow: Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 25
        parts.hour = 15
        parts.minute = 0
        return calendar.date(from: parts)!
    }

    func testClassifyTurnsUnstructuredTitlesIntoKinds() {
        XCTAssertEqual(LifestyleAssetIndex.classify(title: "Maya and Jordan's wedding"), .wedding)
        XCTAssertEqual(LifestyleAssetIndex.classify(title: "Flight to Denver"), .flight)
        XCTAssertEqual(LifestyleAssetIndex.classify(title: "Trip — Denver"), .travel)
        XCTAssertEqual(LifestyleAssetIndex.classify(title: "Raptors vs Celtics"), .game)
        XCTAssertEqual(LifestyleAssetIndex.classify(title: "Dinner at Bar Isabel"), .dinner)
        XCTAssertEqual(LifestyleAssetIndex.classify(title: "Dentist"), .appointment)
        XCTAssertEqual(LifestyleAssetIndex.classify(title: "Standup"), .work)
        XCTAssertEqual(LifestyleAssetIndex.classify(title: "Stay at citizenM Chicago Downtown"), .travel)
        XCTAssertEqual(LifestyleAssetIndex.classify(title: "SRE interview at Cisco"), .work)
        XCTAssertTrue(LifestyleAssetIndex.isInterviewHold(title: "SRE interview at Cisco"))
        XCTAssertTrue(LifestyleAssetIndex.isInterviewHold(title: "Phone screen with recruiter"))
        XCTAssertFalse(LifestyleAssetIndex.isInterviewHold(title: "Standup"))
        XCTAssertNil(LifestyleAssetIndex.classify(title: "Random hold"))
    }

    func testWorkingSetSortsHeadlinesFirstAndKeepsTitlesOffTags() {
        let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        let assets = LifestyleAssetIndex.workingSet(
            from: pack, now: pinnedNow, calendar: calendar
        )
        XCTAssertFalse(assets.isEmpty)
        let buckets = Set(assets.map(\.bucket))
        XCTAssertTrue(buckets.contains(.wedding) || assets.contains { $0.kind == .travel || $0.kind == .flight || $0.kind == .game })
        XCTAssertTrue(LifestyleAssetIndex.titlesStayOnDevice(assets))
        let grouped = LifestyleAssetIndex.grouped(assets)
        XCTAssertFalse(grouped.isEmpty)
        if let firstHeadline = assets.first(where: \.isHeadline),
           let firstOrdinary = assets.first(where: { !$0.isHeadline }) {
            let sorted = LifestyleAssetIndex.sort([firstOrdinary, firstHeadline])
            XCTAssertEqual(sorted.first?.id, firstHeadline.id)
        }
        let spoken = LifestyleAssetIndex.spokenInventory(assets)
        XCTAssertNotNil(spoken)
        XCTAssertTrue(spoken?.contains("I keep the titles on the phone") == true)
        for asset in assets {
            XCTAssertFalse(spoken?.contains(asset.title) == true && !asset.title.isEmpty)
        }
    }

    func testEventKitFieldsClassifyWithoutForgeMarkers() {
        let start = pinnedNow.addingTimeInterval(3 * 86_400)
        let asset = LifestyleAssetIndex.fromCalendarFields(
            title: "Flight to Lisbon",
            placeName: "YYZ",
            start: start,
            end: start.addingTimeInterval(7200),
            isAllDay: false,
            notes: nil,
            url: nil,
            now: pinnedNow,
            calendar: calendar
        )
        XCTAssertEqual(asset?.kind, .flight)
        XCTAssertEqual(asset?.bucket, .travel)
        XCTAssertEqual(asset?.daysUntil, 3)
        XCTAssertEqual(asset?.title, "Flight to Lisbon")
        XCTAssertEqual(asset?.structuredSummary, "a flight in 3 days")
        XCTAssertFalse(asset?.structuredSummary.contains("Lisbon") == true)
        XCTAssertFalse(asset?.structuredSummary.contains("YYZ") == true)
    }

    func testHorizonTagsFromAssetsNeverCarryTitles() {
        let start = pinnedNow.addingTimeInterval(12 * 86_400)
        let wedding = FakeCalendarEvent(
            kind: .wedding,
            title: "Priya's wedding",
            placeName: "The Evergreen Room",
            latitude: 0,
            longitude: 0,
            start: start,
            end: start.addingTimeInterval(10_800)
        )
        let assets = [LifestyleAssetIndex.from(event: wedding, now: pinnedNow, calendar: calendar)]
        let tags = LifestyleAssetIndex.ingestTags(from: assets)
        XCTAssertEqual(tags, ["calendar:horizon:wedding:12"])
        XCTAssertTrue(LifestyleAssetIndex.titlesStayOnDevice(assets))
    }

    func testFarTravelStaysOnTheBoardWithoutReshapingTraining() throws {
        let start = pinnedNow.addingTimeInterval(60 * 86_400)
        let stay = LifestyleAssetIndex.fromCalendarFields(
            title: "Stay at citizenM Chicago Downtown",
            placeName: "Chicago",
            start: start,
            end: start.addingTimeInterval(4 * 86_400),
            isAllDay: true,
            notes: nil,
            url: nil,
            now: pinnedNow,
            calendar: calendar
        )
        let asset = try XCTUnwrap(stay)
        XCTAssertEqual(asset.kind, .travel)
        XCTAssertEqual(asset.daysUntil, 60)
        XCTAssertTrue(LifestyleAssetIndex.isInWorkingSet(asset))
        XCTAssertTrue(LifestyleAssetIndex.ingestTags(from: [asset]).isEmpty)
        XCTAssertTrue(LifestyleAssetIndex.titlesStayOnDevice([asset]))
        let spoken = LifestyleAssetIndex.spokenInventory([asset])
        XCTAssertTrue(spoken?.contains("60 days") == true)
        XCTAssertFalse(spoken?.localizedCaseInsensitiveContains("citizenM") == true)
        XCTAssertFalse(spoken?.localizedCaseInsensitiveContains("Chicago") == true)
    }

    func testInterviewHoldIsFlaggedAtIngestWithoutLeakingTheTitle() {
        let start = pinnedNow.addingTimeInterval(2 * 86_400)
        let asset = LifestyleAssetIndex.fromCalendarFields(
            title: "SRE interview at Cisco",
            placeName: "Zoom",
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false,
            notes: nil,
            url: nil,
            now: pinnedNow,
            calendar: calendar
        )
        XCTAssertEqual(asset?.kind, .work)
        XCTAssertEqual(asset?.isInterview, true)
        XCTAssertEqual(asset?.structuredSummary, "a work block in 2 days")
        XCTAssertFalse(asset?.structuredSummary.contains("Cisco") == true)
        XCTAssertFalse(asset?.structuredSummary.contains("Zoom") == true)
    }
}
