import XCTest
@testable import ForgeCore

final class HobbyPathEngineTests: XCTestCase {

    private func working(
        _ tendency: UserWorkingModel.Tendency,
        feel: UserWorkingModel.PredictedFeel = .mixed
    ) -> UserWorkingModel.Snapshot {
        UserWorkingModel.snapshot(
            UserWorkingModel.Input(
                habitStreakDays: tendency == .rebuilding ? 0 : 6,
                todayHabitCompletion: tendency == .rebuilding ? 0.2 : 0.8,
                weeklyMood0to10: feel == .flat ? 3 : 7,
                acwr: tendency == .overreacher ? 1.7 : 1.05,
                highStrainLowRecoveryDays: tendency == .overreacher ? 4 : 0,
                weekdaySleepAvg: tendency == .weekendDrop ? 82 : nil,
                weekendSleepAvg: tendency == .weekendDrop ? 60 : nil
            )
        )
    }

    func testReservedEnergyOpensGentlyWithSoloHobbies() {
        let snap = HobbyPathEngine.snapshot(
            socialEnergy0to10: 2,
            currentHobbies: [],
            working: working(.steady)
        )
        XCTAssertEqual(snap.socialBand, .reserved)
        XCTAssertEqual(snap.path, .openGently)
        XCTAssertTrue(snap.suggestions.contains { $0.hobby == .cooking || $0.hobby == .outdoors })
        XCTAssertTrue(snap.coachingLine.lowercased().contains("alone"))
        XCTAssertTrue(snap.ariaTags.contains("hobby_path:open_gently"))
        XCTAssertEqual(snap.peopleEnergy, .thin)
        XCTAssertEqual(snap.freeDayWindow, .evening)
        XCTAssertTrue(snap.windowLine.lowercased().contains("quiet") || snap.windowLine.lowercased().contains("thin"))
        XCTAssertTrue(snap.chatPrompt.contains("how I actually live"))
    }

    func testHighEnergyPlusOverreachRestoresQuiet() {
        let snap = HobbyPathEngine.snapshot(
            socialEnergy0to10: 9,
            currentHobbies: [.gym, .outdoors],
            working: working(.overreacher, feel: .flat)
        )
        XCTAssertEqual(snap.socialBand, .burnedOut)
        XCTAssertEqual(snap.path, .restoreQuiet)
        XCTAssertTrue(snap.suggestions.contains { $0.hobby == .reading || $0.hobby == .rest })
        XCTAssertFalse(snap.suggestions.contains { $0.hobby == .gym })
        XCTAssertTrue(snap.coachingLine.lowercased().contains("fit") || snap.coachingLine.lowercased().contains("calendar"))
        XCTAssertEqual(snap.peopleEnergy, .thin)
        XCTAssertEqual(snap.freeDayWindow, .afternoon)
    }

    func testKeepRhythmWhenSociableAndAlreadyHasHobbies() {
        let snap = HobbyPathEngine.snapshot(
            socialEnergy0to10: 8,
            currentHobbies: [.music, .cooking],
            working: working(.steady, feel: .available)
        )
        XCTAssertEqual(snap.path, .keepRhythm)
        XCTAssertEqual(snap.suggestions.map(\.hobby), [.music, .cooking])
    }

    func testCopyNeverClaimsClinicalOrAntiSocialAsDisorder() {
        let snap = HobbyPathEngine.snapshot(
            socialEnergy0to10: 1,
            currentHobbies: [],
            working: working(.rebuilding, feel: .flat)
        )
        let blob = (snap.headline + snap.coachingLine + snap.windowLine + snap.suggestions.map(\.why).joined()).lowercased()
        for needle in ["diagnos", "disorder", "prescrib", "therap", "clinical", "introver"] {
            XCTAssertFalse(blob.contains(needle), "leaked \(needle)")
        }
    }

    func testHobbyQuestionDoesNotStealQoLAsks() {
        XCTAssertTrue(HobbyPathEngine.isHobbyQuestion("help me pick a hobby"))
        XCTAssertTrue(HobbyPathEngine.isHobbyQuestion("I'm burned out socially"))
        XCTAssertTrue(QualityOfLifeLivingStore.isHobbyQuestion("something besides training"))
        XCTAssertFalse(QualityOfLifeLivingStore.isHobbyQuestion("what's my quality of life"))
        XCTAssertFalse(HobbyPathEngine.isHobbyQuestion("what should I train today"))
    }

    func testPredictiveCoachPictureIncludesHobbyTagsARIAReads() {
        let picture = PredictiveCoach.picture(
            forecastInput: ReadinessForecastEngine.Input(
                currentReadiness: 72,
                sleepMinutes: 480,
                hrvMs: 60,
                hrvBaselineMs: 60,
                restingHR: 55,
                restingHRBaseline: 55,
                todayStrain: 8,
                stressLevel: 30
            ),
            workingInput: UserWorkingModel.Input(habitStreakDays: 5, weeklyMood0to10: 7, acwr: 1.0),
            socialEnergy0to10: 2,
            currentHobbies: [.reading]
        )
        XCTAssertTrue(picture.ariaTags.contains { $0.hasPrefix("hobby_path:") })
        XCTAssertTrue(picture.ariaTags.contains { $0.hasPrefix("hobby_people:") })
        XCTAssertTrue(picture.hobby.chatPrompt.lowercased().contains("hobby")
            || picture.hobby.coachingLine.lowercased().contains("alone"))
    }

    func testNightOwlWakeHourPicksEveningWindowNotAMorningClub() {
        let snap = HobbyPathEngine.snapshot(
            socialEnergy0to10: 6,
            currentHobbies: [.music],
            working: working(.steady, feel: .available),
            tomorrowPosture: .steady,
            wakeHour: 10.5
        )
        XCTAssertEqual(snap.freeDayWindow, .evening)
        XCTAssertTrue(snap.windowLine.lowercased().contains("6am") || snap.windowLine.lowercased().contains("quiet"))
        XCTAssertTrue(snap.ariaTags.contains("hobby_window:evening"))
    }

    func testProtectTomorrowCapsPeopleEnergyEvenWhenSociable() {
        let snap = HobbyPathEngine.snapshot(
            socialEnergy0to10: 8,
            currentHobbies: [.music],
            working: working(.steady, feel: .available),
            tomorrowPosture: .protect,
            wakeHour: 7
        )
        XCTAssertEqual(snap.peopleEnergy, .thin)
        XCTAssertTrue(snap.ariaTags.contains("hobby_people:thin"))
    }
}
