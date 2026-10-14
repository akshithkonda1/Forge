import SwiftUI

/// Onboarding step that captures biological sex to auto-configure cycle health features.
/// Female/intersex → cycle tracking auto-enabled.
/// Male → optional educational cycle mode prompt shown inline.
struct BiologicalSexStepView: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: FDS.Spacing.md) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(BiologicalSex.allCases) { sex in
                    let selected = coordinator.profile.biologicalSex == sex
                    Button { coordinator.selectBiologicalSex(sex) } label: {
                        Text(sex.label)
                            .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                            .foregroundColor(selected ? .white : .textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FDS.Spacing.lg)
                            .background(selected ? Color.ember.opacity(0.85) : Color.background.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                                    .stroke(selected ? Color.ember.opacity(0.9) : Color.white.opacity(0.06), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if coordinator.profile.biologicalSex == .male && coordinator.showingEducationalCyclePrompt {
                VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                    Text("Cycle Health education? Useful if you support a partner, daughter, or family.")
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundColor(.textTertiary)
                    HStack(spacing: FDS.Spacing.sm) {
                        Button { coordinator.selectEducationalCycleMode(true) } label: {
                            Text("Yes, enable it")
                                .font(FDS.TypeScale.Dynamic.caption)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, FDS.Spacing.md)
                                .background(Color.ember.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Button { coordinator.selectEducationalCycleMode(false) } label: {
                            Text("No thanks")
                                .font(FDS.TypeScale.Dynamic.caption)
                                .foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, FDS.Spacing.md)
                                .background(Color.background.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(FDS.Spring.page, value: coordinator.showingEducationalCyclePrompt)
    }
}
