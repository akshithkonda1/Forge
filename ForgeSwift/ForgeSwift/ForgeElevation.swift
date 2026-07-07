import SwiftUI

// MARK: - Forge Elevation System
//
// Before this, the app had exactly one depth level: `forgeCardShadow()`.
// Real elevation hierarchies need more than one step so a modal can read
// as "above" a card which reads as "above" the background. Four levels,
// each tuned for light and dark appearance (the app runs `.dark` today,
// but the shadow math is written correctly for both so it isn't a
// landmine if that ever changes):
//
//   .flat     — sits directly on the background (list rows, inline chips)
//   .raised   — the default card level (replaces forgeCardShadow's job)
//   .floating — a card that visually leads the screen (hero/readiness card)
//   .overlay  — sheets, modals, anything presented above everything else
//
// `forgeCardShadow()` is kept as a thin alias to `.raised` so every
// existing call site keeps compiling and rendering identically —
// adopting the new levels elsewhere is additive, not a breaking change.

enum ForgeElevation {
    case flat
    case raised
    case floating
    case overlay

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    /// Two shadows per level (a tight contact shadow + a soft ambient
    /// one) — the same technique `forgeCardShadow()` used for `.raised`,
    /// extended proportionally to the other three levels.
    func shadows(for colorScheme: ColorScheme) -> [Shadow] {
        let dark = colorScheme == .dark
        switch self {
        case .flat:
            return []
        case .raised:
            return [
                Shadow(color: .black.opacity(dark ? 0.55 : 0.06), radius: 10, x: 0, y: 4),
                Shadow(color: .black.opacity(dark ? 0.35 : 0.12), radius: 20, x: 0, y: 10),
            ]
        case .floating:
            return [
                Shadow(color: .black.opacity(dark ? 0.60 : 0.10), radius: 16, x: 0, y: 8),
                Shadow(color: .black.opacity(dark ? 0.40 : 0.16), radius: 32, x: 0, y: 18),
            ]
        case .overlay:
            return [
                Shadow(color: .black.opacity(dark ? 0.70 : 0.18), radius: 24, x: 0, y: 12),
                Shadow(color: .black.opacity(dark ? 0.45 : 0.22), radius: 48, x: 0, y: 24),
            ]
        }
    }
}

private struct ForgeElevationModifier: ViewModifier {
    let level: ForgeElevation
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shadows = level.shadows(for: colorScheme)
        return content
            .shadow(color: shadows.first?.color ?? .clear,
                    radius: shadows.first?.radius ?? 0,
                    x: shadows.first?.x ?? 0,
                    y: shadows.first?.y ?? 0)
            .shadow(color: shadows.count > 1 ? shadows[1].color : .clear,
                    radius: shadows.count > 1 ? shadows[1].radius : 0,
                    x: shadows.count > 1 ? shadows[1].x : 0,
                    y: shadows.count > 1 ? shadows[1].y : 0)
    }
}

extension View {
    func forgeElevation(_ level: ForgeElevation) -> some View {
        modifier(ForgeElevationModifier(level: level))
    }
}
