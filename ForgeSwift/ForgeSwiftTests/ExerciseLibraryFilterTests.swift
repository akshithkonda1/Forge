import XCTest
@testable import ForgeSwift

final class ExerciseLibraryFilterTests: XCTestCase {

    func testBicepsTapReturnsOnlyBicepsMoves() {
        let rows = ExerciseLibrary.filter(query: "", muscle: .biceps, equipment: nil, pattern: nil)
        XCTAssertFalse(rows.isEmpty, "biceps should have library moves")
        XCTAssertTrue(rows.allSatisfy { $0.primary.contains(.biceps) || $0.secondary.contains(.biceps) })
        XCTAssertTrue(rows.contains { $0.name.localizedCaseInsensitiveContains("curl") })
    }

    func testCalvesTapReturnsOnlyCalfMoves() {
        let rows = ExerciseLibrary.filter(query: "", muscle: .calves, equipment: nil, pattern: nil)
        XCTAssertFalse(rows.isEmpty, "calves should have library moves")
        XCTAssertTrue(rows.allSatisfy { $0.primary.contains(.calves) || $0.secondary.contains(.calves) })
    }

    func testEveryBodyMapMuscleHasAtLeastOneMove() {
        let mapped = Set(BodyMapHotspot.all.map(\.muscle) + BodyMapHotspot.extraChips)
        for muscle in mapped {
            XCTAssertGreaterThan(
                ExerciseLibrary.count(matching: muscle),
                0,
                "\(muscle.label) is on the body map but has no catalog moves"
            )
        }
    }

    func testFrontAndBackCoverTheCatalogMuscles() {
        let mapped = Set(BodyMapHotspot.all.map(\.muscle))
        let body = Set(TargetMuscle.allCases).subtracting([.fullBody, .cardio])
        XCTAssertEqual(mapped, body, "every anatomical muscle should be tappable on front or back")
    }

    func testFullBodyAndCardioLiveOnChipsNotTheSilhouette() {
        XCTAssertEqual(BodyMapHotspot.extraChips, [.fullBody, .cardio])
        XCTAssertFalse(BodyMapHotspot.all.contains { $0.muscle == .fullBody || $0.muscle == .cardio })
    }

    func testBicepsLiveOnTheFrontAndCalvesOnBothFaces() {
        let bicepsFaces = Set(BodyMapHotspot.all.filter { $0.muscle == .biceps }.map(\.face))
        let calfFaces = Set(BodyMapHotspot.all.filter { $0.muscle == .calves }.map(\.face))
        XCTAssertEqual(bicepsFaces, [.front])
        XCTAssertEqual(calfFaces, [.front, .back])
    }

    func testSpokenAliasesResolveToCatalogMuscles() {
        XCTAssertEqual(TargetMuscle.mentioned(in: "hit my biceps today"), .biceps)
        XCTAssertEqual(TargetMuscle.mentioned(in: "calf raises after the run"), .calves)
        XCTAssertEqual(TargetMuscle.mentioned(in: "hip flexor stretch"), .hipFlexors)
        XCTAssertNil(TargetMuscle.mentioned(in: "how did I sleep"))
    }

    func testPlanEngineBicepsAskUsesLibraryMoves() {
        let plan = AriaPlanEngine.evaluate(input: "build me a biceps session", context: Self.fixtureContext())
        XCTAssertTrue(plan.workoutPlan.name.localizedCaseInsensitiveContains("bicep"))
        XCTAssertFalse(plan.workoutPlan.exercises.isEmpty)
        XCTAssertTrue(plan.workoutPlan.exercises.contains { $0.name.localizedCaseInsensitiveContains("curl") })
        XCTAssertEqual(plan.richCard.type, .workoutPlan)
    }

    func testLibraryBuildSessionUsesTheTappedMuscle() {
        let plan = AriaPlanEngine.evaluate(input: "Biceps workout", context: Self.fixtureContext())
        XCTAssertTrue(plan.workoutPlan.exercises.contains { $0.name.localizedCaseInsensitiveContains("curl") })
        XCTAssertTrue(plan.workoutPlan.name.localizedCaseInsensitiveContains("bicep"))
    }

    func testPlanEngineCalfAskUsesLibraryMoves() {
        let plan = AriaPlanEngine.evaluate(input: "give me a calf workout", context: Self.fixtureContext())
        XCTAssertTrue(plan.workoutPlan.name.localizedCaseInsensitiveContains("calf"))
        XCTAssertTrue(plan.workoutPlan.exercises.contains { $0.name.localizedCaseInsensitiveContains("calf") })
    }

    func testGroupedByRegionCoversEveryMoveOnce() {
        let sections = ExerciseLibrary.grouped(query: "", muscle: nil, equipment: nil, pattern: nil, by: .region)
        XCTAssertEqual(sections.map(\.title), TargetMuscle.Region.allCases.map(\.label).filter { label in
            sections.contains { $0.title == label }
        })
        let ids = sections.flatMap { $0.items.map(\.id) }
        XCTAssertEqual(Set(ids).count, ids.count, "a move should appear in only one region group")
        XCTAssertEqual(Set(ids), Set(ExerciseLibrary.all.map(\.id)))
        XCTAssertEqual(ExerciseLibrary.OrganizeBy.allCases.map(\.label), ["Region", "Muscle", "Pattern", "Gear"])
    }

    func testGroupedByMusclePutsCompoundsFirst() {
        let sections = ExerciseLibrary.grouped(query: "", muscle: nil, equipment: nil, pattern: nil, by: .muscle)
        XCTAssertFalse(sections.isEmpty)
        XCTAssertTrue(sections.contains { $0.id == TargetMuscle.chest.rawValue && !$0.items.isEmpty })
        for section in sections {
            var seenIsolation = false
            for item in section.items {
                if item.isCompound {
                    XCTAssertFalse(seenIsolation, "\(section.title) should list compounds before isolations")
                } else {
                    seenIsolation = true
                }
            }
        }
    }

    func testHowToScriptNamesTheLiftAndWalksCues() throws {
        let bench = try XCTUnwrap(ExerciseLibrary.match("Barbell Bench Press"))
        let script = ExerciseLibrary.howToScript(for: bench)
        XCTAssertTrue(script.contains("Barbell Bench Press"))
        XCTAssertTrue(script.localizedCaseInsensitiveContains("horizontal push") || script.localizedCaseInsensitiveContains("barbell"))
        XCTAssertTrue(script.contains("Pin the shoulder blades"))
        XCTAssertTrue(script.contains("Watch for") || bench.faults.isEmpty)
    }

    func testGroupedByPatternKeepsEveryMove() {
        let sections = ExerciseLibrary.grouped(query: "", muscle: nil, equipment: nil, pattern: nil, by: .pattern)
        XCTAssertEqual(sections.flatMap(\.items).count, ExerciseLibrary.all.count)
    }

    func testFilterTreatsNilAsWildcard() {
        let all = ExerciseLibrary.filter(query: "")
        XCTAssertEqual(all.count, ExerciseLibrary.all.count)
        let cables = ExerciseLibrary.filter(query: "", equipment: .cable)
        XCTAssertFalse(cables.isEmpty)
        XCTAssertTrue(cables.allSatisfy { $0.equipment == .cable })
    }

    func testAriaSpeechPrepDropsEmptyAndCapsLength() {
        XCTAssertNil(AriaSpeechPrep.clipped("   "))
        XCTAssertNil(AriaSpeechPrep.clipped(""))
        XCTAssertEqual(AriaSpeechPrep.clipped("  Hello ARIA  "), "Hello ARIA")
        let long = String(repeating: "a", count: AriaSpeechPrep.characterLimit + 40)
        XCTAssertEqual(AriaSpeechPrep.clipped(long)?.count, AriaSpeechPrep.characterLimit)
    }

    private static func fixtureContext() -> TrainerContext {
        TrainerContext(
            userProfile: UserProfile(
                name: "Sam",
                gender: .male,
                fitnessGoals: [.buildMuscle],
                experienceLevel: .intermediate,
                preferredWorkouts: [.strength],
                coachingStyle: .balanced,
                connectedDevices: [],
                weeklySchedule: [1, 3, 5],
                trainingEquipment: .commercialGym
            ),
            readiness: ReadinessData(overall: 78, sleepQuality: 80, recoveryScore: 76, stressLevel: 30, energyBank: 70),
            dailyMetrics: DailyMetrics(steps: 8000, activeCalories: 400, hrv: 52, restingHR: 58, deepSleep: 90, totalSleep: 430),
            sleepData: [],
            workoutHistory: [],
            currentTime: Date(),
            conversationHistory: []
        )
    }
}
