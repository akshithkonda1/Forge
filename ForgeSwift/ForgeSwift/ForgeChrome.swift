import SwiftUI
import ForgeCore

// MARK: - Shared chrome
//
// One implementation each. Home plate / CTA / type is the look.
// Event-only motion. Reduce Motion respected. 44 pt taps.

enum ForgeUX {
    static let minTap = ForgeDS.minTap
    static let inset = ForgeDS.safeInset
    static let icon = ForgeDS.iconSize
    static let stroke = ForgeDS.Stroke.thin
    static let hairline = ForgeDS.Stroke.hairline
}

struct ForgeCTAEyebrow: View {
    var label: String
    var energy: Color = .ember

    var body: some View {
        Text(label.uppercased())
            .font(ForgeType.micro)
            .foregroundStyle(energy)
            .tracking(ForgeType.eyebrowTracking)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ForgeSectionHeader: View {
    var title: String
    var subtitle: String? = nil
    var energy: Color = .textTertiary

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
            Text(title)
                .font(ForgeType.caption)
                .foregroundStyle(energy)
                .tracking(ForgeType.eyebrowTracking)
                .textCase(.uppercase)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(ForgeType.body)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ForgeSecondaryButton: View {
    var title: String
    var icon: String? = nil
    var accent: Color = .steel
    var action: () -> Void

    var body: some View {
        Button {
            FDS.haptic(.press)
            action()
        } label: {
            HStack(spacing: FDS.Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: ForgeUX.icon, weight: .semibold))
                }
                Text(title)
                    .font(ForgeType.headline)
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: ForgeUX.minTap)
            .padding(.horizontal, FDS.Spacing.lg)
            .background(accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(accent.opacity(0.28), lineWidth: ForgeUX.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct ForgeChip: View {
    var label: String
    var energy: Color = HudChrome.emberSteel
    var selected: Bool = false

    var body: some View {
        Text(label)
            .font(ForgeType.caption)
            .foregroundStyle(selected ? energy : Color.textSecondary)
            .padding(.horizontal, FDS.Spacing.md)
            .padding(.vertical, FDS.Spacing.sm)
            .frame(minHeight: 28)
            .background((selected ? energy : Color.white).opacity(selected ? 0.14 : 0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(energy.opacity(selected ? 0.32 : 0.16), lineWidth: ForgeUX.hairline))
    }
}

struct ForgeStatTile: View {
    var label: String
    var value: String
    var unit: String? = nil
    var energy: Color = .steel

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text(label)
                .font(ForgeType.micro)
                .foregroundStyle(Color.textTertiary)
                .tracking(ForgeType.eyebrowTracking)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.xs) {
                Text(value)
                    .font(ForgeType.metric)
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(ForgeType.caption)
                        .foregroundStyle(energy)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FDS.Spacing.md)
        .hudPlate(energy: energy, compact: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value) \(unit ?? "")")
    }
}

struct ForgeListRow: View {
    var icon: String? = nil
    var iconColor: Color = .ember
    var title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: FDS.Spacing.md) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: ForgeUX.icon, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ForgeType.headline)
                    .foregroundStyle(Color.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(ForgeType.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(ForgeType.metric)
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
            }
        }
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ForgeToast: View {
    var title: String
    var message: String? = nil
    var energy: Color = .vitality

    var body: some View {
        HStack(spacing: FDS.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: ForgeUX.icon, weight: .semibold))
                .foregroundStyle(energy)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ForgeType.headline)
                    .foregroundStyle(Color.textPrimary)
                if let message {
                    Text(message)
                        .font(ForgeType.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(FDS.Spacing.md)
        .hudPlate(energy: energy, compact: true)
        .accessibilityElement(children: .combine)
    }
}

/// Permission / opt-in card. Same Allow + Skip pattern everywhere.
struct ForgePermissionPrompt: View {
    var title: String
    var message: String
    var systemImage: String
    var accent: Color = .steel
    var allowTitle: String = "Allow"
    var skipTitle: String = "Skip"
    var onAllow: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            HStack(spacing: FDS.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                    Text(title)
                        .font(ForgeType.title)
                        .foregroundStyle(Color.textPrimary)
                    Text(message)
                        .font(ForgeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForgePrimaryButton(title: allowTitle, icon: "checkmark", accent: accent, action: onAllow)
            ForgeSecondaryButton(title: skipTitle, accent: HudChrome.emberSteel, action: onSkip)
        }
        .padding(HomeMetrics.cardPadding)
        .hudPlate(energy: accent)
        .accessibilityElement(children: .contain)
    }
}

struct ForgeLoadingState: View {
    var label: String = "Loading"

    var body: some View {
        VStack(spacing: FDS.Spacing.md) {
            ProgressView()
                .tint(Color.ember)
            Text(label)
                .font(ForgeType.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap)
        .accessibilityElement(children: .combine)
    }
}

struct ForgeErrorState: View {
    var title: String = "Couldn’t load that"
    var message: String = "Try again when you’re ready."
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: FDS.Spacing.md) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(HudChrome.emberSteel)
            Text(title)
                .font(ForgeType.title)
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(ForgeType.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                ForgeSecondaryButton(title: "Try again", icon: "arrow.clockwise", action: retry)
            }
        }
        .padding(FDS.Spacing.xl)
        .hudPlate(energy: HudChrome.emberSteel)
    }
}

// MARK: - Inset tile
//
// Nested plate for stats, rows, and fields that sit *inside* a card
// (`forgeGlassCard` / `hudPlate`). One fill, one hairline edge, token radius.

private struct ForgeInsetTile: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: ForgeUX.hairline)
            )
    }
}

extension View {
    func forgeInsetTile(radius: CGFloat = FDS.Radius.md) -> some View {
        modifier(ForgeInsetTile(radius: radius))
    }
}
