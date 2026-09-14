import XCTest
@testable import ForgeCore

final class PhoneDependencyTests: XCTestCase {

    func testStandaloneCapabilitiesAlwaysAllowed() {
        let standalones: [WatchCapability] = [
            .standaloneAria, .localMindfulness, .localWorkout,
            .localSleepAndWeek, .localLifestyle,
        ]
        for capability in standalones {
            for availability in [CompanionAvailability.unknown, .unavailable, .linkedButUnreachable, .reachable] {
                XCTAssertTrue(
                    PhoneDependency.allows(capability, availability: availability, hasAuthConfig: false),
                    "\(capability) must stay available when \(availability)"
                )
            }
        }
    }

    func testDeeperDebriefRequiresReachablePhoneAndAuth() {
        XCTAssertFalse(
            PhoneDependency.allows(.deeperAriaDebrief, availability: .reachable, hasAuthConfig: false)
        )
        XCTAssertFalse(
            PhoneDependency.allows(.deeperAriaDebrief, availability: .linkedButUnreachable, hasAuthConfig: true)
        )
        XCTAssertTrue(
            PhoneDependency.allows(.deeperAriaDebrief, availability: .reachable, hasAuthConfig: true)
        )
    }

    func testPhoneChatRequiresReachability() {
        XCTAssertFalse(
            PhoneDependency.allows(.phoneAriaChat, availability: .linkedButUnreachable, hasAuthConfig: true)
        )
        XCTAssertTrue(
            PhoneDependency.allows(.phoneAriaChat, availability: .reachable, hasAuthConfig: false)
        )
    }

    func testIndependenceBannerOnlyWhenPhoneAway() {
        XCTAssertNil(PhoneDependency.independenceBanner(for: .reachable))
        XCTAssertNil(PhoneDependency.independenceBanner(for: .unknown))
        XCTAssertNotNil(PhoneDependency.independenceBanner(for: .linkedButUnreachable))
        XCTAssertNotNil(PhoneDependency.independenceBanner(for: .unavailable))
    }

    func testExplanationNilWhenAllowed() {
        XCTAssertNil(
            PhoneDependency.explanation(
                for: .localMindfulness,
                availability: .unavailable,
                hasAuthConfig: false
            )
        )
        XCTAssertNotNil(
            PhoneDependency.explanation(
                for: .phoneAriaChat,
                availability: .unavailable,
                hasAuthConfig: false
            )
        )
    }
}
