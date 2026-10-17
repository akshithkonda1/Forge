import XCTest
@testable import ForgeCore

final class ForgeCoachingPersonalityTests: XCTestCase {

    func testPresetsAreMindsetOnlyAndOriginallyNamed() {
        let labels = ForgeCoachingPersonality.Preset.allCases.map(\.label)
        XCTAssertEqual(labels, [
            "Pillar Training",
            "Steady builder",
            "Direct coach",
            "Curious experimenter",
            "Playful companion",
        ])
        let pillar = ForgeCoachingPersonality.Preset.pillarTraining
        XCTAssertEqual(pillar.label, "Pillar Training")
        XCTAssertTrue(pillar.summary.lowercased().contains("physical"))
        XCTAssertTrue(pillar.summary.lowercased().contains("mental"))
        XCTAssertTrue(pillar.summary.lowercased().contains("psychological"))
        XCTAssertTrue(pillar.summary.lowercased().contains("never exercise form"))
        XCTAssertTrue(pillar.summary.lowercased().contains("comfort") || pillar.summary.lowercased().contains("safety"))
        XCTAssertTrue(pillar.summary.lowercased().contains("progress"))
        let talk = ForgeCoachingPersonality.colorPlanTalk(
            .init(preset: .pillarTraining),
            planLine: "Three compound lifts, honest rest."
        )
        XCTAssertTrue(talk.lowercased().contains("safe") || talk.lowercased().contains("comfort"))
        XCTAssertTrue(talk.lowercased().contains("progress"))
        XCTAssertTrue(ForgeCoachingPersonality.promptDirective(.init(preset: .pillarTraining)).lowercased().contains("comfort or safety"))
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
    }

    func testSafetyOverridesPersonality() {
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
    }
}
