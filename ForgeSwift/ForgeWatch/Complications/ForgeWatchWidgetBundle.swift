import WidgetKit
import SwiftUI

// MARK: - ForgeWatchWidgetBundle
//
// Entry point of the ForgeWatchWidgets extension: the three Phase 1
// complications, the Phase 3 live workout complication, and hydration —
// the only one of the five with a button, because logging a glass is the
// one action short enough to belong on a watch face.

@main
struct ForgeWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadinessComplication()
        MindfulnessResetComplication()
        SleepQualityComplication()
        ActiveWorkoutComplication()
        HydrationComplication()
    }
}
