import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var coordinator = OnboardingCoordinator()

    var body: some View {
        @Bindable var coordinator = coordinator

        ZStack {
            Color.background.ignoresSafeArea()
            ForgeAmbientBackground(step: coordinator.step.rawValue)
                .ignoresSafeArea()

            if coordinator.showAgeBlocked {
                AgeBlockedView { coordinator.resetAfterAgeBlock() }
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                AriaInterviewLayout(coordinator: coordinator) {
                    coordinator.complete(in: store)
                }
            }

            #if DEBUG
            DevSkipButton(coordinator: coordinator)
            #endif
        }
        .animation(FDS.Spring.hero, value: coordinator.showAgeBlocked)
        .onAppear { coordinator.startIfNeeded() }
    }
}

private struct AgeBlockedView: View {
    let onReset: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.danger)
            Text("Access Restricted")
                .font(.title.weight(.bold))
                .foregroundColor(.textPrimary)
            Text("FORGE requires users to be at least 13 years old.")
                .font(.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(action: onReset) {
                Text("Review birthday")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
            }
            .padding(.horizontal, FDS.Spacing.xl)
            .padding(.bottom, 40)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { appeared = true }
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
                    Button("Skip All →") { coordinator.devSkipToEnd(in: store) }
                        .font(.caption.weight(.black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.ember)
                        .clipShape(Capsule())
                } else {
                    Button("DEV") { withAnimation(FDS.Spring.snap) { expanded = true } }
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.warning)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, FDS.Spacing.xl)
            .padding(.top, 8)
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
