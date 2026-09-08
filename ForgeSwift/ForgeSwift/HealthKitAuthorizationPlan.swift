import Foundation
import HealthKit

/// One catalog for every Apple Health Allow path: onboarding, Medicine, lifestyle.
/// Clinical record *types* are only attached when the device supports Health
/// Records. Passing `HKClinicalType` into `requestAuthorization` on Simulator
/// (or a phone without Health Records) aborts the process — that is the
/// Medicine-page Allow crash.
///
/// Vision prescriptions (and any other type with
/// `requiresPerObjectAuthorization()`) cannot go through bulk
/// `requestAuthorization(toShare:read:)`. Apple's current API on iOS 16–27
/// is `requestPerObjectReadAuthorization(for:predicate:)`. Passing those
/// types into the bulk call throws `NSInvalidArgumentException`
/// (`HKVisionPrescriptionTypeIdentifier`) and aborts Connect Health on
/// iOS 26/27 Simulator — Swift `catch` cannot swallow that.
enum HealthKitAuthorizationPlan: Sendable {

    /// Structured records we ingest as name / date / source only.
    /// Never notes. Never insurance coverage. Never FHIR bodies.
    static let structuredClinicalIdentifiers: [HKClinicalTypeIdentifier] = {
        var ids: [HKClinicalTypeIdentifier] = [
            .allergyRecord,
            .medicationRecord,
            .conditionRecord,
            .immunizationRecord,
            .labResultRecord,
            .procedureRecord,
            HKClinicalTypeIdentifier(rawValue: "HKClinicalTypeIdentifierVitalSignRecord"),
        ]
        return ids
    }()

    static let forbiddenClinicalRawValues: Set<String> = [
        "HKClinicalTypeIdentifierClinicalNoteRecord",
        "HKClinicalTypeIdentifierCoverageRecord",
    ]

    static func shouldRequestClinical(
        healthDataAvailable: Bool,
        supportsHealthRecords: Bool
    ) -> Bool {
        healthDataAvailable && supportsHealthRecords
    }

    /// First-connect lifestyle tags. Pure so tests do not touch AriaContextStore.
    static func healthConnectTags(
        existing: [String],
        bloodType: String?,
        hasClinical: Bool,
        clinicalCount: Int
    ) -> [String] {
        var tags = existing.filter { !$0.hasPrefix("healthkit:") }
        tags.append("healthkit:connected")
        if let bloodType, !bloodType.isEmpty {
            tags.append("healthkit:blood_type:\(bloodType)")
        }
        if hasClinical {
            tags.append("healthkit:records:\(clinicalCount)")
        }
        return Array(Set(tags)).sorted()
    }

    /// Types a third-party app may ask to SHARE. Requesting Apple-only,
    /// clinical, characteristic, or reproductive write types on iOS 26/27
    /// (especially Simulator) throws `_throwIfAuthorizationDisallowedForSharing`
    /// as an NSException — Swift `catch` cannot swallow that, and Connect aborts.
    static func sanitizedShareTypes(_ requested: Set<HKSampleType>) -> Set<HKSampleType> {
        requested.filter { isThirdPartyWritable($0) }
    }

    static func isThirdPartyWritable(_ type: HKSampleType) -> Bool {
        if type is HKClinicalType { return false }
        let id = type.identifier
        if id.contains("Apple") { return false }
        if id.hasPrefix("HKCharacteristicType") { return false }
        switch id {
        case HKWorkoutType.workoutType().identifier,
             HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.dietaryProtein.rawValue,
             HKQuantityTypeIdentifier.dietaryCarbohydrates.rawValue,
             HKQuantityTypeIdentifier.dietaryFatTotal.rawValue,
             HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue,
             HKQuantityTypeIdentifier.dietaryWater.rawValue,
             HKQuantityTypeIdentifier.stepCount.rawValue,
             HKQuantityTypeIdentifier.bodyTemperature.rawValue,
             HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
             HKCategoryTypeIdentifier.mindfulSession.rawValue:
            return true
        default:
            return false
        }
    }

    /// Types that must not reach bulk `requestAuthorization(toShare:read:)`.
    /// Identifier fallback keeps Simulator/SDK stubs safe even if
    /// `requiresPerObjectAuthorization()` is wrong or missing.
    static var perObjectReadIdentifiers: Set<String> {
        [HKObjectType.visionPrescriptionType().identifier]
    }

    /// `true` when Apple's bulk authorization sheet may include this type.
    /// Current on iOS 26 and 27: `requiresPerObjectAuthorization()` plus
    /// clinical notes/coverage, which abort instead of returning `HKError`.
    static func isAllowedInBulkRead(_ type: HKObjectType) -> Bool {
        if type.requiresPerObjectAuthorization() { return false }
        if perObjectReadIdentifiers.contains(type.identifier) { return false }
        if let clinical = type as? HKClinicalType,
           forbiddenClinicalRawValues.contains(clinical.identifier) {
            return false
        }
        return true
    }

    /// Drop clinical types when Health Records are unavailable, and always
    /// drop per-object types (vision Rx). Never returns a set that would
    /// abort `requestAuthorization`.
    static func sanitizedReadTypes(
        _ types: Set<HKObjectType>,
        supportsHealthRecords: Bool
    ) -> Set<HKObjectType> {
        types.filter { type in
            guard isAllowedInBulkRead(type) else { return false }
            if !supportsHealthRecords && type is HKClinicalType { return false }
            return true
        }
    }

    static func readTypes(includeClinical: Bool) -> Set<HKObjectType> {
        var types = sampleAndCharacteristicReadTypes
        if includeClinical {
            types.formUnion(clinicalReadTypes)
        }
        return types
    }

    static var clinicalReadTypes: Set<HKObjectType> {
        Set(structuredClinicalIdentifiers.map { HKClinicalType($0) as HKObjectType })
    }

    static var sampleAndCharacteristicReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for id in quantityIdentifiers {
            types.insert(HKQuantityType(id))
        }
        for id in categoryIdentifiers {
            types.insert(HKCategoryType(id))
        }
        for id in characteristicIdentifiers {
            types.insert(HKCharacteristicType(id))
        }
        types.insert(HKObjectType.workoutType())
        types.insert(HKObjectType.activitySummaryType())
        types.insert(HKObjectType.electrocardiogramType())
        types.insert(HKObjectType.audiogramSampleType())
        // Do not insert `visionPrescriptionType()`. Glasses/contacts Rx
        // require `requestPerObjectReadAuthorization` and abort Connect
        // Health on iOS 26/27 Simulator if they ride the bulk sheet.
        return types
    }

    static var writeTypes: Set<HKSampleType> {
        [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryWater),
            HKWorkoutType.workoutType(),
            HKCategoryType(.sexualActivity),
            HKCategoryType(.mindfulSession),
            HKCategoryType(.menstrualFlow),
            HKQuantityType(.basalBodyTemperature),
            HKCategoryType(.cervicalMucusQuality),
            HKCategoryType(.ovulationTestResult),
        ]
    }

    static let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
        .heartRate, .restingHeartRate, .walkingHeartRateAverage,
        .heartRateRecoveryOneMinute, .heartRateVariabilitySDNN,
        .oxygenSaturation, .respiratoryRate, .bloodGlucose,
        .bloodPressureSystolic, .bloodPressureDiastolic,
        .bodyTemperature, .basalBodyTemperature, .appleSleepingWristTemperature,
        .activeEnergyBurned, .basalEnergyBurned,
        .appleExerciseTime, .appleStandTime, .appleMoveTime,
        .stepCount, .flightsClimbed,
        .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
        .swimmingStrokeCount, .walkingSpeed, .walkingStepLength,
        .runningSpeed, .runningPower, .runningStrideLength,
        .cyclingSpeed, .cyclingPower, .vo2Max,
        .bodyMass, .leanBodyMass, .bodyFatPercentage, .height, .bodyMassIndex,
        .waistCircumference,
        .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal,
        .dietaryFiber, .dietarySugar, .dietarySodium, .dietaryCaffeine,
        .dietaryEnergyConsumed, .dietaryWater, .dietaryCholesterol,
        .dietaryIron, .dietaryCalcium, .dietaryPotassium, .dietaryVitaminD,
        .insulinDelivery, .numberOfTimesFallen,
        .peakExpiratoryFlowRate, .forcedVitalCapacity, .forcedExpiratoryVolume1,
        .peripheralPerfusionIndex, .electrodermalActivity,
        .environmentalAudioExposure, .headphoneAudioExposure,
        .sixMinuteWalkTestDistance, .walkingAsymmetryPercentage,
        .walkingDoubleSupportPercentage, .stairAscentSpeed, .stairDescentSpeed,
        .appleWalkingSteadiness, .uvExposure, .timeInDaylight,
        .atrialFibrillationBurden, .physicalEffort,
    ]

    static let categoryIdentifiers: [HKCategoryTypeIdentifier] = [
        .sleepAnalysis, .mindfulSession, .appleStandHour,
        .highHeartRateEvent, .lowHeartRateEvent, .irregularHeartRhythmEvent,
        .lowCardioFitnessEvent, .environmentalAudioExposureEvent,
        .toothbrushingEvent, .handwashingEvent,
        .menstrualFlow, .intermenstrualBleeding,
        .infrequentMenstrualCycles, .irregularMenstrualCycles,
        .persistentIntermenstrualBleeding, .prolongedMenstrualPeriods,
        .cervicalMucusQuality, .ovulationTestResult, .progesteroneTestResult,
        .sexualActivity, .contraceptive, .pregnancy, .pregnancyTestResult, .lactation,
        .abdominalCramps, .bloating, .constipation, .diarrhea, .heartburn,
        .nausea, .vomiting, .appetiteChanges, .dizziness, .fainting, .fatigue,
        .fever, .generalizedBodyAche, .headache, .hotFlashes,
        .chestTightnessOrPain, .coughing, .rapidPoundingOrFlutteringHeartbeat,
        .shortnessOfBreath, .skippedHeartbeat, .wheezing,
        .lowerBackPain, .moodChanges, .memoryLapse,
        .soreThroat, .sinusCongestion, .runnyNose, .lossOfSmell, .lossOfTaste,
        .acne, .drySkin, .hairLoss, .nightSweats, .sleepChanges,
        .breastPain, .pelvicPain,
    ]

    static let characteristicIdentifiers: [HKCharacteristicTypeIdentifier] = [
        .dateOfBirth, .biologicalSex, .bloodType, .activityMoveMode, .fitzpatrickSkinType, .wheelchairUse,
    ]
}
