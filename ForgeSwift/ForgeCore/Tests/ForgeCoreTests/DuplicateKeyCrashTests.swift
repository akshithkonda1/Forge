// Tess equivalent — DuplicateKeyCrashTests was not on any branch or PR.
// `Dictionary(uniqueKeysWithValues:)` traps when a HealthKit night date or
// hobby id repeats. These cases crash the test host on main if a call site
// still uses uniqueKeysWithValues on user-derived keys.
import XCTest
@testable import ForgeCore

final class DuplicateKeyCrashTests: XCTestCase {

    func testEngageWithDuplicateHobbyIdsDoesNotTrap() {
        let persona = HobbyFit.hobbies(from: [.outdoors, .gym])
        let profile = [
            HobbyFit.Hobby(id: "outdoors", label: "Being outside", kind: .outdoor, interest: .medium),
            HobbyFit.Hobby(id: "outdoors", label: "Outside again", kind: .outdoor, interest: .high),
        ]
        let engaged = HobbyFit.engage(
            fromWorkouts: [
                .init(name: "Morning hike", type: "cardio", dateISO: "2026-10-16"),
                .init(name: "Lunch walk", type: "cardio", dateISO: "2026-10-16"),
            ],
            existing: persona + profile
        )
        XCTAssertEqual(engaged.filter { $0.id == "outdoors" }.count, 1)
    }

    func testUniquedNightsByDateKeepsFirstOnRepeatedSleepDate() {
        let byDate = SleepDebtMeter.uniquedNightsByDate([
            ("2026-10-16", 7.2),
            ("2026-10-16", 4.0),
            ("2026-10-15", 8.0),
        ])
        XCTAssertEqual(byDate["2026-10-16"], 7.2)
        XCTAssertEqual(byDate.count, 2)
        let meter = SleepDebtMeter.make(
            nightsByDate: byDate,
            needHours: 8,
            asleepHoursOldestFirst: [8.0, 7.2]
        )
        XCTAssertEqual(meter.days.filter { $0.hours != nil }.count >= 0, true)
    }

    func testQualityOfLifeWeightsDoNotTrapOnAllCases() {
        let weights = QualityOfLifeCalculator.weights(archetype: .balanced, hobbies: nil)
        XCTAssertEqual(weights.count, QualityOfLifePillar.allCases.count)
    }

    func testMessageContextSortWithRepeatedKindsDoesNotTrap() {
        let now = Date()
        let facts = [
            LifeContextFact(
                kind: .plan,
                label: "dinner",
                summary: "Dinner Friday",
                date: now,
                confidence: 0.9,
                sourceHash: "a",
                observedAt: now
            ),
            LifeContextFact(
                kind: .plan,
                label: "lunch",
                summary: "Lunch Saturday",
                date: now.addingTimeInterval(60),
                confidence: 0.8,
                sourceHash: "b",
                observedAt: now.addingTimeInterval(60)
            ),
        ]
        let sorted = MessageContextEngine.sorted(facts)
        XCTAssertEqual(sorted.count, 2)
    }
}
