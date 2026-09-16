import XCTest
@testable import ForgeCore

final class AriaMemoryControlsTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "forge.aria.memory.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        suite = nil
        super.tearDown()
    }

    func testManagedFoldersAreTheSevenConsumerVaults() {
        XCTAssertEqual(AriaKnowledgeCategory.managedCases.map(\.title), [
            "Goals", "Identity", "Lifestyle", "Preferences", "Events", "Body notes", "Mood"
        ])
        XCTAssertEqual(AriaKnowledgeCategory.healthHistory.rawValue, "healthHistory")
        XCTAssertEqual(AriaKnowledgeCategory.healthHistory.title, "Body notes")
        XCTAssertFalse(AriaKnowledgeCategory.healthHistory.blurb.localizedCaseInsensitiveContains("health history"))
        XCTAssertTrue(AriaKnowledgeCategory.healthHistory.blurb.localizedCaseInsensitiveContains("qualitative"))
        XCTAssertFalse(AriaKnowledgeCategory.healthHistory.blurb.localizedCaseInsensitiveContains("rem"))
        XCTAssertFalse(AriaKnowledgeCategory.healthHistory.blurb.localizedCaseInsensitiveContains("insomnia"))
        XCTAssertEqual(
            AriaKnowledgeCategory.appleHealth.managedFolder(kind: "sleep"),
            .healthHistory
        )
        XCTAssertEqual(
            AriaKnowledgeCategory.otherData.managedFolder(kind: "calendar_week"),
            .events
        )
        XCTAssertEqual(
            AriaKnowledgeCategory.weSpokeAbout.managedFolder(kind: "weekly_mood"),
            .mood
        )
        XCTAssertEqual(
            AriaKnowledgeCategory.weSpokeAbout.managedFolder(kind: "schedule_goal"),
            .goals
        )
        XCTAssertEqual(
            AriaKnowledgeCategory.weSpokeAbout.managedFolder(kind: "living_hobbies"),
            .identity
        )
        XCTAssertEqual(
            AriaKnowledgeCategory.weSpokeAbout.managedFolder(kind: "chat"),
            .lifestyle
        )
    }

    func testAddEditDeleteRoundTrip() throws {
        var controls = AriaMemoryControls.load(defaults: defaults)
        let added = controls.addFact(
            category: .goals,
            summary: "I want earlier nights.",
            defaults: defaults
        )
        XCTAssertEqual(added?.category, .goals)
        XCTAssertEqual(controls.listedFacts(in: .goals).count, 1)
        let id = try XCTUnwrap(added?.id)
        XCTAssertTrue(controls.updateFact(id: id, summary: "I want 7.5 hours.", defaults: defaults))
        XCTAssertEqual(controls.listedFacts(in: .goals).first?.summary, "I want 7.5 hours.")
        controls.deleteFact(id: id, defaults: defaults)
        XCTAssertTrue(controls.listedFacts(in: .goals).isEmpty)
        XCTAssertTrue(AriaKnowledgeLedgerStore.load(defaults: defaults).facts.isEmpty)
    }

    func testLegacyFactsShowUpInManagedFolders() {
        AriaKnowledgeLedgerStore.file(
            AriaKnowledgeFact(
                category: .appleHealth,
                kind: "sleep",
                summary: "7.6h last night",
                source: "apple-health"
            ),
            defaults: defaults
        )
        let controls = AriaMemoryControls.load(defaults: defaults)
        XCTAssertEqual(controls.listedFacts(in: .healthHistory).first?.summary, "7.6h last night")
        XCTAssertEqual(
            controls.listedFacts(in: .healthHistory).first?.managedFolder,
            .healthHistory
        )
    }

    func testMemoryOffKeepsStorageAndBlocksAutoUse() {
        var controls = AriaMemoryControls.load(defaults: defaults)
        XCTAssertNotNil(controls.addFact(
            category: .lifestyle,
            summary: "Keep this note.",
            defaults: defaults
        ))
        controls.setMemoryEnabled(false, defaults: defaults)
        XCTAssertEqual(controls.listedFacts(in: .lifestyle).map(\.summary), ["Keep this note."])
        XCTAssertTrue(controls.coachingFacts(in: .lifestyle).isEmpty)
        XCTAssertEqual(controls.memoryStatusLine, "Memory off")

        AriaKnowledgeLedgerStore.file(
            AriaKnowledgeFact(
                category: .weSpokeAbout,
                kind: "chat",
                summary: "Auto ingest should miss.",
                source: "chat"
            ),
            defaults: defaults
        )
        AriaKnowledgeLedgerStore.replace(
            category: .otherData,
            source: "calendar",
            with: [
                AriaKnowledgeFact(
                    category: .otherData,
                    kind: "calendar_week",
                    summary: "This week: a wedding.",
                    source: "calendar"
                )
            ],
            defaults: defaults
        )
        controls = AriaMemoryControls.load(defaults: defaults)
        XCTAssertEqual(controls.listedFacts(in: .lifestyle).map(\.summary), ["Keep this note."])
        XCTAssertTrue(controls.listedFacts(in: .events).isEmpty)

        let addedWhileOff = controls.addFact(
            category: .mood,
            summary: "A quiet week.",
            defaults: defaults
        )
        XCTAssertNotNil(addedWhileOff)
        XCTAssertEqual(controls.listedFacts(in: .mood).first?.summary, "A quiet week.")
        XCTAssertTrue(controls.coachingFacts(in: .mood).isEmpty)
        XCTAssertEqual(AriaKnowledgeLedgerStore.load(defaults: defaults).facts.count, 2)
    }

    func testDisableFolderStopsCoachingAndAutoFileButKeepsTheNote() {
        var controls = AriaMemoryControls.load(defaults: defaults)
        XCTAssertNotNil(controls.addFact(
            category: .lifestyle,
            summary: "Keep this note.",
            defaults: defaults
        ))
        controls.setCategory(.lifestyle, enabled: false, defaults: defaults)
        AriaKnowledgeLedgerStore.file(
            AriaKnowledgeFact(
                category: .weSpokeAbout,
                kind: "chat",
                summary: "Should not land.",
                source: "chat"
            ),
            defaults: defaults
        )
        controls = AriaMemoryControls.load(defaults: defaults)
        XCTAssertEqual(controls.listedFacts(in: .lifestyle).map(\.summary), ["Keep this note."])
        XCTAssertTrue(controls.coachingFacts(in: .lifestyle).isEmpty)

        AriaKnowledgeLedgerStore.file(
            AriaKnowledgeFact(
                category: .weSpokeAbout,
                kind: "weekly_mood",
                summary: "7",
                source: "weekly"
            ),
            defaults: defaults
        )
        controls.setCategory(.mood, enabled: false, defaults: defaults)
        controls = AriaMemoryControls.load(defaults: defaults)
        XCTAssertEqual(controls.listedFacts(in: .mood).first?.summary, "7")
        XCTAssertNil(
            AriaKnowledgeLedgerStore.load(defaults: defaults)
                .latestWeeklyMood(prefs: controls.prefs)
        )
    }

    func testPrivacyGateStripsAttendeesPlacesAndEmails() {
        let leaked = AriaFactPrivacy.sanitizeSummary(
            "Jordan & Alex's wedding at 12 Main Street with maya@example.com"
        )
        XCTAssertEqual(leaked, "This week: a wedding.")
        XCTAssertFalse(leaked.lowercased().contains("jordan"))
        XCTAssertFalse(leaked.contains("@"))
        XCTAssertFalse(leaked.lowercased().contains("street"))

        let days = AriaFactPrivacy.sanitizeSummary(
            "calendar:title:Plaza Ballroom wedding in 2 weeks calendar:attendee:maya@example.com"
        )
        XCTAssertEqual(days, "Wedding in 14 days — you told me.")

        XCTAssertEqual(AriaFactPrivacy.sanitizeSummary("maya@example.com"), "")
        XCTAssertFalse(AriaFactPrivacy.privacyLine.lowercased().contains("recover"))
        XCTAssertFalse(AriaFactPrivacy.privacyLine.lowercased().contains("medical"))
        var controls = AriaMemoryControls.load(defaults: defaults)
        XCTAssertNil(controls.addFact(
            category: .events,
            summary: "Meet Maya at 44 Oak Avenue",
            defaults: defaults
        ))
    }

    func testEditRefusesACalendarLeak() {
        var ledger = AriaKnowledgeLedger()
        let fact = AriaKnowledgeFact(
            id: "fact-1",
            category: .events,
            kind: "calendar_week",
            summary: "This week: a wedding.",
            source: "calendar"
        )
        ledger.file(fact)
        XCTAssertFalse(ledger.updateSummary(id: "fact-1", summary: "Meet Maya at 44 Oak Avenue"))
        XCTAssertEqual(ledger.facts.first?.summary, "This week: a wedding.")
    }

    func testPersonaDisableAndClearStayOnDevice() {
        var controls = AriaMemoryControls.load(defaults: defaults)
        let persona = QualityOfLifePersona(
            archetype: .homebody,
            sleepNeedPreferenceHours: 7.5,
            nutritionRelationship: "fuel",
            movementPreference: .cardio,
            hobbies: [.cooking]
        )
        controls.savePersona(persona, defaults: defaults)
        XCTAssertTrue(QualityOfLifeLivingStore.isPersonaEnabled(defaults: defaults))
        XCTAssertTrue(QualityOfLifeLivingStore.livingTags(defaults: defaults).contains("living:archetype:homebody"))

        controls.setPersonaEnabled(false, defaults: defaults)
        XCTAssertTrue(QualityOfLifeLivingStore.livingTags(defaults: defaults).isEmpty)
        XCTAssertEqual(QualityOfLifeLivingStore.loadPersonaForCoaching(defaults: defaults), .balanced)
        XCTAssertEqual(QualityOfLifeLivingStore.loadPersona(defaults: defaults).archetype, .homebody)
        let paused = QualityOfLifeLivingStore.characterLine(defaults: defaults)
        XCTAssertTrue(paused.localizedCaseInsensitiveContains("who-you-are")
                      || paused.localizedCaseInsensitiveContains("paused"))
        XCTAssertFalse(paused.localizedCaseInsensitiveContains("doctor"))
        XCTAssertFalse(paused.localizedCaseInsensitiveContains("recovery week"))

        controls.clearPersona(defaults: defaults)
        XCTAssertEqual(QualityOfLifeLivingStore.loadPersona(defaults: defaults), .balanced)
        XCTAssertFalse(QualityOfLifeLivingStore.hasCompletedInterview(defaults: defaults))
    }

    func testToneAndCheckInPrefsPersist() {
        var controls = AriaMemoryControls.load(defaults: defaults)
        XCTAssertEqual(controls.prefs.tone, .checkIn)
        XCTAssertEqual(controls.prefs.checkInCadence, .weekly)
        XCTAssertEqual(AriaCheckInCadence.weekly.interval, 6 * 24 * 60 * 60)
        XCTAssertNil(AriaCheckInCadence.off.interval)

        controls.setTone(.peer, defaults: defaults)
        controls.setCheckInCadence(.off, defaults: defaults)
        let reloaded = AriaMemoryControls.load(defaults: defaults)
        XCTAssertEqual(reloaded.prefs.tone, .peer)
        XCTAssertEqual(reloaded.prefs.checkInCadence, .off)
        XCTAssertEqual(reloaded.prefs.tone.line.lowercased().contains("honest peer"), true)
        XCTAssertFalse(reloaded.prefs.tone.line.lowercased().contains("clinician"))
        XCTAssertFalse(reloaded.prefs.checkInCadence.detail.lowercased().contains("medical"))
        XCTAssertFalse(reloaded.prefs.tone.line.lowercased().contains("recovery"))
    }

    func testLegacyLedgerJSONStillDecodes() throws {
        let fact = AriaKnowledgeFact(
            category: .weSpokeAbout,
            kind: "chat",
            summary: "keep me",
            source: "chat",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let data = try JSONEncoder().encode(AriaKnowledgeLedger(facts: [fact]))
        let decoded = try JSONDecoder().decode(AriaKnowledgeLedger.self, from: data)
        XCTAssertEqual(decoded.facts.first?.managedFolder, .lifestyle)
        XCTAssertEqual(decoded.facts(inManaged: .lifestyle).first?.summary, "keep me")
    }

    func testCheckInDueMath() {
        XCTAssertEqual(AriaCheckInCadence.daily.interval, 20 * 60 * 60)
        XCTAssertEqual(AriaCompanionTone.allCases.map(\.title), [
            "Check-in", "Space", "Patterns", "Honest peer"
        ])
    }

    func testHealthHistoryRawValueStaysStableAsBodyNotesTitle() throws {
        XCTAssertEqual(AriaKnowledgeCategory.healthHistory.rawValue, "healthHistory")
        XCTAssertEqual(AriaKnowledgeCategory.healthHistory.title, "Body notes")
        let encoded = try JSONEncoder().encode(AriaKnowledgeCategory.healthHistory)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"healthHistory\"")
        let decoded = try JSONDecoder().decode(AriaKnowledgeCategory.self, from: encoded)
        XCTAssertEqual(decoded, .healthHistory)
        XCTAssertEqual(decoded.title, "Body notes")

        let prefsJSON = Data("""
        {"memoryEnabled":true,"disabledCategories":["healthHistory"],"personaEnabled":true,"tone":"checkIn","checkInCadence":"weekly"}
        """.utf8)
        let prefs = try JSONDecoder().decode(AriaCompanionPreferences.self, from: prefsJSON)
        XCTAssertFalse(prefs.isCategoryEnabled(.healthHistory))
        XCTAssertTrue(prefs.isCategoryEnabled(.mood))
        XCTAssertEqual(prefs.disabledCategories, ["healthHistory"])
    }

    func testPartnerAndCycleTokensNeverLandInVaultNotes() {
        let banned = [
            "partner_name:sam",
            "partner_phase:luteal",
            "partner_cycle:day14",
            "partner_day:14",
            "support_cycle:yes",
            "cycle:fertile_window",
            "cycle:tww",
            "cycle:goal:trying",
            "cycle:bleeding",
            "cycle:condition",
        ]
        for token in banned {
            XCTAssertTrue(AriaFactPrivacy.isDeniedLifestyleToken(token), token)
            XCTAssertEqual(AriaFactPrivacy.sanitizeSummary(token), "", token)
        }
        XCTAssertFalse(AriaFactPrivacy.isDeniedLifestyleToken("my"))
        XCTAssertFalse(AriaFactPrivacy.isDeniedLifestyleToken("partner"))
        XCTAssertEqual(
            AriaFactPrivacy.sanitizeSummary("my partner is traveling"),
            "my partner is traveling"
        )

        let mixed = AriaFactPrivacy.sanitizeSummary(
            "Morning walks partner_name:sam partner_phase:luteal late_caffeine"
        )
        XCTAssertEqual(mixed, "Morning walks late_caffeine")
        XCTAssertFalse(mixed.lowercased().contains("partner_"))
        XCTAssertFalse(mixed.lowercased().contains("cycle:"))

        var controls = AriaMemoryControls.load(defaults: defaults)
        XCTAssertNil(controls.addFact(
            category: .lifestyle,
            summary: "partner_name:sam",
            defaults: defaults
        ))
        XCTAssertTrue(controls.listedFacts(in: .lifestyle).isEmpty)

        XCTAssertNotNil(controls.addFact(
            category: .healthHistory,
            summary: "Slept restlessly. partner_phase:luteal cycle:fertile_window",
            defaults: defaults
        ))
        let body = controls.listedFacts(in: .healthHistory).first?.summary ?? ""
        XCTAssertEqual(body, "Slept restlessly.")
        XCTAssertFalse(body.lowercased().contains("partner_"))
        XCTAssertFalse(body.lowercased().contains("cycle:"))
        XCTAssertFalse(body.lowercased().contains("rem"))
        XCTAssertFalse(body.contains("%"))

        var ledger = AriaKnowledgeLedger()
        ledger.file(AriaKnowledgeFact(
            category: .lifestyle, kind: "user", summary: "cycle:fertile_window", source: "user"
        ))
        XCTAssertTrue(ledger.facts.isEmpty, "denied tokens must not file into the vault")
        XCTAssertFalse(ledger.updateSummary(id: "missing", summary: "support_cycle:yes"))

        let kept = AriaKnowledgeFact(
            id: "note-1",
            category: .lifestyle,
            kind: "user",
            summary: "late caffeine",
            source: "user"
        )
        ledger.file(kept)
        XCTAssertFalse(ledger.updateSummary(id: "note-1", summary: "partner_cycle:day14"))
        XCTAssertEqual(ledger.facts.first?.summary, "late caffeine")

        // Calendar gate still holds after the partner/cycle widen.
        XCTAssertEqual(
            AriaFactPrivacy.sanitizeSummary(
                "calendar:title:Plaza Ballroom wedding in 2 weeks calendar:attendee:maya@example.com"
            ),
            "Wedding in 14 days — you told me."
        )
        XCTAssertFalse(AriaFactPrivacy.privacyLine.lowercased().contains("doctor"))
        XCTAssertTrue(AriaFactPrivacy.privacyLine.lowercased().contains("partner"))
    }
}
