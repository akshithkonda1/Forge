import XCTest
@testable import ForgeCore

final class AriaContextMemoryTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    func testShelvesSplitDreamsSleepAndUserEditsLock() throws {
        XCTAssertEqual(AriaContextMemory.Shelf.allCases.map(\.rawValue), [
            "dreams", "sleep", "hobbies", "people", "goals", "mood",
        ])
        var snap = AriaContextMemory.Snapshot()
        snap = AriaContextMemory.ingest(
            snap, text: "Dream: the hallway again", source: "settings",
            userLocked: true, domainOverride: .sleepDreams
        )
        snap = AriaContextMemory.ingest(
            snap, text: "I slept six hours", source: "settings",
            userLocked: true, domainOverride: .sleepDreams
        )
        let dream = snap.active.first { AriaContextMemory.Shelf.of($0) == .dreams }
        let sleep = snap.active.first { AriaContextMemory.Shelf.of($0) == .sleep }
        XCTAssertNotNil(dream)
        XCTAssertNotNil(sleep)
        let id = try XCTUnwrap(sleep?.id)
        snap = AriaContextMemory.edit(snap, id: id, text: "I slept seven hours")
        XCTAssertTrue(snap.items.contains { $0.id == id && $0.userLocked })
        snap = AriaContextMemory.delete(snap, id: id)
        XCTAssertFalse(snap.active.contains { $0.id == id })
        XCTAssertFalse(snap.tombstones.isEmpty)
        XCTAssertEqual(AriaContextMemory.Shelf.dreams.persistDomain, .sleepDreams)
        XCTAssertEqual(AriaContextMemory.Shelf.sleep.persistDomain, .sleepDreams)
        XCTAssertEqual(AriaContextMemory.Shelf.hobbies.persistDomain, .lifestyleHobbies)
        XCTAssertEqual(AriaContextMemory.Shelf.people.persistDomain, .people)
        XCTAssertEqual(AriaContextMemory.Shelf.goals.persistDomain, .goals)
        XCTAssertEqual(AriaContextMemory.Shelf.mood.persistDomain, .moodMentality)
    }

    func testClassifyDomainsAndDreamsStaySensitive() {
        XCTAssertEqual(AriaContextMemory.classify("I dreamed the hallway flooded"), .sleepDreams)
        XCTAssertEqual(AriaContextMemory.classify("pottery nights"), .lifestyleHobbies)
        XCTAssertEqual(AriaContextMemory.classify("seizures after late nights"), .healthConstraints)
        XCTAssertEqual(AriaContextMemory.classify("this season is sleep"), .goals)
        XCTAssertTrue(AriaContextMemory.Domain.sleepDreams.isSensitive)
        XCTAssertTrue(AriaContextMemory.Domain.healthConstraints.isSensitive)
        XCTAssertFalse(AriaDreamJournal.containsBanned(AriaDreamJournal.researchLine))
        XCTAssertTrue(AriaDreamJournal.researchLine.lowercased().contains("not a diagnosis"))
    }

    func testConsolidateDecaySupersedeAndPagination() {
        var snap = AriaContextMemory.Snapshot(caps: .sane)
        // At most two facts per domain so unused-domain coarsening cannot
        // collapse the page to a single cluster.
        let seeds = [
            "pottery nights on Tuesday",
            "Free day note cooking and quiet stretch",
            "I dreamed the hallway flooded",
            "nightmare about water",
            "this season is sleep",
            "working toward a calmer week",
            "partnered and going out Saturdays",
            "friend visiting next month",
            "lots on lately at work",
            "mood is drained after crowds",
            "seizures after late nights",
            "condition noted with my doctor",
        ]
        for (i, text) in seeds.enumerated() {
            snap = AriaContextMemory.ingest(
                snap,
                text: text,
                source: "chat",
                now: day.addingTimeInterval(Double(i) * 3600)
            )
        }
        snap = AriaContextMemory.ingest(
            snap,
            text: "up for a little more this week",
            source: "chat",
            now: day.addingTimeInterval(50_000)
        )
        XCTAssertTrue(snap.active.contains { $0.text.contains("up for a little more") })
        XCTAssertTrue(snap.items.contains { $0.supersededBy != nil })

        snap = AriaContextMemory.consolidate(snap, now: day.addingTimeInterval(20 * 24 * 3600))
        let page = AriaContextMemory.retrieve(snap, now: day.addingTimeInterval(20 * 24 * 3600), limit: 5)
        XCTAssertLessThanOrEqual(page.items.count, 5)
        XCTAssertGreaterThan(page.total, page.items.count)
        XCTAssertEqual(AriaContextMemory.Caps.sane.stm, 64)
        XCTAssertGreaterThan(AriaContextMemory.Caps.sane.vault, AriaContextMemory.Caps.legacy.vault)
    }

    func testDecayDropsStaleSTMUnlessUserLocked() {
        var snap = AriaContextMemory.Snapshot()
        snap = AriaContextMemory.ingest(snap, text: "old quiet stretch", source: "chat", now: day)
        snap.items[0].confidence = 0.2
        let decayed = AriaContextMemory.decay(snap, now: day.addingTimeInterval(40 * 24 * 3600))
        XCTAssertFalse(decayed.items[0].isActive)

        var locked = snap
        locked.items[0].userLocked = true
        locked.items[0].confidence = 0.9
        let kept = AriaContextMemory.decay(locked, now: day.addingTimeInterval(40 * 24 * 3600))
        XCTAssertTrue(kept.items[0].isActive)
        XCTAssertTrue(kept.items[0].userLocked)
    }

    func testUserEditAndDeleteOverrideLearningAndPropagate() {
        var snap = AriaContextMemory.Snapshot()
        snap = AriaContextMemory.ingest(snap, text: "I like pottery", source: "chat", now: day)
        let id = snap.items[0].id
        for _ in 0..<6 {
            snap = AriaContextMemory.record(snap, itemId: id, kind: .acted, now: day)
        }
        XCTAssertGreaterThan(snap.items[0].signals.learnedRelevance, 0)

        snap = AriaContextMemory.edit(snap, id: id, text: "I like hiking", now: day.addingTimeInterval(60))
        XCTAssertEqual(snap.items[0].text, "I like hiking")
        XCTAssertTrue(snap.items[0].userLocked)
        let explained = AriaContextMemory.explain(snap.items[0], in: snap, now: day)
        XCTAssertGreaterThan(explained.userOverride, 0)
        XCTAssertTrue(explained.formula.contains("learnedRelevance"))

        snap = AriaContextMemory.delete(snap, id: id, now: day.addingTimeInterval(120))
        XCTAssertTrue(snap.items.isEmpty)
        XCTAssertEqual(AriaContextMemory.pendingServerDeletes(snap).map(\.id), [id])
        snap = AriaContextMemory.markServerDeleteReached(snap, id: id)
        XCTAssertTrue(AriaContextMemory.pendingServerDeletes(snap).isEmpty)

        snap = AriaContextMemory.ingest(snap, text: "I like hiking", source: "chat", now: day.addingTimeInterval(180))
        XCTAssertTrue(snap.items.isEmpty, "deletes override learning — same fact must not return")
    }

    func testDreamsRedactedFromServerUnlessOptIn() {
        var snap = AriaContextMemory.Snapshot(share: .onDeviceOnly)
        let dream = AriaDreamJournal.Entry(night: "2026-10-16", note: "The hallway again")
        snap.items.append(AriaDreamJournal.toMemoryItem(dream))
        let hidden = AriaContextMemory.serverContext(snap)
        XCTAssertFalse((hidden["context_summaries"] ?? "").lowercased().contains("dream"))
        XCTAssertTrue(AriaContextMemory.containsSensitiveServerLeak(["x": "dream hallway"], share: .onDeviceOnly))

        snap.share.shareDreams = true
        snap.items[0].shareOptIn = true
        let shown = AriaContextMemory.serverContext(snap)
        XCTAssertTrue((shown["context_summaries"] ?? "").lowercased().contains("dream"))
    }

    func testTwoEngagementHistoriesRankAndRetainDifferently() {
        func seeded() -> AriaContextMemory.Snapshot {
            var snap = AriaContextMemory.Snapshot()
            snap = AriaContextMemory.ingest(snap, text: "pottery nights", source: "chat", now: day)
            snap = AriaContextMemory.ingest(snap, text: "I dreamed of water", source: "dream-journal", now: day)
            return snap
        }
        var hobbies = seeded()
        var dreams = seeded()
        let pottery = hobbies.items.first { $0.domain == .lifestyleHobbies }!
        let hobbyDream = hobbies.items.first { $0.domain == .sleepDreams }!
        let dreamNote = dreams.items.first { $0.domain == .sleepDreams }!
        let dreamPottery = dreams.items.first { $0.domain == .lifestyleHobbies }!

        hobbies = AriaContextMemory.markUsed(hobbies, itemIds: [pottery.id, hobbyDream.id], now: day)
        dreams = AriaContextMemory.markUsed(dreams, itemIds: [dreamNote.id, dreamPottery.id], now: day)
        for _ in 0..<4 {
            hobbies = AriaContextMemory.recordOutcome(hobbies, kind: .replied, itemIds: [pottery.id], now: day)
            hobbies = AriaContextMemory.recordOutcome(hobbies, kind: .acted, itemIds: [pottery.id], now: day)
            hobbies = AriaContextMemory.recordOutcome(hobbies, kind: .ignored, itemIds: [hobbyDream.id], now: day)
        }
        for _ in 0..<4 {
            dreams = AriaContextMemory.recordOutcome(dreams, kind: .replied, itemIds: [dreamNote.id], now: day)
            dreams = AriaContextMemory.recordOutcome(dreams, kind: .ignored, itemIds: [dreamPottery.id], now: day)
        }

        XCTAssertGreaterThan(hobbies.stats[.lifestyleHobbies]?.mentions ?? 0, 0)
        XCTAssertGreaterThan(dreams.stats[.sleepDreams]?.mentions ?? 0, 0)

        XCTAssertGreaterThan(
            AriaContextMemory.retentionPriority(.lifestyleHobbies, in: hobbies),
            AriaContextMemory.retentionPriority(.lifestyleHobbies, in: dreams)
        )
        XCTAssertGreaterThan(
            AriaContextMemory.retentionPriority(.sleepDreams, in: dreams),
            AriaContextMemory.retentionPriority(.sleepDreams, in: hobbies)
        )
        XCTAssertEqual(AriaContextMemory.granularity(.lifestyleHobbies, in: hobbies), .fine)
        XCTAssertEqual(AriaContextMemory.granularity(.lifestyleHobbies, in: dreams), .coarse)
        XCTAssertGreaterThan(
            AriaContextMemory.decayHalfLifeDays(.lifestyleHobbies, in: hobbies),
            AriaContextMemory.decayHalfLifeDays(.lifestyleHobbies, in: dreams)
        )
        let engagedPottery = hobbies.items.first { $0.id == pottery.id }!
        let ignoredPottery = dreams.items.first { $0.id == dreamPottery.id }!
        XCTAssertGreaterThan(
            AriaContextMemory.decayHalfLifeDays(for: engagedPottery, in: hobbies),
            AriaContextMemory.decayHalfLifeDays(for: ignoredPottery, in: dreams)
        )

        let hobbyRank = AriaContextMemory.rank(hobbies, now: day)
        let dreamRank = AriaContextMemory.rank(dreams, now: day)
        XCTAssertEqual(hobbyRank.first?.domain, .lifestyleHobbies)
        XCTAssertEqual(dreamRank.first?.domain, .sleepDreams)
        XCTAssertNotEqual(hobbyRank.map(\.id), dreamRank.map(\.id))

        let hobbyTop = AriaContextMemory.explain(hobbyRank[0], in: hobbies, now: day)
        let hobbySecond = AriaContextMemory.explain(hobbyRank[1], in: hobbies, now: day)
        XCTAssertGreaterThan(hobbyTop.learnedRelevance, hobbySecond.learnedRelevance)
        XCTAssertEqual(hobbyTop.formula, AriaContextMemory.rankFormula)

        hobbies.caps = AriaContextMemory.Caps(stm: 1, vault: 320, userContext: 48, pageSize: 20)
        dreams.caps = AriaContextMemory.Caps(stm: 1, vault: 320, userContext: 48, pageSize: 20)
        let keptHobbies = AriaContextMemory.consolidate(hobbies, now: day)
        let keptDreams = AriaContextMemory.consolidate(dreams, now: day)
        XCTAssertEqual(keptHobbies.active.filter { $0.layer == .stm }.count, 1)
        XCTAssertEqual(keptDreams.active.filter { $0.layer == .stm }.count, 1)
        XCTAssertEqual(keptHobbies.active.first?.domain, .lifestyleHobbies)
        XCTAssertEqual(keptDreams.active.first?.domain, .sleepDreams)
        XCTAssertNotEqual(keptHobbies.active.first?.id, keptDreams.active.first?.id)

        XCTAssertTrue(AriaContextMemory.bedrockOff)
        XCTAssertTrue(AriaContextMemory.backupExcluded)
    }

    func testEngagedDomainKeepsFineGrainOthersCoarsen() {
        func threeHobbies() -> AriaContextMemory.Snapshot {
            var snap = AriaContextMemory.Snapshot()
            snap = AriaContextMemory.ingest(snap, text: "pottery nights", source: "chat", now: day)
            snap = AriaContextMemory.ingest(snap, text: "cooking on a free day", source: "chat", now: day)
            snap = AriaContextMemory.ingest(snap, text: "evening walk after dinner", source: "chat", now: day)
            return snap
        }
        var engaged = threeHobbies()
        var ignored = threeHobbies()
        for item in engaged.items {
            engaged = AriaContextMemory.record(engaged, itemId: item.id, kind: .replied, now: day)
            engaged = AriaContextMemory.record(engaged, itemId: item.id, kind: .acted, now: day)
        }
        for item in ignored.items {
            ignored = AriaContextMemory.record(ignored, itemId: item.id, kind: .ignored, now: day)
        }
        XCTAssertEqual(AriaContextMemory.granularity(.lifestyleHobbies, in: engaged), .fine)
        XCTAssertEqual(AriaContextMemory.granularity(.lifestyleHobbies, in: ignored), .coarse)
        let fine = AriaContextMemory.summarizeClusters(engaged, now: day)
        let coarse = AriaContextMemory.summarizeClusters(ignored, now: day)
        XCTAssertEqual(fine.active.count, 3)
        XCTAssertEqual(coarse.active.count, 1)
        XCTAssertNotNil(coarse.active.first?.summary)
    }

    func testLockedEditSurvivesCapPressureFromLearnedRelevance() {
        var snap = AriaContextMemory.Snapshot(caps: AriaContextMemory.Caps(
            stm: 1, vault: 40, userContext: 8, pageSize: 8
        ))
        snap = AriaContextMemory.ingest(snap, text: "I like pottery", source: "chat", now: day)
        let lockedId = snap.items[0].id
        snap = AriaContextMemory.edit(snap, id: lockedId, text: "I like hiking", now: day)
        snap = AriaContextMemory.ingest(snap, text: "I dreamed of water", source: "dream-journal", now: day)
        let dreamId = snap.items.first { $0.id != lockedId }!.id
        for _ in 0..<8 {
            snap = AriaContextMemory.record(snap, itemId: dreamId, kind: .acted, now: day)
        }
        snap = AriaContextMemory.consolidate(snap, now: day)
        XCTAssertTrue(snap.items.contains { $0.id == lockedId && $0.userLocked })
        XCTAssertEqual(snap.items.first { $0.id == lockedId }?.text, "I like hiking")
    }

    func testOnDeviceStoreRoundTripExcludesBackup() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-memory-\(UUID().uuidString)", isDirectory: true)
        var snap = AriaContextMemory.Snapshot()
        snap = AriaContextMemory.ingest(snap, text: "pottery nights", source: "chat", now: day)
        XCTAssertNotNil(AriaContextMemoryStore.save(snap, to: root))
        let loaded = AriaContextMemoryStore.load(from: root)
        XCTAssertEqual(loaded.items.map(\.text), snap.items.map(\.text))
        XCTAssertTrue(AriaContextMemory.backupExcluded)
        XCTAssertTrue(AriaContextMemory.bedrockOff)
        try? FileManager.default.removeItem(at: root)
    }
}
