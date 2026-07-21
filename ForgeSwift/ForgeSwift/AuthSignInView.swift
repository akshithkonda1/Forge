import SwiftUI
import AuthenticationServices

// MARK: - Sign In

struct AuthSignInView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var mode: Mode = .signIn

    enum Mode: String, CaseIterable {
        case signIn = "Sign in"
        case signUp = "Create account"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(mode == .signIn ? "Welcome back" : "Join Forge")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .padding(.top, 8)

                    Text(
                        mode == .signIn
                            ? "Sign in to continue with HealthKit, ARIA, and your plan."
                            : "Create an account, then complete a short onboarding."
                    )
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    // Social (simulated local session — production would wire ASAuthorization / Google)
                    VStack(spacing: 10) {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleApple(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            completeSocialSignIn(provider: "google", displayName: "Athlete")
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 20))
                                Text("Continue with Google")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.borderColor, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Rectangle().fill(Color.borderColor).frame(height: 1)
                        Text("or email")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textMuted)
                        Rectangle().fill(Color.borderColor).frame(height: 1)
                    }

                    VStack(spacing: 12) {
                        field(title: "Email", text: $email, contentType: .emailAddress, secure: false)
                        field(title: "Password", text: $password, contentType: .password, secure: true)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.danger)
                    }

                    Button {
                        submitEmail()
                    } label: {
                        HStack {
                            if isBusy { ProgressView().tint(.white) }
                            Text(mode == .signIn ? "Sign in with email" : "Create account with email")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSubmit ? FDS.Gradient.ember : LinearGradient(colors: [Color.surfaceElevated], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || isBusy)

                    Text("After sign-in, HealthKit connects during onboarding (or Settings if you already finished setup).")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.ember)
                }
            }
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6
    }

    private func field(
        title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        secure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
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
            .font(.system(size: 16))
            .foregroundColor(.textPrimary)
            .padding(14)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            let name: String
            if let cred = auth.credential as? ASAuthorizationAppleIDCredential {
                let parts = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }
                name = parts.isEmpty ? "Athlete" : parts.joined(separator: " ")
            } else {
                name = "Athlete"
            }
            completeSocialSignIn(provider: "apple", displayName: name)
        case .failure(let error):
            // User cancelled is silent; other failures surface.
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func completeSocialSignIn(provider: String, displayName: String) {
        isBusy = true
        errorMessage = nil
        store.authenticate(
            provider: provider,
            email: "\(provider)@forge.local",
            displayName: displayName,
            isNewAccount: mode == .signUp
        )
        isBusy = false
        dismiss()
    }

    private func submitEmail() {
        guard canSubmit else { return }
        isBusy = true
        errorMessage = nil
        let local = email.split(separator: "@").first.map(String.init) ?? "Athlete"
        store.authenticate(
            provider: "email",
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            displayName: local.capitalized,
            isNewAccount: mode == .signUp
        )
        isBusy = false
        dismiss()
    }
}
