import XCTest
@testable import ForgeCore

final class HydrationEngineTests: XCTestCase {

    func testTargetScalesWithBodyMass() {
        let light = HydrationEngine.targetMilliliters(weightKilograms: 55)
        let heavy = HydrationEngine.targetMilliliters(weightKilograms: 90)
        XCTAssertGreaterThan(heavy, light)
        XCTAssertEqual(light, 55 * HydrationEngine.millilitersPerKilogram, accuracy: 0.1)
    }

    func testTargetFallsBackToDefaultWeight() {
        let fallback = HydrationEngine.targetMilliliters(weightKilograms: nil)
        let explicit = HydrationEngine.targetMilliliters(
            weightKilograms: HydrationEngine.defaultWeightKilograms
        )
        XCTAssertEqual(fallback, explicit, accuracy: 0.1)
    }

    func testTargetIsClampedToPhysiologicalRange() {
        let tiny = HydrationEngine.targetMilliliters(weightKilograms: 20)
        XCTAssertGreaterThanOrEqual(tiny, HydrationEngine.minimumTargetMilliliters)

        let huge = HydrationEngine.targetMilliliters(
            weightKilograms: 140,
            activeCalories: 4_000,
            hotEnvironment: true
        )
        XCTAssertLessThanOrEqual(huge, HydrationEngine.maximumTargetMilliliters)
    }

    func testActivityAddsMilliliterPerKilocalorie() {
        let rest = HydrationEngine.targetMilliliters(weightKilograms: 70, activeCalories: 0)
        let session = HydrationEngine.targetMilliliters(weightKilograms: 70, activeCalories: 500)
        XCTAssertEqual(session - rest, 500, accuracy: 0.1)
    }

    func testActivityBonusIsCapped() {
        let rest = HydrationEngine.targetMilliliters(weightKilograms: 70, activeCalories: 0)
        let long = HydrationEngine.targetMilliliters(weightKilograms: 70, activeCalories: 5_000)
        XCTAssertEqual(long - rest, 1_200, accuracy: 0.1)
    }

    func testCycleAdjustmentsRaiseNeed() {
        let base = HydrationEngine.targetMilliliters(weightKilograms: 70, cycle: .none)
        let luteal = HydrationEngine.targetMilliliters(weightKilograms: 70, cycle: .luteal)
        let period = HydrationEngine.targetMilliliters(weightKilograms: 70, cycle: .menstruation)
        XCTAssertEqual(luteal - base, HydrationEngine.lutealBonusMilliliters, accuracy: 0.1)
        XCTAssertEqual(period - base, HydrationEngine.menstruationBonusMilliliters, accuracy: 0.1)
        XCTAssertGreaterThan(period, luteal)
    }

    func testGlassConversionRoundTrips() {
        let glasses = HydrationEngine.glasses(fromMilliliters: 474)
        XCTAssertEqual(glasses, 2, accuracy: 0.01)
        XCTAssertEqual(HydrationEngine.milliliters(fromGlasses: 2), 474, accuracy: 0.01)
    }

    func testOunceConversionMatchesUSFluidOunce() {
        let ml = HydrationEngine.milliliters(fromFluidOunces: 8)
        XCTAssertEqual(ml, 8 * HydrationEngine.millilitersPerFluidOunce, accuracy: 0.01)
        XCTAssertEqual(HydrationEngine.fluidOunces(fromMilliliters: ml), 8, accuracy: 0.01)
    }

    func testExpectedIsZeroJustAfterWake() {
        let target = 2_000.0
        let expected = HydrationEngine.expectedMilliliters(
            atHour: 7.2, target: target, wakeHour: 7, onsetHour: 23
        )
        XCTAssertEqual(expected, 0, accuracy: 0.1)
    }

    func testExpectedReachesTargetBeforeEveningTaper() {
        let target = 2_000.0
        // Onset 23, taper 2h → should be done by 21:00.
        let atTaper = HydrationEngine.expectedMilliliters(
            atHour: 21, target: target, wakeHour: 7, onsetHour: 23
        )
        XCTAssertEqual(atTaper, target, accuracy: 0.1)
        let late = HydrationEngine.expectedMilliliters(
            atHour: 22.5, target: target, wakeHour: 7, onsetHour: 23
        )
        XCTAssertEqual(late, target, accuracy: 0.1)
    }

    func testExpectedClimbsThroughTheWakingDay() {
        let target = 2_000.0
        let morning = HydrationEngine.expectedMilliliters(
            atHour: 10, target: target, wakeHour: 7, onsetHour: 23
        )
        let afternoon = HydrationEngine.expectedMilliliters(
            atHour: 15, target: target, wakeHour: 7, onsetHour: 23
        )
        XCTAssertGreaterThan(afternoon, morning)
        XCTAssertGreaterThan(morning, 0)
        XCTAssertLessThan(afternoon, target)
    }

    func testExpectedHoldsForANightOwl() {
        let target = 2_000.0
        let early = HydrationEngine.expectedMilliliters(
            atHour: 10.2, target: target, wakeHour: 10, onsetHour: 2
        )
        XCTAssertEqual(early, 0, accuracy: 0.1, "twelve minutes after a 10am wake is still the ramp")
        let done = HydrationEngine.expectedMilliliters(
            atHour: 0, target: target, wakeHour: 10, onsetHour: 2
        )
        XCTAssertEqual(done, target, accuracy: 0.1, "midnight is inside a 2am-onset taper")
    }

    func testStatusBehindOnTrackMetOver() {
        XCTAssertEqual(HydrationEngine.status(consumed: 400, target: 2_000, expected: 1_000), .behind)
        XCTAssertEqual(HydrationEngine.status(consumed: 950, target: 2_000, expected: 1_000), .onTrack)
        XCTAssertEqual(HydrationEngine.status(consumed: 2_000, target: 2_000, expected: 2_000), .met)
        XCTAssertEqual(HydrationEngine.status(consumed: 2_400, target: 2_000, expected: 2_000), .over)
    }

    func testGuidanceNamesTheGapWhenBehind() {
        let text = HydrationEngine.guidance(status: .behind, remaining: 500, hoursUntilOnset: 8)
        XCTAssertTrue(text.lowercased().contains("glass"))
        XCTAssertFalse(text.isEmpty)
    }

    func testGuidanceTapersLateEvenWhenBehind() {
        let text = HydrationEngine.guidance(status: .behind, remaining: 800, hoursUntilOnset: 1.5)
        XCTAssertTrue(text.lowercased().contains("late") || text.lowercased().contains("small"))
    }

    func testResolvedTargetPrefersAUserGoal() {
        let suggested = 2_310.0
        XCTAssertEqual(
            HydrationEngine.resolvedTargetMilliliters(userGoal: 3_000, suggested: suggested),
            3_000,
            accuracy: 0.1
        )
        XCTAssertEqual(
            HydrationEngine.resolvedTargetMilliliters(userGoal: nil, suggested: suggested),
            suggested,
            accuracy: 0.1
        )
    }

    func testResolvedTargetClampsAWildUserGoal() {
        XCTAssertEqual(
            HydrationEngine.resolvedTargetMilliliters(userGoal: 50, suggested: 2_000),
            HydrationEngine.minimumTargetMilliliters,
            accuracy: 0.1
        )
        XCTAssertEqual(
            HydrationEngine.resolvedTargetMilliliters(userGoal: 80_000, suggested: 2_000),
            HydrationEngine.maximumTargetMilliliters,
            accuracy: 0.1
        )
    }

    func testPresetsArePositiveAndOrdered() {
        let mls = HydrationEngine.presets.map(\.milliliters)
        XCTAssertEqual(HydrationEngine.presets.count, 4)
        XCTAssertEqual(mls, mls.sorted())
        XCTAssertTrue(mls.allSatisfy { $0 > 0 })
    }
}
