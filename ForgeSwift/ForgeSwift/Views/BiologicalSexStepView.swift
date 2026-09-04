import SwiftUI

/// Onboarding step that captures biological sex to auto-configure cycle health features.
/// Female/intersex → cycle tracking auto-enabled.
/// Male → optional educational cycle mode prompt shown inline.
struct BiologicalSexStepView: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(BiologicalSex.allCases) { sex in
                    let selected = coordinator.profile.biologicalSex == sex
                    Button { coordinator.selectBiologicalSex(sex) } label: {
                        Text(sex.label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(selected ? .white : .textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selected ? Color.ember.opacity(0.85) : Color.background.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selected ? Color.ember.opacity(0.9) : Color.white.opacity(0.06), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if coordinator.profile.biologicalSex == .male && coordinator.showingEducationalCyclePrompt {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cycle Health education? Useful if you support a partner, daughter, or family.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                    HStack(spacing: 8) {
                        Button { coordinator.selectEducationalCycleMode(true) } label: {
                            Text("Yes, enable it")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.ember.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Button { coordinator.selectEducationalCycleMode(false) } label: {
                            Text("No thanks")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.background.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
