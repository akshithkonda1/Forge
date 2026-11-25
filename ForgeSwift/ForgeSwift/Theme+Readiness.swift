import SwiftUI
import ForgeCore

// MARK: - Shared readiness helpers (Home is source of truth)

func readinessLabel(for score: Int) -> String {
    HomeReadiness.label(score)
}
