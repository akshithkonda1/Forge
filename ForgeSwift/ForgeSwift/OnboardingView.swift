import SwiftUI
import ForgeCore

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var coordinator = OnboardingCoordinator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var coordinator = coordinator

        ZStack {
            ForgeAmbientBackground(step: coordinator.step.rawValue)
                .ignoresSafeArea()

            if coordinator.showAgeBlocked {
                AgeBlockedView { coordinator.resetAfterAgeBlock() }
                    .forgeTransition(.scale(scale: 0.96).combined(with: .opacity))
            } else if coordinator.isPrepping || store.needsForgePrep {
                AriaForgePrepView(coordinator: coordinator)
                    .transition(.opacity)
            } else {
                AriaInterviewLayout(coordinator: coordinator) {
                    coordinator.complete(in: store)
                }
            }

            #if DEBUG
            DevSkipButton(coordinator: coordinator)
            #endif
        }
        .animation(reduceMotion ? nil : ForgeMotion.gentle, value: coordinator.showAgeBlocked)
        .animation(reduceMotion ? nil : ForgeMotion.gentle, value: coordinator.isPrepping)
        .onAppear { coordinator.startIfNeeded(in: store) }
        .onDisappear { coordinator.stopInterviewVoice() }
    }
}

private struct AgeBlockedView: View {
    let onReset: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            ForgeEmptyStateCard(
                icon: "lock.shield.fill",
                title: "Access Restricted",
                message: "FORGE requires users to be at least 13 years old.",
                accent: .steel,
                cta: "Review birthday",
                action: onReset
            )
            .forgeScreenInsets(top: ForgeLayout.screenTop)
        }
    }
}

#if DEBUG
private struct DevSkipButton: View {
    var coordinator: OnboardingCoordinator
    @EnvironmentObject private var store: AppStore
    @State private var expanded = false

    var body: some View {
        VStack {
            HStack {
                Spacer()
                if expanded {
                    if coordinator.isPrepping {
                        Button("Skip wait →") { coordinator.skipPrepHoldForDebug() }
                            .font(HomeType.label)
                            .foregroundColor(.white)
                            .padding(.horizontal, FDS.Spacing.lg)
                            .padding(.vertical, FDS.Spacing.sm)
                            .background(Color.ember)
                            .clipShape(Capsule())
                    } else {
                        Button("Skip All →") { coordinator.devSkipToEnd(in: store) }
                            .font(HomeType.label)
                            .foregroundColor(.white)
                            .padding(.horizontal, FDS.Spacing.lg)
                            .padding(.vertical, FDS.Spacing.sm)
                            .background(Color.ember)
                            .clipShape(Capsule())
                    }
                } else {
                    Button("DEV") { withForgeMotion(ForgeMotion.snappy) { expanded = true } }
                        .font(HomeType.micro)
                        .foregroundColor(.black)
                        .padding(.horizontal, FDS.Spacing.sm)
                        .padding(.vertical, FDS.Spacing.xs)
                        .background(Color.warning)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.top, FDS.Spacing.sm)
            Spacer()
        }
    }
}
#endif

#Preview("ARIA Onboarding") {
    OnboardingView()
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}

#Preview("Intro logo") {
    ZStack {
        Color.background.ignoresSafeArea()
        IntroComposer(coordinator: OnboardingCoordinator())
    }
    .preferredColorScheme(.dark)
}
