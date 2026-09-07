import XCTest
@testable import ForgeSwift

final class ExerciseLibraryFilterTests: XCTestCase {

    func testLibraryHasMoreThan215UniqueMoves() {
        let rows = ExerciseLibrary.all
        XCTAssertGreaterThanOrEqual(rows.count, 215, "library must be a real gym floor, not a starter pack")
        let ids = rows.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "every move needs a unique slug")
        let names = rows.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "every move needs a unique name")
        XCTAssertNotNil(ExerciseLibrary.match("Turkish Get-Up"))
        XCTAssertNotNil(ExerciseLibrary.match("Power Clean"))
        XCTAssertNotNil(ExerciseLibrary.match("Ski Erg"))
    }

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
        XCTAssertEqual(ExerciseLibrary.OrganizeBy.allCases.map(\.label), ["Style", "Region", "Muscle", "Pattern", "Gear"])
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

    func testStyleGroupsCalisthenicsAndSportsSeparately() {
        let sections = ExerciseLibrary.grouped(query: "", muscle: nil, equipment: nil, pattern: nil, by: .style)
        XCTAssertEqual(sections.map(\.title).first, "Calisthenics")
        XCTAssertTrue(sections.contains { $0.title == "Sports" })
        let ids = sections.flatMap { $0.items.map(\.id) }
        XCTAssertEqual(Set(ids).count, ids.count, "a move should appear in only one style group")
        XCTAssertEqual(Set(ids), Set(ExerciseLibrary.all.map(\.id)))

        let cali = sections.first { $0.title == "Calisthenics" }
        XCTAssertNotNil(cali)
        XCTAssertTrue(cali?.items.contains { $0.name == "Push-Up" } == true)
        XCTAssertTrue(cali?.items.contains { $0.name == "Pike Push-Up" } == true)
        XCTAssertFalse(cali?.items.contains { $0.name == "Foam Roll Flow" } == true)
        XCTAssertTrue(cali?.items.allSatisfy { $0.modality != .mobility } == true)

        let sports = sections.first { $0.title == "Sports" }
        XCTAssertTrue(sports?.items.contains { $0.name == "Basketball" } == true)
        XCTAssertTrue(sports?.items.contains { $0.name == "Tennis" } == true)
        XCTAssertTrue(sports?.items.allSatisfy { $0.trainingStyle == .sports } == true)
        XCTAssertGreaterThanOrEqual(ExerciseLibrary.sports.count, 12)
        XCTAssertEqual(ExerciseLibrary.matchSport(in: "I played hoops")?.name, "Basketball")
        XCTAssertEqual(ExerciseLibrary.matchSport(in: "log pickleball")?.name, "Pickleball")
        XCTAssertEqual(ExerciseLibrary.welcomeSubtitle, "Find a move. I'll walk you through it.")
    }

    func testCalisthenicsPlanUsesLibraryMoves() {
        let plan = ExerciseLibrary.calisthenicsPlan(keepLight: true, skipLegs: true)
        XCTAssertTrue(plan.name.localizedCaseInsensitiveContains("calisthenic"))
        XCTAssertFalse(plan.exercises.isEmpty)
        XCTAssertFalse(plan.exercises.contains { $0.name.localizedCaseInsensitiveContains("squat") })
    }

    func testSportSessionIsPartOfTraining() {
        let plan = ExerciseLibrary.sportSession(named: "Tennis", minutes: 45, completed: true)
        XCTAssertEqual(plan.type, .sportSpecific)
        XCTAssertEqual(plan.duration, 45)
        XCTAssertTrue(plan.exercises.contains { $0.name == "Tennis" })
        XCTAssertTrue(plan.exercises.contains { $0.reps.contains("45") })
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

    func testPlanEngineUsesMedicationAsForYouLifestyleNotAPrescription() {
        var context = Self.fixtureContext()
        context.medicationLayer = MedicationContext.resolve(savedNames: ["Xcopri"])
        XCTAssertTrue(context.medicationLayer.shouldSoftenTraining)
        XCTAssertTrue(context.medicationLayer.inferredNeeds.contains("Epilepsy"))
        let plan = AriaPlanEngine.evaluate(input: "what should I train today?", context: context)
        let text = (plan.narrative + " " + plan.workoutPlan.name).lowercased()
        XCTAssertTrue(text.contains("no prescription") || text.contains("no dose"))
        XCTAssertFalse(text.contains(" mg"))
        XCTAssertFalse(text.contains("take two"))
    }

    func testNextSessionAfterLegsIsChestAndAbs() {
        let yesterday = Calendar(identifier: .gregorian).date(byAdding: .hour, value: -20, to: Date())!
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let context = TrainerContext(
            userProfile: Self.fixtureContext().userProfile,
            readiness: Self.fixtureContext().readiness,
            dailyMetrics: Self.fixtureContext().dailyMetrics,
            sleepData: [],
            workoutHistory: [
                WorkoutHistory(
                    id: "w1",
                    date: iso.string(from: yesterday),
                    name: "Tuesday Leg Day",
                    type: .strength,
                    duration: 55,
                    volume: 8000,
                    intensity: .high
                )
            ],
            currentTime: Date(),
            conversationHistory: []
        )
        let focus = NextSessionFocus.suggest(
            history: context.workoutHistory,
            now: context.currentTime,
            experience: .intermediate,
            readiness: 72
        )
        XCTAssertEqual(focus.region, .push)
        XCTAssertEqual(focus.extra, .core)
        XCTAssertEqual(focus.avoided, .legs)
        XCTAssertEqual(focus.title, "Chest and abs")

        let plan = AriaPlanEngine.evaluate(input: "What should I train today?", context: context)
        let name = plan.workoutPlan.name.lowercased()
        XCTAssertTrue(name.contains("chest") || name.contains("abs") || name.contains("push"))
        XCTAssertFalse(plan.workoutPlan.exercises.contains { $0.name.localizedCaseInsensitiveContains("squat") })
        XCTAssertFalse(plan.workoutPlan.exercises.isEmpty)
    }

    func testWednesdayWithoutHistoryOpensChestAndAbsFromTheWeek() {
        let wednesday = Self.weekdayDate(4) // Calendar weekday: 1=Sun … 4=Wed
        XCTAssertEqual(WeeklySplit.sun0(from: wednesday), 3)

        let focus = NextSessionFocus.suggest(
            history: [],
            now: wednesday,
            experience: .intermediate,
            readiness: 72,
            mode: .rotate,
            split: WeeklySplitSlot.defaultWeek
        )
        XCTAssertEqual(focus.region, .push)
        XCTAssertEqual(focus.extra, .core)
        XCTAssertEqual(focus.title, "Chest and abs")
        XCTAssertEqual(focus.exerciseCount, 6)
        XCTAssertEqual(focus.weekday, 3)
    }

    func testReplayPriorOpensYesterdaysSlot() {
        let wednesday = Self.weekdayDate(4)
        let focus = NextSessionFocus.suggest(
            history: [],
            now: wednesday,
            experience: .intermediate,
            readiness: 70,
            replayPrior: true
        )
        XCTAssertEqual(focus.region, .legs)
        XCTAssertEqual(focus.weekday, 2)
        XCTAssertTrue(focus.reason.lowercased().contains("back"))
    }

    func testFixedThursdayIsPullEvenAfterLegs() {
        let thursday = Self.weekdayDate(5) // Thursday
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let yesterday = thursday.addingTimeInterval(-20 * 3600)
        let focus = NextSessionFocus.suggest(
            history: [
                WorkoutHistory(
                    id: "w1",
                    date: iso.string(from: yesterday),
                    name: "Tuesday Leg Day",
                    type: .strength,
                    duration: 55,
                    volume: 8000,
                    intensity: .high
                )
            ],
            now: thursday,
            experience: .intermediate,
            readiness: 74,
            mode: .fixed
        )
        XCTAssertEqual(focus.region, .pull)
        XCTAssertEqual(focus.weekday, 4)
        XCTAssertEqual(focus.planningMode, .fixed)
    }

    func testParseWeekdayAndReplayPhrases() {
        XCTAssertEqual(WeeklySplit.parseWeekday(in: "Do Tuesday's session"), 2)
        XCTAssertTrue(WeeklySplit.wantsReplayPrior("Do yesterday's session"))
        XCTAssertFalse(WeeklySplit.wantsReplayPrior("Build today's session from my sleep"))
    }

    func testInferRegionFromWorkoutName() {
        XCTAssertEqual(NextSessionFocus.inferRegion(name: "Tuesday Leg Day", type: .strength), .legs)
        XCTAssertEqual(NextSessionFocus.inferRegion(name: "Bench night", type: .strength), .push)
        XCTAssertEqual(NextSessionFocus.inferRegion(name: "Easy run", type: .cardio), .conditioning)
    }

    func testAriaSpeechPrepDropsEmptyAndCapsLength() {
        XCTAssertNil(AriaSpeechPrep.clipped("   "))
        XCTAssertNil(AriaSpeechPrep.clipped(""))
        XCTAssertEqual(AriaSpeechPrep.clipped("  Hello ARIA  "), "Hello ARIA")
        let long = String(repeating: "a", count: AriaSpeechPrep.characterLimit + 40)
        XCTAssertEqual(AriaSpeechPrep.clipped(long)?.count, AriaSpeechPrep.characterLimit)
    }

    private static func weekdayDate(_ weekday: Int) -> Date {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "en_US_POSIX")
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = weekday
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps) ?? Date()
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
