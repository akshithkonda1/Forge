import XCTest
@testable import ForgeCore

final class HabitEngineSleepTests: XCTestCase {

    func testSleepVarianceCompanionIsIdentityNotStreak() {
        let signals = HabitSignals(
            sleepAverage: 6.2,
            sleepVarianceMinutes: 95,
            steps: 9000,
            protein: 180,
            waterGlasses: 8,
            totalCalories: 2200,
            nightsAvailable: 7
        )
        let habits = HabitEngine.analyze(signals)
        XCTAssertEqual(habits.first?.id, "sleep_variance")
        let line = HabitEngine.companionLine(for: habits) ?? ""
        XCTAssertTrue(line.lowercased().contains("becoming someone"), line)
        XCTAssertFalse(line.lowercased().contains("streak"), line)
    }

    func testOutcomeFactFilesImmediately() {
        let habit = DeepHabit(
            id: "sleep_variance",
            title: "Wobbly wind-down",
            cue: "Evening",
            routine: "Scroll",
            payoff: "Felt busy",
            cost: "Late sleep",
            category: .sleep,
            confidence: 0.8,
            evidence: "variance 95m",
            breaker: "Kitchen phone",
            breakerAction: "Try kitchen-phone"
        )
        let fact = HabitFeedbackStore.outcomeFact(for: habit, answer: "yeah")
        XCTAssertEqual(fact.kind, "habit_outcome")
        XCTAssertEqual(fact.category, .inferences)
        XCTAssertTrue(fact.summary.contains("sleep_variance"))
        let attempt = HabitFeedbackStore.attemptFact(for: habit)
        XCTAssertEqual(attempt.kind, "habit_attempt")
    }
}
