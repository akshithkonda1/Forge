import XCTest
@testable import ForgeCore

final class ForgeHealthPotentialTests: XCTestCase {

    func testUnusedHistoryIsPotentialNeverShame() {
        let history = ForgeHealthPotential.History(
            name: "Ada Lovelace",
            sleepHours: [7.2, 6.8, 7.5, 8.0, 6.4],
            steps: [5200, 6100, 4800]
        )
        let picture = ForgeHealthPotential.picture(from: history)
        XCTAssertTrue(picture.unusedLine.contains("Ada"))
        XCTAssertTrue(picture.unusedLine.lowercased().contains("unused"))
        XCTAssertFalse(picture.unusedLine.lowercased().contains("should have"))
        XCTAssertFalse(ForgeHealthPotential.containsBanned(picture.unusedLine))
        XCTAssertNil(picture.backgroundReference)
        XCTAssertFalse(picture.howYoureDoing.lowercased().contains("national"))
        XCTAssertTrue(picture.howYoureDoing.lowercased().contains("aria")
                      || picture.howYoureDoing.lowercased().contains("conversation"))
    }

    func testPersonalIndexesSkipBMIAndNationalRank() {
        let nights = [6.5, 7.0, 7.2, 6.8, 7.4, 8.1, 6.9]
        let history = ForgeHealthPotential.History(
            name: "Ada",
            sleepHours: nights,
            steps: [8000, 7200, 9100, 6400, 7000, 8800, 7500],
            workoutsThisWeek: 2,
            workoutGoal: 3,
            weightKg: 68,
            heightCm: 170
        )
        let picture = ForgeHealthPotential.picture(from: history)
        XCTAssertEqual(picture.indexes.map(\.id), ["sleep", "move", "train"])
        for index in picture.indexes {
            XCTAssertFalse(index.personalLine.lowercased().contains("bmi"))
            XCTAssertFalse(index.personalLine.lowercased().contains("national"))
            XCTAssertFalse(ForgeHealthPotential.containsBanned(index.personalLine))
        }
        let drilled = ForgeHealthPotential.picture(from: history, includeBackground: true)
        XCTAssertNotNil(drilled.backgroundReference)
        XCTAssertTrue(drilled.backgroundReference!.contains("Background reference only"))
        XCTAssertTrue(drilled.backgroundReference!.contains("CDC"))
        XCTAssertFalse(drilled.indexes.contains { $0.personalLine.lowercased().contains("bmi") })
    }

    func testEmptyHistoryOmitsBMIAndUsesDemoMosaic() {
        let picture = ForgeHealthPotential.picture(from: .init(name: "Ada"))
        XCTAssertTrue(picture.usingDemoMosaic)
        XCTAssertNil(ForgeHealthPotential.bmiBackground(kg: nil, cm: 170))
        XCTAssertTrue(picture.clinicianLine.lowercased().contains("doctor"))
        XCTAssertFalse(ForgeHealthPotential.containsBanned(picture.firstWinLine))
        XCTAssertFalse(ForgeHealthPotential.containsBanned(picture.howYoureDoing))
    }

    func testCopyBansNationalWorryAndRecovery() {
        XCTAssertTrue(ForgeHealthPotential.containsBanned("Don't worry about the national average"))
        XCTAssertTrue(ForgeHealthPotential.containsBanned("Recovery is holding"))
        XCTAssertFalse(ForgeHealthPotential.containsBanned("Last night looked solid."))
        XCTAssertTrue(ForgeHealthPotential.tutorialLeadsWithBMI("BMI 24 is your score"))
        XCTAssertFalse(ForgeHealthPotential.tutorialLeadsWithBMI("Your night index sits on your own line."))
    }
}

final class ForgePopulationBaselinesTests: XCTestCase {

    func testCitedTableIsBackgroundOnlyAndLockstepWithJSON() {
        XCTAssertEqual(ForgePopulationBaselines.kind, "forge-population-baselines")
        XCTAssertEqual(ForgePopulationBaselines.version, 1)
        XCTAssertEqual(ForgePopulationBaselines.serverDatasetStatus, "todo")
        XCTAssertEqual(ForgePopulationBaselines.shortSleepPrevalence.value, 30.5)
        XCTAssertEqual(ForgePopulationBaselines.shortSleepPrevalence.year, 2024)
        XCTAssertTrue(ForgePopulationBaselines.shortSleepPrevalence.source.contains("NCHS"))
        XCTAssertEqual(ForgePopulationBaselines.stepsPerDay.value, 6540)
        XCTAssertTrue(ForgePopulationBaselines.stepsPerDay.source.contains("NHANES"))
        XCTAssertEqual(ForgePopulationBaselines.metBothActivityGuidelines.value, 24.2)
        XCTAssertNil(ForgePopulationBaselines.metric(id: "bmi"))
        XCTAssertEqual(ForgePopulationBaselines.all.map(\.id), [
            "shortSleepPrevalence", "stepsPerDay", "metBothActivityGuidelines",
        ])
    }
}
