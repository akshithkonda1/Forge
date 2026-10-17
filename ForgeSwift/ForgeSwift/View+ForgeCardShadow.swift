import SwiftUI

// Card chrome primitive used only by `forgeContentCard`. Screens never call
// this directly — one card anatomy lives on `ForgeChrome.forgeContentCard`.
extension View {
    /// Flat surface + hairline. Default radius is 20 — dense like a fitness
    /// OS card, not a modal. Accent is accepted and ignored (no halo).
    func forgeGlassCard(cornerRadius: CGFloat = FDS.Radius.xl, accent: Color? = nil) -> some View {
        modifier(ForgeGlassCard(cornerRadius: cornerRadius, accent: accent))
    }

    /// Compact section eyebrow used on Home / Sleep / Profile headers.
    func forgeSectionLabel() -> some View {
        self
            .font(FDS.TypeScale.Dynamic.label)
            .foregroundStyle(Color.textTertiary)
            .tracking(1.4)
            .textCase(.uppercase)
    }
}

private struct ForgeGlassCard: ViewModifier {
    var cornerRadius: CGFloat
    /// No longer tints the card; kept so `forgeContentCard(accent:)` compiles.
    var accent: Color?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: 0.5)
            }
    }
}
