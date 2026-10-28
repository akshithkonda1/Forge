import SwiftUI
import ForgeCore

/// Single source of truth for build metadata. "v1.0" used to be typed into the settings
/// row by hand, so it stayed at 1.0 no matter what shipped.
enum ForgeAppInfo {
    static let supportEmail = "support@forge.health"

    static var shortVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v" + (version ?? "1.0")
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var fullVersion: String { "\(shortVersion) (\(buildNumber))" }
}

struct ForgeAboutView: View {
    @Environment(\.dismiss) private var dismiss
    /// Long-press the version to open the hidden Reliability screen (tester
    /// tool, every build: TestFlight builds are Release).
    @State private var showReliability = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                ForgeScreenStack(top: ForgeLayout.screenTop) {
                    ForgePageHeader(title: "Forge", subtitle: ForgeAppInfo.fullVersion)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.8) {
                            ForgeHaptics.play(.press)
                            showReliability = true
                        }
                        .accessibilityAction(named: "Reliability") {
                            showReliability = true
                        }

                    Text("Training, recovery, cycle health, and lifestyle coaching that runs on your own data. ARIA reasons over what you allow it to see, and nothing more.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()

                    principlesCard
                    supportCard
                }
            }
            .forgeScreenBackground(accent: .ember)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showReliability) {
                ReliabilityView()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.ember)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var principlesCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            aboutRow("lock.shield.fill", "Local-first", "Your profile, cycle logs, and photos live on this device. Cycle data is coaching-only and is never sold.")
            aboutRow("heart.text.square.fill", "Apple Health", "Read and write is scoped to what you approve in the Health app, and can be revoked there at any time.")
            aboutRow("text.bubble", "ARIA", "Adaptive lifestyle coach. Compound interest: enough small changes and life is slightly different. Over time you see it and appreciate it. Not a new personality. Not clinical care.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Support")
            Text(ForgeAppInfo.supportEmail)
                .font(HomeType.status)
                .foregroundStyle(Color.ember)
                .textSelection(.enabled)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
    }

    private func aboutRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: icon, tint: .ember)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(body)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ForgeTermsAndConditionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                ForgeScreenStack(top: ForgeLayout.screenTop) {
                    Text("Forge is built around local-first health and lifestyle data. You and only you have access to your personal data. Forge never sees, sells, rents, or shares your data in any way whatsoever.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()

                    VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                        legalPoint("Your Apple Health, cycle, sexual health, workout, sleep, nutrition, and lifestyle data stays under your control.")
                        legalPoint("Forge uses Apple Health permissions only for features you enable and only through Apple's permission system.")
                        legalPoint("If you allow it, Forge may read allergies, medications, conditions, immunizations, lab results, and procedures from Apple Health. Clinical notes and insurance coverage are never requested.")
                        legalPoint("Forge does not sell personal information, health information, or lifestyle data.")
                        legalPoint("You can revoke Health permissions at any time in the iOS Settings app or Apple Health.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeContentCard()
                }
            }
            .forgeScreenBackground(accent: .ember)
            .navigationTitle("Terms & Conditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func legalPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.success)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(text)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
