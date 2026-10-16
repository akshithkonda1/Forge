import SwiftUI
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
            case .loseFat: return "figure.walk"
            case .energy: return "bolt.fill"
            case .performance: return "trophy.fill"
            case .recovery: return "heart.fill"
            }
        }

        var accent: Color {
            switch self {
            case .buildMuscle: return Color.ember
            case .loseFat: return Color.amber
            case .energy: return Color.steel
            case .performance: return Color.aurora
            case .recovery: return Color.vitality
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
            PremiumAtmosphere(
                accent: spark.accent,
                secondary: HudChrome.plate,
                intensity: 0.85
            )
            .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.4), value: spark)

            VStack(spacing: 0) {
                topBar

                Group {
                    switch step {
                    case .identity: identityStep
                    case .spark: sparkStep
                    case .account: accountStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(stepTransition)
                .animation(stepAnimation, value: step)
            }

            if celebrate {
                SignUpCelebrationOverlay(name: firstName.trimmingCharacters(in: .whitespaces))
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : FDS.Spring.hero) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                nameFieldFocused = true
            }
        }
        .onChange(of: errorMessage) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    private var stepAnimation: Animation? {
        reduceMotion ? nil : FDS.Spring.page
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: Chrome

    /// One row: a 44 pt back (or close on the first step) and the progress bar.
    private var topBar: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            if step != .identity { navButton }
            progressBar
            if step == .identity { navButton }
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, ForgeLayout.screenTop)
        .padding(.bottom, ForgeLayout.rowGap)
    }

    private var navButton: some View {
        ForgeIconButton(
            systemImage: step == .identity ? "xmark" : "chevron.left",
            accessibilityLabel: step == .identity ? "Close" : "Back",
            tinted: false
        ) {
            goBack()
        }
    }

    private func goBack() {
        if step == .identity {
            dismiss()
        } else {
            withAnimation(stepAnimation) {
                step = SignUpStep(rawValue: step.rawValue - 1) ?? .identity
                showEmailForm = false
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(Color.paper)
                    .frame(width: max(12, geo.size.width * step.progress))
                    .animation(reduceMotion ? nil : FDS.Spring.standard, value: step)
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.title)
        .accessibilityValue("\(step.rawValue + 1) of \(SignUpStep.allCases.count)")
    }

    // MARK: Step 1 — Identity

    private var identityStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ForgeLayout.groupBreak) {
                heroCopy(
                    kicker: "Who are you?",
                    title: "What should ARIA call you?",
                    body: "Preferred name is what you'll hear in coaching. Last name is optional and stays on your profile."
                )

                nameFields

                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    // Quiet trust cues — no vanity Day-0 stats strip
                    Text("About 90 seconds · Private by design")
                        .font(ForgeFont.sans(.footnote))
                        .foregroundColor(.textTertiary)

                    primaryButton(
                        title: "Continue",
                        enabled: trimmedName.count >= 2,
                        icon: "arrow.right"
                    ) {
                        FDS.haptic(.medium)
                        withAnimation(stepAnimation) { step = .spark }
                    }
                }
            }
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.bottom, ForgeLayout.scrollBottomClearance)
        }
    }

    private var nameIsValid: Bool {
        firstName.trimmingCharacters(in: .whitespaces).count >= 2
    }

    private var firstNameStrokeColor: Color {
        if nameIsValid { return Color.paper.opacity(0.35) }
        if nameFieldFocused { return Color.ember.opacity(0.32) }
        return Color.clear
    }

    private var nameFields: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                Text("PREFERRED NAME")
                    .forgeSectionLabel()
                firstNameField
            }

            VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                Text("LAST NAME (OPTIONAL)")
                    .forgeSectionLabel()
                lastNameField
            }

            if nameIsValid {
                nameConfirmation
            }
        }
    }

    private var firstNameField: some View {
        TextField("Maya", text: $firstName)
            .focused($nameFieldFocused)
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .font(FDS.TypeScale.Dynamic.pageTitle)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, ForgeLayout.compactCardPadding)
            .padding(.vertical, ForgeLayout.tilePadding)
            .frame(minHeight: 48)
            .forgeInsetTile(radius: FDS.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                    .strokeBorder(firstNameStrokeColor, lineWidth: 1.5)
            )
            .onChange(of: firstName) { _, _ in
                if firstName.trimmingCharacters(in: .whitespaces).count == 2 {
                    FDS.selectionHaptic()
                }
            }
    }

    private var lastNameField: some View {
        TextField("Optional", text: $lastName)
            .textContentType(.familyName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .font(FDS.TypeScale.Dynamic.title)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, ForgeLayout.compactCardPadding)
            .padding(.vertical, ForgeLayout.tilePadding)
            .frame(minHeight: 48)
            .forgeInsetTile(radius: FDS.Radius.lg)
    }

    private var nameConfirmation: some View {
        HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.vitality)
                .accessibilityHidden(true)
            Text("ARIA will call you \(trimmedName).")
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()
        }
        .transition(.opacity)
    }

    // MARK: Step 2 — Your goal

    private var sparkStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ForgeLayout.groupBreak) {
                heroCopy(
                    kicker: "Nice to meet you, \(trimmedName).",
                    title: "\(trimmedName), what should we start with?",
                    body: "Pick one focus. You can change it later — this just helps today’s session fit you.",
                    kickerIsLabel: false
                )

                VStack(spacing: ForgeLayout.rowGap) {
                    ForEach(SignUpSpark.allCases) { option in
                        sparkRow(option)
                    }
                }

                primaryButton(
                    title: "Continue",
                    enabled: true,
                    icon: "arrow.right"
                ) {
                    FDS.haptic(.medium)
                    withAnimation(stepAnimation) { step = .account }
                }
            }
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.bottom, ForgeLayout.scrollBottomClearance)
        }
    }

    private func sparkRow(_ option: SignUpSpark) -> some View {
        let isSelected = spark == option
        return Button {
            FDS.selectionHaptic()
            withAnimation(reduceMotion ? nil : FDS.Spring.snap) { spark = option }
        } label: {
            sparkRowLabel(option, isSelected: isSelected)
        }
        .buttonStyle(AuthPressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sparkRowLabel(_ option: SignUpSpark, isSelected: Bool) -> some View {
        HStack(spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: option.icon, tint: option.accent)

            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(option.label)
                    .font(HomeType.status)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                Text(option.detail)
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? option.accent : Color.white.opacity(0.2))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, ForgeLayout.compactCardPadding)
        .padding(.vertical, ForgeLayout.tilePadding)
        .frame(minHeight: ForgeUX.minTap)
        .background(isSelected ? option.accent.opacity(0.12) : Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                .strokeBorder(
                    isSelected ? option.accent.opacity(0.28) : Color.white.opacity(0.06),
                    lineWidth: isSelected ? 1 : ForgeUX.hairline
                )
        )
    }

    // MARK: Step 3 — Account

    private var accountStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ForgeLayout.groupBreak) {
                heroCopy(
                    kicker: "YOUR ACCOUNT",
                    title: "Save this so I remember you, \(trimmedName).",
                    body: "One tap. Then a few questions — Apple Health optional — and a first session that fits."
                )

                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    sparkSummary
                    accountActions
                    testerButton
                    legalNote
                }
            }
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.bottom, ForgeLayout.scrollBottomClearance)
        }
    }

    private var sparkSummary: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: spark.icon, tint: spark.accent)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("Starting with")
                    .font(HomeType.micro)
                    .foregroundColor(.textTertiary)
                Text(spark.label)
                    .font(HomeType.status)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .forgeContentCard(tint: spark.accent, padding: ForgeLayout.compactCardPadding)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var accountActions: some View {
        if awaitingCode {
            verifyCodeBlock
        } else if !showEmailForm {
            entryBlock
        } else {
            emailFormBlock
        }
    }

    private var entryBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            errorText

            primaryButton(
                title: "Continue with email",
                enabled: true,
                icon: "envelope.fill"
            ) {
                withAnimation(reduceMotion ? nil : FDS.Spring.snap) { showEmailForm = true }
                FDS.haptic(.light)
            }

            Text("Apple and Google sign-up will appear here when connected for this build.")
                .font(ForgeFont.sans(.footnote))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
                .forgeWrapping()
                .frame(maxWidth: .infinity)
        }
    }

    private var emailFormBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            authField("Email", text: $email, contentType: .emailAddress, secure: false)
            authField("Password (12+ · upper, lower, number, symbol)", text: $password, contentType: .newPassword, secure: true)

            errorText

            primaryButton(
                title: isBusy ? "Creating…" : "Create account",
                enabled: canSubmitEmail && !isBusy,
                icon: "arrow.right"
            ) {
                submitEmail()
            }

            textAction("Back") {
                withAnimation(reduceMotion ? nil : FDS.Spring.snap) { showEmailForm = false }
            }
        }
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(HomeType.body)
                .foregroundColor(.danger)
                .forgeWrapping()
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var legalNote: some View {
        Text("By continuing you get lifestyle and fitness coaching, not medical care. ARIA is not a doctor. For emergencies, call 911.")
            .font(ForgeFont.sans(.footnote))
            .foregroundColor(.textTertiary)
            .multilineTextAlignment(.center)
            .forgeWrapping()
            .frame(maxWidth: .infinity)
    }

    // MARK: Shared UI

    private var trimmedName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitEmail: Bool {
        email.contains("@") && CognitoPasswordPolicy.isValid(password)
    }

    private var verifyCodeBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text("We emailed a confirmation code to \(codeDestination.isEmpty ? email : codeDestination).")
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()
            authField("Confirmation code", text: $confirmCode, contentType: .oneTimeCode, secure: false)
            errorText
            primaryButton(
                title: isBusy ? "Confirming…" : "Confirm email",
                enabled: confirmCode.trimmingCharacters(in: .whitespaces).count >= 4 && !isBusy,
                icon: "checkmark"
            ) {
                submitConfirmation()
            }
            textAction("Use a different email") {
                awaitingCode = false
                confirmCode = ""
            }
        }
    }

    /// Eyebrow, title and body. A kicker that is a sentence ("Nice to meet
    /// you, Maya.") reads as a status line, not an uppercase label.
    private func heroCopy(
        kicker: String,
        title: String,
        body: String,
        kickerIsLabel: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                heroKicker(kicker, isLabel: kickerIsLabel)
                Text(title)
                    .font(FDS.TypeScale.Dynamic.pageTitle)
                    .foregroundColor(.textPrimary)
                    .minimumScaleFactor(0.85)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(body)
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()
        }
    }

    @ViewBuilder
    private func heroKicker(_ kicker: String, isLabel: Bool) -> some View {
        if isLabel {
            Text(kicker)
                .forgeSectionLabel()
        } else {
            Text(kicker)
                .font(HomeType.status)
                .foregroundColor(.textSecondary)
        }
    }

    private func textAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            FDS.haptic(.press)
            action()
        } label: {
            Text(title)
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(
        title: String,
        enabled: Bool,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        PremiumPrimaryButton(
            title: title,
            icon: icon,
            enabled: enabled,
            busy: isBusy && enabled
        ) {
            action()
        }
    }

    private func authField(
        _ title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        secure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text(title)
                .forgeSectionLabel()
                .forgeWrapping()
            authFieldInput(title, text: text, contentType: contentType, secure: secure)
        }
    }

    private func authFieldInput(
        _ title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        secure: Bool
    ) -> some View {
        let keyboard: UIKeyboardType = contentType == .oneTimeCode ? .numberPad : .emailAddress
        return Group {
            if secure {
                SecureField(title, text: text)
                    .textContentType(contentType)
            } else {
                TextField(title, text: text)
                    .textContentType(contentType)
                    .textInputAutocapitalization(.never)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
            }
        }
        .font(ForgeFont.sans(.body))
        .foregroundColor(.textPrimary)
        .padding(.horizontal, ForgeLayout.compactCardPadding)
        .padding(.vertical, ForgeLayout.tilePadding)
        .frame(minHeight: 48)
        .forgeInsetTile(radius: FDS.Radius.md)
    }

    // MARK: Actions

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
        withAnimation(reduceMotion ? nil : FDS.Spring.hero) { celebrate = true }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: ForgeLayout.sectionGap) {
                ZStack {
                    PremiumPresenceBloom(size: 140, accent: .ember, frost: HudChrome.plate, live: false)
                    AuroraOrbView(
                        state: .idle,
                        amplitude: 0.5,
                        mood: .energized,
                        size: 88,
                        followPresence: false
                    )
                }
                .accessibilityHidden(true)

                VStack(spacing: ForgeLayout.pairGap) {
                    Text("Welcome")
                        .forgeSectionLabel()
                    Text(name.isEmpty ? "Let’s learn how you live." : "Nice to meet you, \(name).")
                        .font(FDS.TypeScale.Dynamic.pageTitle)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                }

                Text("ARIA will ask a few questions so today’s session fits you.")
                    .font(HomeType.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
            }
            .padding(.horizontal, ForgeLayout.screenInset)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : FDS.Spring.hero) {
                scale = 1
                opacity = 1
            }
        }
    }
}
