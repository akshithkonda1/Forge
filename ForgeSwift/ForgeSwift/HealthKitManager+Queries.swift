import Foundation
import HealthKit
import ForgeCore

extension HealthKitManager {

    func fetchCumulativeQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    func fetchAverageQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                guard let average = statistics?.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: average.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    func fetchMostRecentQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
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
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    func fetchCategorySamples(_ identifier: HKCategoryTypeIdentifier, predicate: NSPredicate?, limit: Int) async -> [HKCategorySample] {
        let type = HKCategoryType(identifier)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    func fetchMostRecentCategoryValue(_ identifier: HKCategoryTypeIdentifier) async -> String? {
        let samples = await fetchCategorySamples(identifier, predicate: nil, limit: 1)
        guard let value = samples.first?.value else { return nil }
        return categoryLabel(identifier: identifier, rawValue: value)
    }

    func categoryLabel(identifier: HKCategoryTypeIdentifier, rawValue: Int) -> String? {
        switch identifier {
        case .menstrualFlow:
            return menstrualFlowLabel(rawValue: rawValue)
        case .ovulationTestResult:
            guard let value = HKCategoryValueOvulationTestResult(rawValue: rawValue) else { return nil }
            switch value {
            case .negative: return "Negative"
            case .luteinizingHormoneSurge: return "LH Surge"
            case .indeterminate: return "Indeterminate"
            case .estrogenSurge: return "Estrogen Surge"
            case .positive: return "Positive"
            @unknown default: return nil
            }
        case .pregnancyTestResult:
            guard let value = HKCategoryValuePregnancyTestResult(rawValue: rawValue) else { return nil }
            switch value {
            case .negative: return "Negative"
            case .positive: return "Positive"
            case .indeterminate: return "Indeterminate"
            @unknown default: return nil
            }
        case .progesteroneTestResult:
            guard let value = HKCategoryValueProgesteroneTestResult(rawValue: rawValue) else { return nil }
            switch value {
            case .negative: return "Negative"
            case .positive: return "Positive"
            case .indeterminate: return "Indeterminate"
            @unknown default: return nil
            }
        default:
            return nil
        }
    }

    func menstrualFlowLabel(rawValue: Int) -> String? {
        guard let value = HKCategoryValueMenstrualFlow(rawValue: rawValue) else { return nil }
        switch value {
        case .unspecified: return "Unspecified"
        case .none: return "None"
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        @unknown default: return nil
        }
    }

    func fetchQuantitySamples(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate?,
        limit: Int
    ) async -> [(date: Date, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let mapped = (samples as? [HKQuantitySample] ?? []).map {
                    (date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: mapped)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Detailed Profile Data
}
