import XCTest
@testable import ForgeSwift

final class CycleHealthLaunchTests: XCTestCase {

    func testExplicitPartnerAndSupportAliases() {
        XCTAssertEqual(pane(requested: "partner"), .partner)
        XCTAssertEqual(pane(requested: "Support"), .partner)
        XCTAssertEqual(pane(requested: " partner "), .partner)
    }

    func testExplicitMeWinsOverFamilySupport() {
        XCTAssertEqual(
            pane(requested: "me", selfTrackingEnabled: false, hasConsentedPeople: true, defaultToSupport: true),
            .me
        )
        XCTAssertEqual(pane(requested: "self"), .me)
    }

    func testSelfTrackingDefaultsToMyCycle() {
        XCTAssertEqual(
            pane(requested: nil, selfTrackingEnabled: true, hasConsentedPeople: true, defaultToSupport: true),
            .me
        )
    }

    func testFamilySupportOpensSupportWhenSelfTrackingIsOff() {
        XCTAssertEqual(
            pane(requested: nil, selfTrackingEnabled: false, hasConsentedPeople: true, defaultToSupport: false),
            .partner
        )
    }

    func testMaleWithoutSelfCycleOpensSupport() {
        XCTAssertEqual(
            pane(requested: nil, selfTrackingEnabled: false, hasConsentedPeople: false, defaultToSupport: true),
            .partner
        )
    }

    func testFemaleWithoutLogsOpensMyCycleEnablement() {
        XCTAssertEqual(
            pane(requested: nil, selfTrackingEnabled: false, hasConsentedPeople: false, defaultToSupport: false),
            .me
        )
    }

    private func pane(
        requested: String?,
        selfTrackingEnabled: Bool = false,
        hasConsentedPeople: Bool = false,
        defaultToSupport: Bool = false
    ) -> CycleHealthLaunch.Pane {
        CycleHealthLaunch.pane(
            requested: requested,
            selfTrackingEnabled: selfTrackingEnabled,
            hasConsentedPeople: hasConsentedPeople,
            defaultToSupport: defaultToSupport
        )
    }
}

final class CycleHealthCopyTests: XCTestCase {

    func testPhaseTrainingBiasOmitsRecovery() {
        for phase in MenstrualPhase.allCases {
            XCTAssertFalse(
                phase.trainingBias.localizedCaseInsensitiveContains("recovery"),
                phase.rawValue
            )
        }
    }

    func testConditionTrackingImplicationsOmitRecovery() {
        for condition in CycleCondition.allCases {
            XCTAssertFalse(
                condition.trackingImplication.localizedCaseInsensitiveContains("recovery"),
                condition.rawValue
            )
        }
    }

    func testEngineDisclaimerOmitsRecoveryAndKeepsLifestyleFrame() {
        XCTAssertFalse(MenstrualCycleEngine.disclaimer.localizedCaseInsensitiveContains("recovery"))
        XCTAssertTrue(MenstrualCycleEngine.disclaimer.localizedCaseInsensitiveContains("not medical diagnosis"))
        XCTAssertTrue(MenstrualCycleEngine.disclaimer.localizedCaseInsensitiveContains("readiness"))
    }

    @MainActor
    func testAnalystDirectiveOmitsRecoveryAndKeepsNeverDiagnose() {
        let directive = CycleAriaAnalyst.systemDirective
        XCTAssertFalse(directive.localizedCaseInsensitiveContains("recovery"))
        XCTAssertTrue(directive.contains("Never diagnose"))
        XCTAssertTrue(directive.localizedCaseInsensitiveContains("readiness"))
    }

    func testWorkoutDirectiveUsesTendenciesAndBlocksMaxEffortOnLowConfidence() {
        let banned = ["recovery", "aggression", "one-rep", "1rm", "best day for", "best phase for strength"]
        for phase in MenstrualPhase.allCases where phase != .unknown {
            let high = CyclePhaseCoachingDirective.directive(for: phase, domain: .workout, confidence: 0.85)
            let low = CyclePhaseCoachingDirective.directive(
                for: phase,
                domain: .workout,
                confidence: 0.45,
                ovulationMethod: "population_fallback"
            )
            for text in [high, low] {
                let lower = text.lowercased()
                for token in banned {
                    XCTAssertFalse(lower.contains(token), "\(phase.rawValue) still contains '\(token)'")
                }
                XCTAssertTrue(text.localizedCaseInsensitiveContains("lifestyle coaching"), phase.rawValue)
                XCTAssertTrue(text.localizedCaseInsensitiveContains("readiness"), phase.rawValue)
                XCTAssertTrue(text.localizedCaseInsensitiveContains("never diagnose"), phase.rawValue)
            }
            XCTAssertTrue(low.localizedCaseInsensitiveContains("low-confidence"), phase.rawValue)
            XCTAssertTrue(low.localizedCaseInsensitiveContains("do not push max efforts"), phase.rawValue)
            XCTAssertFalse(high.localizedCaseInsensitiveContains("low-confidence calendar estimate"), phase.rawValue)
        }
    }

    func testPeriodCoachingDirectiveOmitsRecovery() {
        var prefs = PeriodCoachingPreferences.neutral
        prefs.sampleCount = 2
        prefs.recoveryBias = 0.7
        prefs.avoidIntensityPush = true
        prefs.averageLifeImpact = 0.7
        prefs.lastLearnedSummary = "Next period: lean on more rest buffer"
        XCTAssertFalse(prefs.coachingDirective.localizedCaseInsensitiveContains("recovery"))
        XCTAssertTrue(prefs.coachingDirective.localizedCaseInsensitiveContains("rest"))
    }
}
