import Foundation
import ForgeCore

// Local testing and the Dummy both build their Swarm snapshot here. It lived
// in AriaDummyTurn.swift, so compiling the Dummy out would have taken
// LocalTestingOrchestrator's snapshot with it.
extension AriaSwarmSnapshot {
    /// Local testing / Dummy snapshot from the on-device ledger.
    @MainActor
    static func from(store: AppStore) -> AriaSwarmSnapshot {
        let night = store.sleepData.first
        let sleepHours = night?.totalHours ?? (
            store.dailyMetrics.totalSleep > 0 ? Double(store.dailyMetrics.totalSleep) / 60.0 : nil
        )
        let hrv = store.dailyMetrics.hrv > 0 ? Double(store.dailyMetrics.hrv) : nil
        var samples: [AriaSwarmSample] = []
        if sleepHours != nil {
            samples.append(AriaSwarmSample(type: "sleep", source: "oura"))
        }
        if hrv != nil {
            samples.append(AriaSwarmSample(type: "hrv", source: "whoop"))
        }
        if store.dailyMetrics.steps > 0 {
            samples.append(AriaSwarmSample(type: "steps", source: "apple-watch"))
        }
        return AriaSwarmSnapshot(
            sleepHours: sleepHours,
            hrvMs: hrv,
            readiness: store.readiness.overall > 0 ? store.readiness.overall : nil,
            workoutLogged: store.todayWorkout != nil,
            daysSinceWorkout: store.todayWorkout != nil ? 0 : nil,
            trainingStreak: store.currentStreak,
            samples: samples,
            connected: store.metricSources
        )
    }
}
