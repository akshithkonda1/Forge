import SwiftUI

/// Onboarding step that captures biological sex to auto-configure cycle health features.
/// Female/intersex → cycle tracking auto-enabled.
/// Male → optional educational cycle mode prompt shown inline.
struct BiologicalSexStepView: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 8) {
            ForEach(BiologicalSex.allCases) { sex in
                Button { coordinator.selectBiologicalSex(sex) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sex.label)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.textPrimary)
                        }
                        Spacer()
                        if coordinator.profile.biologicalSex == sex {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.ember)
                                .font(.subheadline)
                        } else {
                            Image(systemName: "circle")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.textMuted)
                        }
                    }
                    .padding(14)
                    .background(
                        coordinator.profile.biologicalSex == sex
                            ? Color.ember.opacity(0.12)
                            : Color.surface
                    )
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                            .stroke(
                                coordinator.profile.biologicalSex == sex
                                    ? Color.ember.opacity(0.45)
                                    : Color.borderColor,
                                lineWidth: 0.7
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            // Educational cycle mode prompt — shown inline after male is selected
            if coordinator.profile.biologicalSex == .male && coordinator.showingEducationalCyclePrompt {
                VStack(spacing: 8) {
                    Button { coordinator.selectEducationalCycleMode(true) } label: {
                        HStack {
                            Image(systemName: "heart.text.square")
                                .foregroundColor(.ember)
                            Text("Yes, enable it")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.textPrimary)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.ember.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                                .stroke(Color.ember.opacity(0.4), lineWidth: 0.7)
                        )
                    }
                    .buttonStyle(.plain)

                    Button { coordinator.selectEducationalCycleMode(false) } label: {
                        Text("No thanks")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(FDS.Spring.page, value: coordinator.showingEducationalCyclePrompt)
    }
}
