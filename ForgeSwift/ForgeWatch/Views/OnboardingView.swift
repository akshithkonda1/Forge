import SwiftUI
import ForgeCore

// MARK: - OnboardingView
//
// Three short pages, shown exactly once: what Forge on the wrist is, the
// philosophy that shapes every interaction, and the permissions ask
// framed honestly (what's read, where it stays). No marketing crescendo —
// the calm starts here.

struct OnboardingView: View {
    @Environment(WatchHealthKitManager.self) private var health
    @Environment(ContextEngine.self) private var contextEngine

    @State private var page = 0
    @State private var requestingAccess = false

    var body: some View {
        TabView(selection: $page) {
            welcomePage.tag(0)
            philosophyPage.tag(1)
            permissionsPage.tag(2)
        }
        .tabViewStyle(.verticalPage)
    }

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: ForgeDS.Spacing.md) {
                AuroraOrbWatch(accent: ForgePalette.steel, size: 64, intensity: 0.6)
                Text("Forge, on your wrist")
                    .font(ForgeType.title(17))
                    .foregroundStyle(ForgePalette.textPrimary)
                Text("Readiness at a glance, workouts with honest coaching, and short resets that fit between the things you already do.")
                    .font(.system(size: 12))
                    .foregroundStyle(ForgePalette.textSecondary)
                    .multilineTextAlignment(.center)
                Text("Scroll for more")
                    .font(.system(size: 10))
                    .foregroundStyle(ForgePalette.textTertiary)
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Scroll down to continue onboarding.")
    }

    private var philosophyPage: some View {
        ScrollView {
            VStack(spacing: ForgeDS.Spacing.md) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(ForgePalette.jade)
                Text("You can live your best life and still be healthy.")
                    .font(ForgeType.title(15))
                    .foregroundStyle(ForgePalette.textPrimary)
                    .multilineTextAlignment(.center)
                Text("No streaks to break, no guilt, no all-or-nothing. Forge reads your signals and suggests the smallest thing that genuinely helps.")
                    .font(.system(size: 12))
                    .foregroundStyle(ForgePalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var permissionsPage: some View {
        ScrollView {
            VStack(spacing: ForgeDS.Spacing.md) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(ForgePalette.steel)
                Text("Your data stays yours")
                    .font(ForgeType.title(15))
                    .foregroundStyle(ForgePalette.textPrimary)
                Text("Forge reads sleep, heart, and activity from Health to compute readiness on this watch. Nothing leaves the device unless you connect deeper coaching.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ForgePalette.textSecondary)
                    .multilineTextAlignment(.center)

                HapticButton(haptic: .success) {
                    requestingAccess = true
                    Task {
                        await health.requestAuthorization()
                        await health.refreshAll()
                        contextEngine.completeOnboarding()
                    }
                } label: {
                    if requestingAccess {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Connect Health & begin")
                            .font(ForgeType.caption(13))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ForgePalette.steel.opacity(0.85))
                .disabled(requestingAccess)
                .accessibilityLabel("Connect Health and begin")
                .accessibilityHint("Shows the Health permission sheet, then opens Forge.")

                Button("Not now — look around first") {
                    contextEngine.completeOnboarding()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(ForgePalette.textTertiary)
                .accessibilityHint("Skips permissions. Forge will show honest empty states until Health is connected.")
            }
            .padding(.horizontal, 4)
        }
    }
}
