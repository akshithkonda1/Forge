import XCTest
@testable import ForgeCore

// HealthKit is unavailable on macOS, and CI runs these through `swift test` on a
// Mac — so the mapping tests below compile out there. They are still worth
// carrying: they run the moment anyone tests on an iOS or watchOS destination,
// and they are the thing that catches a mapping collision.
#if canImport(HealthKit)
import HealthKit
#endif

final class WorkoutModelsTests: XCTestCase {

    // MARK: HR zones — parity with iOS Theme.swift hrZone(for:)

    func testZoneThresholdsMatchiOSTheme() {
        XCTAssertEqual(ForgeHRZones.zone(for: 109).zone, 1)
        XCTAssertEqual(ForgeHRZones.zone(for: 110).zone, 2)
        XCTAssertEqual(ForgeHRZones.zone(for: 129).zone, 2)
        XCTAssertEqual(ForgeHRZones.zone(for: 130).zone, 3)
        XCTAssertEqual(ForgeHRZones.zone(for: 149).zone, 3)
        XCTAssertEqual(ForgeHRZones.zone(for: 150).zone, 4)
        XCTAssertEqual(ForgeHRZones.zone(for: 164).zone, 4)
        XCTAssertEqual(ForgeHRZones.zone(for: 165).zone, 5)
        XCTAssertEqual(ForgeHRZones.zone(for: 200).zone, 5)
    }

    func testZoneByNumberRoundTrips() {
        for number in 1...5 {
            XCTAssertEqual(ForgeHRZones.zone(number: number).zone, number)
        }
    }

    func testEveryZoneHasSupportiveCoachingLine() {
        for number in 1...5 {
            let line = ForgeHRZones.zone(number: number).coachingLine
            XCTAssertFalse(line.isEmpty)
            for banned in ["push harder", "no excuses", "weak", "failed"] {
                XCTAssertFalse(line.lowercased().contains(banned))
            }
        }
    }

    // MARK: Workout types

    func testTargetZonesAreOrderedByIntensity() {
        XCTAssertLessThan(ForgeWorkoutType.mobility.targetZone, ForgeWorkoutType.cardio.targetZone)
        XCTAssertLessThan(ForgeWorkoutType.cardio.targetZone, ForgeWorkoutType.strength.targetZone)
        XCTAssertLessThan(ForgeWorkoutType.strength.targetZone, ForgeWorkoutType.hiit.targetZone)
    }

    // MARK: HealthKit activity type mapping
    //
    // Recovering a workout that outlived the app gives back only an
    // HKWorkoutConfiguration, so the mapping has to survive a round trip. If it
    // ever stops doing so, a recovered session comes back labelled as the wrong
    // kind of workout and its debrief reasons about the wrong target zone.

    #if canImport(HealthKit)
    func testEveryWorkoutTypeSurvivesAHealthKitRoundTrip() {
        for type in ForgeWorkoutType.allCases {
            XCTAssertEqual(
                ForgeWorkoutType(hkActivityType: type.hkActivityType),
                type,
                "\(type.rawValue) did not survive the HealthKit round trip"
            )
        }
    }

    func testDistinctForgeTypesUseDistinctHealthKitTypes() {
        // A collision would make the round trip above pass while still
        // resolving two different workouts to whichever case came first.
        let mapped = Set(ForgeWorkoutType.allCases.map(\.hkActivityType.rawValue))
        XCTAssertEqual(mapped.count, ForgeWorkoutType.allCases.count)
    }

    func testUnmappedActivityTypeFallsBackRatherThanTrapping() {
        XCTAssertEqual(ForgeWorkoutType(hkActivityType: .archery), .cardio)
    }
    #endif

    // MARK: Structured plan

    func testStarterPlanIsWellFormed() {
        let plan = StructuredWorkout.starterStrength
        XCTAssertFalse(plan.exercises.isEmpty)
        XCTAssertEqual(plan.totalSets, plan.exercises.reduce(0) { $0 + $1.sets.count })
        for exercise in plan.exercises {
            XCTAssertFalse(exercise.sets.isEmpty)
            XCTAssertGreaterThan(exercise.restSeconds, 0)
        }
    }

    // MARK: Live state

    func testWorkoutLiveStateCodableRoundTrip() throws {
        var state = WorkoutLiveState(
            workoutType: .strength,
            phase: .resting,
            startedAt: Date(timeIntervalSince1970: 1_750_000_000),
            elapsedSeconds: 754,
            heartRate: 132,
            zoneNumber: 3,
            activeCalories: 187.5,
            currentExerciseName: "Goblet Squat",
            currentExerciseIndex: 1,
            totalExercises: 4,
            currentSetIndex: 2,
            totalSetsInExercise: 3,
            restSecondsRemaining: 42
        )
        let decoded = try JSONDecoder().decode(
            WorkoutLiveState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded, state)

        state.phase = .ended
        XCTAssertNotEqual(decoded, state)
    }

    func testElapsedLabelFormatting() {
        var state = WorkoutLiveState(workoutType: .cardio, phase: .active, startedAt: Date())
        state.elapsedSeconds = 65
        XCTAssertEqual(state.elapsedLabel, "1:05")
        state.elapsedSeconds = 3725
        XCTAssertEqual(state.elapsedLabel, "1:02:05")
    }

    func testSnapshotWithActiveWorkoutStaysBackwardCompatible() throws {
        // Old snapshots (no activeWorkout key) must still decode.
        var old = WatchSnapshot()
        old.readinessOverall = 80
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(old)
        ) as! [String: Any]
        json.removeValue(forKey: "activeWorkout")
        let decoded = try JSONDecoder().decode(
            WatchSnapshot.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertNil(decoded.activeWorkout)
        XCTAssertEqual(decoded.readinessOverall, 80)
    }
}

final class WorkoutSuggestionEngineTests: XCTestCase {

    private func context(readiness: Int?, confidence: Double = 0.9) -> WatchARIAContext {
        var ctx = WatchARIAContext()
        ctx.readinessOverall = readiness
        ctx.readinessConfidence = confidence
        return ctx
    }

    func testRecoveryBandSuggestsGentleMobility() {
        let suggestion = WorkoutSuggestionEngine.suggest(for: context(readiness: 40))
        XCTAssertEqual(suggestion.type, .mobility)
        XCTAssertEqual(suggestion.targetZone, 1)
    }

    func testModerateBandSuggestsZone2Cardio() {
        let suggestion = WorkoutSuggestionEngine.suggest(for: context(readiness: 60))
        XCTAssertEqual(suggestion.type, .cardio)
        XCTAssertEqual(suggestion.targetZone, 2)
    }

    func testReadyBandSuggestsStrength() {
        let suggestion = WorkoutSuggestionEngine.suggest(for: context(readiness: 78))
        XCTAssertEqual(suggestion.type, .strength)
    }

    func testPrimedBandOffersIntensityWithoutPressure() {
        let suggestion = WorkoutSuggestionEngine.suggest(for: context(readiness: 90))
        XCTAssertEqual(suggestion.type, .hiit)
        // Primed copy must still leave the door open to NOT going hard.
        XCTAssertTrue(suggestion.reason.contains("or") || suggestion.reason.lowercased().contains("if you want"))
    }

    func testLowConfidenceNeverPrescribesIntensity() {
        let suggestion = WorkoutSuggestionEngine.suggest(for: context(readiness: 90, confidence: 0.1))
        XCTAssertEqual(suggestion.trigger, "low-confidence-default")
        XCTAssertLessThanOrEqual(suggestion.targetZone, 2)
    }

    func testAllReasonsFollowToneRules() {
        let contexts = [
            context(readiness: 30), context(readiness: 60),
            context(readiness: 78), context(readiness: 92),
            context(readiness: nil, confidence: 0),
        ]
        for ctx in contexts {
            let reason = WorkoutSuggestionEngine.suggest(for: ctx).reason
            let sentences = reason.split(whereSeparator: { ".!?".contains($0) })
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            XCTAssertLessThanOrEqual(sentences.count, 2, "too long: \(reason)")
            for banned in ["should have", "lazy", "guilt", "no excuses", "failed"] {
                XCTAssertFalse(reason.lowercased().contains(banned))
            }
        }
    }
}
