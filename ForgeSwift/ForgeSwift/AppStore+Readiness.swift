import Foundation
import Combine
import UIKit
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

extension AppStore {

    func refreshDailyData() async {
        let hk = HealthKitManager.shared
        let authorized = await hk.checkAuthorizationStatus()
        healthKitLive = authorized

        if authorized {
            await hk.refreshHydration()
        }
        if authorized, let snapshot = await hk.fetchRecentSnapshot() {
            updateMetrics(
                steps: snapshot.steps,
                activeCalories: snapshot.activeCalories,
                hrv: snapshot.hrv.map { Int($0) },
                restingHR: snapshot.restingHeartRate,
                deepSleep: nil,
                totalSleep: snapshot.sleepHours.map { Int($0 * 60) }
            )
            if let weight = userProfile.weight {
                userProfile.weight = weight
            }
        }

        let samples = BiometricsObserveService.shared.samplesFromStore(self)
        _ = await BiometricsObserveService.shared.observe(store: self, samples: samples)

        // Menstrual cycle: auto-enable + quiet weekly HealthKit sync (or immediate if broken).
        MenstrualHealthStore.shared.enableForFemaleProfileIfNeeded(gender: userProfile.gender)
        if let sex = userProfile.biologicalSex {
            MenstrualHealthStore.shared.enableForBiologicalSexIfNeeded(sex)
        }
        if MenstrualHealthStore.shared.settings.enabled {
            await MenstrualHealthStore.shared.quietWeeklyHealthKitSync(force: !authorized)
            MenstrualHealthStore.shared.refresh(from: self)
        }

        if authorized {
            let nights = await HealthKitSleepService.shared.fetchRecentSleepData(days: 14)
            mergeSleepDataLocally(nights)
        }

        lastMetricsRefresh = Date()
        rebuildTodayPlanFromLife()
        recomputeStreak()
        await flushPendingWidgetWater()
        publishHomeWidgets()
        objectWillChange.send()
    }

    /// Sleep, HRV, or any Health write that means today's number is theirs — not a blank launch.
    var hasMeaningfulLifeSignal: Bool {
        dailyMetrics.totalSleep > 0
            || dailyMetrics.hrv > 0
            || sleepData.contains(where: { $0.totalHours > 0 })
            || (healthKitLive && (dailyMetrics.steps > 0 || dailyMetrics.activeCalories > 0))
    }

    /// Rebuild today's session from readiness, cycle, equipment, constraints, theme.
    /// Skipped while a session is in progress so we don't yank the floor out.
    func rebuildTodayPlanFromLife() {
        guard !isWorkoutActive else { return }
        let plan = AriaPlanEngine.evaluate(
            input: "Build today's session from my sleep, readiness, cycle, equipment, and the time I actually have.",
            context: makeTrainerContext()
        )
        var workout = plan.workoutPlan
        let dayKey: String = {
            let f = DateFormatter()
            f.calendar = Calendar.current
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        workout.id = "life-\(dayKey)-\(workout.name)"
        todayWorkout = workout
    }

    /// Write the session from *this* moment's life, then open Train.
    /// Recovery and "build" both land here — not in chat.
    func startLifeShapedSession() {
        if !isWorkoutActive {
            rebuildTodayPlanFromLife()
            startWorkout()
        }
        activeTab = .workout
    }

    /// Update user metrics (typically from HealthKit integration)
    func updateMetrics(
        steps: Int? = nil,
        activeCalories: Int? = nil,
        hrv: Int? = nil,
        restingHR: Int? = nil,
        deepSleep: Int? = nil,
        totalSleep: Int? = nil
    ) {
        if let steps = steps { dailyMetrics.steps = steps }
        if let activeCalories = activeCalories { dailyMetrics.activeCalories = activeCalories }
        if let hrv = hrv { dailyMetrics.hrv = hrv }
        if let restingHR = restingHR { dailyMetrics.restingHR = restingHR }
        if let deepSleep = deepSleep { dailyMetrics.deepSleep = deepSleep }
        if let totalSleep = totalSleep { dailyMetrics.totalSleep = totalSleep }
        
        // Recalculate readiness based on new metrics
        recalculateReadiness()
    }

    /// Recalculate readiness score based on current metrics
    private func recalculateReadiness() {
        // Simplified readiness calculation
        // In production, this would use more sophisticated algorithms
        
        let sleepScore = calculateSleepScore()
        let hrvScore = calculateHRVScore()
        let restingHRScore = calculateRestingHRScore()
        
        readiness.overall = (sleepScore + hrvScore + restingHRScore) / 3
        readiness.sleepQuality = sleepScore
        readiness.recoveryScore = (hrvScore + restingHRScore) / 2
    }

    private func calculateSleepScore() -> Int {
        let totalHours = Double(dailyMetrics.totalSleep) / 60
        let deepMinutes = dailyMetrics.deepSleep
        
        var score = 0
        
        // Total sleep score (0-50 points)
        if totalHours >= 7.5 {
            score += 50
        } else if totalHours >= 7 {
            score += 40
        } else if totalHours >= 6 {
            score += 25
        } else {
            score += 10
        }
        
        // Deep sleep score (0-50 points)
        if deepMinutes >= 90 {
            score += 50
        } else if deepMinutes >= 70 {
            score += 40
        } else if deepMinutes >= 50 {
            score += 25
        } else {
            score += 10
        }
        
        return min(score, 100)
    }

    private func calculateHRVScore() -> Int {
        // HRV scoring (typical range: 20-100ms)
        let hrv = dailyMetrics.hrv
        
        if hrv >= 60 {
            return 90
        } else if hrv >= 50 {
            return 80
        } else if hrv >= 40 {
            return 65
        } else if hrv >= 30 {
            return 50
        } else {
            return 30
        }
    }

    private func calculateRestingHRScore() -> Int {
        // Resting HR scoring (lower is better for athletes)
        let hr = dailyMetrics.restingHR
        
        if hr <= 55 {
            return 95
        } else if hr <= 60 {
            return 85
        } else if hr <= 65 {
            return 75
        } else if hr <= 70 {
            return 60
        } else {
            return 40
        }
    }
    
    // MARK: - Profile Management

    func connectHealthDevice(_ id: String) {
        var ids = HealthDeviceCatalog.migrateStoredIDs(userProfile.connectedDevices)
        if !ids.contains(id) { ids.append(id) }
        userProfile.connectedDevices = ids
    }

    func disconnectHealthDevice(_ id: String) {
        var ids = HealthDeviceCatalog.migrateStoredIDs(userProfile.connectedDevices)
        ids.removeAll { $0 == id }
        userProfile.connectedDevices = ids
    }

    func mergeSleepDataLocally(_ local: [SleepData]) {
        guard !local.isEmpty else { return }
        var merged = Dictionary(sleepData.map { ($0.date, $0) }, uniquingKeysWith: { _, new in new })
        for night in local {
            merged[night.date] = night
        }
        sleepData = merged.values.sorted { $0.date > $1.date }
        if let latest = sleepData.first {
            dailyMetrics.totalSleep = Int(latest.totalHours * 60)
            dailyMetrics.deepSleep = latest.deepMinutes
            recalculateReadiness()
        }
    }

    func addSleepData(_ sleep: SleepData) {
        sleepData.insert(sleep, at: 0)
        
        // Update daily metrics
        dailyMetrics.totalSleep = Int(sleep.totalHours * 60)
        dailyMetrics.deepSleep = sleep.deepMinutes
        
        // Recalculate readiness
        recalculateReadiness()
    }
    
    // MARK: - Personal Records
}
