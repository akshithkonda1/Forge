import Foundation
import HealthKit
import ForgeCore

extension HealthKitManager {

    func fetchClinicalRecordsSummary() async -> ClinicalRecordsSummary {
        if let lastClinicalAt, let clinicalSummary,
           Date().timeIntervalSince(lastClinicalAt) < Self.clinicalTTL {
            return clinicalSummary
        }
        let recordBuckets = await withTaskGroup(of: (StructuredHealthKind, [StructuredHealthItem]).self) { group in
            for identifier in Self.structuredHealthRecordIdentifiers {
                group.addTask { [healthStore] in
                    guard let kind = StructuredHealthKind(identifier: identifier),
                          let type = HKObjectType.clinicalType(forIdentifier: identifier) else {
                        return (.allergy, [])
                    }
                    let records = await Self.fetchClinicalRecords(type: type, healthStore: healthStore)
                    let items = records.map { record in
                        StructuredHealthItem(
                            id: record.uuid.uuidString,
                            kind: kind,
                            name: record.displayName,
                            date: record.endDate,
                            source: record.sourceRevision.source.name
                        )
                    }
                    return (kind, items)
                }
            }

            var buckets: [(StructuredHealthKind, [StructuredHealthItem])] = []
            for await bucket in group {
                buckets.append(bucket)
            }
            return buckets
        }

        let items = recordBuckets.flatMap(\.1).sorted { $0.date > $1.date }
        // uniquingKeysWith, not uniqueKeysWithValues: every identifier falls
        // back to the same (.allergy, []) bucket if HKObjectType.clinicalType
        // ever returns nil for it (line 16-18 above) -- two such collisions
        // in the same batch would trap here otherwise. Not currently
        // reachable (the six identifiers are stable pre-iOS-12 API), but
        // this is the identical failure class already fixed once in
        // MenstrualHealthStore+HealthKit.swift, so it's summed rather than
        // left to collide -- recordCountsByType should still add up to
        // items.count either way.
        let counts = Dictionary(recordBuckets.map { ($0.0.rawValue, $0.1.count) }, uniquingKeysWith: +)
        let summary = ClinicalRecordsSummary(
            items: items,
            totalRecordCount: items.count,
            recordCountsByType: counts,
            recentRecordNames: Array(items.prefix(8).map(\.name)),
            connectedSourceNames: Array(Set(items.map(\.source))).sorted(),
            hasData: !items.isEmpty
        )
        clinicalSummary = summary
        lastClinicalAt = Date()
        return summary
    }

    func fetchCycleSummary() async -> CycleHealthSummary {
        let calendar = Calendar.current
        let now = Date()
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: ninetyDaysAgo, end: now, options: .strictStartDate)
        
        async let flowSamples = fetchCategorySamples(.menstrualFlow, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let spottingSamples = fetchCategorySamples(.intermenstrualBleeding, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let infrequentCycles = fetchCategorySamples(.infrequentMenstrualCycles, predicate: predicate, limit: 1)
        async let irregularCycles = fetchCategorySamples(.irregularMenstrualCycles, predicate: predicate, limit: 1)
        async let persistentSpotting = fetchCategorySamples(.persistentIntermenstrualBleeding, predicate: predicate, limit: 1)
        async let prolongedPeriods = fetchCategorySamples(.prolongedMenstrualPeriods, predicate: predicate, limit: 1)
        async let ovulationResult = fetchMostRecentCategoryValue(.ovulationTestResult)
        async let progesteroneResult = fetchMostRecentCategoryValue(.progesteroneTestResult)
        async let pregnancyResult = fetchMostRecentCategoryValue(.pregnancyTestResult)
        async let basalTemperature = fetchMostRecentQuantity(.basalBodyTemperature, unit: .degreeFahrenheit())
        async let sexualActivitySamples = fetchCategorySamples(.sexualActivity, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let pregnancySamples = fetchCategorySamples(.pregnancy, predicate: predicate, limit: 1)
        async let lactationSamples = fetchCategorySamples(.lactation, predicate: predicate, limit: 1)
        
        let flow = await flowSamples
        let spotting = await spottingSamples
        let cycleDeviationValues = await (infrequentCycles, irregularCycles, persistentSpotting, prolongedPeriods)
        let reproductiveValues = await (ovulationResult, progesteroneResult, pregnancyResult, basalTemperature, sexualActivitySamples, pregnancySamples, lactationSamples)
        
        let periodSamples = flow.filter { sample in
            guard let value = HKCategoryValueMenstrualFlow(rawValue: sample.value) else { return false }
            return value != .none
        }
        let cycleStart = periodSamples.first { sample in
            sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool == true
        }?.startDate ?? periodSamples.first?.startDate
        let currentCycleDay = cycleStart.map { max(calendar.dateComponents([.day], from: $0, to: now).day ?? 0, 0) + 1 }
        let lastFlowLevel = periodSamples.first.flatMap { menstrualFlowLabel(rawValue: $0.value) }
        let sexualActivity = reproductiveValues.4
        let lastSexualActivity = sexualActivity.first
        let hasCycleDeviation = !cycleDeviationValues.0.isEmpty || !cycleDeviationValues.1.isEmpty || !cycleDeviationValues.2.isEmpty || !cycleDeviationValues.3.isEmpty
        let hasData = !flow.isEmpty || !spotting.isEmpty || hasCycleDeviation || reproductiveValues.0 != nil || reproductiveValues.1 != nil || reproductiveValues.2 != nil || reproductiveValues.3 != nil || !sexualActivity.isEmpty || !reproductiveValues.5.isEmpty || !reproductiveValues.6.isEmpty
        
        let summary = CycleHealthSummary(
            lastPeriodStart: cycleStart,
            currentCycleDay: currentCycleDay,
            periodDaysInLast90: periodSamples.count,
            lastFlowLevel: lastFlowLevel,
            hasRecentSpotting: !spotting.isEmpty,
            hasCycleDeviation: hasCycleDeviation,
            latestOvulationTestResult: reproductiveValues.0,
            latestProgesteroneTestResult: reproductiveValues.1,
            latestPregnancyTestResult: reproductiveValues.2,
            latestBasalBodyTemperature: reproductiveValues.3,
            menopausalState: nil,
            sexualActivityCountLast90Days: sexualActivity.count,
            lastSexualActivityDate: lastSexualActivity?.startDate,
            lastSexualActivityProtectionUsed: lastSexualActivity?.metadata?[HKMetadataKeySexualActivityProtectionUsed] as? Bool,
            isPregnant: !reproductiveValues.5.isEmpty,
            isLactating: !reproductiveValues.6.isEmpty,
            hasData: hasData
        )
        cycleSummary = summary
        return summary
    }

    /// Full multi-signal menstrual bundle for the high-accuracy cycle engine.
    func fetchMenstrualHealthBundle(days: Int = 400) async -> MenstrualHealthKitBundle {
        guard HKHealthStore.isHealthDataAvailable() else {
            return MenstrualHealthKitBundle(flowSamples: [], bbtSamples: [], ovulationTests: [], mucusSamples: [])
        }
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        async let flowSamples = fetchCategorySamples(.menstrualFlow, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let mucusSamples = fetchCategorySamples(.cervicalMucusQuality, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let ovuSamples = fetchCategorySamples(.ovulationTestResult, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let bbtSamples = fetchQuantitySamples(.basalBodyTemperature, unit: .degreeCelsius(), predicate: predicate, limit: HKObjectQueryNoLimit)

        let flow = await flowSamples
        let mucus = await mucusSamples
        let ovu = await ovuSamples
        let bbt = await bbtSamples

        let flowMapped: [(date: Date, flow: MenstrualFlowLevel)] = flow.compactMap { sample in
            guard let value = HKCategoryValueMenstrualFlow(rawValue: sample.value) else { return nil }
            let level: MenstrualFlowLevel
            switch value {
            case .none: level = .none
            case .light: level = .light
            case .medium: level = .medium
            case .heavy: level = .heavy
            case .unspecified: level = .unspecified
            @unknown default: level = .unspecified
            }
            // Skip pure none samples unless marked cycle start
            if level == .none { return nil }
            return (sample.startDate, level)
        }

        let mucusMapped: [(date: Date, quality: CervicalMucusQuality)] = mucus.compactMap { sample in
            guard let value = HKCategoryValueCervicalMucusQuality(rawValue: sample.value) else { return nil }
            let q: CervicalMucusQuality
            switch value {
            case .dry: q = .dry
            case .sticky: q = .sticky
            case .creamy: q = .creamy
            case .watery: q = .watery
            case .eggWhite: q = .eggWhite
            @unknown default: q = .unknown
            }
            return (sample.startDate, q)
        }

        let ovuMapped: [(date: Date, result: OvulationTestResult)] = ovu.compactMap { sample in
            guard let value = HKCategoryValueOvulationTestResult(rawValue: sample.value) else { return nil }
            let r: OvulationTestResult
            switch value {
            case .negative: r = .negative
            case .luteinizingHormoneSurge: r = .lhSurge
            case .indeterminate: r = .indeterminate
            case .estrogenSurge: r = .estrogenSurge
            case .positive: r = .positive
            @unknown default: r = .unknown
            }
            return (sample.startDate, r)
        }

        let bbtMapped: [(date: Date, celsius: Double)] = bbt.map { ($0.date, $0.value) }

        return MenstrualHealthKitBundle(
            flowSamples: flowMapped,
            bbtSamples: bbtMapped,
            ovulationTests: ovuMapped,
            mucusSamples: mucusMapped
        )
    }

    func fetchUserProfile() async -> UserHealthProfile? {
        async let dob = fetchDateOfBirth()
        async let biologicalSex = fetchBiologicalSex()
        async let bloodType = fetchBloodType()
        async let weight = fetchMostRecentWeight()
        async let height = fetchHeight()
        async let bmi = fetchMostRecentQuantity(.bodyMassIndex, unit: .count())
        async let leanMass = fetchMostRecentQuantity(.leanBodyMass, unit: .gramUnit(with: .kilo))
        async let bodyFat = fetchMostRecentQuantity(.bodyFatPercentage, unit: .percent())
        async let restingHR = fetchMostRecentRestingHeartRate()
        async let vo2Max = fetchMostRecentVO2Max()
        async let avgHRV = fetchAverageHRV()

        let profileValues = await (dob, biologicalSex, bloodType, weight, height, bmi, leanMass, bodyFat, restingHR, vo2Max, avgHRV)
        let birth = profileValues.0
        let age: Int? = birth.flatMap {
            Calendar.current.dateComponents([.year], from: $0, to: Date()).year
        }
        let expandedRequested = UserDefaults.standard.bool(forKey: expandedAuthorizationRequestedKey)
        let clinicalRequested = UserDefaults.standard.bool(forKey: clinicalAuthorizationRequestedKey)
        let cycle = expandedRequested ? await fetchCycleSummary() : nil
        let clinical = clinicalRequested ? await fetchClinicalRecordsSummary() : nil

        return UserHealthProfile(
            age: age,
            dateOfBirth: birth,
            biologicalSex: profileValues.1,
            bloodType: profileValues.2,
            weightKg: profileValues.3,
            heightCm: profileValues.4,
            bodyMassIndex: profileValues.5,
            leanBodyMassKg: profileValues.6,
            bodyFatPercentage: profileValues.7,
            restingHeartRate: profileValues.8,
            vo2Max: profileValues.9,
            averageHRV: profileValues.10,
            cycleSummary: cycle?.hasData == true ? cycle : nil,
            clinicalSummary: clinical?.hasData == true ? clinical : nil
        )
    }

    private func fetchDateOfBirth() async -> Date? {
        do {
            let components = try healthStore.dateOfBirthComponents()
            return Calendar.current.date(from: components)
        } catch {
            return nil
        }
    }

    private func fetchBiologicalSex() async -> String? {
        do {
            switch try healthStore.biologicalSex().biologicalSex {
            case .female: return "Female"
            case .male: return "Male"
            case .other: return "Other"
            case .notSet: return nil
            @unknown default: return nil
            }
        } catch {
            return nil
        }
    }

    private func fetchBloodType() async -> String? {
        do {
            switch try healthStore.bloodType().bloodType {
            case .aPositive: return "A+"
            case .aNegative: return "A-"
            case .bPositive: return "B+"
            case .bNegative: return "B-"
            case .abPositive: return "AB+"
            case .abNegative: return "AB-"
            case .oPositive: return "O+"
            case .oNegative: return "O-"
            case .notSet: return nil
            @unknown default: return nil
            }
        } catch {
            return nil
        }
    }

    private func fetchMostRecentWeight() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            healthStore.execute(query)
        }
    }

    private func fetchHeight() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .height) else { return nil }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let cm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                continuation.resume(returning: cm)
            }
            healthStore.execute(query)
        }
    }

    func fetchMostRecentVO2Max() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return nil }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let vo2 = sample.quantity.doubleValue(for: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute())))
                continuation.resume(returning: vo2)
            }
            healthStore.execute(query)
        }
    }
}
