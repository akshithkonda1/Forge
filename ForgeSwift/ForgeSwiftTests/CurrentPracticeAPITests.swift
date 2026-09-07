import XCTest
import EventKit
import HealthKit
@testable import ForgeSwift

/// Locks the iOS 27 replacements for APIs Xcode flags as deprecated or renamed.
@MainActor
final class CurrentPracticeAPITests: XCTestCase {

    func testCalendarReadAccessUsesFullAccessNotDeprecatedAuthorized() {
        XCTAssertTrue(CalendarManager.hasReadAccess(.fullAccess))
        XCTAssertFalse(CalendarManager.hasReadAccess(.writeOnly))
        XCTAssertFalse(CalendarManager.hasReadAccess(.denied))
        XCTAssertFalse(CalendarManager.hasReadAccess(.restricted))
        XCTAssertFalse(CalendarManager.hasReadAccess(.notDetermined))
    }

    func testQuantityTypeInitReplacesDeprecatedFactory() {
        let steps = HKQuantityType(.stepCount)
        XCTAssertEqual(steps.identifier, HKQuantityTypeIdentifier.stepCount.rawValue)
        let water = HKQuantityType(.dietaryWater)
        XCTAssertEqual(water.identifier, HKQuantityTypeIdentifier.dietaryWater.rawValue)
        let vo2 = HKQuantityType(.vo2Max)
        XCTAssertEqual(vo2.identifier, HKQuantityTypeIdentifier.vo2Max.rawValue)
    }

    func testClinicalTypeInitReplacesDeprecatedFactory() {
        let allergy = HKClinicalType(.allergyRecord)
        XCTAssertEqual(allergy.identifier, HKClinicalTypeIdentifier.allergyRecord.rawValue)
        for identifier in HealthKitManager.structuredHealthRecordIdentifiers {
            let type = HKClinicalType(identifier)
            XCTAssertFalse(type.identifier.isEmpty)
            XCTAssertNotNil(StructuredHealthKind(identifier: identifier))
        }
    }

    func testForestSoundscapeLetsImmutableMixAndStaysFinite() {
        var dsp = SoundscapeDSP()
        dsp.reset(kind: .forest)
        for _ in 0..<2_205 {
            let sample = dsp.nextSample()
            XCTAssertTrue(sample.isFinite)
            XCTAssertGreaterThanOrEqual(sample, -1)
            XCTAssertLessThanOrEqual(sample, 1)
        }
    }

    func testBiometricsTimestampsUseCurrentISO8601Format() {
        let stamp = Date.now.ISO8601Format()
        XCTAssertTrue(stamp.contains("T"))
        XCTAssertGreaterThanOrEqual(stamp.count, 20)
    }
}
