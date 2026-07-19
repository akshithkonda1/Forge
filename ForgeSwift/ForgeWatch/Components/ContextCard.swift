import SwiftUI
import ForgeCore

// MARK: - ContextCard
//
// The watch-sized sibling of the iOS ProactiveCardView: icon + title +
// supportive body on a soft elevated surface. Used for the Home
// recommendation card and session debriefs.

struct ContextCard: View {
    let systemImage: String
    let title: String
    let body_: String
    var accent: Color = ForgePalette.steel
    var accessibilityHint: String?
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                HapticButton(haptic: .click, action: action) { cardContent }
                    .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(body_)")
        .accessibilityHint(accessibilityHint ?? "")
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            HStack(spacing: ForgeDS.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(ForgeType.caption(13))
                    .foregroundStyle(ForgePalette.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            Text(body_)
                .font(.system(size: 12))
                .foregroundStyle(ForgePalette.textSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ForgeDS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ForgeDS.Radius.lg, style: .continuous)
                .fill(ForgePalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: ForgeDS.Radius.lg, style: .continuous)
                        .stroke(accent.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
