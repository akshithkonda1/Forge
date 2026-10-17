import XCTest
@testable import ForgeCore

final class ForgeConditionAdaptationTests: XCTestCase {

    func testEpilepsyDiabetesAndADHDArePositiveAndNotMedicalAdvice() {
        let epilepsy = ForgeConditionAdaptation.constraints([.epilepsy]).joined()
        let epilepsyLower = epilepsy.lowercased()
        XCTAssertTrue(epilepsyLower.contains("seizure-aware"))
        XCTAssertTrue(epilepsyLower.contains("intensity"))
        XCTAssertTrue(epilepsyLower.contains("rest"))
        XCTAssertTrue(epilepsyLower.contains("solo") && epilepsyLower.contains("high-risk"))
        XCTAssertTrue(epilepsyLower.contains("sleep-deprivation") || epilepsyLower.contains("sleep"))
        XCTAssertTrue(epilepsyLower.contains("works with your body"))
        XCTAssertFalse(epilepsyLower.contains("recovery"))
        XCTAssertFalse(epilepsyLower.contains("limitation") || epilepsyLower.contains("warning"))
        XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(epilepsy))
        XCTAssertFalse(ForgeConditionAdaptation.containsRecovery(epilepsy))

        let diabetes = ForgeConditionAdaptation.constraints([.diabetes]).joined()
        let diabetesLower = diabetes.lowercased()
        XCTAssertTrue(diabetesLower.contains("blood-sugar"))
        XCTAssertTrue(diabetesLower.contains("timing"))
        XCTAssertTrue(diabetesLower.contains("fueling"))
        XCTAssertTrue(diabetesLower.contains("works with your body"))
        XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(diabetes))
        XCTAssertFalse(ForgeConditionAdaptation.containsRecovery(diabetes))

        let adhd = ForgeConditionAdaptation.constraints([.adhd]).joined()
        let adhdLower = adhd.lowercased()
        XCTAssertTrue(adhdLower.contains("short blocks"))
        XCTAssertTrue(adhdLower.contains("variety"))
        XCTAssertTrue(adhdLower.contains("next step"))
        XCTAssertTrue(adhdLower.contains("works with your body"))
        XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(adhd))

        let line = ForgeConditionAdaptation.coachLine([.epilepsy, .diabetes])
        XCTAssertTrue(line.lowercased().contains("works with your body"))
        XCTAssertTrue(line.lowercased().contains("doctor"))
        XCTAssertFalse(line.lowercased().contains("diagnos"))
        XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(line))

        let persona = ForgeLifestylePersonas.seizuresSleepCare
        XCTAssertTrue(persona.hasSeizureConstraint)
        let share = ForgeLifestyleProfile.serverContext(persona)
        XCTAssertNil(share["health_constraints"])
        XCTAssertFalse(ForgeLifestyleProfile.containsSensitiveServerLeak(share, policy: persona.share))
    }

    func testTwentySixYearOldSeizurePersonaIsOnDeviceAndPositive() {
        XCTAssertEqual(ForgeLifestylePersonas.seizuresSleepCareAge, 26)
        let persona = ForgeLifestylePersonas.seizuresSleepCare
        XCTAssertTrue(persona.hasSeizureConstraint)
        XCTAssertTrue(persona.healthNote.lowercased().contains("twenty-six")
                      || persona.routineNote.contains("26"))
        let lines = ForgeConditionAdaptation.constraints(persona.healthConstraints, freeform: persona.healthNote)
        let blob = lines.joined().lowercased()
        XCTAssertTrue(blob.contains("seizure-aware"))
        XCTAssertTrue(blob.contains("rest"))
        XCTAssertTrue(blob.contains("solo") && blob.contains("high-risk"))
        XCTAssertTrue(blob.contains("sleep"))
        XCTAssertTrue(blob.contains("works with your body") || blob.contains("twenty-six"))
        XCTAssertFalse(blob.contains("recovery"))
        XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(lines.joined()))
        XCTAssertTrue(ForgeConditionAdaptation.coachLine(persona.healthConstraints).lowercased().contains("doctor"))
        let leaked = ForgeLifestyleProfile.serverContext(persona)
        XCTAssertNil(leaked["health_constraints"], "conditions stay on-device by default")
        XCTAssertEqual(persona.share.shareConditions, false)

        var opted = persona
        opted.share.shareConditions = true
        let sent = ForgeLifestyleProfile.serverContext(opted)
        XCTAssertEqual(sent["health_constraints"], "seizures")

        for personality in AriaSoul.Personality.allCases {
            let config = AriaSoul.Config(blend: AriaSoul.Blend(
                coach: personality == .coach ? 1 : 0,
                friend: personality == .friend ? 1 : 0,
                drillSergeant: personality == .drillSergeant ? 1 : 0,
                anchor: personality
            ))
            assertSoulRails(AriaSoul.directive(config), label: personality.label)
        }
        let fused = AriaSoul.fuse(
            experience: "beginner",
            goals: [],
            engagement: 0.2,
            override: nil
        )
        assertSoulRails(AriaSoul.directive(AriaSoul.Config(blend: fused)), label: "fused beginner")
        let competitor = AriaSoul.fuse(
            experience: "elite",
            goals: ["competition"],
            engagement: 0.8,
            override: nil
        )
        assertSoulRails(AriaSoul.directive(AriaSoul.Config(blend: competitor)), label: "fused competitor")
    }

    func testSleepStressMoodAndDayToDayStayPositive() {
        let conditions: [ForgeLifestyleProfile.HealthConstraint] = [.epilepsy, .diabetes, .adhd]
        for domain in ForgeConditionAdaptation.Domain.allCases {
            let line = ForgeConditionAdaptation.line(domain: domain, conditions: conditions)
            XCTAssertFalse(line.isEmpty, domain.rawValue)
            XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(line), domain.rawValue)
            XCTAssertFalse(ForgeConditionAdaptation.containsRecovery(line), domain.rawValue)
            XCTAssertTrue(line.lowercased().contains("doctor"), domain.rawValue)
        }
        let sleep = ForgeConditionAdaptation.line(domain: .sleep, conditions: [.epilepsy]).lowercased()
        XCTAssertTrue(sleep.contains("sleep-deprivation") || sleep.contains("rest"))
        let diabetesSleep = ForgeConditionAdaptation.line(domain: .sleep, conditions: [.diabetes]).lowercased()
        XCTAssertTrue(diabetesSleep.contains("fueling"))
        let adhdMood = ForgeConditionAdaptation.line(domain: .mood, conditions: [.adhd]).lowercased()
        XCTAssertTrue(adhdMood.contains("next step") || adhdMood.contains("short block"))
        let life = ForgeConditionAdaptation.coachingAcrossLife([.epilepsy])
        XCTAssertEqual(life.count, 4)
        XCTAssertFalse(life.joined().lowercased().contains("recovery"))
    }

    func testAdaptiveTrainingModelAppliesConstraintsAutomatically() {
        let adapted = ForgeConditionAdaptation.applyToTrainingModel(
            "intense physical, intense mental",
            conditions: [.epilepsy]
        )
        XCTAssertTrue(adapted.contains("intense physical"))
        XCTAssertTrue(adapted.lowercased().contains("seizure-aware"))
        XCTAssertTrue(adapted.lowercased().contains("doctor"))
        XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(adapted))
        XCTAssertFalse(ForgeConditionAdaptation.containsRecovery(adapted))

        let directive = ForgeCoachingPersonality.promptDirective(
            .init(freeText: "intense physical"),
            conditions: [.diabetes, .adhd],
            freeform: "fuel before late sessions"
        )
        XCTAssertTrue(directive.lowercased().contains("blood-sugar"))
        XCTAssertTrue(directive.lowercased().contains("short blocks"))
        XCTAssertTrue(directive.lowercased().contains("fuel before"))
        XCTAssertTrue(directive.lowercased().contains("doctor"))
        XCTAssertTrue(directive.lowercased().contains("not a doctor"))
        XCTAssertTrue(directive.lowercased().contains("never say recovery"))
        let conditionBlob = ForgeConditionAdaptation.constraints(
            [.diabetes, .adhd],
            freeform: "fuel before late sessions"
        ).joined()
        XCTAssertFalse(ForgeConditionAdaptation.containsRecovery(conditionBlob))
        XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(conditionBlob))

        let catalog = [
            ForgeExerciseDiscovery.Exercise(id: "hang", name: "Hang Clean", equipment: "barbell"),
            ForgeExerciseDiscovery.Exercise(id: "goblet", name: "Goblet Squat", equipment: "dumbbell"),
            ForgeExerciseDiscovery.Exercise(id: "pushup", name: "Push-Up", equipment: "bodyweight"),
        ]
        let memory = ForgeExerciseDiscovery.Memory(gymType: "commercial gym", equipmentNotes: "barbell, dumbbell")
        let ranked = ForgeExerciseDiscovery.rank(
            catalog: catalog,
            memory: memory,
            trainingModel: "intense physical",
            goals: ["strength"],
            readiness: 80,
            conditions: [.epilepsy]
        )
        XCTAssertFalse(ranked.contains { $0.id == "hang" }, "solo high-risk is skipped")
        XCTAssertTrue(ranked.contains { $0.id == "goblet" })
        XCTAssertTrue(ranked.contains { $0.reasons.joined().lowercased().contains("grounded intensity") })
        XCTAssertFalse(ranked.contains { $0.reasons.joined().lowercased().contains("recovery") })

        let adhdRank = ForgeExerciseDiscovery.rank(
            catalog: catalog,
            memory: memory,
            trainingModel: "structure",
            goals: [],
            readiness: 70,
            conditions: [.adhd, .diabetes]
        )
        let reasons = adhdRank.flatMap(\.reasons).joined().lowercased()
        XCTAssertTrue(reasons.contains("short blocks"))
        XCTAssertTrue(reasons.contains("blood-sugar"))
    }

    func testHealthFilterIngestsEpilepsyDiabetesAndADHDOnDevice() {
        switch AriaHealthFilter.decide("I have epilepsy and occasional seizures") {
        case .store, .storeHealthAngle: break
        case .skip: XCTFail("epilepsy must pass the health filter")
        }
        switch AriaHealthFilter.decide("ADHD makes long blocks hard") {
        case .store, .storeHealthAngle: break
        case .skip: XCTFail("ADHD must pass the health filter")
        }
        switch AriaHealthFilter.decide("diabetes and blood sugar around training") {
        case .store, .storeHealthAngle: break
        case .skip: XCTFail("diabetes must pass the health filter")
        }
        XCTAssertEqual(AriaContextMemory.classify("I have epilepsy"), .healthConstraints)
        XCTAssertEqual(AriaContextMemory.classify("ADHD short blocks"), .healthConstraints)
        XCTAssertEqual(AriaContextMemory.classify("diabetes fueling"), .healthConstraints)

        let empty = AriaContextMemory.Snapshot()
        let kept = AriaContextMemory.ingest(empty, text: "I have epilepsy", source: "onboarding")
        XCTAssertFalse(kept.items.isEmpty)
        XCTAssertEqual(kept.items.first?.domain, .healthConstraints)
        let hidden = AriaContextMemory.serverContext(kept)
        XCTAssertFalse((hidden["context_summaries"] ?? "").lowercased().contains("epilep"))
    }

    func testSnapshotEditAndDeleteStayOnDevice() {
        var snap = ForgeLifestylePersonas.seizuresSleepCare
        XCTAssertTrue(snap.hasSeizureConstraint)
        snap.removeHealthConstraint(.seizures)
        XCTAssertFalse(snap.hasSeizureConstraint)
        snap.healthConstraints = [.diabetes, .adhd]
        snap.healthNote = "Fueling reminders, short blocks."
        XCTAssertEqual(snap.healthConstraints, [.diabetes, .adhd])
        snap.clearHealthConstraints()
        XCTAssertTrue(snap.healthConstraints.isEmpty)
        XCTAssertTrue(snap.healthNote.isEmpty)
        XCTAssertNil(ForgeLifestyleProfile.serverContext(snap)["health_constraints"])
    }

    func testFreeformOtherConditionAdaptsWithoutDiagnosing() {
        let lines = ForgeConditionAdaptation.constraints(
            [.other],
            freeform: "migraines after late nights"
        )
        let blob = lines.joined().lowercased()
        XCTAssertTrue(blob.contains("migraines"))
        XCTAssertTrue(blob.contains("doctor"))
        XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(blob))
        XCTAssertFalse(blob.contains("recovery"))
    }

    private func assertSoulRails(_ directive: String, label: String) {
        let lower = directive.lowercased()
        XCTAssertTrue(lower.contains("not a doctor"), label)
        XCTAssertTrue(lower.contains("never diagnose"), label)
        XCTAssertTrue(lower.contains("suggest a doctor"), label)
        XCTAssertTrue(lower.contains("adapt around"), label)
        XCTAssertTrue(lower.contains("medical advice"), label)
        XCTAssertFalse(AriaSoul.containsRailBreak(directive), label)
    }
}
