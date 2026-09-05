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

    func testAvoidPregnancyJSONDecodesAsIntimacy() throws {
        let data = Data("\"avoidPregnancy\"".utf8)
        let goal = try JSONDecoder().decode(CycleGoal.self, from: data)
        XCTAssertEqual(goal, .intimacy)
        XCTAssertEqual(goal.label, "Intimacy & sex")
    }

    func testDigestWindowKeepsTrailingMonthsFromLogs() {
        let logs = [
            CycleDayLog(dayKey: "2026-01-10", flow: .medium),
            CycleDayLog(dayKey: "2026-02-10", flow: .light),
            CycleDayLog(dayKey: "2026-03-10", flow: .medium),
            CycleDayLog(dayKey: "2026-04-10", flow: .light),
            CycleDayLog(dayKey: "2026-05-10", flow: .medium),
        ]
        let months = CycleMonthlyDigestFactory.window(
            months: 3,
            logs: logs,
            snapshot: .empty,
            settings: .default
        )
        XCTAssertEqual(months.map(\.monthKey), ["2026-03", "2026-04", "2026-05"])
    }

    func testIntimacyCurriculumIsNotAContraceptive() {
        let blob = [
            SexualHealthCurriculum.safeSexBasics(),
            SexualHealthCurriculum.positionsAndIdeas(for: .menstruation),
            SexualHealthCurriculum.thingsYouCanTry(for: .luteal),
            SexualHealthCurriculum.partnerAndYouTips(roleHint: nil),
            SexualHealthCurriculum.periodSex(phase: .menstruation),
            SexualHealthCurriculum.medicalDisclaimer,
        ].joined(separator: "\n").lowercased()
        XCTAssertTrue(blob.contains("consent"))
        XCTAssertTrue(blob.contains("positions") || blob.contains("side-lying") || blob.contains("spooning"))
        XCTAssertTrue(blob.contains("friend") && blob.contains("help"))
        XCTAssertTrue(blob.contains("not a birth-control") || blob.contains("not an fda"))
        XCTAssertFalse(blob.contains("pearl index"))
        XCTAssertFalse(blob.contains("forge is a contraceptive"))
    }

    func testAriaCycleToolsRoutesPositionsAndDoesNotTreatExerciseAsSex() {
        XCTAssertFalse(AriaCoachAgentRouter.isCycleQuery("what should I exercise today"))
        XCTAssertTrue(AriaCoachAgentRouter.isCycleQuery("what positions can we try"))
        XCTAssertTrue(AriaCoachAgentRouter.isCycleQuery("tips for my partner during sex"))
        let composed = AriaCycleTools.compose(
            text: "positions and things we can try",
            phase: .menstruation,
            relationshipLabel: nil,
            reportText: nil,
            trainingText: nil
        )
        XCTAssertNotNil(composed)
        XCTAssertTrue(composed?.lowercased().contains("lube") == true)
        XCTAssertTrue(composed?.contains("Forge") == true)
        XCTAssertTrue(composed?.contains("on this iPhone") == true
                      || composed?.contains("On this iPhone") == true)
    }

    func testRemoteInferenceStripsHealthLedger() {
        var payload = ARIAContextPayload(
            timestamp: "2026-09-05T00:00:00Z",
            sleep: .init(hrv: 62),
            readiness: .init(recoveryScore: 71),
            training: .init(),
            activity: .init(steps3DayAvg: 8000),
            chronotype: .init(),
            body: .init(weightKg: 70),
            nutrition: .init(),
            profile: .init(constraints: ["cycle luteal volume cap"]),
            progress: .init(workoutsCompleted30d: 12),
            lifestyle: .init(
                tags: ["cycle_phase:luteal", "persona:stressed"],
                recentPatterns: ["cycle:bleeding"],
                goals: ["run"],
                cyclePhaseDirective: "secret phase law"
            ),
            clinicalData: .init(
                allergies: ["peanuts"],
                medications: [],
                conditions: [],
                immunizations: [],
                labResults: [],
                procedures: []
            )
        )
        payload = AriaOnDeviceHealthPolicy.strippedForRemoteInference(payload)
        XCTAssertNil(payload.sleep.hrv)
        XCTAssertNil(payload.readiness.recoveryScore)
        XCTAssertNil(payload.body.weightKg)
        XCTAssertNil(payload.progress.workoutsCompleted30d)
        XCTAssertNil(payload.lifestyle.cyclePhaseDirective)
        XCTAssertNil(payload.clinicalData)
        XCTAssertFalse(payload.lifestyle.tags.contains { $0.hasPrefix("cycle") })
        XCTAssertTrue(payload.lifestyle.tags.contains("persona:stressed"))
        XCTAssertTrue(payload.profile.constraints.isEmpty)
    }
}
