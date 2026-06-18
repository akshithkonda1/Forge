import SwiftUI

// MARK: - Shared readiness helpers (used across Home, Chat, Workout)

func readinessColor(for score: Int) -> Color {
    switch score {
    case 85...: return .success
    case 70..<85: return .steel
    case 55..<70: return .warning
    default: return .danger
    }
}

func readinessLabel(for score: Int) -> String {
    switch score {
    case 85...: return "Primed"
    case 70..<85: return "Ready"
    case 55..<70: return "Moderate"
    default: return "Recovery"
    }
}

// MARK: - Typography scale

enum ForgeTypography {
    static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func body(_ size: CGFloat = 15.5) -> Font {
        .system(size: size, weight: .regular)
    }

    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium)
    }

    static func metric(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}