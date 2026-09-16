import SwiftUI
import ForgeCore

/// First-meet copy. Lockstep with `src/lib/aria-intro.ts`.
enum AriaMeetCopy: Sendable {
    static let eyebrow = "Adaptive Recovery Interactive Assistant"
    static let title = "This is ARIA"
    static let lead = "I was designed for Forge — I power how you train, recover, and live the day."
    static let pairingForbidden = "FORGE × ARIA"
    static let talkCta = "Talk with ARIA"
    static let skipCta = "Look around first"

    static let capabilities: [(title: String, body: String, icon: String)] = [
        ("Train today", "What to do with the body you woke up with — not a plan from last week.", "dumbbell.fill"),
        ("Recovery", "Last night, load, and when to ease off before you overreach.", "heart.fill"),
        ("What's in the way", "Talk. You don't have to know the question. I'll stay with it.", "bubble.left.and.bubble.right.fill"),
        ("Plans that fit", "I coach the life you already have — not a spreadsheet of you.", "calendar"),
    ]
}

/// Tutorial-style first meeting. Shown on first login or the first ARIA tap.
struct AriaMeetView: View {
    var onTalk: () -> Void
    var onSkip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            PremiumAtmosphere(
                accent: ForgePalette.ember,
                secondary: Color(hex: "A9D8FF"),
                intensity: 0.85
            )

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        ZStack {
                            PremiumPresenceBloom(
                                size: 190,
                                accent: ForgePalette.ember,
                                frost: Color(hex: "A9D8FF")
                            )
                            AuroraOrbView(
                                state: .idle,
                                amplitude: 0.55,
                                mood: .focused,
                                size: 132,
                                followPresence: true
                            )
                        }
                        .padding(.top, 28)

                        Text(AriaMeetCopy.eyebrow.uppercased())
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .tracking(2.2)
                            .foregroundColor(.textTertiary)
                            .multilineTextAlignment(.center)
                            .premiumEntrance(index: 0, appeared: appeared)

                        Text(AriaMeetCopy.title)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .premiumEntrance(index: 1, appeared: appeared)

                        Text(AriaMeetCopy.lead)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .premiumEntrance(index: 2, appeared: appeared)

                        VStack(spacing: 10) {
                            ForEach(Array(AriaMeetCopy.capabilities.enumerated()), id: \.element.title) { index, item in
                                HStack(alignment: .top, spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.06))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: item.icon)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(Color(hex: "F7F4F0").opacity(0.85))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.textPrimary)
                                        Text(item.body)
                                            .font(.system(size: 14, weight: .regular, design: .rounded))
                                            .foregroundColor(.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                                .premiumEntrance(index: 3 + index, appeared: appeared)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                }

                VStack(spacing: 10) {
                    PremiumPrimaryButton(
                        title: AriaMeetCopy.talkCta,
                        icon: "waveform",
                        action: onTalk
                    )

                    Button(action: onSkip) {
                        Text(AriaMeetCopy.skipCta)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(FDS.Spring.fluid) { appeared = true }
            }
        }
    }
}
