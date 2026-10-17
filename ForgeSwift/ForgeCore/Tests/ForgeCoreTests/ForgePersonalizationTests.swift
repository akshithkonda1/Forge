import XCTest
@testable import ForgeCore

final class ForgePersonalizationTests: XCTestCase {

    func testFocusFromOnboardingGoals() {
        XCTAssertEqual(
            ForgePersonalization.focus(goals: ["build-muscle"], workouts: ["strength"]),
            .strength
        )
        XCTAssertEqual(
            ForgePersonalization.focus(goals: ["improve-endurance"], workouts: ["running"]),
            .endurance
        )
        XCTAssertEqual(
            ForgePersonalization.focus(goals: ["better sleep"], workouts: []),
            .sleep
        )
        XCTAssertEqual(
            ForgePersonalization.focus(goals: ["general-fitness"], workouts: ["yoga"]),
            .lifestyle
        )
        XCTAssertEqual(
            ForgePersonalization.focus(goals: ["build-muscle"], workouts: [], override: .sleep),
            .sleep
        )
    }

    func testGreetingUsesNameTimeAndFocusWithoutRecovery() {
        let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 8))!
        let line = ForgePersonalization.greeting(
            name: "Akshith Konda",
            goals: ["build-muscle"],
            workouts: ["strength"],
            now: morning
        )
        XCTAssertTrue(line.contains("Akshith"))
        XCTAssertTrue(line.lowercased().contains("morning"))
        XCTAssertFalse(ForgePersonalization.containsBannedCopy(line))
    }

    func testAriaOpenerHandlesSensitiveTopicsAndBansRecovery() {
        let line = ForgePersonalization.ariaOpener(
            name: "Ada",
            goals: ["better sleep"],
            workouts: []
        )
        XCTAssertTrue(line.contains("Ada"))
        XCTAssertTrue(line.lowercased().contains("sleep") || line.lowercased().contains("stress"))
        XCTAssertTrue(line.lowercased().contains("doctor"))
        XCTAssertFalse(ForgePersonalization.containsBannedCopy(line))
    }

    func testHomeSectionOrderAdaptsToFocusAndDaypart() {
        let morningSleep = ForgePersonalization.homeSections(focus: .sleep, daypart: .morning)
        XCTAssertEqual(morningSleep.first, .todayHero)
        XCTAssertEqual(morningSleep[1], .briefing)

        let strength = ForgePersonalization.homeSections(focus: .strength, daypart: .afternoon)
        XCTAssertEqual(strength[1], .forecast)

        let custom = ForgePersonalization.homeSections(
            focus: .lifestyle,
            daypart: .evening,
            custom: ["mosaic", "briefing"]
        )
        XCTAssertEqual(custom.prefix(2).map(\.rawValue), ["mosaic", "briefing"])
    }

    func testUnitsFormatting() {
        XCTAssertTrue(ForgePersonalization.formatKg(80, units: .metric).contains("kg"))
        XCTAssertTrue(ForgePersonalization.formatKg(80, units: .imperial).contains("lb"))
        XCTAssertTrue(ForgePersonalization.formatCm(180, units: .imperial).contains("'"))
        XCTAssertTrue(ForgePersonalization.formatMl(500, units: .imperial).contains("oz"))
        XCTAssertTrue(ForgePersonalization.containsBannedCopy("Recovery is holding."))
        XCTAssertFalse(ForgePersonalization.containsBannedCopy("Last night looked solid."))
    }
}
