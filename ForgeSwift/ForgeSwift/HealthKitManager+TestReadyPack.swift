import Foundation
import HealthKit
import ForgeCore

extension HealthKitManager {

    var packMetadata: [String: Any] {
        ForgeTestHealthPackWriter.packMetadata
    }

    /// Delete last run's tagged samples, write this pack into the simulator
    /// Health store, so the normal HealthKit fetch path is what ARIA sees.
    /// The rewrite runs off the main actor so Home stays interactive.
    func replaceTestReadyPack(_ pack: FakeHealthPack) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            let message = HealthKitError.notAvailable.errorDescription
                ?? "Health data is not available on this device."
            lastPackWriteError = message
            throw HealthKitError.notAvailable
        }
        isReplacingTestReadyPack = true
        defer { isReplacingTestReadyPack = false }
        nonisolated(unsafe) let store = healthStore
        do {
            let cycleError = try await Task.detached(priority: .utility) {
                try await ForgeTestHealthPackWriter.replace(pack: pack, store: store)
            }.value
            lastPackWriteError = cycleError
            installedTestReadySeed = pack.seed
        } catch {
            lastPackWriteError = LifeIngestError.explain(
                error,
                doing: "Couldn't write the Test-Ready Health pack into Apple Health"
            )
            throw error
        }
    }

    func deleteTestReadyPackSamples() async throws {
        nonisolated(unsafe) let store = healthStore
        try await Task.detached(priority: .utility) {
            try await ForgeTestHealthPackWriter.deleteSamples(store: store)
        }.value
    }
}

/// HealthKit Test-Ready rewrite. Not MainActor — serial workout builders must
/// not freeze Home for minutes on Simulator launch.
enum ForgeTestHealthPackWriter {
    static var packMetadata: [String: Any] {
        [
            HealthKitManager.testReadyPackMetadataKey: "1",
            HKMetadataKeyWasUserEntered: true,
        ]
    }

    /// Returns a cycle-overlay warning, or nil when the pack is healthy.
    static func replace(pack: FakeHealthPack, store: HKHealthStore) async throws -> String? {
        try await deleteSamples(store: store)
        do {
            try await saveQuantityAndSleep(from: pack, store: store)
        } catch {
            print("Test-ready vitals overlay skipped: \(error.localizedDescription)")
        }
        do {
            try await saveWorkouts(from: pack, store: store)
        } catch {
            print("Test-ready workouts overlay skipped: \(error.localizedDescription)")
        }
        do {
            try await saveCycle(from: pack, store: store)
            return nil
        } catch {
            return LifeIngestError.explain(
                error,
                doing: "Test-Ready cycle overlay wasn't written"
            )
        }
    }

    static func deleteSamples(store: HKHealthStore) async throws {
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
            withMetadataKey: HealthKitManager.testReadyPackMetadataKey,
            allowedValues: ["1"]
        )
        for type in types {
            let samples: [HKSample]
            do {
                samples = try await querySamples(type: type, predicate: predicate, store: store)
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
                try await store.delete(samples)
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

    private static func saveQuantityAndSleep(from pack: FakeHealthPack, store: HKHealthStore) async throws {
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
                try await store.save(Array(samples[index..<next]))
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

    private static func saveWorkouts(from pack: FakeHealthPack, store: HKHealthStore) async throws {
        let calendar = Calendar.current
        for day in pack.days {
            guard let session = day.workout else { continue }
            let start = calendar.date(bySettingHour: 17, minute: 15, second: 0, of: day.dayStart) ?? day.dayStart
            let end = start.addingTimeInterval(TimeInterval(session.durationMinutes * 60))
            guard end <= Date() else { continue }
            let config = HKWorkoutConfiguration()
            config.activityType = session.type.hkActivityType
            config.locationType = .indoor
            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            var meta = packMetadata
            meta[HealthKitManager.testReadySessionNameKey] = session.name
            meta[HealthKitManager.testReadyIntensityKey] = session.intensity
            meta[HealthKitManager.testReadyVolumeKey] = "\(session.volume)"
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

    private static func saveCycle(from pack: FakeHealthPack, store: HKHealthStore) async throws {
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
                try await store.save(Array(samples[index..<next]))
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

    private static func menstrualFlowValue(_ raw: String) -> HKCategoryValueVaginalBleeding? {
        switch raw {
        case "spotting", "light": return .light
        case "medium": return .medium
        case "heavy": return .heavy
        default: return nil
        }
    }

    private static func ovulationValue(_ raw: String) -> HKCategoryValueOvulationTestResult? {
        switch raw {
        case "negative": return .negative
        case "lhSurge": return .luteinizingHormoneSurge
        case "estrogenSurge": return .estrogenSurge
        case "positive": return .luteinizingHormoneSurge
        case "indeterminate": return .indeterminate
        default: return nil
        }
    }

    private static func mucusValue(_ raw: String) -> HKCategoryValueCervicalMucusQuality? {
        switch raw {
        case "dry": return .dry
        case "sticky": return .sticky
        case "creamy": return .creamy
        case "watery": return .watery
        case "eggWhite": return .eggWhite
        default: return nil
        }
    }

    private static func sleepValue(_ stage: SleepStage) -> HKCategoryValueSleepAnalysis {
        switch stage {
        case .deep: return .asleepDeep
        case .rem: return .asleepREM
        case .core: return .asleepCore
        case .awake: return .awake
        }
    }

    private static func querySamples(
        type: HKSampleType,
        predicate: NSPredicate,
        store: HKHealthStore
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let once = ClinicalQueryResumeOnce<Result<[HKSample], Error>>()
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    once.finish(Result<[HKSample], Error>.failure(error)) {
                        continuation.resume(with: $0)
                    }
                } else {
                    once.finish(.success(samples ?? [])) {
                        continuation.resume(with: $0)
                    }
                }
            }
            store.execute(query)
        }
    }
}
