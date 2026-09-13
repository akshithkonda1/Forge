import XCTest
@testable import ForgeSwift

/// Locks Train auto-scale, extra-set, and nav copy so the tab stays a session
/// — not a catalog — and Sleep's empty state stays honest.
@MainActor
final class TrainSleepUsableTests: XCTestCase {

    func testTrainTabIsNotNamedWorkout() {
        XCTAssertEqual(TabItem.workout.label, "Train")
        XCTAssertEqual(ForgePrimaryDestination.workout.title, "Train")
    }

    func testAutoScaleCutsVolumeWhenReadinessIsLow() {
        let plan = samplePlan(sets: 4, weight: 135, duration: 45)
        let low = ReadinessData(overall: 40, sleepQuality: 40, recoveryScore: 40, stressLevel: 70, energyBank: 30)
        let scaled = AdaptiveEngine.apply(to: plan, readiness: low, experience: .intermediate)
        XCTAssertTrue(scaled.autoScaled)
        XCTAssertLessThan(scaled.exercises[0].sets, 4)
        XCTAssertLessThan(scaled.exercises[0].weight ?? 135, 135)
        XCTAssertEqual(scaled.scaleHeadline, "Recovery day protocol")
    }

    func testAutoScaleLeavesOnPlanUnmodified() {
        let plan = samplePlan(sets: 4, weight: 135, duration: 45)
        let mid = ReadinessData(overall: 75, sleepQuality: 75, recoveryScore: 75, stressLevel: 40, energyBank: 70)
        let scaled = AdaptiveEngine.apply(to: plan, readiness: mid, experience: .intermediate)
        XCTAssertFalse(scaled.autoScaled)
        XCTAssertEqual(scaled.exercises[0].sets, 4)
        XCTAssertEqual(scaled.exercises[0].weight, 135)
        XCTAssertEqual(scaled.scaleHeadline, "On plan")
    }

    func testAddFeltSetDoesNotUndoScale() {
        let store = AppStore()
        store.todayWorkout = samplePlan(sets: 3, weight: 100, duration: 30)
        store.addFeltSet(exerciseId: "bench")
        XCTAssertEqual(store.todayWorkout?.exercises.first?.sets, 4)
        store.addFeltSet(exerciseId: "missing")
        XCTAssertEqual(store.todayWorkout?.exercises.first?.sets, 4)
    }

    func testSleepEmptyCopyNeverAsksAriaWhenThereIsNoNight() {
        let copy = HealthKitSleepService.dayEmptyCopy(healthConnected: true)
        XCTAssertFalse(copy.cta.localizedCaseInsensitiveContains("ask"))
        XCTAssertTrue(copy.message.localizedCaseInsensitiveContains("apple health"))
    }

    private func samplePlan(sets: Int, weight: Int, duration: Int) -> WorkoutPlan {
        WorkoutPlan(
            id: "train-test",
            name: "Push",
            type: .strength,
            duration: duration,
            intensity: .high,
            exercises: [
                Exercise(
                    id: "bench",
                    name: "Bench Press",
                    sets: sets,
                    reps: "8",
                    weight: weight,
                    restSeconds: 90,
                    notes: nil
                )
            ]
        )
    }
}
