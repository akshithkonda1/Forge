import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - ForgeWidgetExtensionBundle
//
// iOS widget extension entry point: workout + cycle Live Activities,
// cycle lockscreen widget, and the Lifestyle home-screen widget.

@main
struct ForgeWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ReadinessWidget()
        HydrationWidget()
        SleepWidget()
        LifestyleWidget()
        CyclePhaseWidget()
        SupportGlanceWidget()
        ForgeWorkoutLiveActivity()
        CycleFertileWindowLiveActivity()
    }
}
