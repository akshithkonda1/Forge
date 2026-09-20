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

    func testSimulatorSkipsPhoneSessionUnlessCompanionScheme() {
        XCTAssertFalse(
            PhoneDependency.shouldActivatePhoneSession(
                isSupported: true, isSimulator: true, companionLaunchRequested: false
            ),
            "phone-only Simulator Run must not activate WCSession"
        )
        XCTAssertTrue(
            PhoneDependency.shouldActivatePhoneSession(
                isSupported: true, isSimulator: true, companionLaunchRequested: true
            )
        )
        XCTAssertTrue(
            PhoneDependency.shouldActivatePhoneSession(
                isSupported: true, isSimulator: false, companionLaunchRequested: false
            ),
            "a physical iPhone still activates so a later pair works"
        )
        XCTAssertFalse(
            PhoneDependency.shouldActivatePhoneSession(
                isSupported: false, isSimulator: false, companionLaunchRequested: true
            )
        )
    }

    func testTalkGatesRequireARealPair() {
        XCTAssertFalse(
            PhoneDependency.phoneMayTalkToWatch(
                isActivated: true, isPaired: false, isWatchAppInstalled: true
            )
        )
        XCTAssertTrue(
            PhoneDependency.phoneMayTalkToWatch(
                isActivated: true, isPaired: true, isWatchAppInstalled: true
            )
        )
        XCTAssertFalse(
            PhoneDependency.watchMayTalkToPhone(
                isActivated: true, isCompanionAppInstalled: false
            )
        )
        XCTAssertTrue(
            PhoneDependency.watchMayTalkToPhone(
                isActivated: true, isCompanionAppInstalled: true
            )
        )
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
