import XCTest
@testable import ForgeCore

/// Launch-stability fixtures: duplicate-keyed data that has trapped at launch.
/// `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key, which kills
/// the process before the first frame. These run in the launch gate
/// (.github/workflows/launch-stability.yml) and in swift.yml's ForgeCore step.
final class LaunchStabilityFixtureTests: XCTestCase {

    // HobbyFit.engage (HobbyFit.swift ~524): persona chips + lifestyle rows
    // both carry id "outdoors".
    func testHobbyEngageSurvivesDuplicateExistingIDs() {
        let dup = [
            HobbyFit.Hobby(id: "outdoors", label: "Outdoors", kind: .outdoor, interest: .high),
            HobbyFit.Hobby(id: "outdoors", label: "Outdoors", kind: .outdoor, interest: .low),
            HobbyFit.Hobby(id: "outdoors", label: "Outdoors", kind: .outdoor, interest: .medium),
        ]
        let workouts = [
            HobbyFit.WorkoutHint(name: "Hike", type: "hiking", dateISO: "2026-10-01"),
            HobbyFit.WorkoutHint(name: "Walk", type: "walking", dateISO: "2026-10-02"),
            HobbyFit.WorkoutHint(name: "Walk", type: "walking", dateISO: "2026-10-02"),
        ]
        let out = HobbyFit.engage(fromWorkouts: workouts, existing: dup)
        XCTAssertEqual(out.filter { $0.id == "outdoors" }.count, 1)
        XCTAssertEqual(out.first { $0.id == "outdoors" }?.interest, .high, "first row wins")
    }

    // SleepDebtMeterCard (SleepNightTab.swift ~882) builds nightsByDate from
    // store.sleepData; HealthKit can return the same night twice.
    func testSleepDebtMeterSurvivesDuplicateNights() {
        let nights: [(String, Double)] = [
            ("2026-10-20", 7.0), ("2026-10-20", 6.0),
            ("2026-10-21", 7.5), ("2026-10-21", 7.5), ("2026-10-22", 5.0),
        ]
        let byDate = Dictionary(nights, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(byDate["2026-10-20"], 7.0)
        let result = SleepDebtMeter.make(
            nightsByDate: byDate,
            needHours: 8,
            asleepHoursOldestFirst: nights.map(\.1)
        )
        XCTAssertFalse(result.days.isEmpty)
        XCTAssertTrue(result.stretchHours.isFinite)
    }
}
