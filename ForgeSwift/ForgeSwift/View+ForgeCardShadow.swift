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
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Color.textTertiary)
            .tracking(1.8)
            .textCase(.uppercase)
    }
}

private struct ForgeCardShadow: ViewModifier {
    var glow: Color?

    func body(content: Content) -> some View {
        content
            // One soft ambient shadow rather than three stacked ones. Depth now
            // comes from the card's fill sitting above the background, not from
            // piling up dark halos — which is what made every card read heavy.
            .shadow(color: .black.opacity(0.38), radius: 18, x: 0, y: 8)
            // Tinted from the accent actually passed in. This used to be
            // hardcoded to Color.ember regardless of accent, so the green cycle
            // card, the indigo support-pulse card and the steel/red readiness
            // card all emitted an orange halo.
            .shadow(color: (glow ?? .clear).opacity(glow == nil ? 0 : 0.13),
                    radius: 26, x: 0, y: 10)
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
                    // The accent is now a whisper rather than a wash. It still
                    // carries meaning on the data-driven cards (cycle phase,
                    // readiness band) but no longer paints the whole surface.
                    if let accent {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.05), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                // Flat hairline. The old gradient stroke read as a bevel and
                // gave each card a slightly different edge depending on accent.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            }
            .forgeCardShadow(glow: accent)
    }
}
