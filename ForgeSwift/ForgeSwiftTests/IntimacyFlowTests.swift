import XCTest
@testable import ForgeSwift
import ForgeCore

final class IntimacyFlowTests: XCTestCase {

    func testOpenersStayShortAndAreNotTheCurriculum() {
        for flow in IntimacyFlow.allCases where flow.opensChat {
            XCTAssertLessThan(flow.userOpener.count, 120, flow.rawValue)
            XCTAssertFalse(flow.userOpener.lowercased().contains("pearl index"))
            XCTAssertFalse(flow.userOpener.contains(SexualHealthCurriculum.safeSexBasics()))
        }
    }

    func testHealthySafeSexOpeningIsARIASpeaking() {
        let session = IntimacyFlowComposer.session(
            .healthySafeSex,
            phase: .follicular,
            snapshot: nil,
            todayLog: nil,
            relationshipLabel: nil
        )
        XCTAssertEqual(session.userOpener, IntimacyFlow.healthySafeSex.userOpener)
        XCTAssertTrue(session.ariaOpening.contains("I'm ARIA"))
        XCTAssertTrue(session.ariaOpening.lowercased().contains("consent"))
        XCTAssertTrue(session.suggestedActions.contains("Consent and protection"))
        XCTAssertFalse(session.ariaOpening.lowercased().contains("pearl index"))
    }

    func testPeriodSexUsesLogsToLeanWaitOnHeavyPain() {
        let log = CycleDayLog(
            dayKey: "2026-09-05",
            flow: .heavy,
            symptoms: [.cramps, .pelvicPain],
            painScale: 8
        )
        var snap = MenstrualCycleSnapshot.empty
        snap.phase = .menstruation
        snap.isCurrentlyBleeding = true
        snap.dayInCycle = 2
        let eval = SexualHealthCurriculum.periodSexEvaluation(
            phase: .menstruation,
            isBleeding: true,
            flow: .heavy,
            painScale: 8,
            symptoms: [.cramps, .pelvicPain],
            dayInCycle: 2
        )
        XCTAssertEqual(eval.lean, .wait)
        XCTAssertTrue(eval.headline.lowercased().contains("wait"))

        let session = IntimacyFlowComposer.session(
            .periodSex,
            phase: .menstruation,
            snapshot: snap,
            todayLog: log,
            relationshipLabel: nil
        )
        XCTAssertTrue(session.ariaOpening.lowercased().contains("wait"))
        XCTAssertTrue(session.ariaOpening.contains("8/10") || session.ariaOpening.contains("Pain scale"))
        XCTAssertTrue(session.ariaOpening.contains("you still decide") || session.ariaOpening.contains("You still decide"))
    }

    func testPeriodSexOptionalWhenNotBleedingAndCalm() {
        let eval = SexualHealthCurriculum.periodSexEvaluation(
            phase: .follicular,
            isBleeding: false,
            flow: .none,
            painScale: nil,
            symptoms: [],
            dayInCycle: 8
        )
        XCTAssertEqual(eval.lean, .optional)
    }

    func testPartnerTipsParentLaneHasNoSexMenu() {
        let session = IntimacyFlowComposer.session(
            .partnerTips,
            phase: .luteal,
            snapshot: nil,
            todayLog: nil,
            relationshipLabel: "parent"
        )
        let blob = session.ariaOpening.lowercased()
        XCTAssertTrue(blob.contains("parent"))
        XCTAssertFalse(blob.contains("spooning"))
        XCTAssertFalse(blob.contains("you on top"))
    }

    func testTryingToConceiveAsksWhatTheyMean() {
        let session = IntimacyFlowComposer.session(
            .tryingToConceive,
            phase: .fertileWindow,
            snapshot: nil,
            todayLog: nil,
            relationshipLabel: nil
        )
        XCTAssertTrue(session.ariaOpening.lowercased().contains("what are you trying to conceive"))
        XCTAssertTrue(session.suggestedActions.contains("A pregnancy this cycle"))
    }

    func testDifficultyGuideListsSpecialistsAndIsNotAClinic() {
        XCTAssertTrue(DifficultyConceivingGuide.specialists.contains { $0.title.contains("REI") })
        XCTAssertTrue(DifficultyConceivingGuide.specialists.contains { $0.title.lowercased().contains("urology") })
        let blob = DifficultyConceivingGuide.copy.joined(separator: " ").lowercased()
        XCTAssertTrue(blob.contains("literacy"))
        XCTAssertFalse(blob.contains("pearl index"))
    }

    func testAriaCycleToolsPeriodSexIncludesEvaluation() {
        let composed = AriaCycleTools.compose(
            text: "sex during my period given my logs",
            phase: .menstruation,
            relationshipLabel: nil,
            reportText: nil,
            trainingText: nil,
            periodSex: .init(
                isBleeding: true,
                flow: .light,
                painScale: 2,
                symptoms: [],
                dayInCycle: 4
            )
        )
        XCTAssertNotNil(composed)
        XCTAssertTrue(composed?.lowercased().contains("optional") == true
                      || composed?.lowercased().contains("bleeding") == true)
        XCTAssertTrue(composed?.contains("On this iPhone") == true)
    }

    func testHandoffSeedsIntimacyWithoutAutoSend() {
        let session = IntimacyChatSession(
            flow: .positions,
            userOpener: "Positions and things to try — explain them like you would.",
            ariaOpening: "A short menu",
            suggestedActions: ["Just the menu"]
        )
        let result = ARIAChatHandoff.consume(
            .init(pendingPrompt: "should not send", voiceLaunch: false, intimacySession: session)
        )
        XCTAssertFalse(result.autoSend)
        XCTAssertNil(result.prompt)
        XCTAssertEqual(result.intimacySession, session)
    }

    func testCycleReportPDFFileNameAndBytes() {
        let name = CycleReportPDF.fileName(windowMonths: 12, dayKey: "2026-09-05")
        XCTAssertEqual(name, "forge-cycle-report-12m-2026-09-05.pdf")
        let data = CycleReportPDF.render(title: "FORGE — 12-MONTH TRACKING SUMMARY", body: "Days logged: 12")
        XCTAssertGreaterThan(data.count, 20)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)) || String(data: data, encoding: .utf8)?.contains("PDF") == true)
    }

    func testClinicianPDFTextStillPassesDenylist() {
        let text = CycleRhythmReport.clinicianText(
            months: [
                CycleMonthlyDigest(
                    monthKey: "2026-08",
                    daysLogged: 20,
                    bleedingDays: 5,
                    cycleStarts: 1
                )
            ],
            generatedDayKey: "2026-09-05",
            typicalCycle: 28,
            typicalPeriod: 5,
            mae: 1.1,
            maeSamples: 3,
            windowMonths: 3
        )
        for term in CycleRhythmReport.forbiddenClinicianTerms {
            XCTAssertFalse(text.lowercased().contains(term), "clinician pack leaked \(term)")
        }
    }
}
