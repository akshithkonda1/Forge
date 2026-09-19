import XCTest
@testable import ForgeCore

final class MetabolicHealthSnapshotTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testNoDataKeepsSoldSeparatelyHonesty() {
        let snap = MetabolicHealthSnapshot.evaluate(meals: [], glucose: [], now: now)
        XCTAssertFalse(snap.hasGlucose)
        XCTAssertEqual(snap.mealCount, 0)
        XCTAssertTrue(snap.accessoryLine.contains("sold separately"))
        XCTAssertTrue(snap.storyLine.lowercased().contains("sold separately"))
        XCTAssertEqual(snap.bullets, TranslationCatalog.metabolic.bullets)
        XCTAssertEqual(snap.bullets.count, 4)
    }

    func testGlucoseWithoutMealsAsksForAMeal() {
        let snap = MetabolicHealthSnapshot.evaluate(
            meals: [],
            glucose: [GlucosePoint(date: now.addingTimeInterval(-20 * 60), mgdl: 102, sourceName: "Dexcom Stelo")],
            now: now
        )
        XCTAssertEqual(snap.latestMgdl, 102)
        XCTAssertEqual(snap.latestSource, "Dexcom Stelo")
        XCTAssertEqual(snap.storyLine, "Latest glucose 102 mg/dL. Log a meal to see how food lands.")
        XCTAssertTrue(snap.accessoryLine.contains("Dexcom Stelo"))
        XCTAssertTrue(snap.accessoryLine.contains("Apple Health"))
        XCTAssertFalse(snap.accessoryLine.contains("sold separately"))
    }

    func testMealPlusPostMealRiseTellsTheLanding() {
        let lunch = now.addingTimeInterval(-90 * 60)
        let meals = [
            MetabolicMealEvent(name: "Lunch", date: lunch, calories: 640, carbs: 64, protein: 38, fat: 18)
        ]
        let glucose = [
            GlucosePoint(date: lunch.addingTimeInterval(-10 * 60), mgdl: 98, sourceName: "Stelo"),
            GlucosePoint(date: lunch.addingTimeInterval(55 * 60), mgdl: 129, sourceName: "Stelo"),
        ]
        let snap = MetabolicHealthSnapshot.evaluate(meals: meals, glucose: glucose, now: now)
        XCTAssertEqual(snap.pairs.count, 1)
        XCTAssertEqual(snap.pairs.first?.deltaMgdl, 31)
        XCTAssertEqual(snap.storyLine, "Lunch · 64g carbs · glucose rose 31 mg/dL after.")
        XCTAssertEqual(snap.mealCount, 1)
        XCTAssertEqual(snap.carbsGrams, 64)
    }

    func testStablePostMealDoesNotInventASpike() {
        let lunch = now.addingTimeInterval(-80 * 60)
        let snap = MetabolicHealthSnapshot.evaluate(
            meals: [MetabolicMealEvent(name: "Oats", date: lunch, calories: 310, carbs: 48)],
            glucose: [
                GlucosePoint(date: lunch.addingTimeInterval(-5 * 60), mgdl: 104, sourceName: "Libre"),
                GlucosePoint(date: lunch.addingTimeInterval(50 * 60), mgdl: 107, sourceName: "Libre"),
            ],
            now: now
        )
        XCTAssertEqual(snap.pairs.first?.line, "Oats · 48g carbs · glucose held near 107 mg/dL after.")
    }

    func testNoPostMealReadingDoesNotInventAPair() {
        let lunch = now.addingTimeInterval(-10 * 60)
        let snap = MetabolicHealthSnapshot.evaluate(
            meals: [MetabolicMealEvent(name: "Lunch", date: lunch, calories: 500, carbs: 50)],
            glucose: [GlucosePoint(date: lunch.addingTimeInterval(-15 * 60), mgdl: 99, sourceName: "Stelo")],
            now: now
        )
        XCTAssertTrue(snap.pairs.isEmpty)
        XCTAssertTrue(snap.storyLine.contains("waiting on a post-meal reading"))
    }

    func testSelectedSteloWithoutReadingsStaysSoldSeparately() {
        let line = MetabolicHealthSnapshot.accessoryLine(
            connectedDeviceIDs: ["dexcom-stelo"],
            latestSource: nil
        )
        XCTAssertTrue(line.contains("Stelo"))
        XCTAssertTrue(line.contains("sold separately"))
        XCTAssertTrue(line.contains("Apple Health"))
    }

    func testImplausibleGlucoseIsIgnored() {
        let snap = MetabolicHealthSnapshot.evaluate(
            meals: [],
            glucose: [GlucosePoint(date: now, mgdl: 12, sourceName: "Stelo")],
            now: now
        )
        XCTAssertFalse(snap.hasGlucose)
        XCTAssertTrue(snap.accessoryLine.contains("sold separately"))
    }

    func testCopyNeverClaimsDiagnosis() {
        let lunch = now.addingTimeInterval(-90 * 60)
        let snap = MetabolicHealthSnapshot.evaluate(
            meals: [MetabolicMealEvent(name: "Pasta", date: lunch, calories: 820, carbs: 110)],
            glucose: [
                GlucosePoint(date: lunch.addingTimeInterval(-8 * 60), mgdl: 95, sourceName: "Dexcom G7"),
                GlucosePoint(date: lunch.addingTimeInterval(70 * 60), mgdl: 168, sourceName: "Dexcom G7"),
            ],
            now: now
        )
        let blob = (snap.storyLine + " " + snap.accessoryLine + " " + snap.bullets.joined(separator: " ")).lowercased()
        for banned in ["diagnos", "diabet", "disease", "patient", "insulin", "a1c", "hypergly", "hypogly"] {
            XCTAssertFalse(blob.contains(banned), banned)
        }
    }
}
