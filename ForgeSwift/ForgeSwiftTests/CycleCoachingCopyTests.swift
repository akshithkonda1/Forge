import XCTest
@testable import ForgeSwift

final class CycleCoachingCopyTests: XCTestCase {

    func testUserFacingCycleCopyNeverSaysRecovery() {
        let surfaces: [(String, String)] = [
            ("disclaimer", MenstrualCycleEngine.disclaimer),
            ("luteal training", MenstrualPhase.luteal.trainingBias),
            ("endo tracking", CycleCondition.endometriosis.trackingImplication),
            ("aria system", CycleAriaAnalyst.systemDirective),
            ("aria disclaimer", CycleAriaAnalyst.lifestyleDisclaimer),
        ]
        for (name, text) in surfaces {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("recovery"), "\(name): \(text)")
        }
        for phase in MenstrualPhase.allCases {
            for domain: CoachingDomain in [.workout, .nutrition, .sleep, .stress, .general] {
                let high = CyclePhaseCoachingDirective.directive(
                    for: phase, domain: domain, confidence: 0.9, lutealDays: 14
                )
                XCTAssertFalse(high.localizedCaseInsensitiveContains("recovery"), high)
            }
        }
    }

    func testWorkoutGuidanceIsTentativeAndReadinessFirst() {
        let follicular = CyclePhaseCoachingDirective.directive(
            for: .follicular, domain: .workout, confidence: 0.8, lutealDays: 14
        )
        XCTAssertTrue(follicular.localizedCaseInsensitiveContains("many people")
                      || follicular.localizedCaseInsensitiveContains("some"))
        XCTAssertTrue(follicular.localizedCaseInsensitiveContains("readiness"))
        XCTAssertTrue(follicular.localizedCaseInsensitiveContains("lifestyle coaching"))
        XCTAssertFalse(follicular.localizedCaseInsensitiveContains("one-rep"))
        XCTAssertFalse(follicular.localizedCaseInsensitiveContains("aggression"))
        XCTAssertFalse(follicular.localizedCaseInsensitiveContains("best day"))

        let ovulation = CyclePhaseCoachingDirective.directive(
            for: .ovulation, domain: .workout, confidence: 0.85, lutealDays: 14
        )
        XCTAssertFalse(ovulation.localizedCaseInsensitiveContains("one-rep"))
        XCTAssertFalse(ovulation.localizedCaseInsensitiveContains("aggression"))
        XCTAssertFalse(ovulation.localizedCaseInsensitiveContains("best day"))
        XCTAssertTrue(ovulation.localizedCaseInsensitiveContains("some people")
                      || ovulation.localizedCaseInsensitiveContains("some"))
    }

    func testLowConfidenceCalendarEstimateDoesNotPushMaxEfforts() {
        let text = CyclePhaseCoachingDirective.directive(
            for: .follicular,
            domain: .workout,
            confidence: 0.45,
            lutealDays: 14,
            ovulationMethod: "population_fallback"
        )
        XCTAssertTrue(CyclePhaseCoachingDirective.isLowConfidenceEstimate(
            confidence: 0.45, ovulationMethod: "population_fallback"
        ))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("low-confidence"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("do not push max efforts"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("readiness"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("encourage ambition"))
    }

    func testLutealGuidanceUsesEffectiveLutealLength() {
        let split14 = CyclePhaseCoachingDirective.lutealSplit(lutealDays: 14)
        XCTAssertEqual(split14.earlyEnd, 7)
        XCTAssertEqual(split14.lateStart, 8)
        XCTAssertEqual(split14.luteal, 14)

        let split12 = CyclePhaseCoachingDirective.lutealSplit(lutealDays: 12)
        XCTAssertEqual(split12.lateStart, 7)
        XCTAssertEqual(split12.luteal, 12)

        let luteal = CyclePhaseCoachingDirective.directive(
            for: .luteal, domain: .workout, confidence: 0.8, lutealDays: 12
        )
        XCTAssertTrue(luteal.contains("7") && luteal.contains("12"), luteal)
        XCTAssertFalse(luteal.contains("8–14") || luteal.contains("8-14"))
    }

    func testPrivacyCopyMentionsARIAOptIn() {
        XCTAssertTrue(CyclePrivacy.policy.localizedCaseInsensitiveContains("ARIA reads cycle"))
        XCTAssertTrue(CyclePrivacy.bullets.contains { $0.text.localizedCaseInsensitiveContains("share with ARIA") })
        XCTAssertTrue(CyclePrivacy.shortPromise.contains("on device")
                      || CyclePrivacy.shortPromise.contains("on-device")
                      || CyclePrivacy.shortPromise.localizedCaseInsensitiveContains("stays on device"))
    }
}
