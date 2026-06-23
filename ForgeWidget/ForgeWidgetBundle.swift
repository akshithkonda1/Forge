import WidgetKit
import SwiftUI

// Entry point for the widget extension. Add this file (and LifestyleWidget.swift)
// ONLY to the widget extension target — never to the app target, or the duplicate
// @main will clash with ForgeSwiftApp.
@main
struct ForgeWidgetBundle: WidgetBundle {
    var body: some Widget {
        LifestyleWidget()
    }
}
