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

struct SectionCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .forgeGlassCard(cornerRadius: FDS.Radius.lg)
    }
}

struct SettingsRow<Trailing: View>: View {
    private let icon: String?
    private let iconColor: Color?
    private let label: String
    private let trailingText: String?
    private let showChevron: Bool
    private let trailing: Trailing

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

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                ZStack {
                    RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous)
                        .fill((iconColor ?? Color.ember).opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: ForgeUX.icon, weight: .semibold))
                        .foregroundColor(iconColor ?? .ember)
                }
            }
            Text(label)
                .font(ForgeType.headline)
                .foregroundColor(.textPrimary)
            Spacer()
            if let t = trailingText {
                Text(t)
                    .font(ForgeType.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 160, alignment: .trailing)
            }
            trailing
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: ForgeUX.minTap)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            if AriaMemoryAccess.shouldAnimate(reduceMotion: reduceMotion) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { isOn.toggle() }
            } else {
                isOn.toggle()
            }
        }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.ember : Color.borderLight)
                    .frame(width: 48, height: 28)
                    .shadow(color: isOn ? Color.ember.opacity(0.45) : .clear, radius: 8, y: 2)
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.2), radius: 2)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct TimeRangePicker: View {
    @Binding var selection: ProgressPageView.TimeRange
    @Namespace private var pickerAnimation

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProgressPageView.TimeRange.allCases, id: \.self) { range in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = range
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                }) {
                    ZStack {
                        if selection == range {
                            Capsule()
                                .fill(Color.ember)
                                .matchedGeometryEffect(id: "picker", in: pickerAnimation)
                                .shadow(color: Color.ember.opacity(0.3), radius: 8, y: 2)
                        }

                        Text(range.rawValue)
                            .font(.system(size: 13, weight: selection == range ? .semibold : .medium))
                            .foregroundColor(selection == range ? .white : .textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .forgeInnerWell(cornerRadius: 100)
    }
}
