import SwiftUI

// Card chrome across Forge: flat surface, hairline edge, no halo.
extension View {
    /// `glow` tints the outer halo. Pass the card's own accent — passing `nil`
    /// (the default) means no halo at all.
    func forgeCardShadow(glow: Color? = nil) -> some View {
        modifier(ForgeCardShadow(glow: glow))
    }

    /// Full premium glass card: fill + hairline + depth.
    /// Default radius is 20 — dense like a fitness OS card, not a modal.
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

    /// Inner well used inside glass cards — briefing text, chips, tiles.
    func forgeInnerWell(cornerRadius: CGFloat = FDS.Radius.md) -> some View {
        self
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.borderHairline, lineWidth: 0.5)
            )
    }

    /// Drop-in upgrade for the old `Color.surface + cornerRadius + hairline` stack.
    func forgeSurfaceCard(cornerRadius: CGFloat = FDS.Radius.xl, accent: Color? = nil) -> some View {
        modifier(ForgeGlassCard(cornerRadius: cornerRadius, accent: accent))
    }
}

private struct ForgeCardShadow: ViewModifier {
    /// Colored halos are retired; `glow` is accepted and ignored.
    var glow: Color?

    func body(content: Content) -> some View {
        // Flat surfaces separate by lightness and a hairline, not by shadow.
        content
    }
}

private struct ForgeGlassCard: ViewModifier {
    var cornerRadius: CGFloat
    /// No longer tints the card; kept so call sites compile unchanged.
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
