import SwiftUI
import ForgeCore

/// Full-screen first boot after the interview. Ember orb, editorial copy,
/// a quiet fill — never a "Loading 47%" readout, and never spoken ARIA.
struct AriaForgePrepView: View {
    var coordinator: OnboardingCoordinator
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(AriaSpokenMute.mutedKey) private var spokenMuted = true

    private var orbSize: CGFloat { typeSize.isAccessibilitySize ? 96 : 132 }

    var body: some View {
        let stage = coordinator.prepStage
        let progress = coordinator.prepProgress

        ZStack {
            Color.background.ignoresSafeArea()
            ForgeAmbientBackground(step: 3)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                // Flexible frame so the first layout has height. A ScrollView
                // that hugs zero collapsed this stack into Color.background
                // (#09090B) — the launch gate's 87% rgb(9,9,11) blank.
                ScrollView(showsIndicators: false) {
                    content(stage: stage, progress: progress)
                        .frame(maxWidth: .infinity, minHeight: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    // The mute control sits outside the combined status group so VoiceOver
    // can still reach and toggle it.
    private var topBar: some View {
        HStack {
            Spacer()
            AriaSpokenMuteButton()
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, FDS.Spacing.sm)
    }

    private func content(stage: AriaForgePrep.Stage, progress: Double) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: ForgeLayout.sectionGap)

            VStack(spacing: FDS.Spacing.xl) {
                // Static ember disc. The nest Canvas compiles a Metal
                // pipeline on the main thread; that compile plus Home
                // pushed prep_wedge sample 0 to 2.88s (limit 2.0s).
                Circle()
                    .fill(Color.ember)
                    .frame(width: orbSize, height: orbSize)
                    .accessibilityHidden(true)

                statusCopy(stage: stage)
            }

            Spacer(minLength: ForgeLayout.sectionGap)

            progressBlock(stage: stage, progress: progress)
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.bottom, FDS.Spacing.xl)
    }

    private func statusCopy(stage: AriaForgePrep.Stage) -> some View {
        VStack(spacing: ForgeLayout.pairGap) {
            Text(stage.eyebrow)
                .forgeSectionLabel()
                .multilineTextAlignment(.center)

            Text(stage.headline)
                .font(ForgeType.pageTitle)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .forgeWrapping()

            Text(stage.detail(healthConnected: coordinator.prepHealthConnected))
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .forgeWrapping()
                .padding(.top, ForgeLayout.pairGap)
                .padding(.horizontal, FDS.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prepping Forge")
        .accessibilityValue(stage.headline)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func progressBlock(stage: AriaForgePrep.Stage, progress: Double) -> some View {
        VStack(spacing: ForgeLayout.rowGap) {
            ForgeProgressBar(fraction: progress, tint: Color.paper, height: 4)
                .padding(.horizontal, FDS.Spacing.xl)
                .accessibilityHidden(true)

            Text(stage.footer(progress: progress))
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .forgeWrapping()

            if spokenMuted {
                Text("Voice is muted")
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}
