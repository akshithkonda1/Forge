import XCTest
import HealthKit
@testable import ForgeSwift

/// Locks the Allow-tap contract: clinical types never go to HealthKit when
/// Health Records are unavailable, per-object types (vision Rx) never ride
/// the bulk sheet, and first connect uses the full lifestyle catalog.
final class HealthKitAuthorizationPlanTests: XCTestCase {

    func testSimulatorMustNotRequestClinicalTypes() {
        XCTAssertFalse(
            HealthKitAuthorizationPlan.shouldRequestClinical(
                healthDataAvailable: true,
                supportsHealthRecords: false
            ),
            "No Health Records: clinical types must not ride requestAuthorization"
        )
        let types = HealthKitAuthorizationPlan.readTypes(includeClinical: false)
        XCTAssertFalse(types.contains { $0 is HKClinicalType })
        XCTAssertFalse(
            HealthKitAuthorizationPlan.sanitizedReadTypes(
                HealthKitAuthorizationPlan.readTypes(includeClinical: true),
                supportsHealthRecords: false
            ).contains { $0 is HKClinicalType }
        )
    }

    func testSupportedDeviceRequestsClinicalButNeverNotesOrCoverage() {
        XCTAssertTrue(
            HealthKitAuthorizationPlan.shouldRequestClinical(
                healthDataAvailable: true,
                supportsHealthRecords: true
            )
        )
        let clinical = HealthKitAuthorizationPlan.clinicalReadTypes
        XCTAssertFalse(clinical.isEmpty)
        let raw = Set(HealthKitAuthorizationPlan.structuredClinicalIdentifiers.map(\.rawValue))
        XCTAssertTrue(raw.contains(HKClinicalTypeIdentifier.medicationRecord.rawValue))
        XCTAssertTrue(raw.contains(HKClinicalTypeIdentifier.allergyRecord.rawValue))
        XCTAssertTrue(raw.isDisjoint(with: HealthKitAuthorizationPlan.forbiddenClinicalRawValues))
        for type in clinical {
            guard let clinicalType = type as? HKClinicalType else {
                XCTFail("non-clinical type in clinical catalog")
                continue
            }
            XCTAssertFalse(
                HealthKitAuthorizationPlan.forbiddenClinicalRawValues.contains(clinicalType.identifier)
            )
        }
    }

    func testFirstConnectCatalogIncludesLifestyleVitalsAndWorkouts() {
        let types = HealthKitAuthorizationPlan.readTypes(includeClinical: false)
        XCTAssertTrue(types.contains(HKQuantityType(.heartRate)))
        XCTAssertTrue(types.contains(HKQuantityType(.bloodGlucose)))
        XCTAssertTrue(types.contains(HKQuantityType(.bloodPressureSystolic)))
        XCTAssertTrue(types.contains(HKQuantityType(.oxygenSaturation)))
        XCTAssertTrue(types.contains(HKQuantityType(.bodyTemperature)))
        XCTAssertTrue(types.contains(HKCategoryType(.sleepAnalysis)))
        XCTAssertTrue(types.contains(HKCategoryType(.menstrualFlow)))
        XCTAssertTrue(types.contains(HKObjectType.workoutType()))
        XCTAssertTrue(types.contains(HKCharacteristicType(.dateOfBirth)))
        XCTAssertGreaterThan(types.count, 60, "first connect must ask for the full Health catalog")
    }

    func testUnavailableHealthNeverRequestsClinical() {
        XCTAssertFalse(
            HealthKitAuthorizationPlan.shouldRequestClinical(
                healthDataAvailable: false,
                supportsHealthRecords: true
            )
        )
    }

    func testHealthConnectTagsReplacePreviousHealthkitPrefix() {
        let tags = HealthKitAuthorizationPlan.healthConnectTags(
            existing: ["healthkit:records:3", "keep_me"],
            bloodType: "O+",
            hasClinical: true,
            clinicalCount: 7
        )
        XCTAssertTrue(tags.contains("keep_me"))
        XCTAssertTrue(tags.contains("healthkit:connected"))
        XCTAssertTrue(tags.contains("healthkit:blood_type:O+"))
        XCTAssertTrue(tags.contains("healthkit:records:7"))
        XCTAssertFalse(tags.contains("healthkit:records:3"))
    }

    func testShareCatalogNeverIncludesTypesThatAbortAllow() {
        let requested = HealthKitAuthorizationPlan.writeTypes
            .union(HealthKitAuthorizationPlan.testReadyPackShareTypes)
            .union([
                HKQuantityType(.heartRateVariabilitySDNN),
                HKQuantityType(.restingHeartRate),
                HKCategoryType(.menstrualFlow),
                HKCategoryType(.sexualActivity),
            ])
        let share = HealthKitAuthorizationPlan.sanitizedShareTypes(requested)
        XCTAssertTrue(share.contains(HKWorkoutType.workoutType()))
        XCTAssertTrue(share.contains(HKQuantityType(.dietaryWater)))
        XCTAssertTrue(share.contains(HKCategoryType(.sleepAnalysis)))
        XCTAssertFalse(share.contains(HKQuantityType(.heartRateVariabilitySDNN)))
        XCTAssertFalse(share.contains(HKQuantityType(.restingHeartRate)))
        XCTAssertFalse(share.contains(HKCategoryType(.menstrualFlow)))
        XCTAssertFalse(share.contains(HKCategoryType(.sexualActivity)))
        XCTAssertFalse(share.contains { $0 is HKClinicalType })
        XCTAssertFalse(share.contains { $0.identifier.contains("Apple") })
        XCTAssertFalse(
            HealthKitAuthorizationPlan.writeTypes.contains(HKCategoryType(.sleepAnalysis)),
            "Sleep stays off the production share set. Connect Health for everyone does not ask to write sleep."
        )
        XCTAssertFalse(
            HealthKitAuthorizationPlan.sanitizedShareTypes(HealthKitAuthorizationPlan.writeTypes)
                .contains(HKCategoryType(.sleepAnalysis))
        )
    }

    func testTestReadyPackShareTypesIncludeSleepAndExcludeAppleOnlyVitals() {
        let extras = HealthKitAuthorizationPlan.testReadyPackShareTypes
        XCTAssertTrue(extras.contains(HKCategoryType(.sleepAnalysis)))
        XCTAssertTrue(extras.contains(HKQuantityType(.stepCount)))
        XCTAssertTrue(extras.contains(HKQuantityType(.bodyTemperature)))
        XCTAssertTrue(extras.contains(HKQuantityType(.activeEnergyBurned)))
        XCTAssertTrue(extras.contains(HKQuantityType(.dietaryWater)))
        XCTAssertTrue(extras.contains(HKObjectType.workoutType()))
        XCTAssertFalse(extras.contains(HKQuantityType(.heartRateVariabilitySDNN)))
        XCTAssertFalse(extras.contains(HKQuantityType(.restingHeartRate)))
        XCTAssertEqual(HealthKitAuthorizationPlan.sanitizedShareTypes(extras), extras)

        let combined = HealthKitAuthorizationPlan.sanitizedShareTypes(
            HealthKitAuthorizationPlan.writeTypes.union(extras)
        )
        XCTAssertTrue(combined.contains(HKCategoryType(.sleepAnalysis)))
        XCTAssertFalse(combined.contains(HKQuantityType(.heartRateVariabilitySDNN)))
        XCTAssertFalse(combined.contains(HKQuantityType(.restingHeartRate)))
    }

    func testSkippableAuthorizationFailureRecognizesNotAuthorized() {
        XCTAssertTrue(
            HealthKitAuthorizationPlan.isSkippableAuthorizationFailure(
                NSError(
                    domain: HKError.errorDomain,
                    code: HKError.Code.errorAuthorizationDenied.rawValue
                )
            )
        )
        XCTAssertTrue(
            HealthKitAuthorizationPlan.isSkippableAuthorizationFailure(
                NSError(
                    domain: HKError.errorDomain,
                    code: HKError.Code.errorAuthorizationNotDetermined.rawValue
                )
            )
        )
        XCTAssertTrue(
            HealthKitAuthorizationPlan.isSkippableAuthorizationFailure(
                NSError(
                    domain: NSCocoaErrorDomain,
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Not authorized"]
                )
            )
        )
        XCTAssertFalse(
            HealthKitAuthorizationPlan.isSkippableAuthorizationFailure(
                NSError(domain: NSCocoaErrorDomain, code: 1)
            )
        )
    }

    func testVitalKindMapsFromVitalSignRecordIdentifier() {
        let vital = HKClinicalTypeIdentifier(rawValue: "HKClinicalTypeIdentifierVitalSignRecord")
        XCTAssertEqual(StructuredHealthKind(identifier: vital), .vital)
        XCTAssertNil(StructuredHealthKind(identifier: HKClinicalTypeIdentifier(rawValue: "HKClinicalTypeIdentifierCoverageRecord")))
    }

    func testCatalogNeverAsksBulkReadForVisionPrescription() {
        let vision = HKObjectType.visionPrescriptionType()
        XCTAssertEqual(vision.identifier, "HKVisionPrescriptionTypeIdentifier")
        XCTAssertTrue(
            vision.requiresPerObjectAuthorization(),
            "iOS 26/27: vision Rx is per-object, not bulk requestAuthorization"
        )
        let withClinical = HealthKitAuthorizationPlan.readTypes(includeClinical: true)
        let withoutClinical = HealthKitAuthorizationPlan.readTypes(includeClinical: false)
        XCTAssertFalse(withClinical.contains(vision))
        XCTAssertFalse(withoutClinical.contains(vision))
        XCTAssertFalse(withClinical.contains { $0.requiresPerObjectAuthorization() })
        XCTAssertFalse(withoutClinical.contains { $0.requiresPerObjectAuthorization() })
        XCTAssertFalse(
            HealthKitAuthorizationPlan.sampleAndCharacteristicReadTypes.contains(vision)
        )
    }

    func testSanitizerStripsVisionPrescriptionEvenWhenInjected() {
        let vision = HKObjectType.visionPrescriptionType()
        var injected = HealthKitAuthorizationPlan.readTypes(includeClinical: true)
        injected.insert(vision)
        XCTAssertTrue(injected.contains(vision), "precondition: injection reached the set")
        for supportsHealthRecords in [false, true] {
            let sanitized = HealthKitAuthorizationPlan.sanitizedReadTypes(
                injected,
                supportsHealthRecords: supportsHealthRecords
            )
            XCTAssertFalse(sanitized.contains(vision))
            XCTAssertFalse(sanitized.contains { $0.identifier == vision.identifier })
            XCTAssertFalse(sanitized.contains { $0.requiresPerObjectAuthorization() })
            XCTAssertTrue(sanitized.contains(HKQuantityType(.heartRate)))
            XCTAssertTrue(sanitized.contains(HKObjectType.workoutType()))
        }
    }

    func testBulkReadRejectsPerObjectAndClinicalNotes() {
        XCTAssertFalse(
            HealthKitAuthorizationPlan.isAllowedInBulkRead(
                HKObjectType.visionPrescriptionType()
            )
        )
        XCTAssertTrue(
            HealthKitAuthorizationPlan.isAllowedInBulkRead(HKQuantityType(.heartRate))
        )
        XCTAssertTrue(
            HealthKitAuthorizationPlan.perObjectReadIdentifiers.contains(
                "HKVisionPrescriptionTypeIdentifier"
            )
        )
        let notes = HKClinicalType(
            HKClinicalTypeIdentifier(rawValue: "HKClinicalTypeIdentifierClinicalNoteRecord")
        )
        XCTAssertFalse(HealthKitAuthorizationPlan.isAllowedInBulkRead(notes))
    }
}

/// Locks You Page Apple Health labels and reconnect routing. Connected is
/// never claimed just because the Allow sheet was shown.
@MainActor
final class AppleHealthYouStatusTests: XCTestCase {

    func testSheetShownWithoutWriteOrSamplesIsNeedsPermissionNotConnected() {
        XCTAssertEqual(
            AppleHealthYouStatus.resolve(
                healthAvailable: true,
                authorizationRequested: true,
                canWrite: false,
                hasReadableSamples: false,
                hasMeaningfulLifeSignal: false,
                usingTestReadyHealthPack: false
            ),
            .needsPermission
        )
    }

    func testWriteAuthorizationIsConnected() {
        XCTAssertEqual(
            AppleHealthYouStatus.resolve(
                healthAvailable: true,
                authorizationRequested: true,
                canWrite: true,
                hasReadableSamples: false,
                hasMeaningfulLifeSignal: false,
                usingTestReadyHealthPack: false
            ),
            .connected
        )
    }

    func testReadableSamplesAreConnectedWhenReadStatusIsHidden() {
        XCTAssertEqual(
            AppleHealthYouStatus.resolve(
                healthAvailable: true,
                authorizationRequested: true,
                canWrite: false,
                hasReadableSamples: true,
                hasMeaningfulLifeSignal: false,
                usingTestReadyHealthPack: false
            ),
            .connected
        )
    }

    func testMeaningfulLifeSignalIsConnectedUnlessTestReadyPack() {
        XCTAssertEqual(
            AppleHealthYouStatus.resolve(
                healthAvailable: true,
                authorizationRequested: true,
                canWrite: false,
                hasReadableSamples: false,
                hasMeaningfulLifeSignal: true,
                usingTestReadyHealthPack: false
            ),
            .connected
        )
        XCTAssertEqual(
            AppleHealthYouStatus.resolve(
                healthAvailable: true,
                authorizationRequested: true,
                canWrite: false,
                hasReadableSamples: false,
                hasMeaningfulLifeSignal: true,
                usingTestReadyHealthPack: true
            ),
            .needsPermission
        )
    }

    func testNeverRequestedIsOffline() {
        XCTAssertEqual(
            AppleHealthYouStatus.resolve(
                healthAvailable: true,
                authorizationRequested: false,
                canWrite: false,
                hasReadableSamples: false,
                hasMeaningfulLifeSignal: false,
                usingTestReadyHealthPack: false
            ),
            .offline
        )
    }

    func testUnavailableDeviceIsOffline() {
        XCTAssertEqual(
            AppleHealthYouStatus.resolve(
                healthAvailable: false,
                authorizationRequested: true,
                canWrite: true,
                hasReadableSamples: true,
                hasMeaningfulLifeSignal: true,
                usingTestReadyHealthPack: false
            ),
            .offline
        )
    }

    func testStatusLabelsMatchYouPageCopy() {
        XCTAssertEqual(AppleHealthYouStatus.offline.label, "Offline")
        XCTAssertEqual(AppleHealthYouStatus.needsPermission.label, "Needs permission")
        XCTAssertEqual(AppleHealthYouStatus.connected.label, "Connected")
    }

    func testReconnectOpensHealthAfterDeterminedDeny() {
        XCTAssertEqual(
            AppleHealthYouStatus.reconnectAction(
                status: .needsPermission,
                canPresentSheet: false,
                healthAvailable: true
            ),
            .openHealthSharing
        )
    }

    func testReconnectRequestsSheetWhenStillUndetermined() {
        XCTAssertEqual(
            AppleHealthYouStatus.reconnectAction(
                status: .offline,
                canPresentSheet: true,
                healthAvailable: true
            ),
            .requestAuthorization
        )
    }

    func testReconnectResyncsWhenLiveWithoutFlippingViaSheet() {
        XCTAssertEqual(
            AppleHealthYouStatus.reconnectAction(
                status: .connected,
                canPresentSheet: false,
                healthAvailable: true
            ),
            .resync
        )
        XCTAssertEqual(
            AppleHealthYouStatus.reconnectAction(
                status: .connected,
                canPresentSheet: true,
                healthAvailable: true
            ),
            .resync
        )
    }

    func testReconnectUnavailableWhenHealthMissing() {
        XCTAssertEqual(
            AppleHealthYouStatus.reconnectAction(
                status: .offline,
                canPresentSheet: false,
                healthAvailable: false
            ),
            .unavailable
        )
    }

    func testAppleHealthDeepLinkAndSharingCopy() {
        XCTAssertEqual(AppleHealthYouStatus.appleHealthURL?.scheme, "x-apple-health")
        XCTAssertTrue(AppleHealthYouCopy.sharingHint.contains("Health → Sharing"))
        XCTAssertTrue(AppleHealthYouCopy.reopenAfterDeny.contains("Allow sheet"))
        XCTAssertFalse(HealthKitManager.dailyStatsHaveReadableSamples(nil))
        XCTAssertFalse(HealthKitManager.dailyStatsHaveReadableSamples(.default))
        var stats = DailyHealthStats.default
        stats = DailyHealthStats(
            date: Date(),
            steps: 1200,
            activeCalories: 0,
            basalCalories: 0,
            totalCalories: 0,
            distanceWalkingRunningMeters: 0,
            distanceCyclingMeters: 0,
            distanceSwimmingMeters: 0,
            flightsClimbed: 0,
            exerciseMinutes: 0,
            standMinutes: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            fiber: 0,
            sugar: 0,
            sodium: 0,
            caffeine: 0,
            water: 0,
            sleepHours: 0,
            restingHeartRate: 0,
            walkingHeartRateAverage: 0,
            heartRateRecoveryOneMinute: 0,
            hrv: 0,
            vo2Max: 0,
            oxygenSaturation: 0,
            respiratoryRate: 0,
            bodyTemperature: 0,
            bloodPressureSystolic: 0,
            bloodPressureDiastolic: 0,
            walkingSpeed: 0,
            runningSpeed: 0,
            cyclingSpeed: 0,
            runningPower: 0,
            cyclingPower: 0
        )
        XCTAssertTrue(HealthKitManager.dailyStatsHaveReadableSamples(stats))
    }
}
