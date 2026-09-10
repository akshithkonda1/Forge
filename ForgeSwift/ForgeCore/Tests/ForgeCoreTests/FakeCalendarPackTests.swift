import XCTest
@testable import ForgeCore

final class FakeCalendarPackTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 1
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
        XCTAssertEqual(FakeCalendarPack.horizonDays, 365)
    }

    func testYearLooksLikeAPhoneNotAStickerWeek() throws {
        let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        let kinds = Set(pack.events.map(\.kind))
        XCTAssertTrue(kinds.contains(.wedding))
        XCTAssertTrue(kinds.contains(.game))
        XCTAssertTrue(kinds.contains(.travel))
        XCTAssertTrue(kinds.contains(.flight))
        XCTAssertTrue(kinds.contains(.work))
        XCTAssertGreaterThanOrEqual(pack.events.count, 120, "a year on a real phone is denser than two sticker weeks")
        XCTAssertGreaterThanOrEqual(pack.events.filter { $0.kind == .work }.count, 40)
        XCTAssertTrue(pack.events.contains { $0.isAllDay && $0.kind == .travel })
        XCTAssertTrue(pack.events.allSatisfy { $0.end > $0.start })
        XCTAssertTrue(pack.events.contains { !$0.placeName.isEmpty })
        let last = try XCTUnwrap(pack.events.last)
        XCTAssertGreaterThanOrEqual(
            FakeCalendarPack.dayOffset(of: last, from: pinnedNow, calendar: calendar),
            300,
            "the pack must cover a year, not a fortnight"
        )
        let window = FakeCalendarPack.weekWindow(containing: pinnedNow, calendar: calendar)
        XCTAssertGreaterThanOrEqual(pack.events.filter { $0.start >= window.start }.count, pack.events.count - 8)
        let ctx = FakeCalendarPack.weekContext(from: pack, now: pinnedNow, calendar: calendar)
        XCTAssertGreaterThanOrEqual(ctx.weekBusy, 3, "this week still has to look like a phone")
        XCTAssertFalse(ctx.kinds.isEmpty)
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
            "different seeds must not reprint the same year"
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

    func testIngestTagsAreThisWeekOnlyAndNeverContainTitles() {
        let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        let ctx = FakeCalendarPack.weekContext(from: pack, now: pinnedNow, calendar: calendar)
        let tags = ctx.ingestTags
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
        XCTAssertTrue(tags.contains { $0.hasPrefix("calendar:week:busy:") })
        XCTAssertEqual(Set(FakeCalendarPack.kinds(fromTags: tags)), Set(ctx.kinds))
        XCTAssertTrue(tags.allSatisfy(FakeCalendarPack.isAllowedIngestTag))
        if !ctx.kinds.contains(.wedding) {
            XCTAssertFalse(tags.contains("calendar:kind:wedding"))
        }
        XCTAssertTrue(pack.events.contains { $0.kind == .wedding })
        XCTAssertTrue(pack.events.contains { $0.kind == .travel })
    }

    func testWeekContextIgnoresTheRestOfTheYear() throws {
        let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        let wedding = try XCTUnwrap(pack.events.first { $0.kind == .wedding })
        let weddingTags = FakeCalendarPack.ingestTags(from: pack, now: wedding.start, calendar: calendar)
        XCTAssertTrue(weddingTags.contains("calendar:kind:wedding"))

        let window = FakeCalendarPack.weekWindow(containing: pinnedNow, calendar: calendar)
        let thisWeek = FakeCalendarPack.events(in: pack, overlapping: window.start, end: window.end)
        let thisWeekKinds = Set(thisWeek.map(\.kind))
        let nowTags = FakeCalendarPack.ingestTags(from: pack, now: pinnedNow, calendar: calendar)
        XCTAssertEqual(Set(FakeCalendarPack.kinds(fromTags: nowTags)), thisWeekKinds)

        let later = calendar.date(byAdding: .day, value: 21, to: pinnedNow)!
        let laterTags = FakeCalendarPack.ingestTags(from: pack, now: later, calendar: calendar)
        XCTAssertNotEqual(
            nowTags.sorted(),
            laterTags.sorted(),
            "ARIA must contextualize a different week three weeks out"
        )
    }

    func testSanitizeDropsTitleTagsKeepsWeekBusy() {
        let dirty = [
            "calendar:busy:2",
            "calendar:week:busy:11",
            "calendar:kind:wedding",
            "calendar:title:Jordan & Alex's wedding",
            "calendar:attendee:maya@example.com",
            "calendar:kind:not-a-kind",
            "calendar:week:title:Jordan",
            "felt:steady",
        ]
        let clean = FakeCalendarPack.sanitizeTags(dirty)
        XCTAssertEqual(clean, ["calendar:busy:2", "calendar:week:busy:11", "calendar:kind:wedding"])
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

    func testSpokenLineUsesKindsNotTitlesOrPlaces() throws {
        let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        let wedding = try XCTUnwrap(pack.events.first { $0.kind == .wedding })
        let tags = FakeCalendarPack.ingestTags(from: pack, now: wedding.start, calendar: calendar)
        let line = try XCTUnwrap(FakeCalendarPack.spokenLine(fromTags: tags))
        let lower = line.lowercased()
        XCTAssertTrue(lower.contains("wedding"))
        XCTAssertTrue(lower.contains("week"))
        XCTAssertTrue(lower.contains("titles") || lower.contains("phone"))
        XCTAssertFalse(lower.contains("jordan"))
        XCTAssertFalse(lower.contains("osteria"))
        XCTAssertFalse(lower.contains("harbor hall"))
        XCTAssertFalse(lower.contains("standup"))
    }

    func testContextualizeReadsAndThinksAboutThisWeek() throws {
        let line = try XCTUnwrap(
            FakeCalendarPack.contextualizeLine(fromTags: [
                "calendar:kind:wedding",
                "calendar:kind:travel",
                "calendar:busy:3",
                "calendar:week:busy:9",
                "calendar:evening:busy",
            ])
        )
        let lower = line.lowercased()
        XCTAssertTrue(lower.contains("wedding") || lower.contains("trip") || lower.contains("travel"))
        XCTAssertTrue(lower.contains("week"))
        XCTAssertTrue(
            lower.contains("hero")
                || lower.contains("move")
                || lower.contains("train around")
                || lower.contains("spoken for"),
            "ARIA must think about the week, not only list kinds: \(line)"
        )
        XCTAssertFalse(lower.contains("jordan"))
        XCTAssertTrue(lower.contains("titles") || lower.contains("phone"))
    }

    func testSessionFitChangesWhatARIAShouldDo() {
        let wedding = FakeCalendarPack.sessionFitLine(fromTags: [
            "calendar:kind:wedding", "calendar:busy:1",
        ])
        XCTAssertTrue(wedding?.localizedCaseInsensitiveContains("wedding") == true)

        let eveningFit = FakeCalendarPack.sessionFitLine(fromTags: [
            "calendar:evening:busy", "calendar:busy:2",
        ])
        XCTAssertTrue(eveningFit?.localizedCaseInsensitiveContains("evening") == true)

        let morning = FakeCalendarPack.sessionFitLine(fromTags: [
            "calendar:morning:busy", "calendar:busy:2",
        ])
        XCTAssertTrue(morning?.localizedCaseInsensitiveContains("morning") == true)

        let stacked = FakeCalendarPack.thinkingLine(fromTags: [
            "calendar:week:busy:11", "calendar:busy:1",
        ])
        XCTAssertTrue(stacked?.localizedCaseInsensitiveContains("week") == true)

        let travelOnly = FakeCalendarPack.outcome(fromTags: [
            "calendar:kind:travel", "calendar:busy:1", "calendar:week:busy:4",
        ])
        let travelAndWedding = FakeCalendarPack.outcome(fromTags: [
            "calendar:kind:travel",
            "calendar:kind:wedding",
            "calendar:busy:3",
            "calendar:week:busy:9",
            "calendar:evening:busy",
        ])
        XCTAssertEqual(travelOnly.shape, .movable)
        XCTAssertEqual(travelAndWedding.shape, .movable)
        XCTAssertNotEqual(travelOnly.thinkingLine, travelAndWedding.thinkingLine)
        XCTAssertTrue(travelAndWedding.keepLight)
        XCTAssertTrue(travelAndWedding.shorten)
        XCTAssertLessThan(travelAndWedding.maxMinutes, travelOnly.maxMinutes)
        XCTAssertTrue(travelAndWedding.thinkingLine?.localizedCaseInsensitiveContains("wedding") == true)
        XCTAssertTrue(travelAndWedding.thinkingLine?.localizedCaseInsensitiveContains("move") == true)
        XCTAssertTrue(travelAndWedding.thinkingLine?.localizedCaseInsensitiveContains("hero") == true)

        let eveningWindow = FakeCalendarPack.outcome(fromTags: [
            "calendar:evening:busy", "calendar:busy:2", "calendar:week:busy:5",
        ])
        XCTAssertEqual(eveningWindow.shape, .aroundWindow)
        XCTAssertTrue(eveningWindow.shorten)
        XCTAssertNotEqual(eveningWindow.shape, travelOnly.shape)
        XCTAssertNotEqual(eveningWindow.thinkingLine, travelAndWedding.thinkingLine)
    }

    func testDifferentWeeksYieldDifferentOutcomes() throws {
        let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        let nowCtx = FakeCalendarPack.weekContext(from: pack, now: pinnedNow, calendar: calendar)
        let window = FakeCalendarPack.weekWindow(containing: pinnedNow, calendar: calendar)
        let otherWedding = try XCTUnwrap(
            pack.events.first { event in
                event.kind == .wedding && (event.end <= window.start || event.start >= window.end)
            }
        )
        let weddingCtx = FakeCalendarPack.weekContext(from: pack, now: otherWedding.start, calendar: calendar)
        XCTAssertNotEqual(
            nowCtx.weekStart,
            weddingCtx.weekStart,
            "ARIA's working memory is a week, not the year"
        )
        XCTAssertTrue(weddingCtx.kinds.contains(.wedding))
        XCTAssertTrue(weddingCtx.ingestTags.contains("calendar:kind:wedding"))
        XCTAssertTrue(weddingCtx.outcome.thinkingLine?.localizedCaseInsensitiveContains("wedding") == true)
        XCTAssertTrue(weddingCtx.outcome.changesSession)
        if !nowCtx.kinds.contains(.wedding) {
            XCTAssertFalse(nowCtx.ingestTags.contains("calendar:kind:wedding"))
            XCTAssertFalse(
                nowCtx.outcome.thinkingLine?.localizedCaseInsensitiveContains("wedding") == true,
                "this week must not think about another week's wedding"
            )
        }

        let otherTravel = try XCTUnwrap(
            pack.events.first { event in
                event.kind == .travel
                    && (event.end <= window.start || event.start >= window.end)
                    && (event.end <= weddingCtx.weekStart || event.start >= weddingCtx.weekEnd)
            }
        )
        let travelCtx = FakeCalendarPack.weekContext(from: pack, now: otherTravel.start, calendar: calendar)
        XCTAssertTrue(travelCtx.kinds.contains(.travel) || travelCtx.kinds.contains(.flight))
        XCTAssertEqual(travelCtx.outcome.shape, .movable)
        XCTAssertTrue(
            travelCtx.outcome.thinkingLine?.localizedCaseInsensitiveContains("travel") == true
                || travelCtx.outcome.thinkingLine?.localizedCaseInsensitiveContains("trip") == true
                || travelCtx.outcome.thinkingLine?.localizedCaseInsensitiveContains("move") == true
        )
        if !travelCtx.kinds.contains(.wedding) {
            XCTAssertNotEqual(
                travelCtx.outcome.thinkingLine,
                weddingCtx.outcome.thinkingLine,
                "a trip week and a wedding week must not produce the same coaching thought"
            )
        }
    }

    func testGuaranteesHoldAcrossManySeeds() {
        for seed in stride(from: 1, through: 400, by: 7) {
            let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: seed)
            let kinds = Set(pack.events.map(\.kind))
            XCTAssertTrue(kinds.contains(.wedding), "seed \(seed) lost the wedding")
            XCTAssertTrue(kinds.contains(.game), "seed \(seed) lost the game")
            XCTAssertTrue(kinds.contains(.travel), "seed \(seed) lost the trip")
            XCTAssertTrue(kinds.contains(.flight), "seed \(seed) lost the flight")
            XCTAssertGreaterThanOrEqual(pack.events.count, 80, "seed \(seed) too thin to test a year")
            XCTAssertTrue(pack.events.allSatisfy { $0.end > $0.start }, "seed \(seed) inverted an event")
            let last = pack.events.last!
            XCTAssertGreaterThanOrEqual(
                FakeCalendarPack.dayOffset(of: last, from: pinnedNow, calendar: calendar),
                280,
                "seed \(seed) did not fill a year"
            )
            let ctx = FakeCalendarPack.weekContext(from: pack, now: pinnedNow, calendar: calendar)
            XCTAssertEqual(
                Set(FakeCalendarPack.kinds(fromTags: ctx.ingestTags)),
                Set(ctx.kinds),
                "seed \(seed) leaked kinds from outside this week"
            )
            let blob = ctx.ingestTags.joined(separator: " ").lowercased()
            for event in pack.events where event.title.count >= 6 {
                XCTAssertFalse(blob.contains(event.title.lowercased()), "seed \(seed) leaked \(event.title)")
            }
            XCTAssertGreaterThanOrEqual(ctx.weekBusy, 1, "seed \(seed) left this week empty")
            XCTAssertTrue(ctx.outcome.changesSession || ctx.weekBusy >= 3, "seed \(seed) gave ARIA nothing to think about")
            if let think = ctx.outcome.thinkingLine {
                let lower = think.lowercased()
                XCTAssertFalse(lower.contains("jordan"), "seed \(seed) thought a title")
                XCTAssertFalse(lower.contains("osteria"), "seed \(seed) thought a place")
                XCTAssertFalse(lower.contains("@"))
            }
        }
    }

    func testWorkLandsOnWeekdaysAndStoryEventsHavePlaces() throws {
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

    func testMergeKeepsMemoryWeekWhenEventKitIsEmpty() {
        let memory = FakeCalendarPack.weekContext(
            from: FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 3),
            now: pinnedNow,
            calendar: calendar
        )
        let merged = FakeCalendarPack.mergeWeekContexts(eventKit: nil, memory: memory)
        XCTAssertEqual(merged, memory)
        XCTAssertNil(FakeCalendarPack.mergeWeekContexts(eventKit: nil, memory: nil))
    }

    func testMergePrefersTheBusierDayWithoutLosingKinds() throws {
        let window = FakeCalendarPack.weekWindow(containing: pinnedNow, calendar: calendar)
        let eventKit = FakeCalendarWeekContext(
            weekStart: window.start,
            weekEnd: window.end,
            todayBusy: 1,
            weekBusy: 4,
            morningBusy: false,
            eveningBusy: true,
            allDayBusy: false,
            kinds: [.game],
            todayKinds: [.game]
        )
        let memory = FakeCalendarWeekContext(
            weekStart: window.start,
            weekEnd: window.end,
            todayBusy: 3,
            weekBusy: 2,
            morningBusy: true,
            eveningBusy: false,
            allDayBusy: true,
            kinds: [.travel],
            todayKinds: [.travel]
        )
        let merged = try XCTUnwrap(FakeCalendarPack.mergeWeekContexts(eventKit: eventKit, memory: memory))
        XCTAssertEqual(merged.todayBusy, 3)
        XCTAssertEqual(merged.weekBusy, 4)
        XCTAssertTrue(merged.morningBusy)
        XCTAssertTrue(merged.eveningBusy)
        XCTAssertTrue(merged.allDayBusy)
        XCTAssertEqual(Set(merged.kinds), Set([.game, .travel]))
        XCTAssertEqual(Set(merged.todayKinds), Set([.game, .travel]))
        XCTAssertTrue(merged.ingestTags.contains("calendar:kind:game"))
        XCTAssertTrue(merged.ingestTags.contains("calendar:kind:travel"))
    }

    func testHorizonTagsAreKindAndDaysUntilNeverTitles() {
        let pack = FakeCalendarPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        let tags = FakeCalendarPack.horizonTags(
            events: pack.events,
            now: pinnedNow,
            calendar: calendar,
            withinDays: 21
        )
        XCTAssertTrue(tags.allSatisfy { $0.hasPrefix("calendar:horizon:") })
        XCTAssertTrue(tags.allSatisfy(FakeCalendarPack.isAllowedIngestTag))
        let blob = tags.joined(separator: " ").lowercased()
        for event in pack.events where event.title.count >= 6 {
            XCTAssertFalse(blob.contains(event.title.lowercased()), "horizon leaked \(event.title)")
        }
        let combined = FakeCalendarPack.ingestTags(from: pack, now: pinnedNow, calendar: calendar)
        XCTAssertTrue(combined.contains { $0.hasPrefix("calendar:horizon:") || $0.hasPrefix("calendar:kind:") })
        XCTAssertTrue(combined.allSatisfy(FakeCalendarPack.isAllowedIngestTag))
    }
}
