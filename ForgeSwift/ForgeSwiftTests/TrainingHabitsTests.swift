import XCTest
@testable import ForgeSwift

/// The algorithmic Train learner: every catalog exercise discoverable through
/// suggestions, every focus producing valid plans, sports first-class, and
/// the weekday pattern actually changing future rankings.
final class TrainingHabitsTests: XCTestCase {

    // MARK: - Focus coverage

    func testEveryFocusHasAChipLabel() {
        for focus in TrainingFocus.allCases {
            XCTAssertFalse(focus.chipLabel.isEmpty, "\(focus) needs a chip label")
        }
        XCTAssertEqual(TrainingFocus.allCases.count, 8)
    }

    func testEveryFocusMapsToCatalogMuscles() {
        for focus in TrainingFocus.allCases {
            XCTAssertFalse(focus.muscles.isEmpty, "\(focus) must cover catalog muscles")
        }
    }

    func testEveryFocusResolvesThroughMentionedMuscle() {
        // The box's chips must round-trip through the same parser the plan
        // engine uses — a chip that builds no plan is a dead button.
        for focus in TrainingFocus.allCases {
            let resolved = TrainingFocus.from(text: focus.chipLabel)
            XCTAssertEqual(resolved, focus, "'\(focus.chipLabel)' chip must resolve to \(focus)")
        }
    }

    func testEveryCatalogExerciseIsReachableFromSomeFocus() {
        // No orphaned moves: each exercise's primary muscle belongs to at
        // least one focus, so the box can surface the whole library.
        let uncovered = ExerciseLibrary.all.filter { def in
            !TrainingFocus.allCases.contains { focus in
                def.primary.contains { focus.muscles.contains($0) }
            }
        }
        XCTAssertTrue(
            uncovered.isEmpty,
            "exercises unreachable from any focus: \(uncovered.prefix(5).map(\.name))"
        )
    }

    func testEveryFocusHasSportAlternativeOrDocumentedGap() {
        // Sports must coexist with muscle suggestions — a focus with no
        // matching sport simply skips the alternative line (nil), never crashes.
        for focus in TrainingFocus.allCases {
            let matches = ExerciseLibrary.sportsFor(muscles: focus.muscles)
            for sport in matches {
                XCTAssertTrue(
                    sport.primary.contains { focus.muscles.contains($0) }
                        || sport.secondary.contains { focus.muscles.contains($0) },
                    "\(sport.name) must actually train \(focus)"
                )
            }
        }
        // Legs and conditioning definitely have sports; the line must exist.
        XCTAssertFalse(ExerciseLibrary.sportsFor(muscles: TrainingFocus.legs.muscles).isEmpty)
    }

    // MARK: - Weekday learning

    func testColdHabitsSuggestNothing() {
        let habits = TrainingHabits()
        XCTAssertNil(habits.suggestion(forWeekday: 1), "no data → ask, don't guess")
    }

    func testSingleObservationIsNotAPattern() {
        var habits = TrainingHabits()
        habits.record(.focus(.chest), weekday: 1)
        XCTAssertNil(habits.suggestion(forWeekday: 1), "one Monday isn't a pattern")
    }

    func testRepeatedWeekdayChoiceBecomesSuggestion() {
        var habits = TrainingHabits()
        habits.record(.focus(.chest), weekday: 1)
        habits.record(.focus(.chest), weekday: 1)
        let suggestion = habits.suggestion(forWeekday: 1)
        XCTAssertEqual(suggestion?.choice, .focus(.chest))
        XCTAssertTrue(suggestion?.reason.contains("Monday") == true)
        XCTAssertTrue(suggestion?.reason.contains("chest") == true)
    }

    func testPatternIsWeekdaySpecific() {
        var habits = TrainingHabits()
        habits.record(.focus(.chest), weekday: 1)
        habits.record(.focus(.chest), weekday: 1)
        XCTAssertNil(habits.suggestion(forWeekday: 2), "Tuesday shouldn't inherit Monday's pattern")
    }

    func testSplitPatternChangesWhenBehaviorChanges() {
        var habits = TrainingHabits()
        // Two chest Mondays → chest predicted.
        habits.record(.focus(.chest), weekday: 1)
        habits.record(.focus(.chest), weekday: 1)
        XCTAssertEqual(habits.suggestion(forWeekday: 1)?.choice, .focus(.chest))
        // Three back Mondays → the ranking flips to back.
        habits.record(.focus(.back), weekday: 1)
        habits.record(.focus(.back), weekday: 1)
        habits.record(.focus(.back), weekday: 1)
        XCTAssertEqual(habits.suggestion(forWeekday: 1)?.choice, .focus(.back))
    }

    func testMixedWeekdayStaysBelowConfidence() {
        var habits = TrainingHabits()
        habits.record(.focus(.chest), weekday: 1)
        habits.record(.focus(.back), weekday: 1)
        habits.record(.focus(.legs), weekday: 1)
        habits.record(.focus(.chest), weekday: 1)
        // 2/4 = 50% — below the 60% dominance bar. Ask, don't guess.
        XCTAssertNil(habits.suggestion(forWeekday: 1))
    }

    // MARK: - Sports

    func testSportsOnlyOnboardingYieldsSportsShelf() {
        var habits = TrainingHabits()
        habits.seedFromProfile(weeklySplit: [], scheduleMode: .fixed, sportNames: ["Swimming", "Tennis"])
        XCTAssertEqual(habits.favoriteSports, ["Swimming", "Tennis"])
        XCTAssertGreaterThanOrEqual(habits.sportAffinity, 0.5)
    }

    func testSportAffinityGrowsWithSportChoices() {
        var habits = TrainingHabits()
        XCTAssertEqual(habits.sportAffinity, 0)
        habits.record(.sport("Swimming"), weekday: 3)
        habits.record(.sport("Swimming"), weekday: 3)
        XCTAssertGreaterThan(habits.sportAffinity, 0.2)
        XCTAssertEqual(habits.favoriteSports.first, "Swimming")
    }

    func testHighSportAffinitySuggestsSportOnBlankWeekday() {
        var habits = TrainingHabits()
        habits.seedFromProfile(weeklySplit: [], scheduleMode: .fixed, sportNames: ["Boxing"])
        // Four sport picks push affinity to 0.5 + 4×0.15 = 1.0 (capped).
        for _ in 0..<4 { habits.record(.sport("Boxing"), weekday: 5) }
        let suggestion = habits.suggestion(forWeekday: 2)
        XCTAssertEqual(suggestion?.choice, .sport("Boxing"))
    }

    func testMuscleChoicesDecaySportAffinity() {
        var habits = TrainingHabits()
        habits.seedFromProfile(weeklySplit: [], scheduleMode: .fixed, sportNames: ["Boxing"])
        for _ in 0..<12 { habits.record(.focus(.chest), weekday: 1) }
        XCTAssertEqual(habits.sportAffinity, 0, accuracy: 0.001)
    }

    // MARK: - Ownership modes

    func testRotateModeHandsAriaTheWeek() {
        var habits = TrainingHabits()
        habits.seedFromProfile(weeklySplit: [], scheduleMode: .rotate, sportNames: [])
        XCTAssertEqual(habits.mode, .ariaLeads)
        // Delegated: no suggestion, no box — ARIA just builds.
        habits.record(.focus(.chest), weekday: 1)
        habits.record(.focus(.chest), weekday: 1)
        XCTAssertNil(habits.suggestion(forWeekday: 1))
    }

    func testFixedModeKeepsUserInCharge() {
        var habits = TrainingHabits()
        habits.seedFromProfile(weeklySplit: [], scheduleMode: .fixed, sportNames: [])
        XCTAssertEqual(habits.mode, .userLeads)
    }

    func testSetModeFlipsOwnership() {
        var habits = TrainingHabits()
        habits.setMode(.ariaLeads)
        XCTAssertEqual(habits.mode, .ariaLeads)
        habits.setMode(.userLeads)
        XCTAssertEqual(habits.mode, .userLeads)
    }

    // MARK: - Onboarding seeding

    func testWeeklySplitSeedsDayOnePredictions() {
        var habits = TrainingHabits()
        let split = [
            WeeklySplitSlot(weekday: 1, primary: "push", extra: nil, exerciseCount: 5),
            WeeklySplitSlot(weekday: 3, primary: "legs", extra: nil, exerciseCount: 6),
            WeeklySplitSlot(weekday: 0, primary: "rest", extra: nil, exerciseCount: 0),
        ]
        habits.seedFromProfile(weeklySplit: split, scheduleMode: .fixed, sportNames: [])
        XCTAssertEqual(habits.suggestion(forWeekday: 1)?.choice, .focus(.chest))
        XCTAssertEqual(habits.suggestion(forWeekday: 3)?.choice, .focus(.legs))
        XCTAssertNil(habits.suggestion(forWeekday: 0), "rest days predict nothing")
    }

    // MARK: - Phrases

    func testTakeChargePhrases() {
        for phrase in ["take charge", "you pick", "surprise me", "whatever you think",
                       "rotate for me", "you decide", "i trust you", "dealer's choice"] {
            XCTAssertTrue(TrainingHabits.isTakeChargePhrase(in: phrase), "'\(phrase)'")
        }
        XCTAssertFalse(TrainingHabits.isTakeChargePhrase(in: "give me a workout"))
    }

    func testUserLedPhrases() {
        for phrase in ["i'll pick", "let me decide", "my call", "i will choose"] {
            XCTAssertTrue(TrainingHabits.isUserLedPhrase(in: phrase), "'\(phrase)'")
        }
        XCTAssertFalse(TrainingHabits.isUserLedPhrase(in: "give me a workout"))
    }

    func testSportPickerRequests() {
        XCTAssertTrue(TrainingHabits.isSportPickerRequest(in: "sports"))
        XCTAssertTrue(TrainingHabits.isSportPickerRequest(in: "something sporty"))
        XCTAssertFalse(TrainingHabits.isSportPickerRequest(in: "swimming"))
        XCTAssertFalse(TrainingHabits.isSportPickerRequest(in: "give me a chest workout"))
    }

    // MARK: - Persistence round-trip

    func testHabitsSurviveCodableRoundTrip() {
        var habits = TrainingHabits()
        habits.record(.focus(.chest), weekday: 1)
        habits.record(.focus(.chest), weekday: 1)
        habits.record(.sport("Swimming"), weekday: 3)
        habits.setMode(.ariaLeads)
        let data = try! JSONEncoder().encode(habits)
        let restored = try! JSONDecoder().decode(TrainingHabits.self, from: data)
        XCTAssertEqual(restored.mode, .ariaLeads)
        XCTAssertEqual(restored.favoriteSports.first, "Swimming")
        XCTAssertGreaterThan(restored.sportAffinity, 0)
        // Weekday counts survive — the pattern persists across relaunch.
        habits.setMode(.userLeads)
        let data2 = try! JSONEncoder().encode(habits)
        let restored2 = try! JSONDecoder().decode(TrainingHabits.self, from: data2)
        XCTAssertEqual(restored2.suggestion(forWeekday: 1)?.choice, .focus(.chest))
    }

    func testWeekdayIndexConvention() {
        // WeeklySplit convention: 0 = Sunday … 6 = Saturday.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // 2026-09-21 is a Monday.
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21))!
        XCTAssertEqual(TrainingHabits.weekdayIndex(for: monday, calendar: calendar), 1)
        XCTAssertEqual(TrainingHabits.weekdayName(for: 1), "Monday")
    }

    // MARK: - Chip routing

    func testBoxChipsAreExactLabels() {
        for focus in TrainingFocus.allCases {
            XCTAssertTrue(TrainingHabits.isBoxChip(focus.chipLabel), focus.chipLabel)
        }
        XCTAssertTrue(TrainingHabits.isBoxChip("Sports"))
        XCTAssertTrue(TrainingHabits.isBoxChip("You pick"))
        XCTAssertTrue(TrainingHabits.isBoxChip("Something else"))
        // Precision: injury-adjacent prose must NOT route as a chip.
        XCTAssertFalse(TrainingHabits.isBoxChip("my shoulders are tight"))
        XCTAssertFalse(TrainingHabits.isBoxChip("chest day was hard"))
    }

    func testBareChipTextRoutesToTraining() {
        let signals = AriaIntentInput(text: "Chest")
        let turn = AriaDummyTurn.interpret(
            text: "Chest",
            agent: .aria,
            agents: [],
            signals: signals,
            sleepWeak: false,
            readinessLow: false
        )
        XCTAssertTrue(turn.domains.contains(.training), "a 'Chest' chip tap must reach the training worker")
    }

    // MARK: - Integration (through the orchestrator)

    func testVagueRequestShowsSuggestionBox() async {
        let store = AppStore()
        let reply = await AriaDummyOrchestrator.reply(
            text: "what should I train today",
            store: store,
            agent: .aria,
            agents: nil
        )
        XCTAssertNil(store.todayWorkout, "the box asks — it doesn't build yet")
        let chips = reply.suggestedActions ?? []
        XCTAssertTrue(chips.contains("Chest"), "box chips: \(chips)")
        XCTAssertTrue(chips.contains("Sports"), "box chips: \(chips)")
        XCTAssertTrue(chips.contains("You pick"), "box chips: \(chips)")
        XCTAssertGreaterThanOrEqual(chips.count, 10, "the full box survives — no 4-chip truncation: \(chips)")
    }

    func testChestChipTapBuildsChestPlan() async throws {
        let store = AppStore()
        let reply = await AriaDummyOrchestrator.reply(
            text: "Chest",
            store: store,
            agent: .aria,
            agents: nil
        )
        let workout = try XCTUnwrap(store.todayWorkout, "tapping Chest must build the plan")
        XCTAssertFalse(workout.exercises.isEmpty)
        XCTAssertTrue(
            workout.exercises.contains {
                ExerciseLibrary.match($0.name)?.primary.contains(.chest) == true
                    || ExerciseLibrary.match($0.name)?.secondary.contains(.chest) == true
            },
            "a Chest tap should build chest work, not a generic plan"
        )
        XCTAssertFalse(reply.message.isEmpty)
    }

    func testTakeChargeSkipsTheBox() async throws {
        let store = AppStore()
        _ = await AriaDummyOrchestrator.reply(
            text: "take charge",
            store: store,
            agent: .aria,
            agents: nil
        )
        XCTAssertEqual(store.trainingHabits.mode, .ariaLeads)
        // Delegated: the next vague request builds straight away, no box.
        _ = await AriaDummyOrchestrator.reply(
            text: "what should I train today",
            store: store,
            agent: .aria,
            agents: nil
        )
        XCTAssertNotNil(store.todayWorkout, "delegated mode builds without asking")
    }
}
