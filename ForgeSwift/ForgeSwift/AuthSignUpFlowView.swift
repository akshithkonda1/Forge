import SwiftUI
import AuthenticationServices
import ForgeCore

// MARK: - Immersive Sign Up

/// Multi-beat identity → goal → account. Designed to feel like meeting a coach who will remember you.
struct AuthSignUpFlowView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: SignUpStep = .identity
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var spark: SignUpSpark = .buildMuscle
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showEmailForm = false
    @State private var awaitingCode = false
    @State private var confirmCode = ""
    @State private var pendingPassword = ""
    @State private var codeDestination = ""
    @State private var celebrate = false
    @State private var appeared = false
    @FocusState private var nameFieldFocused: Bool

    enum SignUpStep: Int, CaseIterable {
        case identity, spark, account

        var title: String {
            switch self {
            case .identity: return "Your name"
            case .spark: return "Your goal"
            case .account: return "Your account"
            }
        }

        var progress: Double {
            Double(rawValue + 1) / Double(SignUpStep.allCases.count)
        }
    }

    enum SignUpSpark: String, CaseIterable, Identifiable {
        case buildMuscle, loseFat, energy, performance, recovery

        var id: String { rawValue }

        var label: String {
            switch self {
            case .buildMuscle: return "Build muscle"
            case .loseFat: return "Lose fat"
            case .energy: return "More energy"
            case .performance: return "Perform better"
            case .recovery: return "Recover smarter"
            }
        }

        var detail: String {
            switch self {
            case .buildMuscle: return "Progressive strength + protein"
            case .loseFat: return "Readiness-aware deficit"
            case .energy: return "Sleep + lifestyle load"
            case .performance: return "Peak windows from signal"
            case .recovery: return "HRV, cycle, wind-down"
            }
        }

        var icon: String {
            switch self {
            case .buildMuscle: return "dumbbell.fill"
            case .loseFat: return "flame.fill"
            case .energy: return "bolt.fill"
            case .performance: return "trophy.fill"
            case .recovery: return "heart.fill"
            }
        }

        var accentHex: String {
            switch self {
            case .buildMuscle: return "FF5A00"
            case .loseFat: return "F59E0B"
            case .energy: return "38BDF8"
            case .performance: return "A855F7"
            case .recovery: return "22C55E"
            }
        }

        var onboardingGoal: OnboardingFitnessGoal {
            switch self {
            case .buildMuscle: return .buildMuscle
            case .loseFat: return .loseWeight
            case .energy: return .betterSleep
            case .performance: return .athleticPerformance
            case .recovery: return .reducStress
            }
        }
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            RadialGradient(
                colors: [Color(hex: spark.accentHex).opacity(0.2), Color.ember.opacity(0.08), .clear],
                center: UnitPoint(x: 0.5, y: 0.15),
                startRadius: 10,
                endRadius: 400
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: spark)

            VStack(spacing: 0) {
                topBar
                progressBar
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                Group {
                    switch step {
                    case .identity: identityStep
                    case .spark: sparkStep
                    case .account: accountStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(FDS.Spring.page, value: step)
            }

            if celebrate {
                SignUpCelebrationOverlay(name: firstName.trimmingCharacters(in: .whitespaces))
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .onAppear {
            withAnimation(FDS.Spring.hero) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                nameFieldFocused = true
            }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button {
                FDS.haptic(.light)
                if step == .identity {
                    dismiss()
                } else {
                    withAnimation(FDS.Spring.page) {
                        step = SignUpStep(rawValue: step.rawValue - 1) ?? .identity
                        showEmailForm = false
                    }
                }
            } label: {
                Image(systemName: step == .identity ? "xmark" : "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Color.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("WELCOME")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.ember)
                Text(step.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
            }

            Spacer()

            Text("\(step.rawValue + 1) of \(SignUpStep.allCases.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .frame(minWidth: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(FDS.Gradient.ember)
                    .frame(width: max(12, geo.size.width * step.progress))
                    .shadow(color: Color.ember.opacity(0.5), radius: 6, y: 0)
                    .animation(FDS.Spring.standard, value: step)
            }
        }
        .frame(height: 6)
    }

    // MARK: Step 1 — Identity

    private var identityStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                heroCopy(
                    kicker: "Who are you?",
                    title: "What should ARIA\ncall you?",
                    body: "Preferred name is what you'll hear in coaching. Last name is optional and stays on your profile."
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("PREFERRED NAME")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(.textTertiary)

                    TextField("Maya", text: $firstName)
                        .focused($nameFieldFocused)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .padding(18)
                        .background(Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    firstName.trimmingCharacters(in: .whitespaces).count >= 2
                                        ? Color.ember.opacity(0.55)
                                        : Color.white.opacity(0.08),
                                    lineWidth: 1.5
                                )
                        )
                        .onChange(of: firstName) { _, _ in
                            if firstName.trimmingCharacters(in: .whitespaces).count == 2 {
                                FDS.selectionHaptic()
                            }
                        }

                    Text("LAST NAME (OPTIONAL)")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(.textTertiary)
                        .padding(.top, 8)

                    TextField("Optional", text: $lastName)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .padding(16)
                        .background(Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    if firstName.trimmingCharacters(in: .whitespaces).count >= 2 {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(hex: "22C55E"))
                            Text("ARIA will call you \(trimmedName).")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }

                // Social proof strip
                HStack(spacing: 10) {
                    miniStat("90s", "setup")
                    miniStat("Live", "readiness")
                    miniStat("Private", "cycle data")
                }

                Spacer(minLength: 24)

                primaryButton(
                    title: "Claim my name",
                    enabled: trimmedName.count >= 2,
                    icon: "arrow.right"
                ) {
                    FDS.haptic(.medium)
                    withAnimation(FDS.Spring.page) { step = .spark }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
    }

    // MARK: Step 2 — Your goal

    private var sparkStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                heroCopy(
                    kicker: "Nice to meet you, \(trimmedName).",
                    title: "\(trimmedName), what should\nwe start with?",
                    body: "Pick one focus. You can change it later — this just helps today’s session fit you."
                )

                VStack(spacing: 10) {
                    ForEach(SignUpSpark.allCases) { option in
                        Button {
                            FDS.selectionHaptic()
                            withAnimation(FDS.Spring.snap) { spark = option }
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: option.accentHex).opacity(0.18))
                                        .frame(width: 46, height: 46)
                                    Image(systemName: option.icon)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Color(hex: option.accentHex))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.label)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.textPrimary)
                                    Text(option.detail)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.textTertiary)
                                }
                                Spacer()
                                Image(systemName: spark == option ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(
                                        spark == option
                                            ? Color(hex: option.accentHex)
                                            : Color.white.opacity(0.2)
                                    )
                            }
                            .padding(14)
                            .background(
                                spark == option
                                    ? Color(hex: option.accentHex).opacity(0.12)
                                    : Color.surfaceElevated
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        spark == option
                                            ? Color(hex: option.accentHex).opacity(0.55)
                                            : Color.white.opacity(0.06),
                                        lineWidth: spark == option ? 1.5 : 1
                                    )
                            )
                        }
                        .buttonStyle(AuthPressButtonStyle())
                    }
                }

                primaryButton(
                    title: "Continue",
                    enabled: true,
                    icon: "arrow.right"
                ) {
                    FDS.haptic(.medium)
                    withAnimation(FDS.Spring.page) { step = .account }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
    }

    // MARK: Step 3 — Account

    private var accountStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                heroCopy(
                    kicker: "YOUR ACCOUNT",
                    title: "Save this so I remember you,\n\(trimmedName).",
                    body: "One tap. Then a few questions — Apple Health optional — and a first session that fits."
                )

                HStack(spacing: 12) {
                    Image(systemName: spark.icon)
                        .foregroundStyle(Color(hex: spark.accentHex))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: spark.accentHex).opacity(0.15))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Starting with")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.textTertiary)
                        Text(spark.label)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                }
                .padding(14)
                .forgeGlassCard(cornerRadius: 16, accent: Color(hex: spark.accentHex))

                if awaitingCode {
                    verifyCodeBlock
                } else if !showEmailForm {
                    VStack(spacing: 10) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        SignInWithAppleButton(.signUp) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleApple(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button {
                            errorMessage = ForgeAuthClient.shared.canUseDevOverride
                                ? "Google isn’t wired. Use email, or Continue as tester on this debug build."
                                : "Google sign-up isn’t connected yet. Use email."
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

                        Button {
                            withAnimation(FDS.Spring.snap) { showEmailForm = true }
                            FDS.haptic(.light)
                        } label: {
                            Text("Use email instead")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(spacing: 12) {
                        authField("Email", text: $email, contentType: .emailAddress, secure: false)
                        authField("Password (12+ · upper, lower, number, symbol)", text: $password, contentType: .newPassword, secure: true)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.danger)
                        }

                        primaryButton(
                            title: isBusy ? "Forging…" : "Create account · enter Forge",
                            enabled: canSubmitEmail && !isBusy,
                            icon: "flame.fill"
                        ) {
                            submitEmail()
                        }

                        Button {
                            withAnimation { showEmailForm = false }
                        } label: {
                            Text("Back to Apple / Google")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if ForgeAuthClient.shared.canUseDevOverride {
                    Button {
                        continueAsTester()
                    } label: {
                        Text("Continue as tester")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.steel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.steel.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .accessibilityHint("Debug-only local account. Never ships in Release.")
                }

                Text("By continuing you get lifestyle and fitness coaching, not medical diagnosis or care. ARIA is a lifestyle based fitness coach, not a doctor and cannot help in that way. If you are looking for urgent medical help, please call 911 or visit your local hospital or physician.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
    }

    // MARK: Shared UI

    private var trimmedName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitEmail: Bool {
        email.contains("@") && CognitoPasswordPolicy.isValid(password)
    }

    private var verifyCodeBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("We emailed a confirmation code to \(codeDestination.isEmpty ? email : codeDestination).")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
            authField("Confirmation code", text: $confirmCode, contentType: .oneTimeCode, secure: false)
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.danger)
            }
            primaryButton(
                title: isBusy ? "Confirming…" : "Confirm email · enter Forge",
                enabled: confirmCode.trimmingCharacters(in: .whitespaces).count >= 4 && !isBusy,
                icon: "checkmark"
            ) {
                submitConfirmation()
            }
            Button {
                awaitingCode = false
                confirmCode = ""
            } label: {
                Text("Use a different email")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func heroCopy(kicker: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kicker)
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundColor(.ember)
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color.white.opacity(0.78)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineSpacing(2)
            Text(body)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func primaryButton(
        title: String,
        enabled: Bool,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 17)
            .background {
                if enabled {
                    ZStack {
                        FDS.Gradient.ember
                        LinearGradient.premiumChrome
                    }
                } else {
                    Color.surfaceElevated
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: enabled ? Color.ember.opacity(0.4) : .clear, radius: 16, y: 8)
        }
        .buttonStyle(AuthPressButtonStyle())
        .disabled(!enabled)
        .padding(.top, 8)
    }

    private func authField(
        _ title: String,
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

    // MARK: Actions

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            errorMessage = ForgeAuthClient.shared.canUseDevOverride
                ? "Sign in with Apple isn’t wired. Use email, or Continue as tester on this debug build."
                : "Sign in with Apple isn’t connected yet. Use email."
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func continueAsTester() {
        isBusy = true
        errorMessage = nil
        do {
            seedDraft(name: trimmedName)
            let session = try ForgeAuthClient.shared.continueAsTester()
            complete(with: session)
        } catch {
            errorMessage = "Tester account is off. It only exists in debug builds pointed at a dev API."
            isBusy = false
        }
    }

    private func submitEmail() {
        guard canSubmitEmail else { return }
        isBusy = true
        errorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        Task {
            do {
                guard ForgeAuthClient.shared.config.cognitoConfigured else {
                    errorMessage = ForgeAuthClient.shared.canUseDevOverride
                        ? "Cognito isn’t configured. Use Continue as tester."
                        : "Sign-up isn’t configured for this build."
                    isBusy = false
                    return
                }
                let result = try await ForgeAuthClient.shared.signUp(
                    email: trimmed,
                    password: password,
                    displayName: trimmedName
                )
                if result.userConfirmed {
                    let session = try await ForgeAuthClient.shared.signIn(email: trimmed, password: password)
                    seedDraft(name: trimmedName)
                    complete(with: session)
                } else {
                    pendingPassword = password
                    codeDestination = result.codeDestination ?? trimmed
                    awaitingCode = true
                    isBusy = false
                }
            } catch ForgeAuthError.cognitoNotConfigured {
                errorMessage = ForgeAuthClient.shared.canUseDevOverride
                    ? "Cognito isn’t configured. Use Continue as tester."
                    : "Sign-up isn’t configured for this build."
                isBusy = false
            } catch ForgeAuthError.cognitoRejected(let message) {
                errorMessage = message
                isBusy = false
            } catch {
                errorMessage = "Couldn’t reach the sign-up service."
                isBusy = false
            }
        }
    }

    private func submitConfirmation() {
        let code = confirmCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count >= 4 else { return }
        isBusy = true
        errorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        Task {
            do {
                try await ForgeAuthClient.shared.confirmSignUp(email: trimmed, code: code)
                let session = try await ForgeAuthClient.shared.signIn(email: trimmed, password: pendingPassword)
                seedDraft(name: trimmedName)
                complete(with: session)
            } catch ForgeAuthError.cognitoRejected(let message) {
                errorMessage = message
                isBusy = false
            } catch {
                errorMessage = "Couldn’t confirm that code. Try again."
                isBusy = false
            }
        }
    }

    private func seedDraft(name: String) {
        var draft = store.tempOnboardingProfile
        draft.name = name
        draft.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.fitnessGoals.contains(spark.onboardingGoal) {
            draft.fitnessGoals = [spark.onboardingGoal]
        }
        store.tempOnboardingProfile = draft
    }

    private func complete(with session: ForgeAuthSession) {
        withAnimation(FDS.Spring.hero) { celebrate = true }
        FDS.notificationHaptic(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.35 : 1.15)) {
            store.applyAuthSession(session, isNewAccount: true)
            if !trimmedName.isEmpty {
                store.userProfile.name = [trimmedName, lastName.trimmingCharacters(in: .whitespacesAndNewlines)]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            let core = spark.onboardingGoal.coreGoal
            if !store.userProfile.fitnessGoals.contains(core) {
                store.userProfile.fitnessGoals = [core]
            }
            isBusy = false
            dismiss()
        }
    }
}

// MARK: - Celebration

private struct SignUpCelebrationOverlay: View {
    let name: String
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.ember.opacity(0.25))
                        .frame(width: 120, height: 120)
                        .blur(radius: 16)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(FDS.Gradient.ember)
                }
                Text("WELCOME")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.ember)
                Text(name.isEmpty ? "Let’s learn how you live." : "Nice to meet you, \(name).")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                Text("ARIA will ask a few questions so today’s session fits you.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                scale = 1
                opacity = 1
            }
        }
    }
}
