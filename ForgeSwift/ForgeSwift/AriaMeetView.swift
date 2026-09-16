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
        ("Recovery", "Last night, load, and when to back off before you cook yourself.", "heart.fill"),
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
            Color.background.ignoresSafeArea()
            RadialGradient(
                colors: [ForgePalette.ember.opacity(0.16), ForgePalette.ember.opacity(0.05), .clear],
                center: UnitPoint(x: 0.5, y: 0.22),
                startRadius: 8,
                endRadius: 340
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color.steel.opacity(0.08), .clear],
                center: UnitPoint(x: 0.9, y: 0.92),
                startRadius: 6,
                endRadius: 280
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        ZStack {
                            ForgeFireField(intensity: .rage, origin: .hearth, live: true)
                                .frame(width: 180, height: 190)
                                .opacity(0.72)
                            AuroraOrbView(
                                state: .idle,
                                amplitude: 0.58,
                                mood: .focused,
                                size: 132,
                                followPresence: true
                            )
                        }
                        .padding(.top, 28)

                        Text(AriaMeetCopy.eyebrow.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(2.2)
                            .foregroundColor(.ember)
                            .multilineTextAlignment(.center)

                        Text(AriaMeetCopy.title)
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.textPrimary)

                        Text(AriaMeetCopy.lead)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)

                        VStack(spacing: 10) {
                            ForEach(AriaMeetCopy.capabilities, id: \.title) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.ember.opacity(0.16))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: item.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.ember)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.textPrimary)
                                        Text(item.body)
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .forgeGlassCard(cornerRadius: 16, accent: .ember)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                }

                VStack(spacing: 10) {
                    ForgePrimaryButton(
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
