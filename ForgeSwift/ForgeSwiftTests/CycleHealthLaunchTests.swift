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
