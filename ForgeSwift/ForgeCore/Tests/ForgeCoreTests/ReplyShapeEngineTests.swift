import XCTest
@testable import ForgeCore

final class ReplyShapeEngineTests: XCTestCase {

    private var overreachTags: [String] {
        PredictiveCoach.picture(
            forecastInput: ReadinessForecastEngine.Input(
                currentReadiness: 48,
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
                highStrainLowRecoveryDays: 4,
                weeklyMood0to10: 3
            ),
            socialEnergy0to10: 9,
            currentHobbies: [.gym]
        ).ariaTags
    }

    func testEstimateWinsOverEverythingAndStaysNonClinical() {
        let shape = ReplyShapeEngine.shape(
            prompt: "what should I train tomorrow",
            ariaTags: overreachTags,
            localFallback: true,
            scoutUsed: true,
            estimate: true
        )
        XCTAssertEqual(shape.lanes, ["shape:estimate"])
        XCTAssertTrue(shape.chipLabel.lowercased().contains("estimate"))
        let blob = (shape.headline + shape.detail).lowercased()
        for needle in ["diagnos", "disorder", "prescrib", "therap", "clinical"] {
            XCTAssertFalse(blob.contains(needle), "leaked \(needle)")
        }
    }

    func testHobbyAskNamesPeopleEnergyNotAScore() {
        let shape = ReplyShapeEngine.shape(
            prompt: "help me pick a hobby",
            ariaTags: overreachTags,
            localFallback: true,
            scoutUsed: false,
            estimate: false
        )
        XCTAssertTrue(shape.lanes.contains("shape:hobby"))
        XCTAssertTrue(shape.lanes.contains("shape:local"))
        XCTAssertTrue(shape.detail.lowercased().contains("people-energy")
            || shape.headline.lowercased().contains("people-energy")
            || shape.detail.lowercased().contains("quiet"))
        XCTAssertTrue(shape.chipLabel.hasPrefix("What shaped this"))
    }

    func testTomorrowAskNamesForecastAndCapsHeroics() {
        let shape = ReplyShapeEngine.shape(
            prompt: "How should I train around tomorrow?",
            ariaTags: overreachTags,
            localFallback: false,
            scoutUsed: false,
            estimate: false
        )
        XCTAssertTrue(shape.lanes.contains("shape:forecast"))
        XCTAssertTrue(shape.lanes.contains("shape:working"))
        XCTAssertTrue(shape.detail.lowercased().contains("heroics")
            || shape.detail.lowercased().contains("tomorrow"))
    }

    func testTomorrowAskNamesTheScarceBudget() {
        let shape = ReplyShapeEngine.shape(
            prompt: "How should I train around tomorrow?",
            ariaTags: ["forecast:tomorrow:80:push", "tomorrow_budget:people"],
            localFallback: false,
            scoutUsed: false,
            estimate: false
        )
        XCTAssertTrue(shape.lanes.contains("shape:budget"))
        XCTAssertTrue(shape.detail.lowercased().contains("people-budget"))
    }

    func testScoutIsNamedAsOutsideThenLife() {
        let shape = ReplyShapeEngine.shape(
            prompt: "hey",
            ariaTags: [],
            localFallback: false,
            scoutUsed: true,
            estimate: false
        )
        XCTAssertTrue(shape.lanes.contains("shape:scout"))
        XCTAssertTrue(shape.detail.lowercased().contains("outside"))
    }

    func testForecastParseTagMatchesPython() {
        let parsed = ReadinessForecastEngine.parseTag("forecast:tomorrow:54:protect")
        XCTAssertEqual(parsed?.0, 54)
        XCTAssertEqual(parsed?.1, .protect)
        XCTAssertNil(ReadinessForecastEngine.parseTag("habit:sleep:80"))
    }
}
