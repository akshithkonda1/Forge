import SwiftUI

// Consistent card shadow used across Forge views
// Applies a soft, dual-drop shadow for depth on light and dark appearances.
extension View {
    func forgeCardShadow() -> some View {
        modifier(ForgeCardShadow())
    }
}

private struct ForgeCardShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // Tune shadow strengths for light vs dark to avoid overbearing glow.
        let upper = colorScheme == .dark ? Color.black.opacity(0.55) : Color.black.opacity(0.06)
        let lower = colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.12)

        return content
            .shadow(color: upper, radius: 10, x: 0, y: 4)
            .shadow(color: lower, radius: 20, x: 0, y: 10)
    }
}
