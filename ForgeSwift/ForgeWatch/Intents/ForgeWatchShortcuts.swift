import AppIntents

// MARK: - ForgeWatchShortcuts
//
// Split out of ForgeWatchIntents.swift on purpose.
//
// The intents themselves belong to two targets: the watch app runs them, and
// the widgets extension needs them visible for HydrationComplication's
// `Button(intent:)`. A file compiled into two targets is fine for an AppIntent
// and wrong for an AppShortcutsProvider — two providers registering the same
// phrases leaves the user with duplicates in Shortcuts and Siri.
//
// So this file is app-target only.

/// Phrases that make the intents reachable without opening the Shortcuts app,
/// and assignable to the Apple Watch Ultra's Action Button.
///
/// Every phrase carries the app name because App Intents requires it — a bare
/// "log water" would collide with every other app that logs water.
struct ForgeWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Log a glass in \(.applicationName)",
                "\(.applicationName) water",
            ],
            shortTitle: "Log water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start a \(.applicationName) workout",
                "Train with \(.applicationName)",
            ],
            shortTitle: "Start workout",
            systemImageName: "figure.run"
        )
        AppShortcut(
            intent: StartResetIntent(),
            phrases: [
                "Start a \(.applicationName) reset",
                "Reset with \(.applicationName)",
            ],
            shortTitle: "Start reset",
            systemImageName: "leaf.fill"
        )
    }
}
