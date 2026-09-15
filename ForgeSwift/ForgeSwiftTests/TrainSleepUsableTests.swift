import XCTest
import ForgeCore
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

    func testTrainDayCallRestWinsOverHighReadiness() {
        XCTAssertEqual(TrainDayCall.resolve(readiness: 90, isRestDay: true, intensity: .high), .rest)
        XCTAssertEqual(TrainDayCall.rest.cta, "Optional easy work")
    }

    func testTrainDayCallRecoverWhenReadinessIsLow() {
        XCTAssertEqual(TrainDayCall.resolve(readiness: 40, isRestDay: false, intensity: .high), .recover)
        XCTAssertEqual(TrainDayCall.resolve(readiness: 80, isRestDay: false, intensity: .high), .train)
        XCTAssertEqual(TrainDayCall.resolve(readiness: 62, isRestDay: false, intensity: .high), .easy)
    }

    func testAgingQuestionIsNotClassifiedAsTraining() {
        let gen = RuleBasedResponseGenerator()
        XCTAssertEqual(gen.domain(of: "what's my training age?"), .aging)
        XCTAssertEqual(gen.domain(of: "how old am I compared to fitness age"), .aging)
        XCTAssertEqual(gen.domain(of: "what should I train today?"), .training)
    }

    func testAgingLiveFetchIsAllowedWithoutLocalTestingGate() {
        XCTAssertTrue(
            AriaWebResearch.liveFetchAllowed(question: "what's my training age?", domainRawValue: "lifestyle")
        )
        XCTAssertTrue(
            AriaWebResearch.liveFetchAllowed(question: "hello", domainRawValue: "aging")
        )
        XCTAssertTrue(
            AriaWebResearch.isResearchWorthy(text: "what's my fitness age?", leadingDomain: .lifestyle)
        )
        XCTAssertTrue(
            AriaWebResearch.isDummyResearchWorthy(text: "VO2 max cardiorespiratory fitness")
        )
    }

    func testVendorAgesReachLifestyleAndTrainBridge() {
        AgingVendorStore.replaceAll([
            AgingVendorAge(kind: .fitness, years: 32, confidence: 0.9, source: "garmin"),
            AgingVendorAge(kind: .inner, years: 33, confidence: 0.8, source: "ultrahuman")
        ])
        defer { AgingVendorStore.replaceAll([]) }
        let snap = AgingBridge.snapshot(age: 38, sexFemale: false, stats: nil)
        XCTAssertLessThan(snap.biologicalAge ?? 99, 38)
        XCTAssertTrue(snap.sources.contains { $0.contains("garmin") })
        XCTAssertTrue(snap.hasComparison)
    }

    func testOpenTrainHomeDoesNotStartTheWorkout() {
        let store = AppStore()
        store.todayWorkout = samplePlan(sets: 3, weight: 100, duration: 30)
        store.openTrainHome()
        XCTAssertFalse(store.isWorkoutActive)
        XCTAssertEqual(store.activeTab, .workout)
        XCTAssertNotNil(store.todayWorkout)
    }

    func testLifeShapedSessionLandsOnTrainIdle() {
        let store = AppStore()
        store.startLifeShapedSession()
        XCTAssertFalse(store.isWorkoutActive)
        XCTAssertEqual(store.activeTab, .workout)
        XCTAssertNotNil(store.todayWorkout)
    }

    func testHomePrimaryActionOpensSessionInsteadOfStarting() {
        let action = HomePrimaryAction.startWorkout(id: "p", name: "Push")
        XCTAssertFalse(action.title.localizedCaseInsensitiveContains("start"))
        XCTAssertTrue(action.title.localizedCaseInsensitiveContains("session"))
        XCTAssertEqual(action.icon, "dumbbell.fill")
    }

    func testWriteTodaysSessionDoesNotStartTheWorkout() {
        let store = AppStore()
        store.rebuildTodayPlanFromLife()
        XCTAssertFalse(store.isWorkoutActive)
        XCTAssertNotNil(store.todayWorkout)
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
