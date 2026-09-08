import AppIntents
import ForgeCore

/// Interactive widget action: enqueue a glass, open Forge, and write it
/// to Apple Health from the app process that holds the entitlement.
struct LogWaterGlassIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a glass of water"
    static var description = IntentDescription("Adds one glass to today's hydration and opens Forge so Apple Health stays in sync.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let ml = HydrationEngine.glassMilliliters
        PendingWaterLog.enqueue(ml)
        HomeWidgetSnapshotStore.update { snap in
            snap.hydrationMl += ml
        }
        return .result()
    }
}
