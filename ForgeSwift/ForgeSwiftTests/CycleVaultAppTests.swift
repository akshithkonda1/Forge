import XCTest
@testable import ForgeSwift

final class CycleVaultAppTests: XCTestCase {

    func testSelectableSupportRolesArePartnerRelativeParent() {
        XCTAssertEqual(CycleSupportRole.selectableRoles, [.romantic, .family, .child])
        XCTAssertEqual(CycleSupportRole.romantic.label, "Partner")
        XCTAssertEqual(CycleSupportRole.family.label, "Relative")
        XCTAssertEqual(CycleSupportRole.child.label, "Parent")
    }

    func testMonthlyDigestNeverCopiesNotesOrFertileFields() throws {
        let logs = [
            CycleDayLog(dayKey: "2026-09-01", flow: .medium, symptoms: [.cramps], notes: "private diary", painScale: 4),
            CycleDayLog(dayKey: "2026-09-02", flow: .light, symptoms: [.fatigue], notes: "do not leak"),
            CycleDayLog(dayKey: "2026-09-10", flow: .none, mucus: .eggWhite, notes: "fertile-ish"),
        ]
        var snap = MenstrualCycleSnapshot.empty
        snap.cycleLengthMedian = 28
        snap.periodLengthMedian = 5
        snap.accuracyMAE = 1.2
        snap.accuracySampleCount = 4
        let digest = CycleMonthlyDigestFactory.make(
            monthKey: "2026-09",
            logs: logs,
            snapshot: snap,
            settings: .default
        )
        let data = try JSONEncoder().encode(digest)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("private diary"))
        XCTAssertFalse(json.contains("do not leak"))
        XCTAssertFalse(json.lowercased().contains("fertile"))
        XCTAssertFalse(json.lowercased().contains("eggwhite") || json.lowercased().contains("egg_white"))
        XCTAssertEqual(digest.daysLogged, 3)
        XCTAssertEqual(digest.bleedingDays, 2)
        XCTAssertEqual(digest.symptomCounts["Cramps"], 1)
    }

    func testSettingsDecodePeriodTrainingStyleDefault() throws {
        let json = """
        {"enabled":true,"shareWithAria":false,"typicalLutealDays":14,"usesHormonalContraception":false,"notes":"","privacyAcknowledged":true,"calibrationOffsetDays":0,"highAccuracyMode":true,"overdueWidenDays":0}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(MenstrualTrackingSettings.self, from: json)
        XCTAssertEqual(settings.lifestyleGoal, .none)
        XCTAssertEqual(settings.periodTrainingStyle, .easy)
        XCTAssertEqual(settings.discretionMode, .clinical)
        XCTAssertTrue(settings.highAccuracyMode)
    }

    func testExtraCareMarksDigestThoughtfulnessWithoutPhaseChange() {
        var snap = MenstrualCycleSnapshot.empty
        snap.trackingEnabled = true
        snap.phase = .follicular
        snap.extraCareRequested = true
        let digest = PartnerCycleDigest(redacting: snap, tier: .supportCoach)
        XCTAssertTrue(digest.extraThoughtfulnessHelps)
        XCTAssertEqual(digest.phase, .rebuilding)
        XCTAssertNil(digest.periodDay)
    }
}
