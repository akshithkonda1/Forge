import Foundation
import HealthKit

/// Coordinates HealthKit + Watch vitals upload to Forge backend.
@MainActor
final class HealthSyncCoordinator {
    static let shared = HealthSyncCoordinator()

    private let healthKit = HealthKitManager.shared
    private let repository = ForgeRepository.shared
    private let iso = ISO8601DateFormatter()

    private init() {}

    func syncAll() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let snapshot = await healthKit.fetchRecentSnapshot()
        await syncDailyMetrics(snapshot: snapshot)
        await syncRecentSleep()
        await syncRecentWorkouts()
        await syncWatchVitals()
    }

    private func syncDailyMetrics(snapshot: HealthDataSnapshot?) async {
        guard let snapshot else { return }
        let spo2 = await fetchLatestOxygenSaturation()
        do {
            try await repository.syncHealthMetrics(
                steps: snapshot.steps,
                activeCalories: snapshot.activeCalories,
                hrv: snapshot.hrv.map { Int($0.rounded()) },
                restingHR: snapshot.restingHeartRate,
                oxygenSaturation: spo2
            )
        } catch {
            print("HealthSyncCoordinator metrics failed: \(error)")
        }
    }

    private func syncRecentSleep() async {
        let sessions = await healthKit.fetchRecentSleepSessions(days: 7)
        for session in sessions {
            do {
                try await repository.syncSleepSession(session)
            } catch {
                print("HealthSyncCoordinator sleep failed: \(error)")
            }
        }
    }

    private func syncRecentWorkouts() async {
        let workouts = await healthKit.fetchRecentWorkoutLogs(days: 14)
        for workout in workouts {
            do {
                try await repository.syncWorkoutLog(workout)
            } catch {
                print("HealthSyncCoordinator workout failed: \(error)")
            }
        }
    }

    private func syncWatchVitals() async {
        guard let snapshot = ForgeWatchVitalsBridge.latest(),
              let heartRate = snapshot.heartRate,
              heartRate > 0 else { return }
        let timestamp = Date(timeIntervalSince1970: snapshot.updatedAt)
        do {
            try await repository.syncWorkoutHeartRate(samples: [(bpm: heartRate, timestamp: timestamp)])
            if let spo2 = snapshot.spO2, spo2 > 0 {
                try await repository.syncHealthMetrics(
                    steps: nil,
                    activeCalories: nil,
                    hrv: nil,
                    restingHR: nil,
                    oxygenSaturation: spo2
                )
            }
        } catch {
            print("HealthSyncCoordinator watch vitals failed: \(error)")
        }
    }

    private func fetchLatestOxygenSaturation() async -> Int? {
        await healthKit.fetchLatestOxygenSaturationPercent()
    }
}