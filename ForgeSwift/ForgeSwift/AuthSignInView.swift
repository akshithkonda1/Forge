import SwiftUI
import AuthenticationServices

// MARK: - Sign In (returning athletes)

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
                Color.background.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.ember.opacity(0.14), Color.steel.opacity(0.05), .clear],
                    center: UnitPoint(x: 0.5, y: 0.0),
                    startRadius: 10,
                    endRadius: 360
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WELCOME BACK")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.ember)
                            Text("Your forge is\nwaiting.")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, Color.white.opacity(0.78)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            Text("Pick up readiness, ARIA, and your streak where you left off.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.top, 8)
                        .opacity(appeared ? 1 : 0)

                        VStack(spacing: 10) {
                            SignInWithAppleButton(.signIn) { request in
                                request.requestedScopes = [.fullName, .email]
                            } onCompletion: { result in
                                handleApple(result)
                            }
                            .signInWithAppleButtonStyle(.white)
                            .frame(height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Button {
                                completeSocialSignIn(provider: "google", displayName: "Athlete")
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "g.circle.fill")
                                        .font(.system(size: 20))
                                    Text("Continue with Google")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.borderColor, lineWidth: 1)
                                )
                            }
                            .buttonStyle(AuthPressButtonStyle())
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
                                Text(isBusy ? "Entering…" : "Enter Forge")
                                    .font(.system(size: 16, weight: .bold))
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 17)
                            .background {
                                if canSubmit {
                                    FDS.Gradient.ember
                                } else {
                                    Color.surfaceElevated
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: canSubmit ? Color.ember.opacity(0.4) : .clear, radius: 16, y: 8)
                        }
                        .buttonStyle(AuthPressButtonStyle())
                        .disabled(!canSubmit || isBusy)

                        Text("New here? Close and tap Start forging on the welcome screen.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textTertiary)
                            .padding(.bottom, 28)
                    }
                    .padding(.horizontal, 22)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.ember)
                }
            }
        }
        .onAppear {
            withAnimation(FDS.Spring.hero) { appeared = true }
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
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
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
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.textPrimary)
            .padding(15)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            isNewAccount: false
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
            isNewAccount: false
        )
        isBusy = false
        dismiss()
    }
}
