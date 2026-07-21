import SwiftUI
import AuthenticationServices

// MARK: - Immersive Sign Up (Day 0 forge)

/// Multi-beat identity → goal → account forge. Designed to feel like leveling into Forge.
struct AuthSignUpFlowView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: SignUpStep = .identity
    @State private var firstName = ""
    @State private var spark: SignUpSpark = .buildMuscle
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showEmailForm = false
    @State private var celebrate = false
    @State private var appeared = false
    @State private var nameFocused = false
    @FocusState private var nameFieldFocused: Bool

    enum SignUpStep: Int, CaseIterable {
        case identity, spark, account

        var title: String {
            switch self {
            case .identity: return "Identity"
            case .spark: return "First quest"
            case .account: return "Forge key"
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
                Text("DAY 0")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2)
                    .foregroundColor(.ember)
                Text(step.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
            }

            Spacer()

            // XP chip
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                Text("\(step.rawValue * 40)/120 XP")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color(hex: "F59E0B"))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(hex: "F59E0B").opacity(0.12))
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
                    kicker: "WHO ARE YOU?",
                    title: "What should ARIA\ncall you?",
                    body: "First names only. This is the start of a relationship — not a form."
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR NAME")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(.textTertiary)

                    TextField("e.g. Maya", text: $firstName)
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

                    if firstName.trimmingCharacters(in: .whitespaces).count >= 2 {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(hex: "22C55E"))
                            Text("Nice. \(trimmedName) — locked for ARIA.")
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

    // MARK: Step 2 — First quest

    private var sparkStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                heroCopy(
                    kicker: "FIRST QUEST",
                    title: "\(trimmedName), what are\nwe forging first?",
                    body: "Pick one north star. You can change it later — this unlocks a sharper day-one plan."
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
                    title: "Lock quest · +\(40) XP",
                    enabled: true,
                    icon: "flag.fill"
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
                    kicker: "FORGE KEY",
                    title: "Save your progress,\n\(trimmedName).",
                    body: "One tap. Then ARIA interviews you — HealthKit optional — and builds plan one."
                )

                // Quest recap
                HStack(spacing: 12) {
                    Image(systemName: spark.icon)
                        .foregroundStyle(Color(hex: spark.accentHex))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: spark.accentHex).opacity(0.15))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quest locked")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.textTertiary)
                        Text(spark.label)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                    Text("+80 XP")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Color(hex: "F59E0B"))
                }
                .padding(14)
                .forgeGlassCard(cornerRadius: 16, accent: Color(hex: spark.accentHex))

                if !showEmailForm {
                    VStack(spacing: 10) {
                        SignInWithAppleButton(.signUp) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleApple(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button {
                            finish(provider: "google", email: "google@forge.local")
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
                        authField("Password (6+)", text: $password, contentType: .newPassword, secure: true)

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

                Text("By continuing you get lifestyle coaching only — not medical diagnosis or care.")
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
        email.contains("@") && password.count >= 6
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
        case .success(let auth):
            var name = trimmedName
            if let cred = auth.credential as? ASAuthorizationAppleIDCredential {
                let parts = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }
                if name.isEmpty, !parts.isEmpty {
                    name = parts.joined(separator: " ")
                }
            }
            finish(provider: "apple", email: "apple@forge.local", displayName: name)
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submitEmail() {
        guard canSubmitEmail else { return }
        finish(
            provider: "email",
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            displayName: trimmedName
        )
    }

    private func finish(provider: String, email: String, displayName: String? = nil) {
        isBusy = true
        errorMessage = nil
        let name = (displayName ?? trimmedName).trimmingCharacters(in: .whitespacesAndNewlines)
        // Seed goal into temp onboarding profile so ARIA interview starts partially filled.
        var draft = store.tempOnboardingProfile
        draft.name = name
        if !draft.fitnessGoals.contains(spark.onboardingGoal) {
            draft.fitnessGoals = [spark.onboardingGoal]
        }
        store.tempOnboardingProfile = draft

        withAnimation(FDS.Spring.hero) { celebrate = true }
        FDS.notificationHaptic(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.35 : 1.15)) {
            store.authenticate(
                provider: provider,
                email: email,
                displayName: name.isEmpty ? "Athlete" : name,
                isNewAccount: true
            )
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
                Text("FORGED")
                    .font(.system(size: 13, weight: .black))
                    .tracking(4)
                    .foregroundColor(.ember)
                Text(name.isEmpty ? "Welcome" : "Welcome, \(name)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("ARIA is preparing your interview…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                Text("+120 XP · Day 0 complete")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "F59E0B"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "F59E0B").opacity(0.15))
                    .clipShape(Capsule())
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
