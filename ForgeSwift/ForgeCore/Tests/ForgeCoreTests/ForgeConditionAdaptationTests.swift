import XCTest
@testable import ForgeCore

final class ForgeConditionAdaptationTests: XCTestCase {

    func testEpilepsyDiabetesAndADHDArePositiveAndNotMedicalAdvice() {
        let epilepsy = ForgeConditionAdaptation.constraints([.epilepsy])
        XCTAssertTrue(epilepsy.joined().lowercased().contains("seizure-aware"))
        XCTAssertTrue(epilepsy.joined().lowercased().contains("rest"))
        XCTAssertFalse(epilepsy.joined().lowercased().contains("recovery"))
        XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(epilepsy.joined()))

        let diabetes = ForgeConditionAdaptation.constraints([.diabetes])
        XCTAssertTrue(diabetes.joined().lowercased().contains("blood-sugar"))
        XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(diabetes.joined()))

        let adhd = ForgeConditionAdaptation.constraints([.adhd])
        XCTAssertTrue(adhd.joined().lowercased().contains("short blocks"))

        let line = ForgeConditionAdaptation.coachLine([.epilepsy, .diabetes])
        XCTAssertTrue(line.lowercased().contains("works with your body"))
        XCTAssertTrue(line.lowercased().contains("doctor"))
        XCTAssertFalse(line.lowercased().contains("diagnos"))

        let persona = ForgeLifestylePersonas.seizuresSleepCare
        XCTAssertTrue(persona.hasSeizureConstraint)
        let share = ForgeLifestyleProfile.serverContext(persona)
        XCTAssertNil(share["health_constraints"])
    }

    func testTwentySixYearOldSeizurePersonaIsOnDeviceAndPositive() {
        let persona = ForgeLifestylePersonas.seizuresSleepCare
        XCTAssertTrue(persona.hasSeizureConstraint)
        let lines = ForgeConditionAdaptation.constraints(persona.healthConstraints, freeform: persona.healthNote)
        XCTAssertTrue(lines.joined().lowercased().contains("seizure-aware"))
        XCTAssertFalse(lines.joined().lowercased().contains("recovery"))
        XCTAssertFalse(ForgeConditionAdaptation.containsDiagnosis(lines.joined()))
        XCTAssertTrue(ForgeConditionAdaptation.coachLine(persona.healthConstraints).lowercased().contains("doctor"))
        let leaked = ForgeLifestyleProfile.serverContext(persona)
        XCTAssertNil(leaked["health_constraints"], "conditions stay on-device by default")
        for personality in AriaSoul.Personality.allCases {
            let config = AriaSoul.Config(blend: AriaSoul.Blend(
                coach: personality == .coach ? 1 : 0,
                friend: personality == .friend ? 1 : 0,
                drillSergeant: personality == .drillSergeant ? 1 : 0,
                anchor: personality
            ))
            XCTAssertFalse(AriaSoul.containsRailBreak(AriaSoul.directive(config)))
        }
    }
}
