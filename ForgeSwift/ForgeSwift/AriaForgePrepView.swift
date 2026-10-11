import SwiftUI

/// Full-screen console boot after the interview. Ember orb, editorial copy,
/// a quiet fill — never a "Loading 47%" HUD, and never spoken ARIA.
struct AriaForgePrepView: View {
    var coordinator: OnboardingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AriaSpokenMute.mutedKey) private var spokenMuted = true

    var body: some View {
        let stage = coordinator.prepStage
        let progress = coordinator.prepProgress

        ZStack {
            Color.background.ignoresSafeArea()
            ForgeAmbientBackground(step: 3)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    AriaSpokenMuteButton()
                }
                .padding(.horizontal, FDS.Spacing.xl)
                .padding(.top, FDS.Spacing.sm)

                Spacer()

                VStack(spacing: FDS.Spacing.xl) {
                    AuroraOrbView(
                        state: stage == .ready ? .idle : .processing,
                        amplitude: reduceMotion ? 0.18 : 0.42,
                        mood: .focused,
                        size: 132,
                        followPresence: false
                    )
                    .accessibilityHidden(true)

                    VStack(spacing: FDS.Spacing.md) {
                        Text(stage.eyebrow.uppercased())
                            .font(FDS.TypeScale.Dynamic.micro)
                            .tracking(1.6)
                            .foregroundColor(.textTertiary)

                        Text(stage.headline)
                            .font(FDS.TypeScale.display(28))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                            .animation(reduceMotion ? nil : FDS.Spring.standard, value: stage)

                        Text(stage.detail(healthConnected: coordinator.prepHealthConnected))
                            .font(FDS.TypeScale.Dynamic.body)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, FDS.Spacing.xl)
                            .animation(reduceMotion ? nil : FDS.Spring.standard, value: stage)
                    }
                }

                Spacer()

                VStack(spacing: FDS.Spacing.lg) {
                    prepFill(progress: progress)
                        .padding(.horizontal, 48)

                    Text(stage.footer(progress: progress))
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundColor(.textTertiary)

                    if spokenMuted {
                        Text("Voice is muted")
                            .font(FDS.TypeScale.Dynamic.micro)
                            .foregroundColor(.textTertiary)
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prepping Forge")
        .accessibilityValue(stage.headline)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func prepFill(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(Color.paper)
                    .frame(width: max(6, geo.size.width * progress))
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress)
        .accessibilityHidden(true)
    }
}
