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
            "Goals", "Identity", "Lifestyle", "Preferences", "Events", "Health History", "Mood"
        ])
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

    func testAccessCopyAndReduceMotionContract() {
        XCTAssertTrue(AriaMemoryAccess.shouldAnimate(reduceMotion: false))
        XCTAssertFalse(AriaMemoryAccess.shouldAnimate(reduceMotion: true))

        XCTAssertEqual(AriaMemoryAccess.rememberMeLabel, "Remember me")
        XCTAssertEqual(AriaMemoryAccess.rememberMeValue(isOn: true), "On")
        XCTAssertEqual(AriaMemoryAccess.rememberMeValue(isOn: false), "Off")
        XCTAssertTrue(AriaMemoryAccess.rememberMeHint.localizedCaseInsensitiveContains("does not delete"))
        XCTAssertTrue(AriaMemoryAccess.personaHint.localizedCaseInsensitiveContains("does not forget"))
        XCTAssertTrue(AriaMemoryAccess.folderUseHint.localizedCaseInsensitiveContains("does not delete"))

        XCTAssertEqual(AriaMemoryAccess.addNoteLabel(folder: .goals), "Add a note in Goals")
        XCTAssertEqual(
            AriaMemoryAccess.editNoteLabel(folder: .mood, summary: "Feeling steady."),
            "Edit Mood note, Feeling steady."
        )
        XCTAssertEqual(
            AriaMemoryAccess.deleteNoteLabel(folder: .lifestyle, summary: "Keep this note."),
            "Delete Lifestyle note, Keep this note."
        )
        XCTAssertEqual(AriaMemoryAccess.toneLabel(.checkIn, selected: true), "Tone, Check-in, selected")
        XCTAssertEqual(AriaMemoryAccess.toneLabel(.space, selected: false), "Tone, Space")
        XCTAssertEqual(AriaMemoryAccess.checkInLabel(.weekly, selected: true), "Check-in, Weekly, selected")
        XCTAssertEqual(AriaMemoryAccess.checkInLabel(.off, selected: false), "Check-in, Off")
        XCTAssertEqual(AriaMemoryAccess.folderUseLabel(.events), "ARIA may use Events")
        XCTAssertEqual(AriaMemoryAccess.personaActionLabel(interviewCompleted: true), "Update who I am")
        XCTAssertEqual(AriaMemoryAccess.personaActionLabel(interviewCompleted: false), "Tell ARIA who you are")

        let spoken = [
            AriaMemoryAccess.rememberMeHint,
            AriaMemoryAccess.personaHint,
            AriaMemoryAccess.forgetPersonaHint,
            AriaMemoryAccess.toneLabel(.peer, selected: true),
            AriaMemoryAccess.checkInLabel(.daily, selected: true),
        ].joined(separator: " ").lowercased()
        XCTAssertFalse(spoken.contains("medical"))
        XCTAssertFalse(spoken.contains("recovery week"))
        XCTAssertFalse(spoken.contains("clinician"))
    }
}
