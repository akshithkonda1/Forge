import SwiftUI
import ForgeCore

// MARK: - Atmosphere + motion (premium refresh)
//
// Auth, splash and onboarding sit on the same flat field as the rest of the
// app. Every type below keeps its initializer so call sites are unchanged;
// the washes, flecks, sheens and shimmer are gone. Motion is reserved for
// moments (entrances, presses), never ambient loops.

/// Flat field for auth, splash, and onboarding. Parameters are accepted for
/// API compatibility; nothing animates and no color is washed in.
struct PremiumAtmosphere: View {
    var accent: Color = ForgePalette.ember
    var secondary: Color = Color(hex: "A9D8FF")
    var intensity: Double = 1.0
    var animated: Bool = true
    /// Splash uses a single slow drift. Auth / onboarding may loop.
    var loopMotion: Bool = true

    var body: some View {
        Color.background
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Behind ARIA: a single hairline ring, no bloom. Presence is carried by the
/// mark itself and the words next to it.
struct PremiumPresenceBloom: View {
    var size: CGFloat = 200
    var accent: Color = ForgePalette.ember
    var frost: Color = Color(hex: "A9D8FF")
    var live: Bool = true

    var body: some View {
        Circle()
            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            .frame(width: size * 0.78, height: size * 0.78)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Compact Forge mark — procedural hammer-and-flame silhouette.
struct ForgeBrandMark: View {
    var size: CGFloat = 22
    var labeled: Bool = false

    var body: some View {
        ForgeStrikeMark(size: size, labeled: labeled)
    }
}

/// Primary CTA for Day-0 flows — solid paper fill, ink text, no shimmer.
struct PremiumPrimaryButton: View {
    let title: String
    var icon: String? = "arrow.right"
    var enabled: Bool = true
    var busy: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FDS.Spacing.md) {
                if busy {
                    ProgressView().tint(Color(hex: "0A0A0A"))
                }
                Text(title)
                    .font(FDS.TypeScale.Dynamic.headline)
                Spacer(minLength: 0)
                if let icon, !busy {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundColor(enabled ? Color(hex: "0A0A0A") : Color.white.opacity(0.35))
            .padding(.horizontal, FDS.Spacing.xl)
            .padding(.vertical, FDS.Spacing.lg)
            .background(enabled ? Color.paper : Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .strokeBorder(Color.white.opacity(enabled ? 0 : 0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(ForgePressStyle(scale: 0.97, pressHaptic: true))
        .disabled(!enabled || busy)
        .accessibilityLabel(title)
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
            .animation(
                (reduceMotion ? Animation.easeOut(duration: 0.2) : ForgeMotion.gentle)
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

/// Progress capsules: the current step widens. No ambient pulse.
struct PremiumProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: FDS.Spacing.sm) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.paper : Color.white.opacity(0.16))
                    .frame(width: i == current ? 22 : 6, height: 4)
                    .forgeAnimation(ForgeMotion.snappy, value: current)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

