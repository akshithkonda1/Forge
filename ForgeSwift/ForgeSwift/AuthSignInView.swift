import SwiftUI
import ForgeCore

// MARK: - Sign In (returning athletes) — premium quiet gate

struct AuthSignInView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var appeared = false
    @FocusState private var focusedField: SignInFocus?

    private enum SignInFocus: Hashable {
        case email
        case password
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumAtmosphere(
                    accent: Color.ember.opacity(0.7),
                    secondary: HudChrome.plate,
                    intensity: 0.75
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ForgeLayout.groupBreak) {
                        heroCopy
                            .premiumEntrance(index: 0, appeared: appeared)

                        formBlock
                            .premiumEntrance(index: 1, appeared: appeared)

                        primaryGroup
                            .premiumEntrance(index: 2, appeared: appeared)

                        testerButton

                        noteGroup
                    }
                    .padding(.horizontal, ForgeLayout.screenInset)
                    .padding(.top, ForgeLayout.screenTop)
                    .padding(.bottom, ForgeLayout.scrollBottomClearance)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : ForgeMotion.gentle) { appeared = true }
        }
        .onChange(of: errorMessage) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    // MARK: Blocks

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("Welcome back")
                    .forgeSectionLabel()
                Text("ARIA is still here.")
                    .font(FDS.TypeScale.Dynamic.pageTitle)
                    .foregroundColor(.textPrimary)
                    .minimumScaleFactor(0.85)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("Pick up with your coach where you left off.")
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()
        }
    }

    private var formBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                field(
                    title: "Email",
                    text: $email,
                    contentType: .emailAddress,
                    secure: false,
                    focus: .email
                )
                field(
                    title: "Password",
                    text: $password,
                    contentType: .password,
                    secure: true,
                    focus: .password
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(HomeType.body)
                    .foregroundColor(.danger)
                    .forgeWrapping()
            }
        }
    }

    private var primaryGroup: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            PremiumPrimaryButton(
                title: isBusy ? "Signing in…" : "Sign in",
                enabled: canSubmit,
                busy: isBusy
            ) {
                submitEmail()
            }

            Text("Apple and Google sign-in will appear here when connected for this build.")
                .font(ForgeFont.sans(.footnote))
                .foregroundColor(.textTertiary)
                .forgeWrapping()
        }
    }

    @ViewBuilder
    private var testerButton: some View {
        // Keep until Cognito is paired — remove when real auth ships.
        if ForgeAuthClient.shared.canUseDevOverride {
            ForgeSecondaryButton(title: "Continue as tester", accent: .steel) {
                continueAsTester()
            }
            .disabled(isBusy)
            .accessibilityHint("Debug tester login until Cognito is paired. Never ships in Release.")
        }
    }

    private var noteGroup: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            if !ForgeAuthClient.shared.config.cognitoConfigured,
               ForgeAuthClient.shared.canUseDevOverride {
                Text("Cognito isn’t paired yet — use Continue as tester for device work.")
                    .font(ForgeFont.sans(.footnote))
                    .foregroundColor(.textTertiary)
                    .forgeWrapping()
            }

            Text("New here? Close and tap Get started on the welcome screen.")
                .font(ForgeFont.sans(.footnote))
                .foregroundColor(.textTertiary)
                .forgeWrapping()
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 8
    }

    private func field(
        title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        secure: Bool,
        focus: SignInFocus
    ) -> some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text(title)
                .forgeSectionLabel()
            fieldInput(title: title, text: text, contentType: contentType, secure: secure, focus: focus)
        }
    }

    @ViewBuilder
    private func fieldInput(
        title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        secure: Bool,
        focus: SignInFocus
    ) -> some View {
        let isFocused = focusedField == focus
        Group {
            if secure {
                SecureField(title, text: text)
                    .textContentType(contentType)
                    .focused($focusedField, equals: focus)
                    .submitLabel(.go)
            } else {
                TextField(title, text: text)
                    .textContentType(contentType)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: focus)
                    .submitLabel(.next)
            }
        }
        .onSubmit {
            if focus == .email {
                focusedField = .password
            } else {
                submitEmail()
            }
        }
        .font(ForgeFont.sans(.body))
        .foregroundColor(.textPrimary)
        .padding(.horizontal, ForgeLayout.compactCardPadding)
        .padding(.vertical, ForgeLayout.tilePadding)
        .frame(minHeight: 48)
        .forgeInsetTile(radius: FDS.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                .strokeBorder(isFocused ? Color.ember.opacity(0.32) : Color.clear, lineWidth: 1)
        )
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
