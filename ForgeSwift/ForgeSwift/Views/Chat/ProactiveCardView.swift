import SwiftUI
import ForgeCore

/// Layer 5/6 — proactive ARIA nudge when relationship + patterns warrant outreach.
struct ProactiveCardView: View {
    let insight: String
    let relationshipLevel: Int
    let onTap: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: ForgeLayout.blockGap) {
                // One live mark per screen: this one stays in its still pose.
                ARIAIdentityMark(state: .idle, mood: .focused, size: 44, amplitude: 0.22)
                    .environment(\.forgeMinimalAnimation, true)

                VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                    HStack(spacing: FDS.Spacing.xs) {
                        Text("ARIA")
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(.steel)
                            .tracking(0.8)
                        Text("Lv.\(relationshipLevel)")
                            .font(FDS.TypeScale.Dynamic.micro)
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, FDS.Spacing.sm)
                            .padding(.vertical, 2)
                            .forgeInsetTile(radius: FDS.Radius.xs)
                    }
                    Text(insight)
                        .font(HomeType.body)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .forgeWrapping()
                    Text("Tap to open chat")
                        .font(FDS.TypeScale.Dynamic.micro)
                        .foregroundColor(.steel)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(HomeMetrics.cardPadding)
            // Was a hand-rolled gradient + plain (non-continuous) .cornerRadius(FDS.Radius.lg)
            // + stroke, with no shadow — the only Home card with zero depth and a
            // different corner curve from everything around it.
            .forgeGlassCard(accent: .steel)
        }
        .buttonStyle(.plain)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 8)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(ForgeMotion.gentle) {
                    appeared = true
                }
            }
        }
    }
}