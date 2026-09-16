import SwiftUI
import ForgeCore

// MARK: - Premium atmosphere + motion (Oura / Whoop–class)

/// Soft mesh wash for auth, splash, and onboarding — calm depth, never rage-fire.
/// Drift and breath give the field life without noise.
struct PremiumAtmosphere: View {
    var accent: Color = ForgePalette.ember
    var secondary: Color = Color(hex: "A9D8FF")
    var intensity: Double = 1.0
    var animated: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift: CGFloat = 0
    @State private var pulse: CGFloat = 0

    var body: some View {
        ZStack {
            Color.background

            // Soft top pearl / frost bloom
            RadialGradient(
                colors: [
                    Color(hex: "F7F4F0").opacity(0.08 * intensity),
                    secondary.opacity(0.055 * intensity),
                    .clear
                ],
                center: UnitPoint(x: 0.5 + drift * 0.02, y: 0.10 + pulse * 0.02),
                startRadius: 4,
                endRadius: 400
            )

            // Quiet brand accent — warm, never aggressive
            RadialGradient(
                colors: [
                    accent.opacity(0.12 * intensity),
                    accent.opacity(0.035 * intensity),
                    .clear
                ],
                center: UnitPoint(x: 0.26 + drift * 0.04, y: 0.74 - pulse * 0.03),
                startRadius: 8,
                endRadius: 360
            )
            .blur(radius: reduceMotion ? 0 : 30)

            RadialGradient(
                colors: [
                    secondary.opacity(0.08 * intensity),
                    .clear
                ],
                center: UnitPoint(x: 0.86 - drift * 0.03, y: 0.48 + pulse * 0.04),
                startRadius: 6,
                endRadius: 280
            )
            .blur(radius: reduceMotion ? 0 : 22)

            // Specular sheen — thin diagonal light
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(0.035 * intensity),
                    .clear
                ],
                startPoint: UnitPoint(x: 0.1 + drift * 0.1, y: 0),
                endPoint: UnitPoint(x: 0.7 + drift * 0.1, y: 1)
            )
            .blendMode(.plusLighter)
            .opacity(animated && !reduceMotion ? 0.7 + pulse * 0.3 : 0.5)

            // Soft vignette for typography legibility
            LinearGradient(
                colors: [
                    Color.background.opacity(0.12),
                    .clear,
                    Color.background.opacity(0.5),
                    Color.background.opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.55), value: accent)
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true)) {
                drift = 1
            }
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                pulse = 1
            }
        }
    }
}

/// Soft bloom behind ARIA — presence with orbiting frost ring.
struct PremiumPresenceBloom: View {
    var size: CGFloat = 200
    var accent: Color = ForgePalette.ember
    var frost: Color = Color(hex: "A9D8FF")
    var live: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: CGFloat = 0
    @State private var orbit: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(0.24),
                            frost.opacity(0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)
                .scaleEffect(1.0 + breath * 0.05)
                .blur(radius: reduceMotion ? 6 : 18)

            // Orbiting frost accent — quiet life
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            frost.opacity(0.0),
                            frost.opacity(0.45),
                            Color(hex: "F7F4F0").opacity(0.35),
                            frost.opacity(0.0)
                        ],
                        center: .center,
                        angle: .degrees(orbit)
                    ),
                    lineWidth: 1.2
                )
                .frame(width: size * 0.72, height: size * 0.72)
                .opacity(live && !reduceMotion ? 0.85 : 0.35)

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                .frame(width: size * 0.78, height: size * 0.78)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "F7F4F0").opacity(0.16),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.32
                    )
                )
                .frame(width: size * 0.68, height: size * 0.68)
                .scaleEffect(1.0 + breath * 0.025)
        }
        .onAppear {
            guard live, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) {
                breath = 1
            }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                orbit = 360
            }
        }
        .accessibilityHidden(true)
    }
}

/// Compact Forge wordmark mark — soft square with living specular.
struct ForgeBrandMark: View {
    var size: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheen: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "F7F4F0").opacity(0.95),
                        Color.ember.opacity(0.92),
                        Color.emberDark
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35 * sheen),
                                .clear,
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
            )
            .shadow(color: Color.ember.opacity(0.28), radius: reduceMotion ? 0 : 6, y: 2)
            .onAppear {
                guard !reduceMotion else { sheen = 0.6; return }
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    sheen = 1
                }
            }
            .accessibilityHidden(true)
    }
}

/// Quiet primary CTA — pearl fill with shimmer and press life.
struct PremiumPrimaryButton: View {
    let title: String
    var icon: String? = "arrow.right"
    var enabled: Bool = true
    var busy: Bool = false
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer: CGFloat = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy {
                    ProgressView().tint(Color(hex: "0A0A0A"))
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                if let icon, !busy {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .offset(x: enabled && !reduceMotion ? shimmer * 2 : 0)
                }
            }
            .foregroundColor(enabled ? Color(hex: "0A0A0A") : Color.white.opacity(0.35))
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background {
                ZStack {
                    if enabled {
                        Color(hex: "F7F4F0")
                        // Soft pearl → warm edge
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color(hex: "F7F4F0").opacity(0),
                                Color.ember.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        // Traveling sheen
                        if !reduceMotion {
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color.white.opacity(0.45),
                                    .clear
                                ],
                                startPoint: UnitPoint(x: shimmer - 0.3, y: 0.5),
                                endPoint: UnitPoint(x: shimmer + 0.3, y: 0.5)
                            )
                            .blendMode(.plusLighter)
                        }
                    } else {
                        Color.surfaceElevated
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(enabled ? 0.55 : 0.06),
                                Color.white.opacity(enabled ? 0.12 : 0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: enabled ? Color(hex: "F7F4F0").opacity(0.18) : .clear,
                radius: 18,
                y: 8
            )
        }
        .buttonStyle(AuthPressButtonStyle())
        .disabled(!enabled || busy)
        .accessibilityLabel(title)
        .onAppear {
            guard enabled, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false).delay(0.4)) {
                shimmer = 1.2
            }
        }
    }
}

/// Staggered entrance for Day-0 copy blocks.
struct PremiumEntrance: ViewModifier {
    let index: Int
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (reduceMotion ? 0 : 14))
            .blur(radius: appeared || reduceMotion ? 0 : 4)
            .animation(
                (reduceMotion ? Animation.easeOut(duration: 0.2) : FDS.Spring.hero)
                    .delay(Double(index) * 0.07),
                value: appeared
            )
    }
}

extension View {
    func premiumEntrance(index: Int, appeared: Bool) -> some View {
        modifier(PremiumEntrance(index: index, appeared: appeared))
    }
}

/// Soft progress capsules with fill life.
struct PremiumProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color(hex: "F7F4F0") : Color.white.opacity(0.16))
                    .frame(width: i == current ? 22 : 6, height: 4)
                    .shadow(
                        color: i == current ? Color(hex: "F7F4F0").opacity(0.35) : .clear,
                        radius: 6,
                        y: 0
                    )
                    .animation(FDS.Spring.snap, value: current)
            }
        }
    }
}

struct AuthPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(FDS.Spring.snap, value: configuration.isPressed)
    }
}
