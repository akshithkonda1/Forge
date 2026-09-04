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

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Forge")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(ForgeAppInfo.fullVersion)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.textTertiary)
                    }

                    Text("Training, recovery, cycle health, and lifestyle coaching that runs on your own data. ARIA reasons over what you allow it to see, and nothing more.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)

                    aboutRow("lock.shield.fill", "Local-first", "Your profile, cycle logs, and photos live on this device. Cycle data is coaching-only and is never sold.")
                    aboutRow("heart.text.square.fill", "Apple Health", "Read and write is scoped to what you approve in the Health app, and can be revoked there at any time.")
                    aboutRow("sparkles", "ARIA", "Adaptive lifestyle coach. Compound interest: enough small changes and life is slightly different. Over time you see it and appreciate it. Not a new personality. Not clinical care.")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SUPPORT")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundColor(.textTertiary)
                        Text(ForgeAppInfo.supportEmail)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.ember)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.ember)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func aboutRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(.ember)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ForgeTermsAndConditionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Forge is built around local-first health and lifestyle data. You and only you have access to your personal data. Forge never sees, sells, rents, or shares your data in any way whatsoever.")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineSpacing(3)

                    VStack(alignment: .leading, spacing: 12) {
                        legalPoint("Your Apple Health, cycle, sexual health, workout, sleep, nutrition, and lifestyle data stays under your control.")
                        legalPoint("Forge uses Apple Health permissions only for features you enable and only through Apple's permission system.")
                        legalPoint("If you allow it, Forge may read allergies, medications, conditions, immunizations, lab results, and procedures from Apple Health. Clinical notes and insurance coverage are never requested.")
                        legalPoint("Forge does not sell personal information, health information, or lifestyle data.")
                        legalPoint("You can revoke Health permissions at any time in the iOS Settings app or Apple Health.")
                    }
                }
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 15))
                .foregroundColor(.success)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
        }
    }
}
