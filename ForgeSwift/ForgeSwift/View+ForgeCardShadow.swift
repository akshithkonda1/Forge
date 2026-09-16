import SwiftUI

// Premium dual-layer depth for cards across Forge.
extension View {
    /// `glow` tints the outer halo. Pass the card's own accent — passing `nil`
    /// (the default) means no halo at all.
    func forgeCardShadow(glow: Color? = nil) -> some View {
        modifier(ForgeCardShadow(glow: glow))
    }

    /// Full premium glass card: fill + hairline + depth.
    func forgeGlassCard(cornerRadius: CGFloat = FDS.Radius.xl, accent: Color? = nil) -> some View {
        modifier(ForgeGlassCard(cornerRadius: cornerRadius, accent: accent))
    }

    /// Compact section eyebrow used on Home / Sleep / Profile headers.
    func forgeSectionLabel() -> some View {
        self
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.textTertiary)
            .tracking(1.4)
            .textCase(.uppercase)
    }

    /// Inner well used inside glass cards — briefing text, chips, tiles.
    func forgeInnerWell(cornerRadius: CGFloat = FDS.Radius.md) -> some View {
        self
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
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
            // Whoop / Oura: depth is a whisper, not a black puddle. Glow
            // carries the accent so cards feel lit from the data they hold.
            .shadow(color: .black.opacity(0.20), radius: 14, x: 0, y: 8)
            .shadow(color: (glow ?? .clear).opacity(glow == nil ? 0 : 0.22),
                    radius: 18, x: 0, y: 6)
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
                        .fill(Color.surface.opacity(0.92))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient.premiumSurface)
                    // Top sheen — the hairline luminance Whoop / Health use
                    // instead of a heavy drop shadow.
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    if let accent {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.09), .clear],
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
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.07),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .forgeCardShadow(glow: accent)
    }
}
