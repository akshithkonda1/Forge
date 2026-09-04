import SwiftUI
import WatchKit
import ForgeCore

// MARK: - HapticButton
//
// Every meaningful action on the wrist gets a haptic acknowledgement.
// This wraps Button so views never call WKInterfaceDevice directly and
// haptic policy stays in one place.

struct HapticButton<Label: View>: View {
    var haptic: WKHapticType = .click
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            WKInterfaceDevice.current().play(haptic)
            action()
        } label: {
            label()
        }
    }
}

/// Large, thumb-friendly primary action used on Home and in session flows.
struct ForgeActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = ForgePalette.steel
    var haptic: WKHapticType = .click
    var accessibilityHint: String?
    var action: () -> Void

    var body: some View {
        HapticButton(haptic: haptic, action: action) {
            HStack(spacing: ForgeDS.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(ForgeType.caption(14))
                    .foregroundStyle(ForgePalette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, ForgeDS.Spacing.xs)
        }
        .buttonStyle(.bordered)
        .tint(tint.opacity(0.35))
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "")
    }
}
