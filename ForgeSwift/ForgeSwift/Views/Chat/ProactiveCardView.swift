import SwiftUI

/// Layer 5/6 — proactive ARIA nudge when relationship + patterns warrant outreach.
struct ProactiveCardView: View {
    let insight: String
    let relationshipLevel: Int
    let onTap: () -> Void
    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: FDS.Spacing.lg) {
                ARIAIdentityMark(state: .idle, mood: .focused, size: 44, amplitude: 0.22)

                VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                    HStack(spacing: FDS.Spacing.sm) {
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
                        .font(FDS.TypeScale.Dynamic.body)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                    Text("Tap to open chat")
                        .font(FDS.TypeScale.Dynamic.micro)
                        .foregroundColor(.steel)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
            }
            .padding(FDS.Spacing.lg)
            // Was a hand-rolled gradient + plain (non-continuous) .cornerRadius(FDS.Radius.lg)
            // + stroke, with no shadow — the only Home card with zero depth and a
            // different corner curve from everything around it.
            .forgeGlassCard(accent: .steel)
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }
}