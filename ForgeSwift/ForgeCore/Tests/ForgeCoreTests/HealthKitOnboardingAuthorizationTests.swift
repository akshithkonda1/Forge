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

    func testOnboardingConnectedKeyIsLiveWithoutWriteOrSamples() {
        XCTAssertTrue(
            HealthKitOnboardingAuthorization.isLive(
                canWrite: false,
                hasReadableSamples: false,
                onboardingConnected: true
            )
        )
        XCTAssertFalse(
            HealthKitOnboardingAuthorization.isLive(
                canWrite: false,
                hasReadableSamples: false,
                onboardingConnected: false
            )
        )
        XCTAssertTrue(
            HealthKitOnboardingAuthorization.isLive(
                canWrite: true,
                hasReadableSamples: false,
                onboardingConnected: false
            )
        )
    }

    func testWeekOldNightIsNotPublishedAndLastNightIs() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let lastNight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let weekOld = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17))!
        XCTAssertNil(
            HealthKitOnboardingAuthorization.publishedSleepFields(
                nightKey: weekOld,
                lastNight: lastNight,
                hours: 7.5,
                score: 88,
                calendar: calendar
            )
        )
        let published = HealthKitOnboardingAuthorization.publishedSleepFields(
            nightKey: lastNight,
            lastNight: lastNight,
            hours: 7.5,
            score: 88,
            calendar: calendar
        )
        XCTAssertEqual(published?.hours, 7.5)
        XCTAssertEqual(published?.score, 88)
    }

    func testEmptyBackfillLineOnlyOnCompletedRequestWithZeroNights() {
        XCTAssertTrue(
            HealthKitOnboardingAuthorization.shouldShowEmptyBackfillLine(
                requestCompletedWithoutError: true,
                nightCount: 0,
                alreadyShown: false
            )
        )
        XCTAssertFalse(
            HealthKitOnboardingAuthorization.shouldShowEmptyBackfillLine(
                requestCompletedWithoutError: true,
                nightCount: 2,
                alreadyShown: false
            )
        )
        XCTAssertFalse(
            HealthKitOnboardingAuthorization.shouldShowEmptyBackfillLine(
                requestCompletedWithoutError: true,
                nightCount: 0,
                alreadyShown: true
            )
        )
        XCTAssertFalse(
            HealthKitOnboardingAuthorization.shouldShowEmptyBackfillLine(
                requestCompletedWithoutError: false,
                nightCount: 0,
                alreadyShown: false
            )
        )
        XCTAssertEqual(
            HealthKitOnboardingAuthorization.emptyBackfillLine,
            "No sleep yet. You can manage access in Health anytime."
        )
    }
}
