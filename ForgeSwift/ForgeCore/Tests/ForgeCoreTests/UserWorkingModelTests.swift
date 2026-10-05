import XCTest
@testable import ForgeCore

final class UserWorkingModelTests: XCTestCase {

    func testOverreacherCapsHeroics() {
        let snap = UserWorkingModel.snapshot(
            UserWorkingModel.Input(
                habitStreakDays: 6,
                todayHabitCompletion: 1,
                weeklyMood0to10: 6,
                acwr: 1.7,
                sleepScores: [62, 58, 60],
                readinessToday: 52,
                highStrainLowRecoveryDays: 4
            )
        )
        XCTAssertEqual(snap.tendency, .overreacher)
        XCTAssertEqual(snap.stance, .capHeroics)
        XCTAssertTrue(snap.ariaTags.contains("working:overreacher:cap_heroics"))
        XCTAssertTrue(snap.steeringLine.lowercased().contains("cap heroics"))
        XCTAssertTrue(snap.drivers.contains { $0.title == "Pushing through" })
    }

    func testWeekendDropHoldsTheLine() {
        let snap = UserWorkingModel.snapshot(
            UserWorkingModel.Input(
                habitStreakDays: 5,
                todayHabitCompletion: 0.8,
                weeklyMood0to10: 6,
                acwr: 1.0,
                sleepScores: [80, 82, 78, 60, 58],
                readinessToday: 70,
                weekdaySleepAvg: 82,
                weekendSleepAvg: 60
            )
        )
        XCTAssertEqual(snap.tendency, .weekendDrop)
        XCTAssertEqual(snap.stance, .holdTheLine)
        XCTAssertTrue(snap.steeringLine.lowercased().contains("weekend"))
    }

    func testRebuildingCelebratesShowingUp() {
        let snap = UserWorkingModel.snapshot(
            UserWorkingModel.Input(
                habitStreakDays: 0,
                todayHabitCompletion: 0.2,
                weeklyMood0to10: 3,
                sleepScores: [50],
                readinessToday: 48
            )
        )
        XCTAssertEqual(snap.tendency, .rebuilding)
        XCTAssertEqual(snap.stance, .rebuildTrust)
        XCTAssertEqual(snap.predictedFeel, .flat)
        XCTAssertTrue(snap.steeringLine.lowercased().contains("showing up"))
    }

    func testProtectorKeepsRhythm() {
        let snap = UserWorkingModel.snapshot(
            UserWorkingModel.Input(
                habitStreakDays: 8,
                todayHabitCompletion: 1,
                weeklyMood0to10: 7,
                acwr: 0.6,
                sleepScores: [85, 84, 86],
                readinessToday: 78
            )
        )
        XCTAssertEqual(snap.tendency, .protector)
        XCTAssertEqual(snap.stance, .keepRhythm)
        XCTAssertTrue(snap.steeringLine.lowercased().contains("protect"))
    }

    func testSteadyDoesNotOverCoach() {
        let snap = UserWorkingModel.snapshot(
            UserWorkingModel.Input(
                habitStreakDays: 6,
                todayHabitCompletion: 0.8,
                weeklyMood0to10: 7,
                acwr: 1.05,
                sleepScores: [80, 82, 79],
                readinessToday: 76
            ),
            tomorrowPosture: .push
        )
        XCTAssertEqual(snap.tendency, .steady)
        XCTAssertEqual(snap.stance, .keepRhythm)
        XCTAssertEqual(snap.predictedFeel, .available)
        XCTAssertTrue(snap.steeringLine.lowercased().contains("don't over-coach")
            || snap.steeringLine.lowercased().contains("do not over-coach")
            || snap.steeringLine.contains("don't over-coach"))
    }

    func testUnknownWhenSignalsAreThin() {
        let snap = UserWorkingModel.snapshot(UserWorkingModel.Input())
        XCTAssertEqual(snap.tendency, .unknown)
        XCTAssertEqual(snap.confidence, .low)
        XCTAssertTrue(snap.ariaTags.contains { $0.hasPrefix("working:unknown:") })
    }

    func testParseTagRoundTripsProductionTags() {
        let parsed = UserWorkingModel.parseTag("working:overreacher:cap_heroics")
        XCTAssertEqual(parsed?.0, .overreacher)
        XCTAssertEqual(parsed?.1, .capHeroics)
        XCTAssertNil(UserWorkingModel.parseTag("habit:sleep:80"))
    }

    func testPredictiveCoachPictureIsWhatARIAReads() {
        let picture = PredictiveCoach.picture(
            forecastInput: ReadinessForecastEngine.Input(
                currentReadiness: 40,
                sleepMinutes: 300,
                hrvMs: 40,
                hrvBaselineMs: 60,
                restingHR: 62,
                restingHRBaseline: 55,
                todayStrain: 19,
                stressLevel: 80
            ),
            workingInput: UserWorkingModel.Input(
                habitStreakDays: 6,
                acwr: 1.7,
                highStrainLowRecoveryDays: 4
            )
        )
        XCTAssertTrue(picture.keepLight)
        XCTAssertEqual(picture.forecast.posture, .rest)
        XCTAssertEqual(picture.working.tendency, .overreacher)
        XCTAssertTrue(picture.ariaTags.contains { $0.hasPrefix("forecast:tomorrow:") })
        XCTAssertTrue(picture.ariaTags.contains("working:overreacher:cap_heroics"))
        XCTAssertTrue(picture.steeringLine.lowercased().contains("cap heroics"))
        XCTAssertTrue(picture.forecast.chatPrompt.contains("How should I train around that?"))
    }

    func testCopyNeverClaimsClinicalMentalHealth() {
        let snap = UserWorkingModel.snapshot(
            UserWorkingModel.Input(weeklyMood0to10: 2, highStrainLowRecoveryDays: 4)
        )
        let blob = (snap.steeringLine + " " + snap.drivers.map(\.detail).joined()).lowercased()
        for needle in ["diagnos", "depress", "disorder", "prescrib", "therap", "clinical"] {
            XCTAssertFalse(blob.contains(needle), "lifestyle copy leaked \(needle)")
        }
    }
}
