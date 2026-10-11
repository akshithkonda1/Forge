import XCTest
import ForgeCore

final class StatsMosaicTests: XCTestCase {

    func testEmptyMosaicStaysHonest() {
        let snap = StatsMosaic.snapshot(StatsMosaic.Input())
        XCTAssertEqual(snap.tiles.count, 5)
        XCTAssertEqual(snap.dayPercent, 0)
        XCTAssertEqual(snap.doneCount, 0)
        XCTAssertTrue(snap.tiles.allSatisfy { $0.source == .empty })
        XCTAssertEqual(snap.almostThereCount, 0)
        XCTAssertFalse(snap.closing)
        XCTAssertFalse(StatsMosaic.containsBannedMedical(snap.mosaicLine))
        XCTAssertTrue(snap.mosaicLine.localizedCaseInsensitiveContains("lifestyle"))
        XCTAssertTrue(snap.tiles.contains { $0.headline == "—" })
        XCTAssertTrue(snap.tiles.contains { $0.detail.contains("open") || $0.detail == "Not in yet" })
    }

    func testHealthAndManualSourcesFillTheDayPicture() {
        let snap = StatsMosaic.snapshot(
            StatsMosaic.Input(
                sleepHours: 8,
                sleepManual: false,
                workoutsThisWeek: 3,
                workoutGoal: 3,
                waterGlasses: 8,
                waterManual: true,
                steps: 8_000,
                stepsManual: false,
                habitsDone: 3,
                habitsGoal: 3
            )
        )
        XCTAssertEqual(snap.doneCount, 5)
        XCTAssertEqual(snap.dayPercent, 100)
        XCTAssertEqual(snap.almostThereCount, 0)
        XCTAssertFalse(snap.closing)
        XCTAssertTrue(snap.mosaicLine.localizedCaseInsensitiveContains("ring closed"))
        XCTAssertEqual(snap.tiles.first { $0.track == .sleep }?.source, .health)
        XCTAssertEqual(snap.tiles.first { $0.track == .water }?.source, .manual)
        XCTAssertEqual(snap.tiles.first { $0.track == .move }?.source, .health)
        XCTAssertTrue(snap.mosaicLine.contains("Sleep 8.0h"))
        XCTAssertTrue(snap.mosaicLine.contains("Train 3/3"))
        for tile in snap.tiles {
            XCTAssertFalse(StatsMosaic.containsBannedMedical(tile.ariaPrompt))
            XCTAssertFalse(tile.ariaPrompt.isEmpty)
        }
    }

    func testPartialDayDoesNotInventMissingTracks() {
        let snap = StatsMosaic.snapshot(
            StatsMosaic.Input(sleepHours: 8, workoutsThisWeek: 1, workoutGoal: 4)
        )
        let sleep = snap.tiles.first { $0.track == .sleep }
        let move = snap.tiles.first { $0.track == .move }
        XCTAssertEqual(sleep?.progress, 1)
        XCTAssertEqual(move?.source, .empty)
        XCTAssertEqual(move?.headline, "—")
        XCTAssertLessThan(snap.dayPercent, 100)
        XCTAssertGreaterThan(snap.dayPercent, 0)
    }

    func testAlmostThereTilesUseGoalGradient() {
        let snap = StatsMosaic.snapshot(
            StatsMosaic.Input(
                sleepHours: 7.2,
                sleepGoalHours: 8,
                workoutsThisWeek: 2,
                workoutGoal: 3,
                waterGlasses: 6,
                waterGoal: 8,
                steps: 7_200,
                stepGoal: 8_000,
                habitsDone: 2,
                habitsGoal: 3
            )
        )
        XCTAssertGreaterThan(snap.almostThereCount, 0)
        XCTAssertTrue(snap.tiles.contains(where: \.almostThere))
        XCTAssertTrue(snap.mosaicLine.localizedCaseInsensitiveContains("almost there"))
        XCTAssertFalse(StatsMosaic.containsBannedMedical(snap.mosaicLine))
        for tile in snap.tiles where tile.almostThere {
            XCTAssertGreaterThanOrEqual(tile.progress, HomeReadinessTokens.almostThereFloor)
            XCTAssertLessThan(tile.progress, 1)
        }
    }

    func testBannedMedicalTokensStayLocked() {
        XCTAssertTrue(StatsMosaic.containsBannedMedical("I can diagnose that."))
        XCTAssertTrue(StatsMosaic.containsBannedMedical("medical advice"))
        XCTAssertFalse(StatsMosaic.containsBannedMedical("How did I sleep tonight?"))
    }
}
