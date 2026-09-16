import SwiftUI
import ForgeCore

// MARK: - Sign In (returning athletes) — premium quiet gate

struct AuthSignInView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumAtmosphere(
                    accent: Color.ember.opacity(0.7),
                    secondary: Color(hex: "A9D8FF"),
                    intensity: 0.75
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Welcome back")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .tracking(2.2)
                                .foregroundColor(.textTertiary)
                                .textCase(.uppercase)
                            Text("ARIA is still\nhere.")
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .foregroundColor(.textPrimary)
                                .lineSpacing(2)
                            Text("Pick up with your coach where you left off.")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.textSecondary)
                                .lineSpacing(3)
                        }
                        .padding(.top, 8)
                        .opacity(appeared ? 1 : 0)

                        VStack(spacing: 14) {
                            field(title: "Email", text: $email, contentType: .emailAddress, secure: false)
                            field(title: "Password", text: $password, contentType: .password, secure: true)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.danger)
                        }

                        PremiumPrimaryButton(
                            title: isBusy ? "Signing in…" : "Sign in",
                            enabled: canSubmit,
                            busy: isBusy
                        ) {
                            submitEmail()
                        }

                        Text("Apple and Google sign-in will appear here when connected for this build.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.textTertiary)

                        if ForgeAuthClient.shared.canUseDevOverride {
                            Button {
                                continueAsTester()
                            } label: {
                                Text("Continue as tester")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.steel)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.steel.opacity(0.10))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy)
                            .accessibilityHint("Debug-only local account. Never ships in Release.")
                        }

                        Text("New here? Close and tap Get started on the welcome screen.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.textTertiary)
                            .padding(.bottom, 28)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .onAppear {
            withAnimation(FDS.Spring.hero) { appeared = true }
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 8
    }

    private func field(
        title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        secure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .tracking(0.8)
                .foregroundColor(.textTertiary)
            Group {
                if secure {
                    SecureField(title, text: text)
                        .textContentType(contentType)
                } else {
                    TextField(title, text: text)
                        .textContentType(contentType)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(.textPrimary)
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func continueAsTester() {
        isBusy = true
        errorMessage = nil
        do {
            let session = try ForgeAuthClient.shared.continueAsTester()
            let isNew = !UserDefaults.standard.bool(forKey: "forge.onboarding.completed")
            store.applyAuthSession(session, isNewAccount: isNew)
            dismiss()
        } catch {
            errorMessage = "Tester account is off. It only exists in debug builds pointed at a dev API."
        }
        isBusy = false
    }

    private func submitEmail() {
        guard canSubmit else { return }
        isBusy = true
        errorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        Task {
            do {
                let session = try await ForgeAuthClient.shared.signIn(email: trimmed, password: password)
                let isNew = !UserDefaults.standard.bool(forKey: "forge.onboarding.completed")
                store.applyAuthSession(session, isNewAccount: isNew)
                dismiss()
            } catch ForgeAuthError.cognitoNotConfigured {
                errorMessage = ForgeAuthClient.shared.canUseDevOverride
                    ? "Cognito isn’t configured. Use Continue as tester."
                    : "Sign-in isn’t configured for this build."
            } catch ForgeAuthError.cognitoRejected(let message) {
                errorMessage = message
            } catch {
                errorMessage = "Couldn’t reach the sign-in service."
            }
            isBusy = false
        }
    }
}
