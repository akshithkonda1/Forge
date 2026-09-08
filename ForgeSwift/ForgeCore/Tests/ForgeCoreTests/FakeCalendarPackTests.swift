import XCTest
@testable import ForgeCore

final class FakeCalendarPackTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    /// Tuesday 25 Aug 2026, mid-afternoon — same pin as the health pack.
    private var pinnedNow: Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 25
        parts.hour = 15
        parts.minute = 0
        return calendar.date(from: parts)!
    }

    func testShouldSeedNeverInProductionOrTests() {
        XCTAssertTrue(
            FakeCalendarPack.shouldSeed(
                debugBuild: true, testReady: true, calendarAuthorized: true, isRunningTests: false
            )
        )
        XCTAssertFalse(
            FakeCalendarPack.shouldSeed(
                debugBuild: false, testReady: true, calendarAuthorized: true, isRunningTests: false
            ),
            "Release builds must never write the test calendar"
        )
        XCTAssertFalse(
            FakeCalendarPack.shouldSeed(
                debugBuild: true, testReady: false, calendarAuthorized: true, isRunningTests: false
            )
        )
        XCTAssertFalse(
            FakeCalendarPack.shouldSeed(
                debugBuild: true, testReady: true, calendarAuthorized: false, isRunningTests: false
            )
        )
        XCTAssertFalse(
            FakeCalendarPack.shouldSeed(
                debugBuild: true, testReady: true, calendarAuthorized: true, isRunningTests: true
            ),
            "XCTest must not write EventKit"
        )
    }

    func testNeverWritesOntoPersonalCalendars() {
        XCTAssertFalse(FakeCalendarPack.writesToPersonalCalendars)
        XCTAssertEqual(FakeCalendarPack.calendarTitle, "Forge — Test Pack")
        XCTAssertTrue(FakeCalendarPack.eventURL.hasPrefix("forge://test-ready/calendar"))
    }

    func testWeekLooksLikeAPhoneNotASticker() {
        let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        let kinds = Set(pack.events.map(\.kind))
        XCTAssertTrue(kinds.contains(.wedding))
        XCTAssertTrue(kinds.contains(.game))
        XCTAssertTrue(kinds.contains(.travel))
        XCTAssertTrue(kinds.contains(.flight))
        XCTAssertGreaterThanOrEqual(pack.events.count, 12, "a real phone is denser than seven story events")
        XCTAssertGreaterThanOrEqual(pack.events.filter { $0.kind == .work }.count, 3)
        XCTAssertTrue(pack.events.contains { $0.isAllDay && $0.kind == .travel })
        XCTAssertTrue(pack.events.allSatisfy { $0.end > $0.start })
        XCTAssertTrue(pack.events.contains { !$0.placeName.isEmpty })
        XCTAssertTrue(pack.events.allSatisfy { $0.start > pinnedNow || $0.isAllDay })
    }

    func testGenerateIsDeterministicIncludingPlaces() {
        let a = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 7)
        let b = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 7)
        XCTAssertEqual(a.events.map(\.kind), b.events.map(\.kind))
        XCTAssertEqual(a.events.map(\.title), b.events.map(\.title))
        XCTAssertEqual(a.events.map(\.placeName), b.events.map(\.placeName))
        XCTAssertEqual(a.events.map(\.start), b.events.map(\.start))
        XCTAssertEqual(a.events.map(\.latitude), b.events.map(\.latitude))
    }

    func testTimesAndPlacesVaryWithSeedLikeTheHealthPack() {
        let a = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 11)
        let b = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 977)
        let weddingA = a.events.first { $0.kind == .wedding }
        let weddingB = b.events.first { $0.kind == .wedding }
        XCTAssertNotNil(weddingA)
        XCTAssertNotNil(weddingB)
        XCTAssertNotEqual(
            a.events.map(\.start),
            b.events.map(\.start),
            "different seeds must not reprint the same week"
        )
        XCTAssertNotEqual(
            a.events.map(\.placeName),
            b.events.map(\.placeName),
            "places must move with the seed, not just the minutes"
        )
        let offsetA = FakeCalendarPack.dayOffset(of: weddingA!, from: pinnedNow, calendar: calendar)
        let offsetB = FakeCalendarPack.dayOffset(of: weddingB!, from: pinnedNow, calendar: calendar)
        let hourA = calendar.component(.hour, from: weddingA!.start)
        let hourB = calendar.component(.hour, from: weddingB!.start)
        XCTAssertTrue(
            offsetA != offsetB || hourA != hourB || weddingA!.placeName != weddingB!.placeName,
            "the wedding must not always be the same day, hour, and venue"
        )
    }

    func testIngestTagsNeverContainTitlesPlacesOrAttendees() {
        let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        let tags = FakeCalendarPack.ingestTags(from: pack, now: pinnedNow, calendar: calendar)
        let blob = tags.joined(separator: " ").lowercased()
        for event in pack.events {
            XCTAssertFalse(
                blob.contains(event.title.lowercased()),
                "tag leak of title \(event.title) via \(tags)"
            )
            if event.placeName.count >= 4 {
                XCTAssertFalse(
                    blob.contains(event.placeName.lowercased()),
                    "tag leak of place \(event.placeName) via \(tags)"
                )
            }
        }
        XCTAssertFalse(blob.contains("@"))
        XCTAssertFalse(blob.contains("jordan"))
        XCTAssertFalse(blob.contains("osteria"))
        XCTAssertFalse(blob.contains("denver"))
        XCTAssertTrue(tags.contains { $0.hasPrefix("calendar:busy:") })
        XCTAssertTrue(tags.contains("calendar:kind:wedding"))
        XCTAssertTrue(tags.contains("calendar:kind:game"))
        XCTAssertTrue(tags.contains("calendar:kind:travel"))
        XCTAssertTrue(tags.allSatisfy(FakeCalendarPack.isAllowedIngestTag))
    }

    func testSanitizeDropsTitleTags() {
        let dirty = [
            "calendar:busy:2",
            "calendar:kind:wedding",
            "calendar:title:Jordan & Alex's wedding",
            "calendar:attendee:maya@example.com",
            "calendar:kind:not-a-kind",
            "felt:steady",
        ]
        let clean = FakeCalendarPack.sanitizeTags(dirty)
        XCTAssertEqual(clean, ["calendar:busy:2", "calendar:kind:wedding"])
    }

    func testKindFromNotesAndURL() {
        XCTAssertEqual(
            FakeCalendarPack.kind(fromNotes: "forge-test-pack:wedding"),
            .wedding
        )
        XCTAssertEqual(
            FakeCalendarPack.kind(fromURL: URL(string: "forge://test-ready/calendar#game")),
            .game
        )
        XCTAssertNil(FakeCalendarPack.kind(fromNotes: "Lunch with Maya"))
        XCTAssertNil(FakeCalendarPack.kind(fromURL: URL(string: "https://calendar.google.com/event")))
        XCTAssertTrue(
            FakeCalendarPack.isForgeTestEvent(notes: "forge-test-pack:travel", url: nil)
        )
        XCTAssertFalse(
            FakeCalendarPack.isForgeTestEvent(notes: "Dentist", url: URL(string: "https://example.com"))
        )
    }

    func testSpokenLineUsesKindsNotTitlesOrPlaces() {
        let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        let tags = FakeCalendarPack.ingestTags(from: pack, now: pinnedNow, calendar: calendar)
        let line = try XCTUnwrap(FakeCalendarPack.spokenLine(fromTags: tags))
        let lower = line.lowercased()
        XCTAssertTrue(lower.contains("wedding"))
        XCTAssertTrue(lower.contains("game") || lower.contains("trip") || lower.contains("flight"))
        XCTAssertTrue(lower.contains("titles") || lower.contains("phone"))
        XCTAssertFalse(lower.contains("jordan"))
        XCTAssertFalse(lower.contains("osteria"))
        XCTAssertFalse(lower.contains("harbor hall"))
        XCTAssertFalse(lower.contains("standup"))
    }

    func testSessionFitChangesWhatARIAShouldDo() {
        let wedding = FakeCalendarPack.sessionFitLine(fromTags: [
            "calendar:kind:wedding", "calendar:busy:1",
        ])
        XCTAssertTrue(wedding?.localizedCaseInsensitiveContains("wedding") == true)

        let evening = FakeCalendarPack.sessionFitLine(fromTags: [
            "calendar:evening:busy", "calendar:busy:2",
        ])
        XCTAssertTrue(evening?.localizedCaseInsensitiveContains("evening") == true)

        let morning = FakeCalendarPack.sessionFitLine(fromTags: [
            "calendar:morning:busy", "calendar:busy:2",
        ])
        XCTAssertTrue(morning?.localizedCaseInsensitiveContains("morning") == true)
    }

    func testGuaranteesHoldAcrossManySeeds() {
        for seed in stride(from: 1, through: 400, by: 7) {
            let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: seed)
            let kinds = Set(pack.events.map(\.kind))
            XCTAssertTrue(kinds.contains(.wedding), "seed \(seed) lost the wedding")
            XCTAssertTrue(kinds.contains(.game), "seed \(seed) lost the game")
            XCTAssertTrue(kinds.contains(.travel), "seed \(seed) lost the trip")
            XCTAssertTrue(kinds.contains(.flight), "seed \(seed) lost the flight")
            XCTAssertGreaterThanOrEqual(pack.events.count, 10, "seed \(seed) too thin to test ingest")
            XCTAssertTrue(pack.events.allSatisfy { $0.end > $0.start }, "seed \(seed) inverted an event")
            let tags = FakeCalendarPack.ingestTags(from: pack, now: pinnedNow, calendar: calendar)
            let blob = tags.joined(separator: " ").lowercased()
            for event in pack.events where event.title.count >= 6 {
                XCTAssertFalse(blob.contains(event.title.lowercased()), "seed \(seed) leaked \(event.title)")
            }
        }
    }

    func testWorkLandsOnWeekdaysAndStoryEventsHavePlaces() {
        let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        for event in pack.events where event.kind == .work && !event.isAllDay {
            let weekday = calendar.component(.weekday, from: event.start)
            XCTAssertFalse(weekday == 1 || weekday == 7, "work on a weekend: \(event.title)")
            let hour = calendar.component(.hour, from: event.start)
            XCTAssertTrue((8...17).contains(hour), "work at \(hour):00 is not a real office hour")
        }
        let wedding = try XCTUnwrap(pack.events.first { $0.kind == .wedding })
        XCTAssertFalse(wedding.placeName.isEmpty)
        let flight = try XCTUnwrap(pack.events.first { $0.kind == .flight })
        XCTAssertFalse(flight.placeName.isEmpty)
    }
}
