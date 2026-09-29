import XCTest
@testable import ForgeCore

final class HealthKitOnboardingAuthorizationTests: XCTestCase {

    func testCompletedRequestIsConnectedAndPersisted() {
        XCTAssertTrue(
            HealthKitOnboardingAuthorization.isConnected(requestCompletedWithoutError: true)
        )
        XCTAssertEqual(
            HealthKitOnboardingAuthorization.outcome(requestCompletedWithoutError: true),
            .connected
        )
        XCTAssertTrue(
            HealthKitOnboardingAuthorization.persistConnected(requestCompletedWithoutError: true)
        )
        XCTAssertEqual(
            HealthKitOnboardingAuthorization.automaticRedirect(
                canPresentWriteSheet: false,
                writeStatusRawValue: 1
            ),
            .none
        )
    }

    func testFailedRequestIsEnableLaterWithoutRedirect() {
        XCTAssertFalse(
            HealthKitOnboardingAuthorization.isConnected(requestCompletedWithoutError: false)
        )
        XCTAssertEqual(
            HealthKitOnboardingAuthorization.outcome(requestCompletedWithoutError: false),
            .enableLater
        )
        XCTAssertFalse(
            HealthKitOnboardingAuthorization.persistConnected(requestCompletedWithoutError: false)
        )
        XCTAssertEqual(
            HealthKitOnboardingAuthorization.automaticRedirect(
                canPresentWriteSheet: false,
                writeStatusRawValue: 1
            ),
            .none
        )
    }

    func testUnknownReadStatusIsNotTreatedAsDenied() {
        // authorizationStatus(for:) raw values — write only.
        XCTAssertFalse(HealthKitOnboardingAuthorization.isReadDenied(writeStatusRawValue: 0))
        XCTAssertFalse(HealthKitOnboardingAuthorization.isReadDenied(writeStatusRawValue: 1))
        XCTAssertFalse(HealthKitOnboardingAuthorization.isReadDenied(writeStatusRawValue: 2))
    }

    func testTapAlwaysRequestsReadSheetWhenNotConnected() {
        XCTAssertEqual(
            HealthKitOnboardingAuthorization.tapAction(
                alreadyConnected: false,
                healthAvailable: true
            ),
            .requestReadAuthorization
        )
        XCTAssertEqual(
            HealthKitOnboardingAuthorization.tapAction(
                alreadyConnected: true,
                healthAvailable: true
            ),
            .refreshAlreadyConnected
        )
        XCTAssertEqual(
            HealthKitOnboardingAuthorization.tapAction(
                alreadyConnected: false,
                healthAvailable: false
            ),
            .stayWithoutRedirect
        )
    }

    func testOnboardingSheetIsReadOnlyWithoutClinical() {
        XCTAssertEqual(HealthKitOnboardingAuthorization.onboardingShareTypeCount, 0)
        XCTAssertFalse(HealthKitOnboardingAuthorization.onboardingIncludesClinicalTypes)
        XCTAssertEqual(
            HealthKitOnboardingAuthorization.connectedDefaultsKey,
            "HealthKitOnboardingReadConnected"
        )
    }
}
