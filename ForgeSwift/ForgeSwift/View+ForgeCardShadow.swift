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
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

private struct ForgeCardShadow: ViewModifier {
    var glow: Color?

    func body(content: Content) -> some View {
        content
            // One soft ambient shadow rather than three stacked ones. Depth now
            // comes from the card's fill sitting above the background, not from
            // piling up dark halos — which is what made every card read heavy.
            .shadow(color: .black.opacity(0.32), radius: 20, x: 0, y: 10)
            // Tinted from the accent actually passed in. This used to be
            // hardcoded to Color.ember regardless of accent, so the green cycle
            // card, the indigo support-pulse card and the steel/red readiness
            // card all emitted an orange halo.
            .shadow(color: (glow ?? .clear).opacity(glow == nil ? 0 : 0.16),
                    radius: 22, x: 0, y: 8)
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
                        .fill(Color.surface.opacity(0.94))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient.premiumSurface)
                    // The accent is now a whisper rather than a wash. It still
                    // carries meaning on the data-driven cards (cycle phase,
                    // readiness band) but no longer paints the whole surface.
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
                                Color.white.opacity(0.05),
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
