import SwiftUI
import ForgeCore

/// Onboarding step that captures biological sex to auto-configure cycle health features.
/// Female/intersex → cycle tracking auto-enabled.
/// Male → optional educational cycle mode prompt shown inline.
struct BiologicalSexStepView: View {
    @Bindable var coordinator: OnboardingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsEducationalPrompt: Bool {
        coordinator.profile.biologicalSex == .male && coordinator.showingEducationalCyclePrompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            VStack(spacing: ForgeLayout.tileGap) {
                ForEach(BiologicalSex.allCases) { sex in
                    optionRow(for: sex)
                }
            }

            if showsEducationalPrompt {
                educationalPrompt
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .animation(reduceMotion ? nil : ForgeMotion.smooth, value: coordinator.showingEducationalCyclePrompt)
    }

    // MARK: - Option row

    private func optionRow(for sex: BiologicalSex) -> some View {
        let selected = coordinator.profile.biologicalSex == sex
        return Button {
            ForgeHaptics.play(.selection)
            coordinator.selectBiologicalSex(sex)
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                Text(sex.label)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: ForgeUX.icon, weight: .semibold))
                    .foregroundStyle(selected ? Color.ember : Color.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, ForgeLayout.tilePadding)
            .padding(.vertical, ForgeLayout.rowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap)
            .background(rowFill(selected: selected))
            .clipShape(RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
                    .stroke(rowStroke(selected: selected), lineWidth: ForgeUX.stroke)
            )
            .contentShape(RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sex.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func rowFill(selected: Bool) -> Color {
        selected ? Color.ember.opacity(0.14) : Color.white.opacity(0.045)
    }

    private func rowStroke(selected: Bool) -> Color {
        selected ? Color.ember.opacity(0.32) : Color.white.opacity(0.08)
    }

    // MARK: - Educational cycle prompt

    private var educationalPrompt: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text("Cycle Health education? Useful if you support a partner, daughter, or family.")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()

            ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
                ForgeSecondaryButton(title: "Yes, enable it", accent: .ember) {
                    coordinator.selectEducationalCycleMode(true)
                }
                ForgeSecondaryButton(title: "No thanks", accent: .textSecondary) {
                    coordinator.selectEducationalCycleMode(false)
                }
            }
        }
    }
}
