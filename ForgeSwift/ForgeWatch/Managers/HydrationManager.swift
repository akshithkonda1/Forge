import Foundation
import HealthKit
import Observation
import ForgeCore

// MARK: - HydrationManager
//
// Water on the wrist. HydrationEngine has been in ForgeCore, written and
// tested, since before the watch app existed, and the watch referenced it
// exactly zero times — while the iPhone shipped both an interactive widget and
// an App Intent for it. The device you actually have on you when you finish a
// glass had no way to say so.
//
// Totals are read back from HealthKit rather than tallied here, so a glass
// logged on the phone counts on the wrist and vice versa. Two devices keeping
// separate counts of the same day is how someone gets told they are behind on
// water they already drank.

@MainActor
@Observable
final class HydrationManager {

    private let store = HKHealthStore()

    private(set) var consumedMilliliters: Double = 0
    private(set) var targetMilliliters: Double = HydrationEngine.minimumTargetMilliliters
    private(set) var lastLoggedAt: Date?
    /// Set when a write to Health fails. The count still moves — the drink
    /// happened — but the UI says so rather than pretending it synced.
    private(set) var lastWriteFailed = false

    private var bodyMassKilograms: Double?

    var progress: Double {
        guard targetMilliliters > 0 else { return 0 }
        return min(1, consumedMilliliters / targetMilliliters)
    }

    var status: HydrationEngine.Status {
        HydrationEngine.status(
            consumed: consumedMilliliters,
            target: targetMilliliters,
            expected: expectedByNow
        )
    }

    var remainingMilliliters: Double {
        max(0, targetMilliliters - consumedMilliliters)
    }

    /// Whole glasses left, for a label that means something at a glance.
    var remainingGlasses: Int {
        Int(HydrationEngine.glasses(fromMilliliters: remainingMilliliters).rounded())
    }

    private var expectedByNow: Double {
        HydrationEngine.expectedMilliliters(
            atHour: HydrationEngine.hourOfDay(Date()),
            target: targetMilliliters,
            wakeHour: wakeHour,
            onsetHour: onsetHour
        )
    }

    /// Wake and onset come from the wind-down plan when the predictor has
    /// learned a rhythm; the engine's own defaults otherwise. The pace line is
    /// only as good as the day it is drawn across.
    private var wakeHour: Double = 7
    private var onsetHour: Double = 23

    var guidance: String {
        HydrationEngine.guidance(
            status: status,
            remaining: remainingMilliliters,
            hoursUntilOnset: max(0, onsetHour - HydrationEngine.hourOfDay(Date()))
        )
    }

    // MARK: Refresh

    /// Recomputes the target and reads today's total back from Health.
    ///
    /// `activeCalories` raises the target — a 500 kcal session is roughly half
    /// a litre of extra need — and `cycle` applies the luteal and menstruation
    /// bonuses the engine already knows about, taken from the snapshot the
    /// iPhone syncs rather than read here, since the watch has no cycle store.
    func refresh(
        activeCalories: Double = 0,
        windDown: WindDownPlan? = nil,
        lastNight: SleepNight? = nil
    ) async {
        // The two ends of the pace line come from different places, because
        // nothing knows both: the predictor knows tonight's wind-down, and last
        // night's sleep record knows when this morning started. Either missing
        // leaves the engine's own default in place rather than a guess.
        if let onset = windDown?.windDownStart {
            onsetHour = HydrationEngine.hourOfDay(onset)
        }
        if let wake = lastNight?.end {
            wakeHour = HydrationEngine.hourOfDay(wake)
        }

        if bodyMassKilograms == nil {
            bodyMassKilograms = await ForgeHealthQueries.latestBodyMassKilograms(store: store)
        }

        let suggested = HydrationEngine.targetMilliliters(
            weightKilograms: bodyMassKilograms,
            activeCalories: activeCalories,
            cycle: cycleAdjustment()
        )
        targetMilliliters = HydrationEngine.resolvedTargetMilliliters(
            userGoal: userGoalMilliliters,
            suggested: suggested
        )

        // Anything an App Intent logged while the app was closed is written
        // now, before the total is read, so it is included rather than
        // appearing on the next refresh.
        await flushPendingLogs()
        consumedMilliliters = await ForgeHealthQueries.waterToday(store: store)
        publish()
    }

    /// The cycle phase the iPhone last synced. Read from the snapshot because
    /// the watch has no menstrual store of its own, and absent means none —
    /// never a guess.
    private func cycleAdjustment() -> HydrationEngine.CycleAdjustment {
        switch WatchSnapshotStore.load()?.cyclePhase?.lowercased() {
        case "menstruation", "menstrual", "period": return .menstruation
        case "luteal": return .luteal
        default: return .none
        }
    }

    private var userGoalMilliliters: Double? {
        let stored = defaults?.double(forKey: Keys.goal) ?? 0
        return stored > 0 ? stored : nil
    }

    // MARK: Logging

    /// Logs a drink. The count moves immediately — the glass is already drunk,
    /// and making the user wait on a HealthKit round trip to see it is the
    /// wrong trade on a wrist.
    func log(milliliters: Double) async {
        guard milliliters > 0 else { return }
        consumedMilliliters += milliliters
        lastLoggedAt = Date()
        publish()

        do {
            try await ForgeHealthQueries.saveWater(store: store, milliliters: milliliters)
            lastWriteFailed = false
        } catch {
            // Keep the drink rather than discarding it: queue it for the next
            // refresh so a denied write or a locked device does not silently
            // lose water the user really drank.
            PendingWaterLog.enqueue(milliliters)
            lastWriteFailed = true
        }
    }

    func log(preset: HydrationEngine.Preset) async {
        await log(milliliters: preset.milliliters)
    }

    private func flushPendingLogs() async {
        let pending = PendingWaterLog.drain()
        guard pending > 0 else { return }
        do {
            try await ForgeHealthQueries.saveWater(store: store, milliliters: pending)
            lastWriteFailed = false
        } catch {
            PendingWaterLog.enqueue(pending)  // still ours; try again next time
            lastWriteFailed = true
        }
    }

    // MARK: Persistence

    private let defaults = UserDefaults(suiteName: WatchSnapshotStore.appGroupID)
    private enum Keys {
        static let goal = "forge.hydration.goalMl"
    }

    private func publish() {
        WatchSnapshotStore.update { snapshot in
            snapshot.hydrationMilliliters = consumedMilliliters
            snapshot.hydrationTargetMilliliters = targetMilliliters
        }
    }
}
