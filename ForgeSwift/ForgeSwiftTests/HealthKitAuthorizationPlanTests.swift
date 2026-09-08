import XCTest
import HealthKit
@testable import ForgeSwift

/// Locks the Allow-tap contract: clinical types never go to HealthKit when
/// Health Records are unavailable, and first connect uses the full catalog.
final class HealthKitAuthorizationPlanTests: XCTestCase {

    func testSimulatorMustNotRequestClinicalTypes() {
        XCTAssertFalse(
            HealthKitAuthorizationPlan.shouldRequestClinical(
                healthDataAvailable: true,
                supportsHealthRecords: false
            ),
            "Simulator / no Health Records: clinical types abort requestAuthorization"
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
        let requested = HealthKitAuthorizationPlan.writeTypes.union([
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
    }

    func testVitalKindMapsFromVitalSignRecordIdentifier() {
        let vital = HKClinicalTypeIdentifier(rawValue: "HKClinicalTypeIdentifierVitalSignRecord")
        XCTAssertEqual(StructuredHealthKind(identifier: vital), .vital)
        XCTAssertNil(StructuredHealthKind(identifier: HKClinicalTypeIdentifier(rawValue: "HKClinicalTypeIdentifierCoverageRecord")))
    }
}
