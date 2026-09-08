import XCTest
import EventKit
import HealthKit
import ForgeCore
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

    func testVaginalBleedingReplacesDeprecatedMenstrualFlowEnum() {
        let values: [HKCategoryValueVaginalBleeding] = [
            .unspecified, .none, .light, .medium, .heavy
        ]
        XCTAssertEqual(Set(values.map(\.rawValue)).count, values.count)
        XCTAssertEqual(
            HKCategoryType(.menstrualFlow).identifier,
            HKCategoryTypeIdentifier.menstrualFlow.rawValue
        )
    }

    func testBiometricsTimestampsUseCurrentISO8601Format() {
        let stamp = Date.now.ISO8601Format()
        XCTAssertTrue(stamp.contains("T"))
        XCTAssertGreaterThanOrEqual(stamp.count, 20)
    }

    func testSpeechAmplitudePublishIsThrottledCoarserThanAudioQuantum() {
        XCTAssertGreaterThanOrEqual(SpeechManager.amplitudePublishInterval, 0.1)
        XCTAssertLessThan(SpeechManager.amplitudePublishInterval, 0.25)
    }

    func testHealthKitObserverStopIsIdempotent() {
        HealthKitManager.shared.stopBidirectionalSync()
        HealthKitManager.shared.stopBidirectionalSync()
        XCTAssertEqual(HealthKitManager.bidirectionalSampleTypes.count, 12)
        XCTAssertTrue(HealthKitManager.bidirectionalSampleTypes.contains(HKQuantityType(.dietaryWater)))
        XCTAssertTrue(HealthKitManager.bidirectionalSampleTypes.contains(HKCategoryType(.sleepAnalysis)))
    }

    func testForegroundScreenBrightnessIsFinite() {
        let value = ForegroundScreenBrightness.current
        XCTAssertTrue(value.isFinite)
        XCTAssertGreaterThanOrEqual(value, 0)
        XCTAssertLessThanOrEqual(value, 1)
    }

    func testCalendarIngestGuardsOnlyOnFullAccess() {
        XCTAssertFalse(CalendarManager.hasReadAccess(.writeOnly))
        XCTAssertFalse(CalendarManager.hasReadAccess(.denied))
        XCTAssertTrue(CalendarManager.hasReadAccess(.fullAccess))
    }

    func testCalendarAccessReasonsAreHumanReadable() {
        XCTAssertTrue(CalendarManager.describeAccess(.denied).localizedCaseInsensitiveContains("denied"))
        XCTAssertTrue(CalendarManager.describeAccess(.denied).localizedCaseInsensitiveContains("settings"))
        XCTAssertTrue(CalendarManager.describeAccess(.writeOnly).localizedCaseInsensitiveContains("write-only"))
        XCTAssertTrue(CalendarManager.describeAccess(.restricted).localizedCaseInsensitiveContains("restricted"))
        XCTAssertEqual(CalendarManager.describeAccess(.fullAccess), "full access")
        XCTAssertTrue(CalendarManager.describeAccess(.notDetermined).localizedCaseInsensitiveContains("not asked"))
    }

    func testCalendarWriteFailedKeepsTheUnderlyingReason() {
        let error = CalendarManager.CalendarError.writeFailed(
            "Couldn't save Forge test event 12: calendar is read-only"
        )
        XCTAssertEqual(
            error.errorDescription,
            "Couldn't save Forge test event 12: calendar is read-only"
        )
        XCTAssertEqual(
            LifeIngestError.explain(error, doing: "Couldn't write the Forge test calendar"),
            "Couldn't write the Forge test calendar: Couldn't save Forge test event 12: calendar is read-only"
        )
    }

    func testHealthKitSaveFailedReasonIsTheFullSentence() {
        let error = HealthKitError.saveFailedReason(
            "Couldn't write the Test-Ready Health pack into Apple Health: authorization denied"
        )
        XCTAssertEqual(
            error.errorDescription,
            "Couldn't write the Test-Ready Health pack into Apple Health: authorization denied"
        )
        XCTAssertEqual(
            LifeIngestError.explain(
                error,
                doing: "Couldn't write the Test-Ready Health pack into Apple Health"
            ),
            "Couldn't write the Test-Ready Health pack into Apple Health: authorization denied"
        )
    }

    func testEmptyHealthSnapshotDoesNotCountAsData() {
        let empty = HealthDataSnapshot(
            restingHeartRate: nil,
            activeCalories: nil,
            steps: nil,
            sleepHours: nil,
            hrv: nil,
            vo2Max: nil,
            workoutCount: nil,
            lastWorkoutDate: nil
        )
        XCTAssertFalse(empty.hasData)
        let live = HealthDataSnapshot(
            restingHeartRate: nil,
            activeCalories: nil,
            steps: 40,
            sleepHours: nil,
            hrv: nil,
            vo2Max: nil,
            workoutCount: nil,
            lastWorkoutDate: nil
        )
        XCTAssertTrue(live.hasData)
    }
}
