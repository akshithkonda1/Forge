import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - ForgeWidgetExtensionBundle
//
// iOS widget extension entry point: workout + cycle Live Activities,
// cycle lockscreen widget, Lifestyle home-screen widget, and the MagSafe
// landscape StandBy nest face (`WidgetFamily.systemSmall` — Apple's public
// StandBy slot; there is no dedicated StandBy family).

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
        StandByNestWidget()
        ForgeWorkoutLiveActivity()
        CycleFertileWindowLiveActivity()
    }
}
