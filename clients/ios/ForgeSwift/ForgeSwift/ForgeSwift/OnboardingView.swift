import SwiftUI
import AuthenticationServices

// MARK: - LinearGradient Extensions

extension LinearGradient {
    static let ember = LinearGradient(
        colors: [Color.ember, Color.ember.opacity(0.82)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let deepEmber = LinearGradient(
        colors: [Color(hex: "1A0800"), Color(hex: "0A0A0A")],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Authentication State

enum AuthenticationState { case unauthenticated, authenticated }

// MARK: - Onboarding-scoped enums (separate from core Models.swift types)

enum OnboardingFitnessGoal: String, CaseIterable, Identifiable {
    case loseWeight, buildMuscle, improveEndurance, increaseFlexibility,
         betterSleep, reducStress, athleticPerformance, generalHealth
    var id: String { rawValue }
    var label: String {
        switch self {
        case .loseWeight:           return "Lose Weight"
        case .buildMuscle:          return "Build Muscle"
        case .improveEndurance:     return "Endurance"
        case .increaseFlexibility:  return "Flexibility"
        case .betterSleep:          return "Better Sleep"
        case .reducStress:          return "Reduce Stress"
        case .athleticPerformance:  return "Athletic Performance"
        case .generalHealth:        return "General Health"
        }
    }
    var icon: String {
        switch self {
        case .loseWeight:           return "arrow.down.circle.fill"
        case .buildMuscle:          return "dumbbell.fill"
        case .improveEndurance:     return "figure.run"
        case .increaseFlexibility:  return "figure.flexibility"
        case .betterSleep:          return "moon.zzz.fill"
        case .reducStress:          return "brain.head.profile"
        case .athleticPerformance:  return "trophy.fill"
        case .generalHealth:        return "heart.fill"
        }
    }
    var coreGoal: UserFitnessGoal {
        switch self {
        case .loseWeight:           return .loseFat
        case .buildMuscle:          return .buildMuscle
        case .improveEndurance:     return .improveEndurance
        case .athleticPerformance:  return .athleticPerformance
        default:                    return .generalFitness
        }
    }
}

enum OnboardingWorkoutType: String, CaseIterable, Identifiable {
    case weightlifting, hiit, running, cycling, yoga, swimming,
         boxing, calisthenics, crossfit, pilates, climbing, martial_arts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weightlifting:  return "Weightlifting"
        case .hiit:           return "HIIT"
        case .running:        return "Running"
        case .cycling:        return "Cycling"
        case .yoga:           return "Yoga"
        case .swimming:       return "Swimming"
        case .boxing:         return "Boxing"
        case .calisthenics:   return "Calisthenics"
        case .crossfit:       return "CrossFit"
        case .pilates:        return "Pilates"
        case .climbing:       return "Climbing"
        case .martial_arts:   return "Martial Arts"
        }
    }
    var coreType: WorkoutType {
        switch self {
        case .weightlifting, .calisthenics, .crossfit: return .strength
        case .hiit:                                    return .hiit
        case .running, .cycling, .swimming:            return .cardio
        case .yoga, .pilates:                          return .yoga
        default:                                       return .strength
        }
    }
}

enum OnboardingCoachingStyle: String, CaseIterable, Identifiable {
    case driven, balanced, supportive, scientist, elite
    var id: String { rawValue }
    var label: String {
        switch self {
        case .driven:    return "Driven"
        case .balanced:  return "Balanced"
        case .supportive: return "Supportive"
        case .scientist: return "The Scientist"
        case .elite:     return "Elite"
        }
    }
    var description: String {
        switch self {
        case .driven:    return "No excuses. Intense accountability. ARIA pushes you past every limit."
        case .balanced:  return "Science-backed intensity with room to breathe. Optimal for long-term results."
        case .supportive: return "Encouraging, patient coaching that celebrates every win, big or small."
        case .scientist: return "Data-first coaching with deep analytics and periodization theory."
        case .elite:     return "Designed for high performers. Readiness, output, and adaptation — tracked."
        }
    }
    var icon: String {
        switch self {
        case .driven:    return "bolt.fill"
        case .balanced:  return "scale.3d"
        case .supportive: return "heart.fill"
        case .scientist: return "waveform.path.ecg"
        case .elite:     return "crown.fill"
        }
    }
    var color: Color {
        switch self {
        case .driven:    return .ember
        case .balanced:  return .steel
        case .supportive: return Color(hex: "22C55E")
        case .scientist: return Color(hex: "A855F7")
        case .elite:     return Color(hex: "F59E0B")
        }
    }
    var coreStyle: CoachingStyle {
        switch self {
        case .driven:    return .pushHard
        case .balanced:  return .balanced
        case .supportive: return .patient
        case .scientist: return .dataDriven
        case .elite:     return .ultraElite
        }
    }
}

// MARK: - OnboardingProfile (staging model)

struct OnboardingProfile {
    var name:              String                   = ""
    var birthday:          Date                     = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    var gender:            Gender                   = .preferNotToSay
    var heightCm:          Double                   = 170
    var weightKg:          Double                   = 70
    var fitnessGoals:      [OnboardingFitnessGoal]  = []
    var experienceLevel:   ExperienceLevel          = .intermediate
    var preferredWorkouts: [OnboardingWorkoutType]  = []
    var coachingStyle:     OnboardingCoachingStyle  = .balanced

    func toCoreProfile() -> UserProfile {
        UserProfile(
            name:              name,
            gender:            gender,
            fitnessGoals:      fitnessGoals.map { $0.coreGoal },
            experienceLevel:   experienceLevel,
            preferredWorkouts: Array(Set(preferredWorkouts.map { $0.coreType })),
            coachingStyle:     coachingStyle.coreStyle,
            connectedDevices:  [],
            weeklySchedule:    [],
            age:               Calendar.current.dateComponents([.year], from: birthday, to: Date()).year,
            weight:            weightKg,
            height:            heightCm
        )
    }
}

// MARK: - AppStore staging extension

extension AppStore {
    private static var _tempOnboardingProfile: OnboardingProfile?
    var tempOnboardingProfile: OnboardingProfile {
        get { Self._tempOnboardingProfile ?? OnboardingProfile() }
        set { Self._tempOnboardingProfile = newValue }
    }
}

// MARK: - Root

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var coordinator = OnboardingCoordinator()

    var body: some View {
        @Bindable var coordinator = coordinator

        ZStack {
            Color.background.ignoresSafeArea()
            ForgeAmbientBackground(step: coordinator.route.rawValue)
                .ignoresSafeArea()

            if coordinator.showAgeBlocked {
                AgeBlockedView {
                    coordinator.resetAfterAgeBlock()
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                routeView(coordinator: coordinator)
                    .id(coordinator.route)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }

            // Dev bypass — only compiled in debug builds
            #if DEBUG
            DevSkipButton(coordinator: coordinator)
            #endif
        }
        .animation(FDS.Spring.page, value: coordinator.route)
        .animation(FDS.Spring.hero, value: coordinator.showAgeBlocked)
    }

    @ViewBuilder
    private func routeView(coordinator: OnboardingCoordinator) -> some View {
        switch coordinator.route {
        case .welcome:
            WelcomeStage(coordinator: coordinator)
        case .auth:
            AuthStage(coordinator: coordinator)
        case .profile:
            ProfileMetricsStage(coordinator: coordinator)
        case .health:
            HealthConsentStage(coordinator: coordinator)
        case .training:
            TrainingPreferencesStage(coordinator: coordinator)
        case .coach:
            CoachRevealStage(coordinator: coordinator) {
                coordinator.complete(in: store)
            }
        }
    }
}

// MARK: - Dev Skip Button (DEBUG only)

#if DEBUG
private struct DevSkipButton: View {
    var coordinator: OnboardingCoordinator
    @EnvironmentObject private var store: AppStore
    @State private var expanded = false

    var body: some View {
        VStack {
            HStack {
                Spacer()
                if expanded {
                    HStack(spacing: 8) {
                        Button("Skip All →") {
                            coordinator.devSkipToEnd(in: store)
                        }
                        .font(.caption.weight(.black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.ember)
                        .clipShape(Capsule())

                        Button {
                            withAnimation(FDS.Spring.snap) { expanded = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.textMuted)
                                .frame(width: 28, height: 28)
                                .background(Color.surface)
                                .clipShape(Circle())
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Button {
                        withAnimation(FDS.Spring.snap) { expanded = true }
                    } label: {
                        Text("DEV")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.5)
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.warning)
                            .clipShape(Capsule())
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, FDS.Spacing.xl)
            .padding(.top, 12)
            Spacer()
        }
        .animation(FDS.Spring.snap, value: expanded)
    }
}
#endif

// MARK: - Scaffold

private struct OnboardingScaffold<Content: View>: View {
    @Bindable var coordinator: OnboardingCoordinator
    let eyebrow: String
    let title: String
    let subtitle: String
    let ctaTitle: String
    let ctaIcon: String
    let ctaEnabled: Bool
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    let ctaAction: () -> Void
    let content: Content

    init(
        coordinator: OnboardingCoordinator,
        eyebrow: String,
        title: String,
        subtitle: String,
        ctaTitle: String,
        ctaIcon: String,
        ctaEnabled: Bool,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        ctaAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.coordinator = coordinator
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.ctaTitle = ctaTitle
        self.ctaIcon = ctaIcon
        self.ctaEnabled = ctaEnabled
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.ctaAction = ctaAction
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressBar(
                currentStep: coordinator.currentStep,
                totalSteps: coordinator.totalSteps,
                title: coordinator.route.title,
                canGoBack: coordinator.canGoBack,
                onBack: coordinator.goBack
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    ForgeSectionHeader(
                        eyebrow: eyebrow,
                        title: title,
                        subtitle: subtitle
                    )
                    content
                }
                .padding(.horizontal, FDS.Spacing.xl)
                .padding(.bottom, 128)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            OnboardingBottomBar(
                title: ctaTitle,
                icon: ctaIcon,
                isEnabled: ctaEnabled,
                secondaryTitle: secondaryTitle,
                secondaryAction: secondaryAction,
                action: ctaAction
            )
        }
        .background(Color.background)
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int
    let title: String
    let canGoBack: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(canGoBack ? .textPrimary : .clear)
                    .frame(width: 40, height: 40)
                    .background(Color.surface.opacity(canGoBack ? 1 : 0))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.borderColor.opacity(canGoBack ? 1 : 0), lineWidth: 0.5))
            }
            .disabled(!canGoBack)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title.uppercased())
                        .font(.caption2.weight(.black))
                        .tracking(2)
                        .foregroundColor(.ember)
                    Spacer()
                    Text("\(currentStep)/\(totalSteps)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundColor(.textMuted)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(FDS.Gradient.ember)
                            .frame(width: max(8, geo.size.width * CGFloat(currentStep) / CGFloat(totalSteps)))
                            .animation(FDS.Spring.standard, value: currentStep)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, FDS.Spacing.xl)
        .padding(.top, 56)
        .padding(.bottom, 28)
    }
}

private struct OnboardingBottomBar: View {
    let title: String
    let icon: String
    let isEnabled: Bool
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        VStack(spacing: 12) {
            LinearGradient(
                colors: [Color.background.opacity(0), Color.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)

            Button {
                guard isEnabled else { return }
                FDS.haptic(.medium)
                action()
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Image(systemName: icon)
                        .font(.subheadline.weight(.bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 58)
                .background(isEnabled ? AnyShapeStyle(FDS.Gradient.emberDeep) : AnyShapeStyle(Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                        .stroke(isEnabled ? Color.ember.opacity(0.25) : Color.white.opacity(0.07), lineWidth: 0.7)
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(isEnabled ? 0.12 : 0.04), .clear],
                            startPoint: .top,
                            endPoint: .center
                        ))
                        .frame(height: 28)
                }
                .shadow(color: isEnabled ? Color.ember.opacity(0.30) : .clear, radius: reduceMotion ? 0 : 22, y: 8)
                .shadow(color: isEnabled ? Color.ember.opacity(0.14) : .clear, radius: reduceMotion ? 0 : 44, y: 16)
                .scaleEffect(pressed ? 0.98 : 1)
            }
            .disabled(!isEnabled)
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
            .animation(FDS.Spring.snap, value: pressed)
            .animation(FDS.Spring.standard, value: isEnabled)

            if let secondaryTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, FDS.Spacing.xl)
        .padding(.bottom, 34)
        .background(Color.background)
    }
}

// MARK: - Stage 1: Welcome + Age Gate

private var minimumBirthday: Date {
    Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? Date()
}

private struct WelcomeStage: View {
    @Bindable var coordinator: OnboardingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var ageStatus: String {
        coordinator.isUnderage ? "Must be 13 or older" : "\(coordinator.age) years old"
    }

    var body: some View {
        OnboardingScaffold(
            coordinator: coordinator,
            eyebrow: "FORGE",
            title: "Build the version of you that keeps showing up.",
            subtitle: "First, confirm your age. Then ARIA will shape your plan from your goals, body metrics, and recovery data.",
            ctaTitle: coordinator.isUnderage ? "Age requirement not met" : "Begin setup",
            ctaIcon: coordinator.isUnderage ? "lock.fill" : "arrow.right",
            ctaEnabled: !coordinator.isUnderage,
            ctaAction: coordinator.continueFromWelcome
        ) {
            VStack(spacing: 22) {
                ZStack {
                    if !reduceMotion {
                        PulsingRingView(index: 0, color: .ember, isAnimating: pulse)
                        PulsingRingView(index: 1, color: .ember, isAnimating: pulse)
                    }
                    Image(systemName: "flame.fill")
                        .font(.system(size: 78, weight: .black))
                        .foregroundStyle(LinearGradient(
                            colors: [.white, .emberLight, .ember],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .shadow(color: Color.ember.opacity(0.42), radius: 30, y: 8)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)

                VStack(spacing: 0) {
                    HStack {
                        Label("Date of Birth", systemImage: "birthday.cake.fill")
                            .font(.caption.weight(.bold))
                            .tracking(1.3)
                            .textCase(.uppercase)
                            .foregroundColor(.textMuted)
                        Spacer()
                        Text(ageStatus)
                            .font(.caption.weight(.bold))
                            .foregroundColor(coordinator.isUnderage ? .danger : .success)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                    Divider().overlay(Color.white.opacity(0.08))

                    DatePicker(
                        "Date of Birth",
                        selection: $coordinator.profile.birthday,
                        in: minimumBirthday...Date(),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .tint(.ember)
                    .padding(.vertical, 4)
                    .accessibilityHint("FORGE uses this for age eligibility and fitness calculations.")

                    Divider().overlay(Color.white.opacity(0.08))

                    // Age milestone tracker
                    HStack(spacing: 0) {
                        ForEach(Array([13, 18, 25, 40, 65].enumerated()), id: \.offset) { _, milestone in
                            let reached = coordinator.age >= milestone
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(reached ? Color.ember : Color.white.opacity(0.1))
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(reached ? Color.ember.opacity(0.4) : .clear, lineWidth: 4))
                                Text(milestone == 65 ? "65+" : "\(milestone)")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(reached ? .ember : .textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .animation(FDS.Spring.snap, value: coordinator.age)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                    Divider().overlay(Color.white.opacity(0.08))

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.textMuted)
                        Text("Your birthday stays in your profile and is used for eligibility and training calculations.")
                            .font(.footnote)
                            .foregroundColor(.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                }
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                        .stroke(coordinator.isUnderage ? Color.danger.opacity(0.45) : Color.borderColor, lineWidth: 1)
                )

                if coordinator.isUnderage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.warning)
                        Text("Users must be 13 or older to use FORGE.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.warning)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.warning.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous)
                        .stroke(Color.warning.opacity(0.2), lineWidth: 1))
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                ARIACoachCard(
                    title: "ARIA setup starts clean",
                    message: "Once your age is confirmed, we will only ask for details that change your training plan.",
                    accent: .ember,
                    icon: "sparkles"
                )
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
    }
}

// MARK: - Stage 2: Auth

private struct AuthStage: View {
    @Bindable var coordinator: OnboardingCoordinator
    @State private var selectedProvider: AuthProvider?

    var body: some View {
        OnboardingScaffold(
            coordinator: coordinator,
            eyebrow: "Account",
            title: "Save the plan ARIA builds for you.",
            subtitle: "Sign in with Apple or email to secure your profile and sync with the Forge backend.",
            ctaTitle: "Use Sign in with Apple below",
            ctaIcon: "apple.logo",
            ctaEnabled: false,
            ctaAction: {}
        ) {
            VStack(spacing: 16) {
                SignInWithAppleButton(.signUp) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    if case .success = result {
                        coordinator.markAuthenticated()
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 58)
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)

                ProviderSlotButton(
                    icon: "globe",
                    title: "Continue with Google",
                    subtitle: "Provider slot ready",
                    state: "Ready",
                    action: { selectedProvider = .google }
                )

                ProviderSlotButton(
                    icon: "envelope.fill",
                    title: "Continue with Email",
                    subtitle: "Production form prepared",
                    state: "Ready",
                    action: { selectedProvider = .email }
                )

                ARIACoachCard(
                    title: "No fake sign-ins",
                    message: "Email sign-in uses Cognito. Apple and Google slots remain visible for upcoming provider wiring.",
                    accent: .steel,
                    icon: "checkmark.shield.fill"
                )

                // Debug-only direct bypass on the auth screen itself
                #if DEBUG
                Button {
                    coordinator.markAuthenticated()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right.2")
                            .font(.caption.weight(.black))
                        Text("Dev: Skip Auth")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.textMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.surface.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                            .stroke(Color.borderColor.opacity(0.5), lineWidth: 0.7)
                    )
                }
                .buttonStyle(.plain)
                #endif
            }
        }
        .sheet(item: $selectedProvider) { provider in
            AuthProviderPreparationSheet(provider: provider, coordinator: coordinator)
        }
    }
}

private enum AuthProvider: String, Identifiable {
    case google, email
    var id: String { rawValue }
    var title: String {
        switch self {
        case .google: return "Google Sign-In"
        case .email:  return "Email Sign-In"
        }
    }
}

private struct ProviderSlotButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let state: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                Text(state)
                    .font(.caption2.weight(.black))
                    .tracking(0.8)
                    .foregroundColor(.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.warning.opacity(0.10))
                    .clipShape(Capsule())
            }
            .padding(14)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                    .stroke(Color.borderColor, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("This provider is prepared but does not sign in until backend wiring is complete.")
    }
}

private struct AuthProviderPreparationSheet: View {
    let provider: AuthProvider
    var coordinator: OnboardingCoordinator
    @Environment(\.dismiss) private var dismiss
    @StateObject private var auth = CognitoAuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var confirmationCode = ""
    @State private var mode: AuthMode = .signIn
    @State private var isLoading = false
    @State private var statusMessage: String?

    private enum AuthMode: String, CaseIterable {
        case signIn = "Sign In"
        case signUp = "Sign Up"
        case confirm = "Confirm"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForgeSectionHeader(
                            eyebrow: "Forge Account",
                            title: provider.title,
                            subtitle: "Sign in with Cognito to sync your profile, workouts, and ARIA coaching across devices."
                        )

                        if provider == .email {
                            Picker("Mode", selection: $mode) {
                                ForEach(AuthMode.allCases, id: \.self) { item in
                                    Text(item.rawValue).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)

                            VStack(spacing: 12) {
                                ForgeTextField(placeholder: "Email", text: $email, icon: "envelope.fill", keyboardType: .emailAddress)
                                ForgeTextField(placeholder: "Password", text: $password, icon: "lock.fill", isSecure: true)
                                if mode == .confirm {
                                    ForgeTextField(placeholder: "Confirmation code", text: $confirmationCode, icon: "number", keyboardType: .numberPad)
                                }
                            }

                            if let statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.textSecondary)
                            }

                            if let lastError = auth.lastError {
                                Text(lastError)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.danger)
                            }

                            Button(action: { Task { await submit() } }) {
                                HStack {
                                    if isLoading {
                                        ProgressView().tint(.white)
                                    }
                                    Text(primaryActionTitle)
                                        .font(.system(size: 16, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(FDS.Gradient.ember)
                                .foregroundColor(.white)
                                .cornerRadius(FDS.Radius.lg)
                            }
                            .disabled(isLoading || !canSubmit)
                        } else {
                            ARIACoachCard(
                                title: "Coming soon",
                                message: "Google sign-in will be enabled after OAuth provider wiring in Cognito.",
                                accent: .warning,
                                icon: "globe"
                            )
                        }
                    }
                    .padding(FDS.Spacing.xl)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
        }
    }

    private var primaryActionTitle: String {
        switch mode {
        case .signIn: return "Sign In"
        case .signUp: return "Create Account"
        case .confirm: return "Confirm Email"
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        (mode == .confirm || password.count >= 12)
    }

    private func submit() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            switch mode {
            case .signIn:
                _ = try await auth.signIn(email: email, password: password)
                statusMessage = "Signed in successfully."
                coordinator.markAuthenticated()
                dismiss()
            case .signUp:
                try await auth.signUp(email: email, password: password)
                mode = .confirm
                statusMessage = "Account created. Enter the confirmation code from your email."
            case .confirm:
                try await auth.confirmSignUp(email: email, code: confirmationCode)
                _ = try await auth.signIn(email: email, password: password)
                statusMessage = "Email confirmed. You're signed in."
                coordinator.markAuthenticated()
                dismiss()
            }
        } catch {
            statusMessage = nil
        }
    }
}

// MARK: - Stage 3: Profile + Metrics

private struct ProfileMetricsStage: View {
    @Bindable var coordinator: OnboardingCoordinator
    @State private var useImperial = false

    private var heightDisplay: String {
        if useImperial {
            let inches = Int(coordinator.profile.heightCm / 2.54)
            return "\(inches / 12)' \(inches % 12)\""
        }
        return "\(Int(coordinator.profile.heightCm)) cm"
    }

    private var weightDisplay: String {
        useImperial ? "\(Int(coordinator.profile.weightKg * 2.20462)) lb" : "\(Int(coordinator.profile.weightKg)) kg"
    }

    private var bmi: Double { coordinator.profile.weightKg / pow(coordinator.profile.heightCm / 100, 2) }
    private var bmiCategory: (label: String, color: Color) {
        switch bmi {
        case ..<18.5: return ("Underweight", .warning)
        case 18.5..<25: return ("Healthy", .success)
        case 25..<30:   return ("Overweight", .warning)
        default:        return ("Obese", .danger)
        }
    }

    var body: some View {
        OnboardingScaffold(
            coordinator: coordinator,
            eyebrow: "Profile",
            title: "Give ARIA the calibration points.",
            subtitle: "Name, identity, height, and weight tune intensity, calorie estimates, and coaching language.",
            ctaTitle: coordinator.profileCanContinue ? "Save profile" : "Enter your name",
            ctaIcon: "arrow.right",
            ctaEnabled: coordinator.profileCanContinue,
            ctaAction: coordinator.continueFromProfile
        ) {
            VStack(spacing: 18) {
                ForgeTextField(
                    placeholder: "Preferred name",
                    text: $coordinator.profile.name,
                    icon: "person.fill"
                )

                if !coordinator.profile.trimmedName.isEmpty {
                    Text("Hey, \(coordinator.profile.trimmedName) 👋")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.ember)
                        .padding(.leading, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack(spacing: 10) {
                    ForEach(Gender.allCases) { gender in
                        GenderSelectionCard(
                            gender: gender,
                            isSelected: coordinator.profile.gender == gender,
                            action: { coordinator.profile.gender = gender }
                        )
                    }
                }

                HStack {
                    Spacer()
                    UnitToggle(useImperial: $useImperial)
                }

                MetricSliderCard(
                    title: "Height",
                    icon: "ruler.fill",
                    displayValue: heightDisplay,
                    sliderValue: $coordinator.profile.heightCm,
                    range: 120...220,
                    step: 1
                )

                MetricSliderCard(
                    title: "Weight",
                    icon: "scalemass.fill",
                    displayValue: weightDisplay,
                    sliderValue: $coordinator.profile.weightKg,
                    range: 35...220,
                    step: 0.5
                )

                // BMI readout
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BMI")
                            .font(.system(size: 11, weight: .bold)).tracking(1.5)
                            .foregroundColor(.textMuted).textCase(.uppercase)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", bmi))
                                .font(.system(size: 28, weight: .black, design: .monospaced))
                                .foregroundColor(.textPrimary)
                                .contentTransition(.numericText())
                            Text(bmiCategory.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(bmiCategory.color)
                        }
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { i in
                            let cols: [Color] = [.steel, .success, .warning, .danger]
                            let active = (i == 0 && bmi < 18.5) || (i == 1 && bmi >= 18.5 && bmi < 25)
                                || (i == 2 && bmi >= 25 && bmi < 30) || (i == 3 && bmi >= 30)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(cols[i].opacity(active ? 1 : 0.25))
                                .frame(width: 32, height: active ? 8 : 4)
                                .animation(FDS.Spring.standard, value: bmi)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 18)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(Color.borderColor, lineWidth: 0.5))
                .animation(FDS.Spring.standard, value: bmi)

                if coordinator.hasHealthData {
                    HealthPrefillSummary(coordinator: coordinator)
                } else {
                    ARIACoachCard(
                        title: "Manual is perfectly fine",
                        message: "HealthKit on the next screen can prefill and improve this, but your manual profile is enough to begin.",
                        accent: .steel,
                        icon: "slider.horizontal.3"
                    )
                }
            }
            .task {
                await coordinator.refreshHealthPrefillIfAvailable()
            }
        }
    }
}

private struct UnitToggle: View {
    @Binding var useImperial: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { imperial in
                Button {
                    FDS.selectionHaptic()
                    withAnimation(FDS.Spring.snap) { useImperial = imperial }
                } label: {
                    Text(imperial ? "Imperial" : "Metric")
                        .font(.caption.weight(.bold))
                        .foregroundColor(useImperial == imperial ? .white : .textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(useImperial == imperial ? Color.ember : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
            .stroke(Color.borderColor, lineWidth: 0.7))
    }
}

private struct HealthPrefillSummary: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("HealthKit prefill applied", systemImage: "heart.text.square.fill")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.success)

            if let profile = coordinator.healthProfile {
                VStack(spacing: 8) {
                    if let height = profile.heightCm {
                        HealthDataRow(label: "Height", value: "\(Int(height)) cm", icon: "ruler")
                    }
                    if let weight = profile.weightKg {
                        HealthDataRow(label: "Weight", value: "\(Int(weight)) kg", icon: "scalemass")
                    }
                    if let vo2 = profile.vo2Max {
                        HealthDataRow(label: "VO2 Max", value: String(format: "%.0f", vo2), icon: "lungs.fill")
                    }
                }
            }
        }
        .padding(16)
        .background(Color.success.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
            .stroke(Color.success.opacity(0.26), lineWidth: 1))
    }
}

// MARK: - Stage 4: Health Consent

private struct HealthConsentStage: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            coordinator: coordinator,
            eyebrow: "Health",
            title: "Let recovery shape the work.",
            subtitle: "HealthKit helps ARIA adapt around heart rate, sleep, activity, and recent workouts. You can skip this and connect later.",
            ctaTitle: ctaTitle,
            ctaIcon: "arrow.right",
            ctaEnabled: ctaEnabled,
            secondaryTitle: secondaryTitle,
            secondaryAction: secondaryAction,
            ctaAction: { coordinator.continueFromHealth() }
        ) {
            VStack(spacing: 18) {
                HealthPermissionCard(coordinator: coordinator)

                if let snapshot = coordinator.healthSnapshot {
                    HealthDataPreviewCard(snapshot: snapshot)
                }

                WearableInfoGrid()

                ARIACoachCard(
                    title: "Why this matters",
                    message: "Readiness data lets ARIA reduce volume when recovery is low and push performance when your body is prepared.",
                    accent: .ember,
                    icon: "waveform.path.ecg"
                )
            }
        }
    }

    private var ctaTitle: String {
        switch coordinator.healthKitState {
        case .authorized:            return "Continue with HealthKit"
        case .denied:                return "Continue without HealthKit"
        case .unavailable:           return "Continue"
        case .unknown, .requesting:  return "Connect HealthKit first"
        }
    }

    private var ctaEnabled: Bool {
        switch coordinator.healthKitState {
        case .authorized, .denied, .unavailable: return true
        case .unknown, .requesting:              return false
        }
    }

    private var secondaryTitle: String? {
        coordinator.healthKitState == .authorized ? nil : "Skip HealthKit for now"
    }

    private var secondaryAction: (() -> Void)? {
        guard coordinator.healthKitState != .authorized else { return nil }
        return { coordinator.skipHealthKit() }
    }
}

private struct HealthPermissionCard: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2.weight(.bold))
                    .foregroundColor(color)
                    .frame(width: 54, height: 54)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("HealthKit")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.textPrimary)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Button {
                Task { await coordinator.requestHealthKit() }
            } label: {
                HStack(spacing: 8) {
                    if coordinator.healthKitState == .requesting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "heart.text.square.fill")
                    }
                    Text(buttonTitle)
                        .font(.subheadline.weight(.bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(buttonEnabled ? AnyShapeStyle(FDS.Gradient.ember) : AnyShapeStyle(Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
            }
            .disabled(!buttonEnabled)
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
            .stroke(color.opacity(0.28), lineWidth: 1))
    }

    private var icon: String {
        switch coordinator.healthKitState {
        case .authorized:           return "checkmark.seal.fill"
        case .denied, .unavailable: return "exclamationmark.triangle.fill"
        case .unknown, .requesting: return "heart.text.square.fill"
        }
    }

    private var color: Color {
        switch coordinator.healthKitState {
        case .authorized:           return .success
        case .denied, .unavailable: return .warning
        case .unknown, .requesting: return .ember
        }
    }

    private var statusText: String {
        switch coordinator.healthKitState {
        case .unknown:    return "Optional, private, and used only to personalize your plan."
        case .requesting: return "Waiting for HealthKit authorization."
        case .authorized: return "Connected. ARIA can use recovery and activity signals."
        case .denied:     return "Not connected. You can continue and enable this later."
        case .unavailable: return "Health data is unavailable on this device."
        }
    }

    private var buttonTitle: String {
        switch coordinator.healthKitState {
        case .authorized:  return "Connected"
        case .requesting:  return "Requesting Access"
        case .denied:      return "Try Again in Settings"
        case .unavailable: return "Unavailable"
        case .unknown:     return "Connect HealthKit"
        }
    }

    private var buttonEnabled: Bool {
        coordinator.healthKitState == .unknown
    }
}

private struct WearableInfoGrid: View {
    private let wearables: [(String, String, String)] = [
        ("Apple Watch",  "applewatch",          "HealthKit syncs workouts, heart rate, and activity."),
        ("Oura Ring",    "circle.circle.fill",   "Sleep and recovery can flow through HealthKit."),
        ("WHOOP",        "waveform.path.ecg",    "Connect later when provider support is live."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wearables")
                .font(.caption.weight(.black))
                .tracking(1.4)
                .foregroundColor(.textMuted)
                .textCase(.uppercase)

            VStack(spacing: 10) {
                ForEach(wearables, id: \.0) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.1)
                            .foregroundColor(.steel)
                            .frame(width: 34, height: 34)
                            .background(Color.steel.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.textPrimary)
                            Text(item.2)
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.surface.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Stage 5: Training Preferences

private struct TrainingPreferencesStage: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            coordinator: coordinator,
            eyebrow: "Training",
            title: "Shape the program around real life.",
            subtitle: "Choose your targets, your training language, and what you actually like doing. ARIA will build around both ambition and adherence.",
            ctaTitle: coordinator.trainingCanContinue ? "Build my plan" : "Choose goals and training",
            ctaIcon: "arrow.right",
            ctaEnabled: coordinator.trainingCanContinue,
            ctaAction: coordinator.continueFromTraining
        ) {
            VStack(alignment: .leading, spacing: 28) {
                PreferenceSection(title: "Goals", subtitle: "Pick every outcome that matters.") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 12)], spacing: 12) {
                        ForEach(OnboardingFitnessGoal.allCases) { goal in
                            GoalCard(
                                goal: goal,
                                isSelected: coordinator.profile.fitnessGoals.contains(goal),
                                action: { coordinator.toggleGoal(goal) }
                            )
                        }
                    }
                }

                PreferenceSection(title: "Experience", subtitle: "This controls starting intensity.") {
                    VStack(spacing: 10) {
                        ForEach(ExperienceLevel.allCases) { level in
                            ExperienceLevelButton(
                                level: level,
                                isSelected: coordinator.profile.experienceLevel == level,
                                action: { coordinator.profile.experienceLevel = level }
                            )
                        }
                    }
                }

                PreferenceSection(title: "Training You Enjoy", subtitle: "Sustainable beats perfect.") {
                    OnboardingFlowLayout(spacing: 10) {
                        ForEach(OnboardingWorkoutType.allCases) { workout in
                            TogglePill(
                                label: workout.label,
                                isSelected: coordinator.profile.preferredWorkouts.contains(workout),
                                onTap: { coordinator.toggleWorkout(workout) }
                            )
                        }
                    }
                }

                ARIACoachCard(
                    title: trainingSummaryTitle,
                    message: trainingSummaryMessage,
                    accent: .ember,
                    icon: "brain.head.profile"
                )
            }
        }
    }

    private var trainingSummaryTitle: String {
        coordinator.profile.fitnessGoals.isEmpty ? "ARIA is listening" : "ARIA has enough signal"
    }

    private var trainingSummaryMessage: String {
        if coordinator.profile.fitnessGoals.isEmpty {
            return "Select at least one goal and one training style so your first plan feels specific."
        }
        let goal = coordinator.profile.fitnessGoals.first?.label ?? "your goal"
        let level = coordinator.profile.experienceLevel.label.lowercased()
        return "Starting as \(level), your first block will prioritize \(goal.lowercased()) while keeping recovery visible."
    }
}

private struct PreferenceSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.textTertiary)
            }
            content
        }
    }
}

// MARK: - Stage 6: Coach Reveal

private struct CoachRevealStage: View {
    @Bindable var coordinator: OnboardingCoordinator
    let onFinish: () -> Void

    var body: some View {
        OnboardingScaffold(
            coordinator: coordinator,
            eyebrow: "ARIA",
            title: "Choose the voice that keeps you moving.",
            subtitle: "This shapes every check-in, plan adjustment, and recovery nudge.",
            ctaTitle: coordinator.isCompleting ? "Launching ARIA…" : "Start training with ARIA",
            ctaIcon: "flame.fill",
            ctaEnabled: !coordinator.isCompleting,
            ctaAction: onFinish
        ) {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    ForEach(OnboardingCoachingStyle.allCases) { style in
                        CoachingStyleCard(
                            style: style,
                            isSelected: coordinator.profile.coachingStyle == style,
                            action: { coordinator.profile.coachingStyle = style }
                        )
                    }
                }

                PlanRevealCard(coordinator: coordinator)
            }
        }
    }
}

private struct PlanRevealCard: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(FDS.Gradient.ember)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text("A")
                            .font(.caption.weight(.black))
                            .foregroundColor(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("ARIA Preview")
                        .font(.caption.weight(.black))
                        .tracking(1.2)
                        .foregroundColor(.textMuted)
                    Text(coordinator.profile.coachingStyle.label)
                        .font(.headline.weight(.bold))
                        .foregroundColor(coordinator.profile.coachingStyle.color)
                }
            }

            Text(previewMessage)
                .font(.body)
                .foregroundColor(.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                SummaryPill(icon: "target", label: coordinator.profile.fitnessGoals.first?.label ?? "Goal")
                SummaryPill(icon: "bolt.fill", label: coordinator.profile.experienceLevel.label)
                if coordinator.healthKitState == .authorized {
                    SummaryPill(icon: "heart.text.square.fill", label: "HealthKit")
                }
            }
        }
        .padding(18)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                .stroke(coordinator.profile.coachingStyle.color.opacity(0.35), lineWidth: 1)
        )
        .id(coordinator.profile.coachingStyle.rawValue)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(FDS.Spring.standard, value: coordinator.profile.coachingStyle)
    }

    private var previewMessage: String {
        let name = coordinator.profile.trimmedName.isEmpty ? "you" : coordinator.profile.trimmedName
        let goal = coordinator.profile.fitnessGoals.first?.label.lowercased() ?? "general fitness"
        let healthLine = coordinator.healthKitState == .authorized
            ? " I will also watch recovery signals before pushing intensity."
            : " We can add recovery data later when you connect HealthKit."

        switch coordinator.profile.coachingStyle {
        case .driven:
            return "\(name), we start with clear standards: show up, execute the plan, and earn progression. First block focuses on \(goal).\(healthLine)"
        case .balanced:
            return "\(name), your first week will balance progressive overload with recovery, built around \(goal).\(healthLine)"
        case .supportive:
            return "\(name), we will make this feel doable from day one. Small wins, clear next steps, and steady progress toward \(goal).\(healthLine)"
        case .scientist:
            return "\(name), I will explain the why behind your work: intensity, volume, and recovery decisions all tied back to \(goal).\(healthLine)"
        case .elite:
            return "\(name), your plan will treat performance like a system: readiness, output, recovery, and adaptation toward \(goal).\(healthLine)"
        }
    }
}

private struct SummaryPill: View {
    let icon: String
    let label: String

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.surfaceElevated)
            .clipShape(Capsule())
    }
}

// MARK: - Age Block

private struct AgeBlockedView: View {
    let onReset: () -> Void
    @State private var appeared = false
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            RadialGradient(
                colors: [Color.danger.opacity(0.12), .clear],
                center: .center, startRadius: 0, endRadius: 300
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 32) {
                    ZStack {
                        Circle().fill(Color.danger.opacity(0.08)).frame(width: 120, height: 120)
                        Circle().stroke(Color.danger.opacity(0.22), lineWidth: 1.5).frame(width: 120, height: 120)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(LinearGradient(
                                colors: [Color.danger, Color.danger.opacity(0.7)],
                                startPoint: .top, endPoint: .bottom
                            ))
                    }
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .animation(FDS.Spring.floaty.delay(0.1), value: appeared)
                    .offset(x: shakeOffset)

                    VStack(spacing: 14) {
                        Text("Access Restricted")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

                        Text("FORGE requires users to be at least 13 years old. This app involves biometric data and physical training that isn't appropriate for younger users.")
                            .font(.system(size: 16))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .padding(.horizontal, 32)
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.4).delay(0.4), value: appeared)

                        Label("Minimum age: 13 years", systemImage: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.danger)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(Color.danger.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.danger.opacity(0.25), lineWidth: 1))
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.4).delay(0.5), value: appeared)
                    }
                }
                Spacer()

                VStack(spacing: 12) {
                    Button(action: onReset) {
                        Text("Review birthday")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                                .stroke(Color.borderColor, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, FDS.Spacing.xl)

                    Text("Protected under COPPA & GDPR-K")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
                .padding(.bottom, 52)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.7), value: appeared)
            }
        }
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shakeOffset =  12 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shakeOffset = -10 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shakeOffset =   7 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.spring(response: 0.3,  dampingFraction: 0.7 )) { shakeOffset = 0 }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Ambient Background

struct ForgeAmbientBackground: View {
    let step: Int
    @State private var phase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.background, Color(hex: "140A06").opacity(0.78), Color.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [routeColor.opacity(0.18), routeColor.opacity(0.05), .clear],
                center: UnitPoint(x: 0.32, y: 0.18),
                startRadius: 10,
                endRadius: 520
            )
            .blur(radius: 44)

            if !reduceMotion {
                RadialGradient(
                    colors: [Color.ember.opacity(0.09), .clear],
                    center: UnitPoint(x: 0.5 + 0.24 * cos(phase), y: 0.48 + 0.18 * sin(phase)),
                    startRadius: 0,
                    endRadius: 360
                )
                .blur(radius: 60)
                .onAppear {
                    withAnimation(.linear(duration: FDS.Duration.ambient).repeatForever(autoreverses: false)) {
                        phase = .pi * 2
                    }
                }
            }
        }
    }

    private var routeColor: Color {
        switch step {
        case 0, 1: return .ember
        case 2, 3: return .steel
        case 4:    return .success
        default:   return Color(hex: "A855F7")
        }
    }
}

// MARK: - Section Header

struct ForgeSectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var accentColor: Color = .ember
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(accentColor)
                    .frame(width: appeared ? 22 : 8, height: 3)
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(2.8)
                    .foregroundColor(accentColor)
            }
            .opacity(appeared ? 1 : 0)

            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(LinearGradient(
                    colors: [.white, Color.white.opacity(0.76)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

            Text(subtitle)
                .font(.body)
                .foregroundColor(.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
        }
        .animation(FDS.Spring.hero, value: appeared)
        .onAppear { appeared = true }
    }
}

// MARK: - ARIA Coach Card

struct ARIACoachCard: View {
    let title: String
    let message: String
    var accent: Color
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundColor(accent)
                .frame(width: 32, height: 32)
                .background(accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.textPrimary)
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.textTertiary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.surface.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - Text Field

struct ForgeTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(focused ? .ember : .textMuted)
                .frame(width: 22)
                .scaleEffect(focused ? 1.1 : 1.0)
                .animation(FDS.Spring.snap, value: focused)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder).foregroundColor(.textMuted)
                }
                if isSecure {
                    SecureField("", text: $text).focused($focused)
                } else {
                    TextField("", text: $text)
                        .focused($focused)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                        .autocorrectionDisabled(keyboardType == .emailAddress)
                }
            }
            .font(.body)
            .foregroundColor(.textPrimary)
            .tint(.ember)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .background(focused ? Color.ember.opacity(0.05) : Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                .stroke(focused ? Color.ember.opacity(0.60) : Color.borderColor, lineWidth: focused ? 1.4 : 0.7)
        )
        .animation(FDS.Spring.standard, value: focused)
    }
}

// MARK: - Gender Selection Card

struct GenderSelectionCard: View {
    let gender: Gender
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
            FDS.selectionHaptic()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(isSelected ? Color.ember.opacity(0.16) : Color.surfaceElevated).frame(width: 48, height: 48)
                    if isSelected { Circle().stroke(Color.ember.opacity(0.4), lineWidth: 1.5).frame(width: 48, height: 48) }
                    Image(systemName: gender.icon)
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? .ember : .textSecondary)
                        .scaleEffect(isSelected ? 1.1 : 1.0)
                        .animation(FDS.Spring.snap, value: isSelected)
                }
                Text(gender.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isSelected ? .ember : .textPrimary)
                Spacer()
                ZStack {
                    Circle().stroke(isSelected ? Color.ember : Color.borderColor, lineWidth: 1.5).frame(width: 22, height: 22)
                    if isSelected { Circle().fill(Color.ember).frame(width: 12, height: 12).transition(.scale.combined(with: .opacity)) }
                }
                .animation(FDS.Spring.snap, value: isSelected)
            }
            .padding(16)
            .background(ZStack {
                Color.surface
                if isSelected { RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous).fill(Color.ember.opacity(0.04)) }
            })
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                .stroke(isSelected ? Color.ember.opacity(0.5) : Color.borderColor, lineWidth: isSelected ? 1.5 : 0.5))
            .shadow(color: isSelected ? Color.ember.opacity(0.14) : .black.opacity(0.04), radius: isSelected ? 12 : 4, y: 3)
        }
        .buttonStyle(.plain)
        .animation(FDS.Spring.standard, value: isSelected)
    }
}

// MARK: - Metric Slider Card

struct MetricSliderCard: View {
    let title: String
    let icon: String
    let displayValue: String
    @Binding var sliderValue: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 13)).foregroundColor(.ember)
                    Text(title).font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundColor(.textMuted).textCase(.uppercase)
                }
                Spacer()
                Text(displayValue)
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .contentTransition(.numericText())
            }
            Slider(value: $sliderValue, in: range, step: step)
                .tint(.ember)
                .accessibilityLabel(title)
                .accessibilityValue(displayValue)
        }
        .padding(20)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
            .stroke(Color.borderColor, lineWidth: 0.5))
    }
}

// MARK: - Goal Card

struct GoalCard: View {
    let goal: OnboardingFitnessGoal
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.ember.opacity(0.18) : Color.surfaceElevated)
                            .frame(width: 38, height: 38)
                        Image(systemName: goal.icon)
                            .font(.system(size: 16))
                            .foregroundColor(isSelected ? .ember : .textTertiary)
                            .scaleEffect(isSelected ? 1.1 : 1.0)
                            .animation(FDS.Spring.snap, value: isSelected)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16)).foregroundColor(.ember)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(goal.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .textPrimary : .textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.ember.opacity(0.06) : Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                .stroke(isSelected ? Color.ember.opacity(0.45) : Color.borderColor, lineWidth: isSelected ? 1.5 : 0.5))
            .shadow(color: isSelected ? Color.ember.opacity(0.12) : .black.opacity(0.06), radius: isSelected ? 12 : 4, y: 3)
        }
        .buttonStyle(.plain)
        .animation(FDS.Spring.standard, value: isSelected)
    }
}

// MARK: - Experience Level Button

struct ExperienceLevelButton: View {
    let level: ExperienceLevel
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch level {
        case .beginner:     return "leaf.fill"
        case .intermediate: return "bolt.fill"
        case .advanced:     return "flame.fill"
        case .elite:        return "crown.fill"
        }
    }

    private var levelColor: Color {
        switch level {
        case .beginner:     return .steel
        case .intermediate: return Color(hex: "F59E0B")
        case .advanced:     return .ember
        case .elite:        return Color(hex: "A855F7")
        }
    }

    var body: some View {
        Button(action: { action(); FDS.selectionHaptic() }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(isSelected ? levelColor.opacity(0.16) : Color.surfaceElevated).frame(width: 50, height: 50)
                    if isSelected { Circle().stroke(levelColor.opacity(0.35), lineWidth: 1.5).frame(width: 50, height: 50) }
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? levelColor : .textTertiary)
                        .scaleEffect(isSelected ? 1.1 : 1.0)
                        .animation(FDS.Spring.snap, value: isSelected)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(level.label).font(.system(size: 15, weight: .semibold)).foregroundColor(isSelected ? levelColor : .textPrimary)
                    Text(level.description).font(.system(size: 12)).foregroundColor(.textTertiary).lineLimit(2)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundColor(levelColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(14)
            .background(isSelected ? levelColor.opacity(0.06) : Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                .stroke(isSelected ? levelColor.opacity(0.45) : Color.borderColor, lineWidth: isSelected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .animation(FDS.Spring.standard, value: isSelected)
    }
}

// MARK: - Coaching Style Card

struct CoachingStyleCard: View {
    let style: OnboardingCoachingStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(isSelected ? style.color.opacity(0.15) : Color.surfaceElevated).frame(width: 50, height: 50)
                    if isSelected { Circle().stroke(style.color.opacity(0.35), lineWidth: 1.5).frame(width: 50, height: 50) }
                    Image(systemName: style.icon)
                        .font(.headline.weight(.bold))
                        .foregroundColor(isSelected ? style.color : .textTertiary)
                        .scaleEffect(isSelected ? 1.1 : 1.0)
                        .animation(FDS.Spring.snap, value: isSelected)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(style.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(isSelected ? style.color : .textPrimary)
                    Text(style.description)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                ZStack {
                    Circle().stroke(isSelected ? style.color : Color.borderColor, lineWidth: 1.5).frame(width: 22, height: 22)
                    if isSelected { Circle().fill(style.color).frame(width: 12, height: 12).transition(.scale.combined(with: .opacity)) }
                }
                .animation(FDS.Spring.snap, value: isSelected)
            }
            .padding(15)
            .background(isSelected ? style.color.opacity(0.06) : Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                .stroke(isSelected ? style.color.opacity(0.48) : Color.borderColor, lineWidth: isSelected ? 1.4 : 0.7))
        }
        .buttonStyle(.plain)
        .animation(FDS.Spring.standard, value: isSelected)
    }
}

// MARK: - Toggle Pill

struct TogglePill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isSelected ? .ember : .textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color.ember.opacity(0.13) : Color.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.ember.opacity(0.55) : Color.borderColor, lineWidth: isSelected ? 1.4 : 0.7))
        }
        .buttonStyle(.plain)
        .animation(FDS.Spring.snap, value: isSelected)
    }
}

// MARK: - Flow Layout

struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var positions: [CGPoint] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + lineHeight), positions)
    }
}

// MARK: - Previews

#Preview("Welcome") {
    OnboardingView()
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}

#Preview("Large Type") {
    OnboardingView()
        .environmentObject(AppStore())
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
        .preferredColorScheme(.dark)
}
