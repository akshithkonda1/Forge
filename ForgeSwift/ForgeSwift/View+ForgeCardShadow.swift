import SwiftUI

// Premium dual-layer depth for cards across Forge.
extension View {
    func forgeCardShadow(emberGlow: Bool = false) -> some View {
        modifier(ForgeCardShadow(emberGlow: emberGlow))
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
    var emberGlow: Bool

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 3)
            .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 14)
            .shadow(
                color: emberGlow ? Color.ember.opacity(0.18) : .clear,
                radius: 28,
                x: 0,
                y: 10
            )
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
                    if let accent {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.14), accent.opacity(0.02), .clear],
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
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.05),
                                (accent ?? Color.white).opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .forgeCardShadow(emberGlow: accent != nil)
    }
}
