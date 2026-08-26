import WidgetKit
import SwiftUI

// MARK: - ForgeWatchWidgetBundle
//
// Entry point of the ForgeWatchWidgets extension: readiness, mindfulness,
// sleep, live workout, and the supporter's "how to show up" glance.

@main
struct ForgeWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadinessComplication()
        MindfulnessResetComplication()
        SleepQualityComplication()
        ActiveWorkoutComplication()
        SupportComplication()
    }
}
