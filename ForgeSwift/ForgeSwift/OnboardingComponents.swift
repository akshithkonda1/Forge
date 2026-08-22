import SwiftUI

struct ForgeAmbientBackground: View {
    let step: Int
    @State private var phase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.background, Color(hex: "140A06").opacity(0.78), Color.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [routeColor.opacity(0.18), routeColor.opacity(0.05), .clear],
                center: UnitPoint(x: 0.32, y: 0.18),
                startRadius: 10,
                endRadius: 520
            )
            .blur(radius: 44)

            if !reduceMotion {
                RadialGradient(
                    colors: [Color.ember.opacity(0.09), .clear],
                    center: UnitPoint(x: 0.5 + 0.24 * cos(phase), y: 0.48 + 0.18 * sin(phase)),
                    startRadius: 0,
                    endRadius: 360
                )
                .blur(radius: 60)
                .onAppear {
                    withAnimation(.linear(duration: FDS.Duration.ambient).repeatForever(autoreverses: false)) {
                        phase = .pi * 2
                    }
                }
            }
        }
    }

    private var routeColor: Color {
        switch step {
        case 0, 1, 2: return Color(hex: "A855F7")
        case 3: return .steel
        case 7, 8, 9: return Color(hex: "22C55E")
        case 10: return .warning
        default: return .ember
        }
    }
}

struct ForgeSectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var accentColor: Color = .ember
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Capsule().fill(accentColor).frame(width: appeared ? 22 : 8, height: 3)
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(2.8)
                    .foregroundColor(accentColor)
            }
            .opacity(appeared ? 1 : 0)

            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(LinearGradient(
                    colors: [.white, Color.white.opacity(0.76)],
                    startPoint: .top, endPoint: .bottom
                ))
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)

            Text(subtitle)
                .font(.body)
                .foregroundColor(.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
        }
        .animation(FDS.Spring.hero, value: appeared)
        .onAppear { appeared = true }
    }
}

struct ForgeTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(focused ? .ember : .textMuted)
                .frame(width: 22)
            ZStack(alignment: .leading) {
                if text.isEmpty { Text(placeholder).foregroundColor(.textMuted) }
                if isSecure {
                    SecureField("", text: $text).focused($focused)
                } else {
                    TextField("", text: $text)
                        .focused($focused)
                        .keyboardType(keyboardType)
                }
            }
            .font(.body)
            .foregroundColor(.textPrimary)
            .tint(.ember)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .background(focused ? Color.ember.opacity(0.05) : Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                .stroke(focused ? Color.ember.opacity(0.60) : Color.borderColor, lineWidth: focused ? 1.4 : 0.7)
        )
    }
}

struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
    }
}

struct GenderSelectionCard: View {
    let gender: Gender
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
            FDS.selectionHaptic()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.ember.opacity(0.16) : Color.surfaceElevated)
                        .frame(width: 48, height: 48)
                    if isSelected {
                        Circle().stroke(Color.ember.opacity(0.4), lineWidth: 1.5).frame(width: 48, height: 48)
                    }
                    Image(systemName: gender.icon)
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? .ember : .textSecondary)
                }
                Text(gender.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isSelected ? .ember : .textPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.ember : Color.borderColor, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color.ember).frame(width: 12, height: 12)
                    }
                }
            }
            .padding(16)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(isSelected ? Color.ember.opacity(0.5) : Color.borderColor, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TogglePill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isSelected ? .ember : .textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color.ember.opacity(0.13) : Color.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color.ember.opacity(0.55) : Color.borderColor,
                        lineWidth: isSelected ? 1.4 : 0.7
                    )
                )
        }
        .buttonStyle(.plain)
        .animation(FDS.Spring.snap, value: isSelected)
    }
}
