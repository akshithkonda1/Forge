import Foundation
import HealthKit

@MainActor
final class LiveHeartRateMonitor: ObservableObject {
    @Published private(set) var currentBPM: Int?
    @Published private(set) var isLive = false

    private let healthStore = HKHealthStore()
    private var anchoredQuery: HKAnchoredObjectQuery?
    private var pendingSamples: [(bpm: Int, timestamp: Date)] = []

    func start() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }

        do {
            try await HealthKitManager.shared.requestAuthorization()
        } catch {
            return
        }

        stop()

        let startDate = Date().addingTimeInterval(-120)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.consume(samples: samples)
            }
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.consume(samples: samples)
            }
        }

        anchoredQuery = query
        healthStore.execute(query)
    }

    func stop() {
        if let anchoredQuery {
            healthStore.stop(anchoredQuery)
        }
        anchoredQuery = nil
        isLive = false
    }

    func drainPendingSamples() -> [(bpm: Int, timestamp: Date)] {
        let samples = pendingSamples
        pendingSamples.removeAll()
        return samples
    }

    private func consume(samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
            return
        }

        for sample in quantitySamples {
            let bpm = Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            guard bpm > 0 else { continue }
            currentBPM = bpm
            isLive = true
            pendingSamples.append((bpm: bpm, timestamp: sample.endDate))
        }
    }
}