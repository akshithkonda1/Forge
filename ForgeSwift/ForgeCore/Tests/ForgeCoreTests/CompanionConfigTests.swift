import XCTest
@testable import ForgeCore

/// Classification of the config the iPhone pushes to the watch.
///
/// This is a trust boundary: where each value is written afterwards decides
/// whether a session token ends up in the Keychain or in an unencrypted plist
/// that rides along in backups. It used to be an inline loop in
/// PhoneLinkService with the key list written out twice.
final class CompanionConfigTests: XCTestCase {

    func testTokenAndUserIdAreSecrets() {
        let config = CompanionConfig.parse([
            "forge.aria.authToken": "eyJhbGciOi.tokenish.value",
            "forge.aria.userId": "us-east-1:abc",
        ])
        XCTAssertEqual(config?.secrets["forge.aria.authToken"], "eyJhbGciOi.tokenish.value")
        XCTAssertEqual(config?.secrets["forge.aria.userId"], "us-east-1:abc")
        XCTAssertTrue(config?.preferences.isEmpty ?? false,
                      "a credential must never be routed to the defaults suite")
    }

    func testOrdinaryConfigurationIsAPreference() {
        let config = CompanionConfig.parse([
            "forge.aria.baseURL": "https://api.example.com",
            "forge.user.firstName": "Sam",
            "forge.companion.syncedAt": "2026-08-25T00:00:00Z",
        ])
        XCTAssertEqual(config?.preferences.count, 3)
        XCTAssertTrue(config?.secrets.isEmpty ?? false)
    }

    func testAMixedPayloadSplitsBothWays() {
        let config = CompanionConfig.parse([
            "forge.aria.authToken": "secret",
            "forge.aria.baseURL": "https://api.example.com",
        ])
        XCTAssertEqual(config?.secrets, ["forge.aria.authToken": "secret"])
        XCTAssertEqual(config?.preferences, ["forge.aria.baseURL": "https://api.example.com"])
    }

    func testUnknownKeysAreDroppedRatherThanDefaultingToThePlist() {
        // The failure this type exists to prevent: an unrecognised key has no
        // defined destination, and "write it to defaults" is the wrong guess.
        let config = CompanionConfig.parse([
            "forge.aria.baseURL": "https://api.example.com",
            "forge.some.future.credential": "do-not-store-me",
        ])
        XCTAssertNil(config?.preferences["forge.some.future.credential"])
        XCTAssertNil(config?.secrets["forge.some.future.credential"])
    }

    func testTheNestedFormIsAcceptedAndStillClassified() {
        let config = CompanionConfig.parse([
            CompanionConfig.nestedKey: [
                "forge.aria.authToken": "secret",
                "forge.user.firstName": "Sam",
            ],
        ])
        XCTAssertEqual(config?.secrets, ["forge.aria.authToken": "secret"])
        XCTAssertEqual(config?.preferences, ["forge.user.firstName": "Sam"])
    }

    func testWorkoutPayloadsAreNotConfiguration() {
        // These travel the other way — the watch is their sender. Parsing one
        // would be reading the app's own echo back as settings.
        XCTAssertNil(CompanionConfig.parse([WorkoutLinkKeys.state: Data()]))
        XCTAssertNil(CompanionConfig.parse([WorkoutLinkKeys.ended: true]))
        XCTAssertNil(CompanionConfig.parse([
            WorkoutLinkKeys.state: Data(),
            "forge.aria.authToken": "must-be-ignored-here",
        ]), "a workout payload is rejected whole, not picked over")
    }

    func testNonStringValuesAndEmptyPayloadsYieldNothing() {
        XCTAssertNil(CompanionConfig.parse([:]))
        XCTAssertNil(CompanionConfig.parse(["forge.aria.authToken": 42]))
        XCTAssertNil(CompanionConfig.parse(["unrelated": "value"]))
    }

    func testSecretAndPreferenceKeysDoNotOverlap() {
        XCTAssertTrue(
            CompanionConfig.secretKeys.isDisjoint(with: CompanionConfig.preferenceKeys),
            "a key in both lists would be written to the Keychain and the plist"
        )
    }
}
