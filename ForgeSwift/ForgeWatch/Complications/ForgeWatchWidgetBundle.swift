import WidgetKit
import SwiftUI

// MARK: - ForgeWatchWidgetBundle
//
// Entry point of the ForgeWatchWidgets extension: readiness, mindfulness,
// sleep, live workout, the supporter's "how to show up" glance, and
// hydration — the only one of the six with a button, because logging a
// glass is the one action short enough to belong on a watch face.

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
