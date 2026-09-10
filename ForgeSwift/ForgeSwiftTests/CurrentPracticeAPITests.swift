import XCTest
import EventKit
import HealthKit
import AVFoundation
import ForgeCore
@testable import ForgeSwift

/// Locks the iOS 26/27 replacements for APIs Xcode flags as deprecated or renamed.
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

    func testVisionPrescriptionUsesPerObjectAuthorizationNotBulkSheet() {
        let vision = HKObjectType.visionPrescriptionType()
        XCTAssertEqual(vision.identifier, "HKVisionPrescriptionTypeIdentifier")
        XCTAssertTrue(vision.requiresPerObjectAuthorization())
        XCTAssertFalse(
            HealthKitAuthorizationPlan.isAllowedInBulkRead(vision),
            "Connect Health must not pass vision Rx into requestAuthorization"
        )
        let connectRead = HealthKitAuthorizationPlan.sanitizedReadTypes(
            HealthKitAuthorizationPlan.readTypes(includeClinical: true).union([vision]),
            supportsHealthRecords: false
        )
        XCTAssertFalse(connectRead.contains(vision))
        XCTAssertTrue(connectRead.contains(HKQuantityType(.stepCount)))
        XCTAssertTrue(connectRead.contains(HKQuantityType(.vo2Max)))
        XCTAssertTrue(connectRead.contains(HKCategoryType(.sleepAnalysis)))
    }

    func testQuantityAndClinicalInitsStayCurrentOnIOS26And27() {
        XCTAssertEqual(
            HKQuantityType(.appleSleepingWristTemperature).identifier,
            HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue
        )
        XCTAssertEqual(
            HKQuantityType(.physicalEffort).identifier,
            HKQuantityTypeIdentifier.physicalEffort.rawValue
        )
        XCTAssertEqual(
            HKClinicalType(.medicationRecord).identifier,
            HKClinicalTypeIdentifier.medicationRecord.rawValue
        )
        XCTAssertEqual(
            HKCharacteristicType(.dateOfBirth).identifier,
            HKCharacteristicTypeIdentifier.dateOfBirth.rawValue
        )
    }

    func testHomeLaunchMustNotWaitOnTestReadyIngest() {
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForHealthKitPackWrite)
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForCalendarYearWrite)
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForMedicationCatalog)
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForRemoteDashboard)
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForThirtyDayHealthQueries)
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForHealthKitAuthorizationSheet)
        XCTAssertFalse(TestReadyLaunchPolicy.calendarYearWriteRunsOnMainActor)
        XCTAssertEqual(FakeCalendarPack.horizonDays, 365)
        XCTAssertFalse(CalendarManager.writesToPersonalCalendars)
        XCTAssertFalse(FakeCalendarPack.writesToPersonalCalendars)
        XCTAssertFalse(AriaDummyOrchestrator.usesOffDeviceLLM)
        XCTAssertFalse(AriaDummyTurn.usesOffDeviceLLM)
        XCTAssertEqual(AriaOnboardingGuide.welcomeTitle, "ARIA is already learning.")
        XCTAssertTrue(QualityOfLifeLivingStore.isQuestion("what's my quality of life"))
        XCTAssertFalse(QualityOfLifeLivingStore.isQuestion("what should I train today"))
        XCTAssertTrue(
            AriaPromptCorrelation.correlates(
                reply: "Lifestyle QoL is 71/100 (steady). That's the same grade Life shows.",
                toPrompt: "what's my quality of life"
            )
        )
        XCTAssertFalse(
            AriaPromptCorrelation.correlates(
                reply: "Squats, 4x8, then a long run.",
                toPrompt: "what's my quality of life"
            )
        )
    }

    func testInstalledTestReadySeedsPersistAcrossProcessRestarts() {
        let healthKey = TestReadyLaunchPolicy.healthKitInstalledSeedKey
        let calendarKey = TestReadyLaunchPolicy.calendarInstalledSeedKey
        let previousHealth = UserDefaults.standard.object(forKey: healthKey)
        let previousCalendar = UserDefaults.standard.object(forKey: calendarKey)
        defer {
            if let previousHealth {
                UserDefaults.standard.set(previousHealth, forKey: healthKey)
            } else {
                UserDefaults.standard.removeObject(forKey: healthKey)
            }
            if let previousCalendar {
                UserDefaults.standard.set(previousCalendar, forKey: calendarKey)
            } else {
                UserDefaults.standard.removeObject(forKey: calendarKey)
            }
        }
        TestReadyLaunchPolicy.storeSeed(4_242, defaults: .standard, key: healthKey)
        TestReadyLaunchPolicy.storeSeed(4_242, defaults: .standard, key: calendarKey)
        XCTAssertEqual(HealthKitManager.shared.installedTestReadySeed, 4_242)
        XCTAssertEqual(CalendarManager.shared.installedTestReadySeed, 4_242)
        XCTAssertFalse(
            TestReadyLaunchPolicy.shouldRewrite(
                installedSeed: HealthKitManager.shared.installedTestReadySeed,
                sessionSeed: 4_242
            )
        )
        XCTAssertFalse(
            TestReadyLaunchPolicy.shouldRewrite(
                installedSeed: CalendarManager.shared.installedTestReadySeed,
                sessionSeed: 4_242
            )
        )
        XCTAssertTrue(
            TestReadyLaunchPolicy.shouldRewrite(
                installedSeed: HealthKitManager.shared.installedTestReadySeed,
                sessionSeed: 7
            )
        )
    }

    func testClinicalHealthRecordsShareUsageDescriptionIsDeclared() {
        let bundle = Bundle(for: HealthKitManager.self)
        let share = bundle.object(
            forInfoDictionaryKey: "NSHealthClinicalHealthRecordsShareUsageDescription"
        ) as? String
        let legacy = bundle.object(
            forInfoDictionaryKey: "NSHealthClinicalHealthRecordsUsageDescription"
        ) as? String
        XCTAssertFalse(
            share?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
            "SleepView → requestAuthorization aborts without the Share usage string"
        )
        XCTAssertFalse(legacy?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        XCTAssertTrue(share?.localizedCaseInsensitiveContains("Health") == true)
    }

    func testAudioSessionExposesAsyncActivateOnCurrentSDK() {
        #if compiler(>=6.4)
        XCTAssertTrue(
            AVAudioSession.sharedInstance().responds(
                to: NSSelectorFromString("activateWithOptions:completionHandler:")
            ),
            "iOS 26/27: activate(options:completionHandler:) replaces setActive on the main thread"
        )
        #endif
    }
}
