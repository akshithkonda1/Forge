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
            let message = HealthKitError.notAvailable.errorDescription
                ?? "Health data is not available on this device."
            lastPackWriteError = message
            throw HealthKitError.notAvailable
        }
        if installedTestReadySeed == pack.seed {
            return
        }
        if isReplacingTestReadyPack {
            return
        }
        isReplacingTestReadyPack = true
        defer { isReplacingTestReadyPack = false }
        do {
            try await deleteTestReadyPackSamples()
            try await saveQuantityAndSleep(from: pack)
            try await saveWorkouts(from: pack)
        } catch {
            let message = LifeIngestError.explain(
                error,
                doing: "Couldn't write the Test-Ready Health pack into Apple Health"
            )
            lastPackWriteError = message
            throw HealthKitError.saveFailedReason(message)
        }
        do {
            try await saveCycle(from: pack)
            lastPackWriteError = nil
        } catch {
            lastPackWriteError = LifeIngestError.explain(
                error,
                doing: "Test-Ready cycle overlay wasn't written"
            )
        }
        installedTestReadySeed = pack.seed
    }

    func deleteTestReadyPackSamples() async throws {
        let types: [HKSampleType] = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.dietaryWater),
            HKQuantityType(.bodyTemperature),
            HKWorkoutType.workoutType(),
            HKCategoryType(.menstrualFlow),
            HKQuantityType(.basalBodyTemperature),
            HKCategoryType(.ovulationTestResult),
            HKCategoryType(.cervicalMucusQuality),
        ]
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: Self.testReadyPackMetadataKey,
            allowedValues: ["1"]
        )
        for type in types {
            let samples: [HKSample]
            do {
                samples = try await querySamples(type: type, predicate: predicate)
            } catch {
                throw HealthKitError.saveFailedReason(
                    LifeIngestError.explain(
                        error,
                        doing: "Couldn't read previous Test-Ready \(type.identifier) samples"
                    )
                )
            }
            guard !samples.isEmpty else { continue }
            do {
                try await healthStore.delete(samples)
            } catch {
                throw HealthKitError.saveFailedReason(
                    LifeIngestError.explain(
                        error,
                        doing: "Couldn't delete previous Test-Ready \(type.identifier) samples"
                    )
                )
            }
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
        let tempType = HKQuantityType(.bodyTemperature)
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

            var tempAt = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: day.dayStart) ?? day.dayStart
            if isToday, tempAt > now {
                tempAt = now.addingTimeInterval(-120)
            }
            samples.append(
                HKQuantitySample(
                    type: tempType,
                    quantity: HKQuantity(unit: .degreeFahrenheit(), doubleValue: day.bodyTemperatureF),
                    start: tempAt,
                    end: tempAt,
                    metadata: packMetadata
                )
            )
        }

        var index = samples.startIndex
        while index < samples.endIndex {
            let next = samples.index(index, offsetBy: 100, limitedBy: samples.endIndex) ?? samples.endIndex
            do {
                try await healthStore.save(Array(samples[index..<next]))
            } catch {
                throw HealthKitError.saveFailedReason(
                    LifeIngestError.explain(
                        error,
                        doing: "Couldn't save Test-Ready quantity and sleep samples"
                    )
                )
            }
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
            var meta = packMetadata
            meta[Self.testReadySessionNameKey] = session.name
            meta[Self.testReadyIntensityKey] = session.intensity
            meta[Self.testReadyVolumeKey] = "\(session.volume)"
            meta[HKMetadataKeyWorkoutBrandName] = session.name
            do {
                try await builder.beginCollection(at: start)
                try await builder.addMetadata(meta)
                try await builder.endCollection(at: end)
                _ = try await builder.finishWorkout()
            } catch {
                throw HealthKitError.saveFailedReason(
                    LifeIngestError.explain(
                        error,
                        doing: "Couldn't save Test-Ready workout \(session.name)"
                    )
                )
            }
        }
    }

    private func saveCycle(from pack: FakeHealthPack) async throws {
        var samples: [HKSample] = []
        let flowType = HKCategoryType(.menstrualFlow)
        let bbtType = HKQuantityType(.basalBodyTemperature)
        let opkType = HKCategoryType(.ovulationTestResult)
        let mucusType = HKCategoryType(.cervicalMucusQuality)
        let calendar = Calendar.current

        for day in pack.days {
            guard let cycle = day.cycle else { continue }
            let dayStart = calendar.startOfDay(for: day.dayStart)
            let end = calendar.date(byAdding: .day, value: 1, to: dayStart)?
                .addingTimeInterval(-1) ?? dayStart

            if cycle.isBleeding, let flowValue = menstrualFlowValue(cycle.flow) {
                var meta = packMetadata
                meta[HKMetadataKeyMenstrualCycleStart] = cycle.isCycleStart
                samples.append(
                    HKCategorySample(
                        type: flowType,
                        value: flowValue.rawValue,
                        start: dayStart,
                        end: end,
                        metadata: meta
                    )
                )
            }
            if let celsius = cycle.bbtCelsius {
                samples.append(
                    HKQuantitySample(
                        type: bbtType,
                        quantity: HKQuantity(unit: .degreeCelsius(), doubleValue: celsius),
                        start: dayStart,
                        end: dayStart,
                        metadata: packMetadata
                    )
                )
            }
            if let opk = cycle.ovulationTest, let value = ovulationValue(opk) {
                samples.append(
                    HKCategorySample(
                        type: opkType,
                        value: value.rawValue,
                        start: dayStart,
                        end: end,
                        metadata: packMetadata
                    )
                )
            }
            if let mucus = cycle.cervicalMucus, let value = mucusValue(mucus) {
                samples.append(
                    HKCategorySample(
                        type: mucusType,
                        value: value.rawValue,
                        start: dayStart,
                        end: end,
                        metadata: packMetadata
                    )
                )
            }
        }

        var index = samples.startIndex
        while index < samples.endIndex {
            let next = samples.index(index, offsetBy: 100, limitedBy: samples.endIndex) ?? samples.endIndex
            do {
                try await healthStore.save(Array(samples[index..<next]))
            } catch {
                throw HealthKitError.saveFailedReason(
                    LifeIngestError.explain(
                        error,
                        doing: "Couldn't save Test-Ready cycle overlay samples"
                    )
                )
            }
            index = next
        }
    }

    private func menstrualFlowValue(_ raw: String) -> HKCategoryValueVaginalBleeding? {
        switch raw {
        case "spotting", "light": return .light
        case "medium": return .medium
        case "heavy": return .heavy
        default: return nil
        }
    }

    private func ovulationValue(_ raw: String) -> HKCategoryValueOvulationTestResult? {
        switch raw {
        case "negative": return .negative
        case "lhSurge": return .luteinizingHormoneSurge
        case "estrogenSurge": return .estrogenSurge
        case "positive": return .luteinizingHormoneSurge
        case "indeterminate": return .indeterminate
        default: return nil
        }
    }

    private func mucusValue(_ raw: String) -> HKCategoryValueCervicalMucusQuality? {
        switch raw {
        case "dry": return .dry
        case "sticky": return .sticky
        case "creamy": return .creamy
        case "watery": return .watery
        case "eggWhite": return .eggWhite
        default: return nil
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

    private func querySamples(type: HKSampleType, predicate: NSPredicate) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let once = SampleQueryResumeOnce()
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    once.finish(.failure(error), continuation)
                } else {
                    once.finish(.success(samples ?? []), continuation)
                }
            }
            healthStore.execute(query)
        }
    }
}

/// HealthKit can invoke a query handler more than once. Resume exactly once
/// so a Test-Ready rewrite cannot crash on that path.
private final class SampleQueryResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func finish(
        _ result: Result<[HKSample], Error>,
        _ continuation: CheckedContinuation<[HKSample], Error>
    ) {
        lock.lock()
        if done {
            lock.unlock()
            return
        }
        done = true
        lock.unlock()
        continuation.resume(with: result)
    }
}
