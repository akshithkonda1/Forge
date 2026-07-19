import WidgetKit
import SwiftUI

// MARK: - ForgeWidgetExtensionBundle
//
// iOS widget extension entry point: the Live Activity for watch workouts
// plus the previously orphaned Lifestyle home-screen widget (its source
// is referenced from the repo-root ForgeWidget/ folder).

@main
struct ForgeWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        LifestyleWidget()
        ForgeWorkoutLiveActivity()
    }
}
