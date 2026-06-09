import Foundation
import HealthKit

@MainActor
final class LiveHeartRateMonitor: ObservableObject {
    @Published private(set) var currentBPM: Int?
    @Published private(set) var currentSpO2: Int?
    @Published private(set) var isLive = false
    @Published private(set) var isSpO2Live = false
    @Published private(set) var lastSampleAt: Date?

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var spO2Query: HKAnchoredObjectQuery?
    private var pendingSamples: [(bpm: Int, timestamp: Date)] = []

    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        do {
            try await HealthKitManager.shared.requestAuthorization()
        } catch {
            return
        }

        stop()
        startHeartRateStream()
        startSpO2Stream()
    }

    func stop() {
        if let heartRateQuery {
            healthStore.stop(heartRateQuery)
        }
        if let spO2Query {
            healthStore.stop(spO2Query)
        }
        heartRateQuery = nil
        spO2Query = nil
        isLive = false
        isSpO2Live = false
    }

    func drainPendingSamples() -> [(bpm: Int, timestamp: Date)] {
        let samples = pendingSamples
        pendingSamples.removeAll()
        return samples
    }

    private func startHeartRateStream() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let startDate = Date().addingTimeInterval(-120)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.consumeHeartRate(samples: samples)
            }
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.consumeHeartRate(samples: samples)
            }
        }

        heartRateQuery = query
        healthStore.execute(query)
    }

    private func startSpO2Stream() {
        guard let spO2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return }

        let startDate = Date().addingTimeInterval(-600)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)

        let query = HKAnchoredObjectQuery(
            type: spO2Type,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.consumeSpO2(samples: samples)
            }
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.consumeSpO2(samples: samples)
            }
        }

        spO2Query = query
        healthStore.execute(query)
    }

    private func consumeHeartRate(samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
            return
        }

        for sample in quantitySamples {
            let bpm = Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            guard bpm > 0 else { continue }
            currentBPM = bpm
            isLive = true
            lastSampleAt = sample.endDate
            pendingSamples.append((bpm: bpm, timestamp: sample.endDate))
        }
    }

    private func consumeSpO2(samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
            return
        }

        for sample in quantitySamples {
            let fraction = sample.quantity.doubleValue(for: HKUnit.percent())
            let percent = Int((fraction * 100).rounded())
            guard percent > 0, percent <= 100 else { continue }
            currentSpO2 = percent
            isSpO2Live = true
            lastSampleAt = sample.endDate
        }
    }
}