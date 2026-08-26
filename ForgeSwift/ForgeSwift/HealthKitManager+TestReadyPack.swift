import Foundation
import HealthKit
import ForgeCore

extension HealthKitManager {

    var packMetadata: [String: Any] {
        [
            Self.testReadyPackMetadataKey: "1",
            HKMetadataKeyWasUserEntered: true,
        ]
    }

    /// Delete last run's tagged samples, write this pack into the simulator
    /// Health store, so the normal HealthKit fetch path is what ARIA sees.
    func replaceTestReadyPack(_ pack: FakeHealthPack) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        try await deleteTestReadyPackSamples()
        try await saveQuantityAndSleep(from: pack)
        try await saveWorkouts(from: pack)
    }

    func deleteTestReadyPackSamples() async throws {
        let types: [HKSampleType] = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.dietaryWater),
            HKWorkoutType.workoutType(),
        ]
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: Self.testReadyPackMetadataKey,
            allowedValues: ["1"]
        )
        for type in types {
            let samples = await querySamples(type: type, predicate: predicate)
            guard !samples.isEmpty else { continue }
            try await healthStore.delete(samples)
        }
    }

    // MARK: - Write

    private func saveQuantityAndSleep(from pack: FakeHealthPack) async throws {
        var samples: [HKSample] = []
        let calendar = Calendar.current
        let sleepType = HKCategoryType(.sleepAnalysis)
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let rhrType = HKQuantityType(.restingHeartRate)
        let stepType = HKQuantityType(.stepCount)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let waterType = HKQuantityType(.dietaryWater)
        let milliSeconds = HKUnit.secondUnit(with: .milli)
        let bpm = HKUnit.count().unitDivided(by: .minute())

        let now = Date()
        for day in pack.days {
            let isToday = calendar.isDateInToday(day.dayStart)
            func stamp(_ date: Date) -> Date {
                isToday ? min(date, now) : date
            }
            for segment in day.night.segments {
                let start = stamp(segment.start)
                let end = stamp(segment.end)
                guard end > start else { continue }
                samples.append(
                    HKCategorySample(
                        type: sleepType,
                        value: sleepValue(segment.stage).rawValue,
                        start: start,
                        end: end,
                        metadata: packMetadata
                    )
                )
            }
            if let onset = day.night.start, let wake = day.night.end {
                let start = stamp(onset)
                let end = stamp(wake)
                if end > start {
                    samples.append(
                        HKCategorySample(
                            type: sleepType,
                            value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                            start: start,
                            end: end,
                            metadata: packMetadata
                        )
                    )
                }
            }

            let hrvEnd = isToday ? now : stamp(day.night.end ?? day.dayStart.addingTimeInterval(7 * 3600)).addingTimeInterval(60)
            let hrvStart = hrvEnd.addingTimeInterval(-60)
            if hrvEnd > hrvStart {
                samples.append(
                    HKQuantitySample(
                        type: hrvType,
                        quantity: HKQuantity(unit: milliSeconds, doubleValue: Double(day.hrvMs)),
                        start: hrvStart,
                        end: hrvEnd,
                        metadata: packMetadata
                    )
                )
                samples.append(
                    HKQuantitySample(
                        type: rhrType,
                        quantity: HKQuantity(unit: bpm, doubleValue: Double(day.restingHR)),
                        start: hrvStart,
                        end: hrvEnd,
                        metadata: packMetadata
                    )
                )
            }

            var walkStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day.dayStart) ?? day.dayStart
            var walkEnd = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day.dayStart) ?? walkStart.addingTimeInterval(8 * 3600)
            if isToday {
                walkEnd = min(walkEnd, now)
                if walkStart >= walkEnd {
                    walkEnd = now
                    walkStart = now.addingTimeInterval(-60)
                }
            }
            if walkEnd > walkStart {
                samples.append(
                    HKQuantitySample(
                        type: stepType,
                        quantity: HKQuantity(unit: .count(), doubleValue: Double(day.steps)),
                        start: walkStart,
                        end: walkEnd,
                        metadata: packMetadata
                    )
                )
                samples.append(
                    HKQuantitySample(
                        type: energyType,
                        quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(day.activeCalories)),
                        start: walkStart,
                        end: walkEnd,
                        metadata: packMetadata
                    )
                )
            }

            var drinkAt = calendar.date(bySettingHour: 12, minute: 30, second: 0, of: day.dayStart) ?? day.dayStart
            if isToday, drinkAt > now {
                drinkAt = now.addingTimeInterval(-30)
            }
            samples.append(
                HKQuantitySample(
                    type: waterType,
                    quantity: HKQuantity(unit: .liter(), doubleValue: day.hydrationMl / 1_000),
                    start: drinkAt,
                    end: drinkAt.addingTimeInterval(30),
                    metadata: packMetadata
                )
            )
        }

        var index = samples.startIndex
        while index < samples.endIndex {
            let next = samples.index(index, offsetBy: 100, limitedBy: samples.endIndex) ?? samples.endIndex
            try await healthStore.save(Array(samples[index..<next]))
            index = next
        }
    }

    private func saveWorkouts(from pack: FakeHealthPack) async throws {
        let calendar = Calendar.current
        for day in pack.days {
            guard let session = day.workout else { continue }
            let start = calendar.date(bySettingHour: 17, minute: 15, second: 0, of: day.dayStart) ?? day.dayStart
            let end = start.addingTimeInterval(TimeInterval(session.durationMinutes * 60))
            guard end <= Date() else { continue }
            let config = HKWorkoutConfiguration()
            config.activityType = session.type.hkActivityType
            config.locationType = .indoor
            let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
            try await builder.beginCollection(at: start)
            var meta = packMetadata
            meta[Self.testReadySessionNameKey] = session.name
            meta[Self.testReadyIntensityKey] = session.intensity
            meta[Self.testReadyVolumeKey] = "\(session.volume)"
            meta[HKMetadataKeyWorkoutBrandName] = session.name
            try await builder.addMetadata(meta)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        }
    }

    private func sleepValue(_ stage: SleepStage) -> HKCategoryValueSleepAnalysis {
        switch stage {
        case .deep: return .asleepDeep
        case .rem: return .asleepREM
        case .core: return .asleepCore
        case .awake: return .awake
        }
    }

    private func querySamples(type: HKSampleType, predicate: NSPredicate) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            healthStore.execute(query)
        }
    }
}
