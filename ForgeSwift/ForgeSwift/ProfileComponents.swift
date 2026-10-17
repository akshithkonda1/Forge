import SwiftUI
import UIKit
import ForgeCore

struct ForgeSkeletonBlock: View {
    var height: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.surfaceElevated)
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

struct ForgeEmptyState: View {
    var icon: String
    var title: String
    var message: String
    var cta: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ForgeEmptyStateCard(
            icon: icon,
            title: title,
            message: message,
            accent: .ember,
            cta: cta,
            action: action
        )
    }
}

/// Grouped settings list as one tessera. Rows pad themselves; the card does not.
struct SectionCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .forgeContentCard(padding: 0)
    }
}

struct SettingsRow<Trailing: View>: View {
    private let icon: String?
    private let iconColor: Color?
    private let label: String
    private let trailingText: String?
    private let showChevron: Bool
    private let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    init(
        icon: String? = nil,
        iconColor: Color? = nil,
        label: String,
        trailingText: String? = nil,
        showChevron: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.trailingText = trailingText
        self.showChevron = showChevron
        self.trailing = trailing()
    }

    private var stacksLabelAndValue: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            iconWell
            labelAndValue
            trailing
            chevron
        }
        .padding(.horizontal, FDS.Spacing.lg)
        .padding(.vertical, FDS.Spacing.sm)
        .frame(minHeight: ForgeUX.minTap)
    }

    @ViewBuilder
    private var iconWell: some View {
        if let icon = icon {
            let tint = iconColor ?? Color.ember
            ZStack {
                RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: ForgeUX.icon, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)
        }
    }

    private var labelText: some View {
        Text(label)
            .font(HomeType.status)
            .foregroundStyle(Color.textPrimary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func trailingValue(_ text: String) -> some View {
        Text(text)
            .font(ForgeType.caption)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(stacksLabelAndValue ? 2 : 1)
            .truncationMode(.tail)
            .layoutPriority(-1)
            .frame(maxWidth: .infinity, alignment: stacksLabelAndValue ? .leading : .trailing)
    }

    /// Label with its trailing value. At accessibility sizes the value drops
    /// under the label instead of squeezing it.
    private var labelAndValue: some View {
        let layout = stacksLabelAndValue
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ForgeLayout.pairGap))
            : AnyLayout(HStackLayout(spacing: FDS.Spacing.md))
        return layout {
            labelText
            if let text = trailingText {
                trailingValue(text)
            } else if !stacksLabelAndValue {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chevron: some View {
        if showChevron {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(
        icon: String? = nil,
        iconColor: Color? = nil,
        label: String,
        trailingText: String? = nil,
        showChevron: Bool = false
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            label: label,
            trailingText: trailingText,
            showChevron: showChevron
        ) { EmptyView() }
    }
}

struct ForgeToggle: View {
    @Binding var isOn: Bool
    /// Names the switch for VoiceOver when the surrounding row does not.
    var label: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func toggle() {
        ForgeHaptics.play(.selection)
        if AriaMemoryAccess.shouldAnimate(reduceMotion: reduceMotion) {
            withForgeMotion(ForgeMotion.snappy) { isOn.toggle() }
        } else {
            isOn.toggle()
        }
    }

    private var track: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.ember : Color.borderLight)
                .frame(width: 48, height: 28)
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.2), radius: 2)
                .padding(3)
        }
        .forgeTapOutset(vertical: 8, horizontal: 0)
    }

    private var button: some View {
        Button(action: toggle) { track }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(isOn ? "On" : "Off")
    }

    @ViewBuilder
    var body: some View {
        if let label {
            button.accessibilityLabel(label)
        } else {
            button
        }
    }
}

/// Range switch for Progress. A shared segmented control: 44 pt segments,
/// tinted selection, no glow.
struct TimeRangePicker: View {
    @Binding var selection: ProgressPageView.TimeRange

    private var options: [ForgeSegmentOption<ProgressPageView.TimeRange>] {
        ProgressPageView.TimeRange.allCases.map {
            ForgeSegmentOption(value: $0, title: $0.rawValue)
        }
    }

    var body: some View {
        ForgeSegmentedControl(options, selection: $selection, accent: .ember, bleed: 0)
    }
}
