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

    func testPlanEngineCalfAskUsesLibraryMoves() {
        let plan = AriaPlanEngine.evaluate(input: "give me a calf workout", context: Self.fixtureContext())
        XCTAssertTrue(plan.workoutPlan.name.localizedCaseInsensitiveContains("calf"))
        XCTAssertTrue(plan.workoutPlan.exercises.contains { $0.name.localizedCaseInsensitiveContains("calf") })
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
