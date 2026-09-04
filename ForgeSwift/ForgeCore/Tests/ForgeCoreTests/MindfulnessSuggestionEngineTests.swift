import XCTest
@testable import ForgeCore

final class MindfulnessSuggestionEngineTests: XCTestCase {

    /// Builds a context pinned to a specific hour so tests are independent
    /// of when they run.
    private func context(hour: Int) -> WatchARIAContext {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 0
        var ctx = WatchARIAContext(timestamp: Calendar.current.date(from: components)!)
        ctx.readinessOverall = 75
        ctx.readinessConfidence = 0.9
        return ctx
    }

    func testLongDeskBlockWithHRVDipSuggests90SecondSigh() {
        var ctx = context(hour: 14)
        ctx.lifestyleMode = .deskCoding
        ctx.minutesInCurrentMode = 95
        ctx.hrvTrendMs = -8

        let rec = MindfulnessSuggestionEngine.suggest(for: ctx)
        XCTAssertEqual(rec.practice, .physiologicalSigh)
        XCTAssertEqual(rec.duration, 90)
        XCTAssertEqual(rec.trigger, "desk-block-hrv-dip")
    }

    func testLongDeskBlockWithoutDipSuggestsFocusReset() {
        var ctx = context(hour: 14)
        ctx.lifestyleMode = .deepFocus
        ctx.minutesInCurrentMode = 120

        let rec = MindfulnessSuggestionEngine.suggest(for: ctx)
        XCTAssertEqual(rec.practice, .focusReset)
        XCTAssertEqual(rec.trigger, "desk-block-90m")
    }

    func testShortDeskBlockDoesNotTriggerDeskRule() {
        var ctx = context(hour: 14)
        ctx.lifestyleMode = .deskCoding
        ctx.minutesInCurrentMode = 30

        let rec = MindfulnessSuggestionEngine.suggest(for: ctx)
        XCTAssertNotEqual(rec.trigger, "desk-block-90m")
    }

    func testPostWorkoutWinsOverEverything() {
        var ctx = context(hour: 14)
        ctx.hoursSinceLastWorkout = 0.25
        ctx.lifestyleMode = .deskCoding
        ctx.minutesInCurrentMode = 200
        ctx.hrvTrendMs = -10

        let rec = MindfulnessSuggestionEngine.suggest(for: ctx)
        XCTAssertEqual(rec.practice, .bodyScan)
        XCTAssertEqual(rec.trigger, "post-workout-reset")
    }

    func testEveningSuggestsWindDown() {
        let rec = MindfulnessSuggestionEngine.suggest(for: context(hour: 21))
        XCTAssertEqual(rec.practice, .windDown)
    }

    func testEveningAfterPoorSleepExtendsWindDown() {
        var poor = context(hour: 21)
        poor.sleepQualityScore = 40
        var good = context(hour: 21)
        good.sleepQualityScore = 90

        XCTAssertGreaterThan(
            MindfulnessSuggestionEngine.suggest(for: poor).duration,
            MindfulnessSuggestionEngine.suggest(for: good).duration
        )
    }

    func testLowReadinessMorningIsGentle() {
        var ctx = context(hour: 7)
        ctx.readinessOverall = 42

        let rec = MindfulnessSuggestionEngine.suggest(for: ctx)
        XCTAssertEqual(rec.practice, .morningGrounding)
        XCTAssertEqual(rec.trigger, "low-readiness-morning")
    }

    func testLowConfidenceReadinessIsNotTreatedAsFact() {
        // SimRunner honesty: a low score backed by almost no data must not
        // drive the "low readiness" coaching path.
        var ctx = context(hour: 15)
        ctx.readinessOverall = 30
        ctx.readinessConfidence = 0.1

        let rec = MindfulnessSuggestionEngine.suggest(for: ctx)
        XCTAssertNotEqual(rec.trigger, "low-readiness")
    }

    func testEveryRecommendationHasSupportiveNonEmptyReason() {
        var contexts: [WatchARIAContext] = []
        for hour in [7, 12, 15, 21] {
            var ctx = context(hour: hour)
            contexts.append(ctx)
            ctx.lifestyleMode = .deskCoding
            ctx.minutesInCurrentMode = 100
            contexts.append(ctx)
            ctx.hrvTrendMs = -9
            contexts.append(ctx)
        }
        for ctx in contexts {
            let rec = MindfulnessSuggestionEngine.suggest(for: ctx)
            XCTAssertFalse(rec.reason.isEmpty)
            // Max two sentences, per the ARIA watch voice rules.
            let sentences = rec.reason.split(whereSeparator: { ".!?".contains($0) })
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            XCTAssertLessThanOrEqual(sentences.count, 2, "reason too long: \(rec.reason)")
            // Guilt words are banned from the wrist.
            for banned in ["should have", "failed", "lazy", "guilt", "missed your"] {
                XCTAssertFalse(rec.reason.lowercased().contains(banned))
            }
        }
    }

    func testGreetingWithoutDataIsHonest() {
        var ctx = context(hour: 9)
        ctx.readinessOverall = nil
        ctx.readinessConfidence = nil
        let greeting = MindfulnessSuggestionEngine.greeting(for: ctx)
        XCTAssertTrue(greeting.contains("still gathering"), "no-data greeting must not fake a score")
    }

    func testBreathingPatternPhaseResolution() {
        let pattern = PracticeType.boxBreathing.pattern
        XCTAssertEqual(pattern.cycleDuration, 16)

        let (p0, prog0) = pattern.phase(at: 0)
        XCTAssertEqual(p0.kind, .inhale)
        XCTAssertEqual(prog0, 0, accuracy: 0.001)

        let (p1, _) = pattern.phase(at: 5)     // 4s inhale → in holdIn
        XCTAssertEqual(p1.kind, .holdIn)

        let (p2, prog2) = pattern.phase(at: 18) // wraps to second cycle, 2s in
        XCTAssertEqual(p2.kind, .inhale)
        XCTAssertEqual(prog2, 0.5, accuracy: 0.001)
    }

    func testAllPracticesHaveSafeSlowTimings() {
        // Epilepsy-safety invariant: no phase may be shorter than 1 second.
        for practice in PracticeType.allCases {
            for phase in practice.pattern.phases {
                XCTAssertGreaterThanOrEqual(phase.duration, 1.0,
                    "\(practice.rawValue) has a phase faster than 1s")
            }
            XCTAssertFalse(practice.offeredDurations.isEmpty)
        }
    }
}
