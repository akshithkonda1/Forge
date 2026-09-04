import SwiftUI

/// Layer 5/6 — proactive ARIA nudge when relationship + patterns warrant outreach.
struct ProactiveCardView: View {
    let insight: String
    let relationshipLevel: Int
    let onTap: () -> Void
    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.steel.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.steel)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("ARIA")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.steel)
                            .tracking(0.8)
                        Text("Lv.\(relationshipLevel)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.surfaceElevated)
                            .cornerRadius(6)
                    }
                    Text(insight)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                    Text("Tap to open chat")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.steel)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
            }
            .padding(18)
            // Was a hand-rolled gradient + plain (non-continuous) .cornerRadius(18)
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