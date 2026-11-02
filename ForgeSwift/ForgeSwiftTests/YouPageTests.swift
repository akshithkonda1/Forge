import XCTest
@testable import ForgeSwift

final class YouPageTests: XCTestCase {

    func testGlanceSharingLineNamesEachOptIn() {
        let off = YouContextGlance.Snapshot(
            name: "Ada",
            coachingStyle: "Balanced",
            personality: "Friend",
            voice: "Rowan",
            goals: [],
            healthConnected: false,
            medicineShared: false,
            medicineCount: 0,
            cycleShared: false,
            lifeContextOn: false,
            units: "US"
        )
        let offLine = YouContextGlance.sharingLine(off)
        XCTAssertTrue(offLine.contains("Health off"))
        XCTAssertTrue(offLine.contains("Medicine private"))
        XCTAssertTrue(offLine.contains("Cycle private"))
        XCTAssertTrue(offLine.contains("Life context off"))
        XCTAssertEqual(YouContextGlance.goalsLine(off), "No goals yet")
        XCTAssertEqual(YouContextGlance.subtitle(off), "How Forge behaves toward you")

        let on = YouContextGlance.Snapshot(
            name: "Ada",
            coachingStyle: "Balanced",
            personality: "Friend",
            voice: "Rowan",
            goals: ["Strength", "Sleep"],
            healthConnected: true,
            medicineShared: true,
            medicineCount: 2,
            cycleShared: true,
            lifeContextOn: true,
            units: "Metric"
        )
        let onLine = YouContextGlance.sharingLine(on)
        XCTAssertTrue(onLine.contains("Health on"))
        XCTAssertTrue(onLine.contains("2 medicines shared"))
        XCTAssertTrue(onLine.contains("Cycle shared"))
        XCTAssertTrue(onLine.contains("Life context on"))
        XCTAssertEqual(YouContextGlance.goalsLine(on), "Strength, Sleep")
    }

    func testMeasurementSystemDefaultIsImperialAndRoundTrips() {
        XCTAssertEqual(emptyProfile.measurementSystem, .imperial)
        var profile = emptyProfile
        profile.measurementSystem = .metric
        let data = try XCTUnwrap(try JSONEncoder().encode(profile))
        let decoded = try XCTUnwrap(try JSONDecoder().decode(UserProfile.self, from: data))
        XCTAssertEqual(decoded.measurementSystem, .metric)
    }

    func testLegacyProfileJSONDecodesImperialUnits() throws {
        let profile = emptyProfile
        var encoded = try JSONEncoder().encode(profile)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "measurementSystem")
        encoded = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: encoded)
        XCTAssertEqual(decoded.measurementSystem, .imperial)
    }

    func testCoachAgentUserFacingLabelIsReadiness() {
        XCTAssertEqual(AriaCoachAgent.recovery.label, "Readiness")
        XCTAssertFalse(AriaCoachAgent.recovery.localDirective.localizedCaseInsensitiveContains("recovery"))
        XCTAssertFalse(AriaFirstHealthBriefing.identityShort().localizedCaseInsensitiveContains("recovery"))
        XCTAssertFalse(AriaFirstHealthBriefing.identityBody().localizedCaseInsensitiveContains("recovery"))
    }

    func testSampleNutritionCopyDropsRecovery() {
        let blob = AIRecommendation.sampleRecommendations.map(\.description).joined()
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("recovery"))
    }

    func testCoachingStyleCopyDropsRecovery() {
        for style in CoachingStyle.allCases {
            XCTAssertFalse(style.description.localizedCaseInsensitiveContains("recovery"), style.rawValue)
        }
    }
}
