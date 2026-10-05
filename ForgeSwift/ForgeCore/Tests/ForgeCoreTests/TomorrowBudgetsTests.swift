import XCTest
@testable import ForgeCore

final class TomorrowBudgetsTests: XCTestCase {

    func testGreenBodyThinPeopleIsASplitDay() {
        let snap = TomorrowBudgets.snapshot(
            posture: .push,
            stance: .keepRhythm,
            peopleEnergy: .thin
        )
        XCTAssertEqual(snap.constraint, .people)
        XCTAssertTrue(snap.isSplit)
        XCTAssertTrue(snap.coachingLine.lowercased().contains("people-budget"))
        XCTAssertTrue(snap.coachingLine.lowercased().contains("session"))
        XCTAssertEqual(snap.ariaTags, ["tomorrow_budget:people"])
    }

    func testProtectBodyWithOpenPeopleSavesTheSession() {
        let snap = TomorrowBudgets.snapshot(
            posture: .protect,
            stance: .keepRhythm,
            peopleEnergy: .open
        )
        XCTAssertEqual(snap.constraint, .body)
        XCTAssertTrue(snap.coachingLine.lowercased().contains("people are fine"))
        XCTAssertFalse(snap.coachingLine.lowercased().contains("diagnos"))
    }

    func testCapHeroicsCountsAsAThinBodyEvenOnAPushScore() {
        let snap = TomorrowBudgets.snapshot(
            posture: .push,
            stance: .capHeroics,
            peopleEnergy: .open
        )
        XCTAssertEqual(snap.constraint, .body)
    }

    func testBothThinSaysNoHeroAndNoPlans() {
        let snap = TomorrowBudgets.snapshot(
            posture: .rest,
            stance: .capHeroics,
            peopleEnergy: .thin
        )
        XCTAssertEqual(snap.constraint, .both)
        XCTAssertTrue(snap.coachingLine.lowercased().contains("no hero"))
        XCTAssertTrue(snap.coachingLine.lowercased().contains("no extra plans"))
    }

    func testNeitherBudgetRefusesToSpendBoth() {
        let snap = TomorrowBudgets.snapshot(
            posture: .steady,
            stance: .keepRhythm,
            peopleEnergy: .enough
        )
        XCTAssertEqual(snap.constraint, .neither)
        XCTAssertTrue(snap.coachingLine.lowercased().contains("not both"))
    }

    func testPictureCarriesTheBudgetARIAReads() {
        let picture = PredictiveCoach.picture(
            forecastInput: ReadinessForecastEngine.Input(
                currentReadiness: 82,
                sleepMinutes: 480,
                hrvMs: 70,
                hrvBaselineMs: 60,
                restingHR: 52,
                restingHRBaseline: 55,
                todayStrain: 6,
                stressLevel: 20
            ),
            workingInput: UserWorkingModel.Input(habitStreakDays: 6, weeklyMood0to10: 8, acwr: 1.0),
            socialEnergy0to10: 2
        )
        XCTAssertEqual(picture.budgets.constraint, .people)
        XCTAssertTrue(picture.ariaTags.contains("tomorrow_budget:people"))
        XCTAssertTrue(picture.steeringLine.lowercased().contains("people-budget"))
        XCTAssertEqual(TomorrowBudgets.parseTag("tomorrow_budget:people"), .people)
        XCTAssertNil(TomorrowBudgets.parseTag("forecast:tomorrow:80:push"))
    }
}
