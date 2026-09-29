import SwiftUI

// Premium dual-layer depth for cards across Forge.
extension View {
    /// `glow` tints the outer halo. Pass the card's own accent — passing `nil`
    /// (the default) means no halo at all.
    func forgeCardShadow(glow: Color? = nil) -> some View {
        modifier(ForgeCardShadow(glow: glow))
    }

    /// Full premium glass card: fill + hairline + depth.
    /// Default radius is 20 — dense like a fitness OS card, not a modal.
    func forgeGlassCard(cornerRadius: CGFloat = 20, accent: Color? = nil) -> some View {
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
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
    }

    /// Drop-in upgrade for the old `Color.surface + cornerRadius + hairline` stack.
    func forgeSurfaceCard(cornerRadius: CGFloat = FDS.Radius.xl, accent: Color? = nil) -> some View {
        modifier(ForgeGlassCard(cornerRadius: cornerRadius, accent: accent))
    }
}

private struct ForgeCardShadow: ViewModifier {
    var glow: Color?

    func body(content: Content) -> some View {
        content
            // Photo-board cards: a short lift, not a black puddle.
            .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 6)
            .shadow(color: (glow ?? .clear).opacity(glow == nil ? 0 : 0.16),
                    radius: 12, x: 0, y: 4)
    }
}

private struct ForgeGlassCard: ViewModifier {
    var cornerRadius: CGFloat
    var accent: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.surfaceElevated.opacity(0.94))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient.premiumSurface)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.10), Color.white.opacity(0.02), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    if let accent {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.07), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
            .forgeCardShadow(glow: accent)
    }
}
