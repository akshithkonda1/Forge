import WidgetKit
import SwiftUI

// MARK: - ForgeWatchWidgetBundle
//
// Entry point of the ForgeWatchWidgets extension: readiness, mindfulness,
// sleep, live workout, the supporter's "how to show up" glance, and
// hydration. Tapping any of them opens Forge; none has an in-place
// interactive button today (HydrationComplication's own header explains why
// logging a glass isn't one yet, and what it would take).

@main
struct ForgeWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadinessComplication()
        MindfulnessResetComplication()
        SleepQualityComplication()
        ActiveWorkoutComplication()
        SupportComplication()
        HydrationComplication()
    }
}
