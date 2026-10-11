import SwiftUI
import ForgeCore

// MARK: - Shared readiness helpers (Home is source of truth)

func readinessColor(for score: Int) -> Color {
    HomeReadiness.color(score)
}

func readinessLabel(for score: Int) -> String {
    HomeReadiness.label(score)
}

// MARK: - Typography scale (aliases the named ForgeType roles)

enum ForgeTypography {
    static let display = ForgeType.display
    static let title = ForgeType.title
    static let headline = ForgeType.headline
    static let body = ForgeType.body
    static let caption = ForgeType.caption
    static let metric = ForgeType.metric

    static func title(_ size: CGFloat = 28) -> Font { ForgeType.title(size) }
    static func body(_ size: CGFloat = 15) -> Font { ForgeType.body(size) }
    static func caption(_ size: CGFloat = 12) -> Font { ForgeType.caption(size) }
    static func metric(_ size: CGFloat = 32) -> Font { ForgeType.metric(size) }
}
