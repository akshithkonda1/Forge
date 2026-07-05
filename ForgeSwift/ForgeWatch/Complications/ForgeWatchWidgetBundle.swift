import WidgetKit
import SwiftUI

// MARK: - ForgeWatchWidgetBundle
//
// Entry point of the ForgeWatchWidgets extension: the three Phase 1
// complications plus the Phase 3 live workout complication.

@main
struct ForgeWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadinessComplication()
        MindfulnessResetComplication()
        SleepQualityComplication()
        ActiveWorkoutComplication()
    }
}
