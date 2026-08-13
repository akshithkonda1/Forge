import AppIntents
import ForgeCore

/// Interactive widget action: enqueue a glass so the next app refresh writes
/// it to Apple Health. The snapshot is bumped immediately so the widget
/// does not wait for HealthKit.
struct LogWaterGlassIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a glass of water"
    static var description = IntentDescription("Adds one glass to today's hydration. Forge writes it to Apple Health the next time it opens.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let ml = HydrationEngine.glassMilliliters
        PendingWaterLog.enqueue(ml)
        HomeWidgetSnapshotStore.update { snap in
            snap.hydrationMl += ml
        }
        return .result()
    }
}
