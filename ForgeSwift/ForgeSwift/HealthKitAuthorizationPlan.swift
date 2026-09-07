import Foundation
import HealthKit

/// One catalog for every Apple Health Allow path: onboarding, Medicine, lifestyle.
/// Clinical record *types* are only attached when the device supports Health
/// Records. Passing `HKClinicalType` into `requestAuthorization` on Simulator
/// (or a phone without Health Records) aborts the process — that is the
/// Medicine-page Allow crash.
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
        ]
        let vital = HKClinicalTypeIdentifier(rawValue: "HKClinicalTypeIdentifierVitalSignRecord")
        if HKObjectType.clinicalType(forIdentifier: vital) != nil {
            ids.append(vital)
        }
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

    /// Drop clinical types when Health Records are unavailable. Never returns
    /// a set that would abort `requestAuthorization`.
    static func sanitizedReadTypes(
        _ types: Set<HKObjectType>,
        supportsHealthRecords: Bool
    ) -> Set<HKObjectType> {
        guard supportsHealthRecords else {
            return types.filter { !($0 is HKClinicalType) }
        }
        return types.filter { type in
            guard let clinical = type as? HKClinicalType else { return true }
            return !forbiddenClinicalRawValues.contains(clinical.identifier)
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
        Set(structuredClinicalIdentifiers.compactMap { HKObjectType.clinicalType(forIdentifier: $0) })
    }

    static var sampleAndCharacteristicReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for id in quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        for id in categoryIdentifiers {
            if let type = HKCategoryType.categoryType(forIdentifier: id) {
                types.insert(type)
            }
        }
        for id in characteristicIdentifiers {
            if let type = HKCharacteristicType.characteristicType(forIdentifier: id) {
                types.insert(type)
            }
        }
        types.insert(HKObjectType.workoutType())
        types.insert(HKObjectType.activitySummaryType())
        types.insert(HKObjectType.electrocardiogramType())
        types.insert(HKObjectType.audiogramSampleType())
        types.insert(HKObjectType.visionPrescriptionType())
        return types
    }

    static var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryWater),
            HKWorkoutType.workoutType(),
        ]
        if let sex = HKCategoryType.categoryType(forIdentifier: .sexualActivity) { types.insert(sex) }
        if let mind = HKCategoryType.categoryType(forIdentifier: .mindfulSession) { types.insert(mind) }
        if let flow = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) { types.insert(flow) }
        if let bbt = HKQuantityType.quantityType(forIdentifier: .basalBodyTemperature) { types.insert(bbt) }
        if let mucus = HKCategoryType.categoryType(forIdentifier: .cervicalMucusQuality) { types.insert(mucus) }
        if let ovu = HKCategoryType.categoryType(forIdentifier: .ovulationTestResult) { types.insert(ovu) }
        return types
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
