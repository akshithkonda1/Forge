import XCTest
@testable import ForgeCore

final class AriaIntentResolverTests: XCTestCase {

    func testClearLanguageWins() {
        let ranked = AriaIntentResolver.rank(
            AriaIntentInput(text: "build me a session for today", readiness: 40)
        )
        XCTAssertEqual(ranked.first?.domain, .training)
    }

    func testHabitCannotOverturnAClearSentence() {
        // Someone who has asked about sleep forty times still gets a session
        // when they ask for one. This is the failure mode a learned router has
        // and a keyword router does not, so it is the one worth pinning.
        let ranked = AriaIntentResolver.rank(
            AriaIntentInput(
                text: "build me a session for today",
                topicAffinity: ["sleep": 40, "readiness": 25]
            )
        )
        XCTAssertEqual(ranked.first?.domain, .training)
    }

    func testDataSpeaksWhenTheUserDoesNot() {
        // No recovery language at all — the body makes the case on its own.
        let ranked = AriaIntentResolver.rank(
            AriaIntentInput(
                text: "hey",
                readiness: 38,
                sleepMinutesLastNight: 4 * 60 + 50,
                consecutiveShortNights: 3
            )
        )
        let top = AriaIntentResolver.actionable(ranked)
        XCTAssertTrue(top.contains(.sleep) || top.contains(.readiness),
                      "three short nights and 38 readiness must raise recovery unprompted")
        XCTAssertFalse(ranked.first?.drivers.isEmpty ?? true, "a route must be explainable")
    }

    func testRememberedLimitationRaisesBody() {
        let ranked = AriaIntentResolver.rank(
            AriaIntentInput(text: "what should I do today", rememberedFacts: ["knee"])
        )
        XCTAssertTrue(ranked.contains { $0.domain == .body })
    }

    func testCycleIsSuppressedWhenTrackingIsUnavailable() {
        let ranked = AriaIntentResolver.rank(
            AriaIntentInput(text: "how does my cycle affect training", cycleTrackingAvailable: false)
        )
        XCTAssertFalse(ranked.contains { $0.domain == .cycle })
    }

    func testCycleSurfacesWhenAvailable() {
        let ranked = AriaIntentResolver.rank(
            AriaIntentInput(text: "how does my cycle affect training", cycleTrackingAvailable: true)
        )
        XCTAssertEqual(ranked.first?.domain, .cycle)
    }

    func testMultiPartQuestionSpawnsSeveralSpecialists() {
        let ranked = AriaIntentResolver.rank(
            AriaIntentInput(text: "I slept badly and my knee hurts — what should I eat and train today?",
                            readiness: 45)
        )
        let actionable = AriaIntentResolver.actionable(ranked)
        XCTAssertGreaterThanOrEqual(actionable.count, 2, "a genuinely multi-part ask must fan out")
        XCTAssertLessThanOrEqual(actionable.count, 3, "but not spawn everything")
    }

    func testChattyTurnDoesNotFanOut() {
        let ranked = AriaIntentResolver.rank(AriaIntentInput(text: "morning!"))
        XCTAssertEqual(AriaIntentResolver.actionable(ranked).count, 1)
    }

    func testAlwaysReturnsSomething() {
        let ranked = AriaIntentResolver.rank(AriaIntentInput(text: "?????"))
        XCTAssertFalse(ranked.isEmpty)
        XCTAssertFalse(AriaIntentResolver.actionable(ranked).isEmpty)
    }
}

final class AriaGuidancePolicyTests: XCTestCase {

    func testOrdinaryCoachingCarriesNoDisclaimer() {
        for text in [
            "my quads are sore from squats yesterday",
            "what should I eat before training",
            "I'm tired today, should I still go",
            "how do I get better at pull ups",
        ] {
            let decision = AriaGuidancePolicy.decide(text: text)
            XCTAssertEqual(decision.band, .coach, "«\(text)» should just be coached")
            XCTAssertNil(decision.line)
        }
    }

    func testEmergenciesReferOutAndAreNeverCoached() {
        for text in [
            "I've got chest pain when I run",
            "I passed out at the gym today",
            "my face is drooping and I feel weird",
            "I can't breathe properly",
        ] {
            let decision = AriaGuidancePolicy.decide(text: text)
            XCTAssertEqual(decision.band, .referOut, "«\(text)» must not be coached around")
            XCTAssertNotNil(decision.line)
        }
    }

    func testSelfHarmAndDisorderedEatingReferOut() {
        for text in [
            "I want to hurt myself",
            "how little can I eat and still train",
            "I make myself throw up after meals",
        ] {
            XCTAssertEqual(AriaGuidancePolicy.decide(text: text).band, .referOut)
        }
    }

    func testMedicationAndDiagnosisAreNotOurs() {
        XCTAssertEqual(AriaGuidancePolicy.decide(text: "should i stop taking my beta blockers").band, .referOut)
        XCTAssertEqual(AriaGuidancePolicy.decide(text: "do i have a stress fracture").band, .referOut)
    }

    func testPersistentPainIsCoachedWithCareNotRefused() {
        // The point of the middle band: this person has a real training
        // question attached and deflecting entirely fails them.
        let decision = AriaGuidancePolicy.decide(text: "my shoulder has been sore for weeks, can I still press")
        XCTAssertEqual(decision.band, .coachWithCare)
        XCTAssertNotNil(decision.line)
    }

    func testGuidanceOnlyModeNarrowsToBodyTurnsOnly() {
        // Previously the flag disclaimed on every training and low-energy turn,
        // including "what should I eat", which is why it read as boilerplate.
        XCTAssertEqual(
            AriaGuidancePolicy.decide(text: "what should I eat today", guidanceOnlyMode: true).band,
            .coach
        )
        XCTAssertEqual(
            AriaGuidancePolicy.decide(text: "my back is sore", guidanceOnlyMode: true).band,
            .coachWithCare
        )
    }

    func testEmergencyBeatsGuidanceModeAndOrdinaryLanguage() {
        // A red flag buried in an otherwise ordinary training question still
        // wins — the referOut sweep runs before everything else.
        let decision = AriaGuidancePolicy.decide(
            text: "quick one, planning my week — also I get chest pain on the stairs",
            guidanceOnlyMode: false
        )
        XCTAssertEqual(decision.band, .referOut)
    }

    func testOrdinaryRemindersAreOccasionalNotConstant() {
        let reminders = (0..<36).filter { AriaGuidancePolicy.shouldRemindOnOrdinaryTurn(turnIndex: $0) }
        XCTAssertFalse(reminders.isEmpty, "it should still surface sometimes")
        XCTAssertLessThan(reminders.count, 6, "but not become wallpaper")
        XCTAssertFalse(AriaGuidancePolicy.shouldRemindOnOrdinaryTurn(turnIndex: 0), "never on the first turn")
    }
}
