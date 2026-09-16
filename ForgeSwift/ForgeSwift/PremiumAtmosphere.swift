import SwiftUI
import ForgeCore

// MARK: - Premium atmosphere (Oura / Whoop–class)

/// Soft mesh wash for auth, splash, and onboarding — calm depth, never rage-fire.
struct PremiumAtmosphere: View {
    var accent: Color = ForgePalette.ember
    var secondary: Color = Color(hex: "A9D8FF")
    var intensity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.background

            // Soft top pearl / frost bloom — like Oura's quiet light field
            RadialGradient(
                colors: [
                    Color(hex: "F7F4F0").opacity(0.07 * intensity),
                    secondary.opacity(0.05 * intensity),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.12),
                startRadius: 4,
                endRadius: 380
            )

            // Quiet brand accent — warm, never aggressive
            RadialGradient(
                colors: [
                    accent.opacity(0.10 * intensity),
                    accent.opacity(0.03 * intensity),
                    .clear
                ],
                center: UnitPoint(x: 0.28, y: 0.72),
                startRadius: 8,
                endRadius: 340
            )
            .blur(radius: reduceMotion ? 0 : 28)

            RadialGradient(
                colors: [
                    secondary.opacity(0.06 * intensity),
                    .clear
                ],
                center: UnitPoint(x: 0.88, y: 0.55),
                startRadius: 6,
                endRadius: 260
            )
            .blur(radius: reduceMotion ? 0 : 20)

            // Soft vignette for typography legibility
            LinearGradient(
                colors: [
                    Color.background.opacity(0.15),
                    .clear,
                    Color.background.opacity(0.55),
                    Color.background.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Soft bloom behind ARIA — presence without fire.
struct PremiumPresenceBloom: View {
    var size: CGFloat = 200
    var accent: Color = ForgePalette.ember
    var frost: Color = Color(hex: "A9D8FF")
    var live: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(0.22),
                            frost.opacity(0.10),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)
                .scaleEffect(1.0 + breath * 0.04)
                .blur(radius: reduceMotion ? 6 : 18)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "F7F4F0").opacity(0.14),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.32
                    )
                )
                .frame(width: size * 0.72, height: size * 0.72)
        }
        .onAppear {
            guard live, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                breath = 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// Compact Forge wordmark mark — soft square, never a flame tongue.
struct ForgeBrandMark: View {
    var size: CGFloat = 22

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
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
            )
            .accessibilityHidden(true)
    }
}

/// Quiet primary CTA — pearl fill, dark type (Oura / Whoop–class).
struct PremiumPrimaryButton: View {
    let title: String
    var icon: String? = "arrow.right"
    var enabled: Bool = true
    var busy: Bool = false
    var action: () -> Void

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
                }
            }
            .foregroundColor(enabled ? Color(hex: "0A0A0A") : Color.white.opacity(0.35))
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background {
                if enabled {
                    Color(hex: "F7F4F0")
                } else {
                    Color.surfaceElevated
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(Color.white.opacity(enabled ? 0.08 : 0.04), lineWidth: 1)
            )
        }
        .buttonStyle(AuthPressButtonStyle())
        .disabled(!enabled || busy)
        .accessibilityLabel(title)
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
