import WidgetKit
import SwiftUI

// MARK: - ForgeWatchWidgetBundle
//
// Entry point of the ForgeWatchWidgets extension: the three Phase 1
// complications. ActiveWorkoutComplication joins in Phase 3.

@main
struct ForgeWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadinessComplication()
        MindfulnessResetComplication()
        SleepQualityComplication()
    }
}
