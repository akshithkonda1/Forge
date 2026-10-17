import XCTest
@testable import ForgeCore

final class ForgeCoachingPersonalityTests: XCTestCase {

    func testAdaptiveTrainingModelIsPrimaryAndGuardrailed() {
        let labels = ForgeCoachingPersonality.Preset.allCases.map(\.label)
        XCTAssertEqual(labels, [
            "Steady builder",
            "Direct coach",
            "Curious experimenter",
            "Playful companion",
        ])
        for preset in ForgeCoachingPersonality.Preset.allCases {
            let blob = (preset.label + preset.rawValue).lowercased()
            XCTAssertFalse(blob.contains("pillar"), preset.rawValue)
            XCTAssertFalse(blob.contains("hashira"), preset.rawValue)
            XCTAssertFalse(blob.contains("demon"), preset.rawValue)
            XCTAssertFalse(blob.contains("tanjiro"), preset.rawValue)
        }
        XCTAssertTrue(ForgeCoachingPersonality.Preset.retiredRawValues.contains("pillarTraining"))
        XCTAssertTrue(ForgeCoachingPersonality.Preset.retiredRawValues.contains("hashira"))
        XCTAssertTrue(ForgeCoachingPersonality.Preset.retiredRawValues.contains("hashiraTraining"))
        XCTAssertEqual(ForgeCoachingPersonality.Preset.allCases.count, 4)

        let model = "intense physical, intense mental, intense psychological training"
        let choice = ForgeCoachingPersonality.Choice(freeText: model)
        XCTAssertEqual(choice.adaptiveTrainingModel, model)
        XCTAssertTrue(choice.isCustom)
        XCTAssertNil(choice.preset)

        let directive = ForgeCoachingPersonality.promptDirective(choice)
        XCTAssertTrue(directive.contains(model))
        XCTAssertTrue(directive.lowercased().contains("adaptive training model"))
        XCTAssertTrue(directive.lowercased().contains("never exercise form"))
        XCTAssertTrue(directive.lowercased().contains("comfort or safety"))
        XCTAssertTrue(directive.lowercased().contains("progress"))
        XCTAssertFalse(directive.lowercased().contains("pillar training"))
        XCTAssertFalse(directive.lowercased().contains("hashira"))

        let talk = ForgeCoachingPersonality.colorPlanTalk(
            choice,
            planLine: "Three compound lifts, honest rest."
        )
        XCTAssertTrue(talk.contains("Three compound lifts, honest rest."))
        XCTAssertTrue(talk.lowercased().contains("comfort") || talk.lowercased().contains("safety"))
        XCTAssertTrue(talk.lowercased().contains("progress"))
        XCTAssertFalse(ForgeCoachingPersonality.containsBanned(talk))

        XCTAssertTrue(ForgeCoachingPersonality.modelPlaceholder.lowercased().contains("hashira"))
        XCTAssertTrue(ForgeCoachingPersonality.modelPlaceholder.lowercased().contains("not a preset"))
    }

    func testRetiredPresetNamesDecodeAsNilAndKeepTheModel() throws {
        let json = Data("""
        {"preset":"pillarTraining","freeText":"intense physical, intense mental, intense psychological training"}
        """.utf8)
        let choice = try XCTUnwrap(JSONDecoder().decode(ForgeCoachingPersonality.Choice.self, from: json))
        XCTAssertNil(choice.preset)
        XCTAssertTrue(choice.adaptiveTrainingModel.contains("intense mental"))
        XCTAssertNil(ForgeCoachingPersonality.Preset.fromStored("hashira"))
        XCTAssertNil(ForgeCoachingPersonality.Preset.fromStored("hashiraTraining"))
        XCTAssertNil(ForgeCoachingPersonality.Preset.fromStored("demonSlayer"))
        XCTAssertEqual(ForgeCoachingPersonality.Preset.fromStored("directCoach"), .directCoach)
        let encoded = try JSONEncoder().encode(choice)
        let roundtrip = try JSONDecoder().decode(ForgeCoachingPersonality.Choice.self, from: encoded)
        XCTAssertNil(roundtrip.preset)
        XCTAssertEqual(roundtrip.adaptiveTrainingModel, choice.adaptiveTrainingModel)
    }

    func testPresetChangesToneNotPlan() {
        let plan = ForgeCoachingPersonality.planFingerprint(
            readiness: 74,
            workoutsThisWeek: 2,
            workoutGoal: 3
        )
        var fingerprints: [String] = []
        var talks: [String] = []
        for preset in ForgeCoachingPersonality.Preset.allCases {
            let choice = ForgeCoachingPersonality.Choice(preset: preset)
            fingerprints.append(
                ForgeCoachingPersonality.planFingerprint(
                    readiness: 74,
                    workoutsThisWeek: 2,
                    workoutGoal: 3
                )
            )
            talks.append(
                ForgeCoachingPersonality.colorPlanTalk(
                    choice,
                    planLine: "Three compound lifts, honest rest."
                )
            )
            XCTAssertFalse(ForgeCoachingPersonality.containsBanned(choice.preset!.summary), preset.rawValue)
            XCTAssertFalse(ForgeCoachingPersonality.containsBabyTalk(choice.preset!.setbackFrame))
        }
        XCTAssertTrue(fingerprints.allSatisfy { $0 == plan })
        XCTAssertEqual(Set(talks).count, ForgeCoachingPersonality.Preset.allCases.count)
        for talk in talks {
            XCTAssertTrue(talk.contains("Three compound lifts, honest rest."))
            XCTAssertFalse(talk.lowercased().contains("chest day"))
            XCTAssertFalse(ForgeCoachingPersonality.containsBanned(talk))
        }
    }

    func testFreeTextShapesToneAndIsStoredOnChoice() {
        let choice = ForgeCoachingPersonality.Choice(
            preset: .directCoach,
            freeText: "Talk to me like a senior engineer: short, precise, no pep."
        )
        XCTAssertTrue(choice.isCustom)
        XCTAssertEqual(choice.preset, .directCoach)
        let directive = ForgeCoachingPersonality.promptDirective(choice)
        XCTAssertTrue(directive.contains("senior engineer"))
        XCTAssertTrue(directive.contains("tone and framing only"))
        XCTAssertTrue(directive.lowercased().contains("never"))
        XCTAssertTrue(directive.contains("session plan"))
        XCTAssertFalse(ForgeCoachingPersonality.containsBabyTalk(directive))
        XCTAssertFalse(directive.lowercased().contains("chest day"))
        XCTAssertFalse(directive.lowercased().contains("pillar"))
    }

    func testSafetyOverridesPersonality() {
        let empty = ForgeCoachingPersonality.promptDirective(.init())
        XCTAssertTrue(empty.lowercased().contains("not a doctor"))
        XCTAssertTrue(empty.lowercased().contains("never say recovery")
                      || empty.lowercased().contains("never diagnose"))
        XCTAssertTrue(empty.lowercased().contains("adult"))
        XCTAssertFalse(empty.lowercased().contains("baby"))
        for preset in ForgeCoachingPersonality.Preset.allCases {
            let directive = ForgeCoachingPersonality.promptDirective(.init(preset: preset))
            XCTAssertTrue(directive.lowercased().contains("not a doctor"), preset.rawValue)
            XCTAssertTrue(directive.lowercased().contains("never say recovery")
                          || directive.lowercased().contains("never diagnose"), preset.rawValue)
            XCTAssertTrue(directive.lowercased().contains("adult"), preset.rawValue)
            XCTAssertFalse(directive.lowercased().contains("baby"), preset.rawValue)
        }
        XCTAssertTrue(
            ForgeCoachingPersonality.containsBabyTalk("Good job champ, yay you")
        )
    }

    func testSetbackFramingIsDistinctAndUnashamed() {
        let frames = ForgeCoachingPersonality.Preset.allCases.map {
            ForgeCoachingPersonality.colorSetback(.init(preset: $0), whatHappened: "You skipped last night.")
        }
        XCTAssertEqual(Set(frames).count, frames.count)
        for line in frames {
            XCTAssertTrue(line.contains("You skipped last night."))
            XCTAssertFalse(line.lowercased().contains("shame"))
            XCTAssertFalse(line.lowercased().contains("failing grade") && line.lowercased().contains("you are"))
            XCTAssertFalse(ForgeCoachingPersonality.containsBanned(line))
        }
        let modeled = ForgeCoachingPersonality.colorSetback(
            .init(freeText: "intense physical, intense mental, intense psychological training"),
            whatHappened: "You skipped last night."
        )
        XCTAssertTrue(modeled.contains("You skipped last night."))
        XCTAssertTrue(modeled.lowercased().contains("comfort") || modeled.lowercased().contains("safety"))
        XCTAssertFalse(ForgeCoachingPersonality.containsBanned(modeled))
    }
}
