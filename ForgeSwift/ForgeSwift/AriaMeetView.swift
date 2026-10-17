import SwiftUI
import ForgeCore

/// First-meet copy. Lockstep with `src/lib/aria-intro.ts`.
enum AriaMeetCopy: Sendable {
    static let eyebrow = "Your lifestyle coach"
    static let title = "This is ARIA"
    static let lead = "I was designed for Forge — I power how you train, rest, and live the day."
    static let pairingForbidden = "FORGE × ARIA"
    static let talkCta = "Talk with ARIA"
    static let skipCta = "Skip"

    static let capabilities: [(title: String, body: String, icon: String)] = [
        ("Train today", "What to do with the body you woke up with — not a plan from last week.", "dumbbell.fill"),
        ("Readiness", "Last night, load, and when to ease off before you overreach.", "heart.fill"),
        ("What's in the way", "Talk. You don't have to know the question. I'll stay with it.", "bubble.left.and.bubble.right.fill"),
        ("Plans that fit", "I coach the life you already have — not a spreadsheet of you.", "calendar"),
    ]
}

/// Tutorial-style first meeting. Shown on first login or the first ARIA tap.
struct AriaMeetView: View {
    var onTalk: () -> Void
    var onSkip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var appeared = false

    private var bloomSize: CGFloat { typeSize.isAccessibilitySize ? 140 : 190 }
    private var orbSize: CGFloat { typeSize.isAccessibilitySize ? 96 : 132 }

    var body: some View {
        ZStack {
            PremiumAtmosphere(
                accent: ForgePalette.ember,
                intensity: 0.85,
                animated: false
            )

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: ForgeLayout.sectionGap) {
                        presenceHero
                        copyBlock
                        capabilitiesCard
                    }
                    .padding(.horizontal, ForgeLayout.screenInset)
                    .padding(.top, FDS.Spacing.lg)
                    .padding(.bottom, ForgeLayout.sectionGap)
                }

                actionDock
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withForgeMotion(ForgeMotion.gentle) { appeared = true }
            }
        }
    }

    private var presenceHero: some View {
        ZStack {
            PremiumPresenceBloom(
                size: bloomSize,
                accent: ForgePalette.ember,
                live: false
            )
            AuroraOrbView(
                state: .idle,
                amplitude: 0.55,
                mood: .focused,
                size: orbSize,
                followPresence: true
            )
        }
    }

    private var copyBlock: some View {
        VStack(spacing: ForgeLayout.pairGap) {
            Text(AriaMeetCopy.eyebrow)
                .forgeSectionLabel()
                .multilineTextAlignment(.center)

            Text(AriaMeetCopy.title)
                .font(ForgeType.pageTitle)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)

            Text(AriaMeetCopy.lead)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .forgeWrapping()
                .padding(.top, ForgeLayout.pairGap)
        }
        .frame(maxWidth: .infinity)
    }

    private var capabilitiesCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForEach(Array(AriaMeetCopy.capabilities.enumerated()), id: \.element.title) { index, item in
                AriaMeetCapabilityRow(
                    title: item.title,
                    message: item.body,
                    icon: item.icon,
                    tint: Self.rowTint(index)
                )
            }
        }
        .forgeContentCard(tint: .ember)
    }

    private var actionDock: some View {
        VStack(spacing: ForgeLayout.pairGap) {
            ForgePrimaryButton(
                title: AriaMeetCopy.talkCta,
                icon: "waveform",
                action: onTalk
            )

            Button {
                onSkip()
            } label: {
                Text(AriaMeetCopy.skipCta)
                    .font(HomeType.label)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip")
            .accessibilityHint("Skip the first meeting and look around Forge.")
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.bottom, FDS.Spacing.sm)
    }

    private static func rowTint(_ index: Int) -> Color {
        let tints: [Color] = [Color.ember, Color.steel, Color.aurora, Color.amber]
        return tints[index % tints.count]
    }
}

/// One capability: icon well, status title, wrapping body. Display only.
private struct AriaMeetCapabilityRow: View {
    let title: String
    let message: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: icon, tint: tint)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(message)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: ForgeUX.minTap, alignment: .top)
        .accessibilityElement(children: .combine)
    }
}
