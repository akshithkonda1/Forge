import AppIntents
import Foundation
import ForgeCore

// MARK: - App Intents
//
// The watch app had none, which meant Forge could only ever be reached by
// finding its icon and tapping it. Intents are what make a watch app
// addressable: Siri, the Shortcuts app, an automation, a complication's
// interactive button, and — the one that matters most on a wrist — the Action
// Button on Apple Watch Ultra, which can be bound to any shortcut.
//
// Two shapes here, and the difference is not cosmetic:
//
//   Logging water needs no UI. It runs in the background, writes, and the
//   count is right the next time anything reads it. `openAppWhenRun = false`.
//
//   Starting a workout or a practice cannot run headless. Both need an
//   HKWorkoutSession, which belongs to the app process and dies with it, so
//   these open the app and hand it a route. Pretending otherwise would give the
//   user a "Started!" confirmation for a session that does not exist.

// ------------------------------------------------------------
// MARK: Log water
// ------------------------------------------------------------

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log water"
    static var description = IntentDescription(
        "Adds a drink to today's hydration and writes it to Apple Health."
    )
    /// Runs without bringing the app forward — the whole point of logging a
    /// glass from the Action Button while holding the glass.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount", default: .glass)
    var size: WaterSize

    static var parameterSummary: some ParameterSummary {
        Summary("Log a \(\.$size) of water")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let milliliters = size.milliliters

        // Queued rather than written here. A HealthKit write from an intent
        // process can be denied while the device is locked, and the failure
        // would be invisible — the user would be told it logged. The app
        // drains this on its next refresh, and the snapshot moves now so
        // anything reading it is already correct.
        PendingWaterLog.enqueue(milliliters)
        WatchSnapshotStore.update { snapshot in
            snapshot.hydrationMilliliters = (snapshot.hydrationMilliliters ?? 0) + milliliters
        }

        return .result(dialog: IntentDialog(stringLiteral: size.confirmation))
    }
}

enum WaterSize: String, AppEnum {
    case glass
    case smallBottle
    case bottle
    case large

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Water amount")

    static var caseDisplayRepresentations: [WaterSize: DisplayRepresentation] = [
        .glass: "glass",
        .smallBottle: "small bottle",
        .bottle: "bottle",
        .large: "large bottle",
    ]

    /// Sizes come from HydrationEngine.presets so Siri, the widget and the app
    /// cannot drift into disagreeing about what a "bottle" is.
    var milliliters: Double {
        let id: String
        switch self {
        case .glass: id = "glass"
        case .smallBottle: id = "small"
        case .bottle: id = "bottle"
        case .large: id = "large"
        }
        return HydrationEngine.presets.first { $0.id == id }?.milliliters
            ?? HydrationEngine.glassMilliliters
    }

    var confirmation: String {
        let total = WatchSnapshotStore.load()?.hydrationMilliliters ?? milliliters
        let glasses = Int(HydrationEngine.glasses(fromMilliliters: total).rounded())
        return "Logged. That's \(glasses) glass\(glasses == 1 ? "" : "es") today."
    }
}

// ------------------------------------------------------------
// MARK: Start a workout
// ------------------------------------------------------------

struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a workout"
    static var description = IntentDescription(
        "Opens Forge on the workout screen, with today's suggested session first."
    )
    /// An HKWorkoutSession lives in the app process. Opening is not a
    /// shortcoming of the intent; it is the honest shape of the operation.
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WatchIntentRoute.request(.workout)
        return .result()
    }
}

// ------------------------------------------------------------
// MARK: Start a reset
// ------------------------------------------------------------

struct StartResetIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a reset"
    static var description = IntentDescription(
        "Opens Forge on the breathing practice it recommends for right now."
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WatchIntentRoute.request(.mindfulness)
        return .result()
    }
}

// ------------------------------------------------------------
// MARK: Where an intent leaves a note for the app
// ------------------------------------------------------------

/// A one-shot route request written to the App Group.
///
/// An intent that opens the app cannot navigate it directly — the two are
/// different processes and the app may be cold. It leaves a destination behind;
/// ForgeWatchApp reads and clears it on launch and on activation. Consumed on
/// read so a shortcut run yesterday cannot redirect a launch today.
enum WatchIntentRoute {
    enum Destination: String {
        case workout
        case mindfulness
    }

    private static let key = "forge.watch.intentRoute"
    private static let stampKey = "forge.watch.intentRoute.at"
    /// Beyond this the request is stale — the user launched the app themselves
    /// and should land where they expected, not where a shortcut once pointed.
    private static let freshness: TimeInterval = 60

    static func request(_ destination: Destination) {
        guard let defaults = UserDefaults(suiteName: WatchSnapshotStore.appGroupID) else { return }
        defaults.set(destination.rawValue, forKey: key)
        defaults.set(Date(), forKey: stampKey)
    }

    static func consume() -> Destination? {
        guard let defaults = UserDefaults(suiteName: WatchSnapshotStore.appGroupID),
              let raw = defaults.string(forKey: key) else { return nil }
        let stamp = defaults.object(forKey: stampKey) as? Date
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: stampKey)

        guard let stamp, Date().timeIntervalSince(stamp) <= freshness else { return nil }
        return Destination(rawValue: raw)
    }
}
