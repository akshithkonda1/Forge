import SwiftUI
import AuthenticationServices

// ╔════════════════════════════════════════════════════════════════╗
// ║  FORGE ONBOARDING — Perfect Merged Version                    ║
// ║  A's architecture: OnboardingProfile · toCoreProfile()        ║
// ║     tempOnboardingProfile · DeviceCard · type-safe enums      ║
// ║  B's polish: FDS.* tokens · forgePress · inner speculars      ║
// ║     PulsingRingView · reduceMotion · level-specific colors     ║
// ╚════════════════════════════════════════════════════════════════╝

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

// ============================================================
// MARK: - A's Architecture: Onboarding-specific type layer
// ============================================================
// These deliberately separate onboarding UI types from core
// Models.swift types, enabling toCoreProfile() conversion.

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
        case .weightlifting: return "Weightlifting";  case .hiit:       return "HIIT"
        case .running:       return "Running";         case .cycling:    return "Cycling"
        case .yoga:          return "Yoga";            case .swimming:   return "Swimming"
        case .boxing:        return "Boxing";          case .calisthenics: return "Calisthenics"
        case .crossfit:      return "CrossFit";        case .pilates:    return "Pilates"
        case .climbing:      return "Climbing";        case .martial_arts: return "Martial Arts"
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
    case drill_sergeant, balanced, supportive, scientist
    var id: String { rawValue }
    var label: String {
        switch self {
        case .drill_sergeant: return "Drill Sergeant"
        case .balanced:       return "Balanced"
        case .supportive:     return "Supportive"
        case .scientist:      return "The Scientist"
        }
    }
    var description: String {
        switch self {
        case .drill_sergeant: return "No excuses. Intense accountability. ARIA pushes you past every limit."
        case .balanced:       return "Science-backed intensity with room to breathe. Optimal for long-term results."
        case .supportive:     return "Encouraging, patient coaching that celebrates every win, big or small."
        case .scientist:      return "Data-first coaching with deep analytics and periodization theory."
        }
    }
    var icon: String {
        switch self {
        case .drill_sergeant: return "bolt.fill"
        case .balanced:       return "scale.3d"
        case .supportive:     return "heart.fill"
        case .scientist:      return "waveform.path.ecg"
        }
    }
    var color: Color {
        switch self {
        case .drill_sergeant: return .ember
        case .balanced:       return .steel
        case .supportive:     return Color(hex: "22C55E")
        case .scientist:      return Color(hex: "A855F7")
        }
    }
    var coreStyle: CoachingStyle {
        switch self {
        case .drill_sergeant: return .pushHard
        case .balanced:       return .balanced
        case .supportive:     return .patient
        case .scientist:      return .dataDriven
        }
    }
}

// MARK: - A's Architecture: OnboardingProfile staging model

struct OnboardingProfile {
    var name:              String                    = ""
    var birthday:          Date                      = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    var gender:            Gender                    = .preferNotToSay
    var heightCm:          Double                    = 170
    var weightKg:          Double                    = 70
    var fitnessGoals:      [OnboardingFitnessGoal]   = []
    var experienceLevel:   ExperienceLevel           = .intermediate
    var preferredWorkouts: [OnboardingWorkoutType]   = []
    var coachingStyle:     OnboardingCoachingStyle   = .balanced

    /// Commit staged onboarding data to the core UserProfile
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

// MARK: - A's Architecture: AppStore staging extension

extension AppStore {
    private static var _tempOnboardingProfile: OnboardingProfile?
    var tempOnboardingProfile: OnboardingProfile {
        get { Self._tempOnboardingProfile ?? OnboardingProfile() }
        set { Self._tempOnboardingProfile = newValue }
    }
}

// MARK: - ForgeAmbientBackground

struct ForgeAmbientBackground: View {
    let step: Int
    @State private var phase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack {
            // Base gradient that shifts with each step
            RadialGradient(
                colors: gradientColors,
                center: .center,
                startRadius: 0,
                endRadius: 600
            )
            .blur(radius: 80)
            .opacity(0.3)
            
            // Animated secondary layer
            if !reduceMotion {
                RadialGradient(
                    colors: [
                        Color.ember.opacity(0.15),
                        Color.ember.opacity(0.05),
                        .clear
                    ],
                    center: UnitPoint(
                        x: 0.5 + 0.3 * cos(phase),
                        y: 0.5 + 0.3 * sin(phase)
                    ),
                    startRadius: 0,
                    endRadius: 400
                )
                .blur(radius: 60)
                .opacity(step >= 0 ? 0.4 : 0)
            }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                    phase = .pi * 2
                }
            }
        }
    }
    
    private var gradientColors: [Color] {
        if step < 0 {
            // Pre-auth state
            return [
                Color.ember.opacity(0.1),
                Color(hex: "1A0800").opacity(0.3),
                .clear
            ]
        }
        
        // Subtle color shifts per step
        switch step {
        case 0, 1: // Age & Profile
            return [Color(hex: "FF6A00").opacity(0.08), Color(hex: "1A0800").opacity(0.2), .clear]
        case 2, 3: // Metrics & Devices
            return [Color.steel.opacity(0.12), Color(hex: "0A0A0A").opacity(0.3), .clear]
        case 4, 5: // Goals & Experience
            return [Color.ember.opacity(0.15), Color(hex: "1A0800").opacity(0.25), .clear]
        case 6, 7: // Workouts & Coaching
            return [Color.ember.opacity(0.18), Color(hex: "FF2200").opacity(0.08), .clear]
        default:
            return [Color.ember.opacity(0.1), .clear]
        }
    }
}

// MARK: - Age Gate Helpers

private func calculateAge(from birthday: Date) -> Int {
    Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
}
private var minimumBirthday: Date {
    Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? Date()
}

// MARK: - Root Onboarding Container

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @State private var authState:      AuthenticationState = .unauthenticated
    @State private var step:           Int                 = 0
    @State private var showAgeBlocked: Bool                = false

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            ForgeAmbientBackground(step: authState == .authenticated ? step : -1)
                .ignoresSafeArea()

            if showAgeBlocked {
                AgeBlockedView()
                    .transition(.asymmetric(
                        insertion: AnyTransition.scale(scale: 0.94).combined(with: .opacity),
                        removal:   .opacity
                    ))
            } else if authState == .unauthenticated {
                AuthenticationScreen(onAuthenticated: {
                    withAnimation(FDS.Spring.hero) { authState = .authenticated }
                })
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal:   AnyTransition.scale(scale: 0.92).combined(with: .opacity)
                ))
            } else {
                OnboardingStepHost(
                    step: $step,
                    onFinish:     { store.isOnboarded = true },
                    onAgeBlocked: {
                        withAnimation(FDS.Spring.hero) { showAgeBlocked = true }
                    }
                )
                .transition(.asymmetric(
                    insertion: AnyTransition.scale(scale: 0.96).combined(with: .opacity),
                    removal:   .opacity
                ))
            }
        }
        .animation(FDS.Spring.hero, value: authState == .authenticated)
        .animation(FDS.Spring.hero, value: showAgeBlocked)
    }
}

// MARK: - Step Host

struct OnboardingStepHost: View {
    @Binding var step: Int
    @EnvironmentObject var store: AppStore
    let onFinish:     () -> Void
    let onAgeBlocked: () -> Void

    private let totalSteps = 8

    var body: some View {
        Group {
            switch step {
            case 0: AgeAndBirthdayView(onNext: { birthday in
                store.tempOnboardingProfile.birthday = birthday
                calculateAge(from: birthday) < 13 ? onAgeBlocked() : advance()
            })
            case 1: ProfileSetupView(onNext:       { advance() })
            case 2: BodyMetricsView(onNext:        { advance() })
            case 3: DeviceConnectionView(onNext:   { advance() })
            case 4: GoalsView(onNext:              { advance() })
            case 5: ExperienceLevelView(onNext:    { advance() })
            case 6: WorkoutTypesView(onNext:       { advance() })
            case 7: CoachingStyleView(onFinish:    { onFinish() })
            default: EmptyView()
            }
        }
        .id(step)
        .transition(.asymmetric(
            insertion: AnyTransition.move(edge: .trailing).combined(with: .opacity),
            removal:   AnyTransition.move(edge: .leading).combined(with: .opacity)
        ))
        .animation(FDS.Spring.page, value: step)
    }

    private func advance() {
        FDS.haptic(.light)
        withAnimation(FDS.Spring.page) { step += 1 }
    }
}

// ============================================================
// MARK: - Progress Header  (B polish on A skeleton)
// ============================================================

struct ForgeProgressHeader: View {
    let currentStep: Int
    let totalSteps:  Int
    let onBack:      () -> Void
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Back button — B's forgePress + shadow
            Button(action: { FDS.haptic(.light); onBack() }) {
                ZStack {
                    Circle()
                        .fill(Color.surface)
                        .frame(width: 38, height: 38)
                        .overlay(Circle().stroke(Color.borderColor, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
            }
            .opacity(currentStep > 0 ? 1 : 0)
            .scaleEffect(currentStep > 0 ? 1 : 0.7)
            .disabled(currentStep == 0)
            .animation(FDS.Spring.snap, value: currentStep)
            .forgePress()

            Spacer()

            // Segmented pill progress — B's complete/active/inactive logic
            HStack(spacing: 5) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    let isActive   = i == currentStep
                    let isComplete = i < currentStep
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isActive || isComplete ? Color.ember : Color.white.opacity(0.10))
                        .frame(width: isActive ? 26 : (isComplete ? 16 : 12), height: 3)
                        .animation(FDS.Spring.standard, value: currentStep)
                }
            }

            Spacer()

            Text("\(currentStep + 1) / \(totalSteps)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.textMuted)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, FDS.Spacing.lg)
        .padding(.top, 56)
        .padding(.bottom, 24)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: appeared)
        .onAppear { appeared = true }
    }
}

// ============================================================
// MARK: - Section Header  (B's animated rule + FDS tokens)
// ============================================================

struct ForgeSectionHeader: View {
    let eyebrow:     String
    let title:       String
    let subtitle:    String
    var accentColor: Color = .ember
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: appeared ? 18 : 0, height: 2)
                    .animation(FDS.Spring.hero.delay(0.04), value: appeared)
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(3.2)
                    .foregroundColor(accentColor)
                    .opacity(appeared ? 1 : 0)
                    .animation(FDS.Spring.hero.delay(0.06), value: appeared)
            }
            Text(title)
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(
                    colors: [.white, Color.white.opacity(0.78)],
                    startPoint: .top, endPoint: .bottom
                ))
                .lineSpacing(1)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(FDS.Spring.hero.delay(0.12), value: appeared)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(.textSecondary)
                .lineSpacing(5)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(FDS.Spring.hero.delay(0.20), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

// ============================================================
// MARK: - CTA Button  (B's inner specular + double shadow)
// ============================================================

struct ForgeCtaButton: View {
    let label:     String
    let icon:      String
    let isEnabled: Bool
    let action:    () -> Void
    @State private var pressed = false

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.background.opacity(0), Color.background],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 36)
            .allowsHitTesting(false)

            Button(action: { guard isEnabled else { return }; FDS.haptic(.medium); action() }) {
                HStack(spacing: 10) {
                    Text(label)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    isEnabled
                        ? AnyShapeStyle(FDS.Gradient.emberDeep)
                        : AnyShapeStyle(Color.white.opacity(0.05))
                )
                .cornerRadius(FDS.Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.lg)
                        .stroke(
                            isEnabled ? Color.ember.opacity(0.2) : Color.white.opacity(0.07),
                            lineWidth: 0.5
                        )
                )
                // B's inner top specular
                .overlay(alignment: .top) {
                    if isEnabled {
                        RoundedRectangle(cornerRadius: FDS.Radius.lg)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.12), .clear],
                                startPoint: .top, endPoint: .center
                            ))
                            .frame(height: 30)
                    }
                }
                // B's double ember shadow
                .shadow(color: isEnabled ? Color.ember.opacity(0.50) : .clear, radius: 22, y: 8)
                .shadow(color: isEnabled ? Color.ember.opacity(0.22) : .clear, radius: 44, y: 16)
                .scaleEffect(pressed ? 0.97 : 1.0)
                .animation(FDS.Spring.snap, value: pressed)
            }
            .disabled(!isEnabled)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true  }
                    .onEnded   { _ in pressed = false }
            )
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.bottom, 44)
            .animation(FDS.Spring.standard, value: isEnabled)
        }
        .background(Color.background)
    }
}

// ============================================================
// MARK: - Age Blocked  (A's shake, COPPA note, red tint)
// ============================================================

struct AgeBlockedView: View {
    @State private var appeared     = false
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color(hex: "0A0A0A").ignoresSafeArea()
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
                        Circle().stroke(Color.danger.opacity(0.2), lineWidth: 1.5).frame(width: 120, height: 120)
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

                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.danger)
                            Text("Minimum age: 13 years")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.danger)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color.danger.opacity(0.08))
                        .cornerRadius(FDS.Radius.pill)
                        .overlay(Capsule().stroke(Color.danger.opacity(0.25), lineWidth: 1))
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.5), value: appeared)
                    }
                }
                Spacer()
                VStack(spacing: 8) {
                    Text("Protected under COPPA & GDPR-K")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textMuted)
                    Text("Children's Online Privacy Protection Act")
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted.opacity(0.6))
                }
                .padding(.bottom, 52)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.7), value: appeared)
            }
        }
        .onAppear {
            appeared = true
            // A's 4-beat shake sequence
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shakeOffset =  12 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shakeOffset = -10 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shakeOffset =   7 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.spring(response: 0.3,  dampingFraction: 0.7 )) { shakeOffset =   0 }
                        }
                    }
                }
            }
        }
    }
}

// ============================================================
// MARK: - Age & Birthday  (A's full logic + B's FDS polish)
// ============================================================

struct AgeAndBirthdayView: View {
    let onNext: (Date) -> Void
    @State private var birthday:  Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var appeared   = false
    @State private var didChange  = false

    private var age:       Int  { calculateAge(from: birthday) }
    private var isUnderage: Bool { age < 13 }
    private var tooOld:    Bool  { age > 120 }
    private var isValid:   Bool  { !isUnderage && !tooOld }

    private var ageStatusText:  String {
        if tooOld    { return "Invalid date" }
        if isUnderage { return "Must be 13 or older" }
        return "\(age) years old"
    }
    private var ageStatusColor: Color { (isUnderage || tooOld) ? .danger : .success }

    var body: some View {
        VStack(spacing: 0) {
            // Top ember accent bar
            Rectangle()
                .fill(FDS.Gradient.emberDeep)
                .frame(height: 3)
                .ignoresSafeArea(edges: .top)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Mini wordmark
                    HStack {
                        Text("FORGE")
                            .font(.system(size: 11, weight: .black))
                            .tracking(5)
                            .foregroundColor(.ember)
                        Spacer()
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.ember)
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, FDS.Spacing.lg)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Before we\nbegin.")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundStyle(LinearGradient(
                                colors: [.white, Color.white.opacity(0.75)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .lineSpacing(2)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(FDS.Spring.hero.delay(0.1), value: appeared)

                        Text("We need to verify your age before accessing FORGE. This is required to keep our community safe.")
                            .font(.system(size: 15))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(5)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(FDS.Spring.hero.delay(0.2), value: appeared)
                    }
                    .padding(.horizontal, FDS.Spacing.lg)
                    .padding(.top, 24)
                    .padding(.bottom, 44)

                    // Birthday card
                    VStack(spacing: 0) {
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "birthday.cake.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.ember)
                                Text("Date of Birth")
                                    .font(.system(size: 12, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundColor(.textMuted)
                                    .textCase(.uppercase)
                            }
                            Spacer()
                            if didChange {
                                HStack(spacing: 6) {
                                    Circle().fill(ageStatusColor).frame(width: 6, height: 6)
                                    Text(ageStatusText)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(ageStatusColor)
                                }
                                .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.85)))
                            }
                        }
                        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

                        Divider().background(Color.white.opacity(0.06))

                        DatePicker("", selection: $birthday, in: minimumBirthday...Date(), displayedComponents: [.date])
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .tint(.ember)
                            .padding(.vertical, 8)

                        Divider().background(Color.white.opacity(0.06))

                        // Age milestone visualizer
                        HStack(spacing: 0) {
                            ForEach(Array([13, 18, 25, 40, 65].enumerated()), id: \.offset) { i, milestone in
                                let reached = age >= milestone
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
                                .animation(FDS.Spring.snap, value: age)
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 16)
                    }
                    .background(Color.surface)
                    .cornerRadius(FDS.Radius.lg)
                    .overlay(RoundedRectangle(cornerRadius: FDS.Radius.lg)
                        .stroke(isUnderage && didChange ? Color.danger.opacity(0.4) : Color.white.opacity(0.07), lineWidth: 1))
                    .shadow(color: isUnderage && didChange ? Color.danger.opacity(0.12) : .black.opacity(0.3), radius: 20, y: 8)
                    .padding(.horizontal, FDS.Spacing.lg)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(FDS.Spring.hero.delay(0.3), value: appeared)

                    // Underage warning banner
                    if isUnderage && didChange {
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
                        .cornerRadius(FDS.Radius.sm)
                        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.sm).stroke(Color.warning.opacity(0.2), lineWidth: 1))
                        .padding(.horizontal, FDS.Spacing.lg).padding(.top, 16)
                        .transition(.asymmetric(
                            insertion: AnyTransition.move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    // Privacy note
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.textMuted)
                            .padding(.top, 1)
                        Text("Your date of birth is encrypted and used only for age verification and fitness calculations. It will never be shared with third parties.")
                            .font(.system(size: 12))
                            .foregroundColor(.textMuted)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, FDS.Spacing.lg).padding(.top, 20)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.5), value: appeared)

                    Spacer(minLength: 100)
                }
            }

            // Bottom CTA (inline — not ForgeCtaButton so we can morph label/color)
            VStack(spacing: 0) {
                Divider().background(Color.white.opacity(0.06))
                Button(action: {
                    withAnimation(FDS.Spring.snap) { didChange = true }
                    if isValid { onNext(birthday) }
                }) {
                    HStack(spacing: 10) {
                        Text(isUnderage && didChange ? "Access Denied" : "Confirm Age")
                            .font(.system(size: 17, weight: .bold))
                        Image(systemName: isUnderage && didChange ? "xmark.circle.fill" : "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        isUnderage && didChange
                            ? AnyShapeStyle(Color.danger.opacity(0.3))
                            : AnyShapeStyle(FDS.Gradient.ember)
                    )
                    .cornerRadius(FDS.Radius.md)
                    // B's inner specular on this too
                    .overlay(alignment: .top) {
                        if isValid || !didChange {
                            RoundedRectangle(cornerRadius: FDS.Radius.md)
                                .fill(LinearGradient(
                                    colors: [Color.white.opacity(0.10), .clear],
                                    startPoint: .top, endPoint: .center
                                ))
                                .frame(height: 26)
                        }
                    }
                    .shadow(color: isValid ? Color.ember.opacity(0.4) : .clear, radius: 18, y: 6)
                }
                .padding(.horizontal, FDS.Spacing.lg)
                .padding(.top, 16).padding(.bottom, 40)
                .animation(FDS.Spring.standard, value: isUnderage && didChange)
            }
            .background(Color.background.overlay(
                LinearGradient(colors: [Color.background.opacity(0), Color.background], startPoint: .top, endPoint: .bottom)
            ))
        }
        .background(Color.background)
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: birthday) { _, _ in
            withAnimation(FDS.Spring.snap) { didChange = true }
        }
        .onAppear { withAnimation { appeared = true } }
    }
}

// ============================================================
// MARK: - Profile Setup  (A's store integration + B's polish)
// ============================================================

struct ProfileSetupView: View {
    let onNext: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var name:           String = ""
    @State private var selectedGender: Gender = .preferNotToSay
    @State private var subStep         = 0
    @State private var appeared        = false

    var canContinue: Bool {
        subStep == 0 ? !name.trimmingCharacters(in: .whitespaces).isEmpty : true
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeProgressHeader(currentStep: 1, totalSteps: 8) {
                if subStep > 0 { withAnimation(FDS.Spring.page) { subStep -= 1 } }
            }

            ScrollView(showsIndicators: false) {
                Group {
                    if subStep == 0 {
                        VStack(alignment: .leading, spacing: 32) {
                            ForgeSectionHeader(
                                eyebrow: "Identity",
                                title: "What should\nARIA call you?",
                                subtitle: "Your AI coach uses your name to make every interaction feel personal."
                            )
                            VStack(spacing: 8) {
                                ForgeTextField(placeholder: "Enter your name", text: $name, icon: "person.fill")
                                if !name.isEmpty {
                                    Text("Hello, \(name.trimmingCharacters(in: .whitespaces)) 👋")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.ember)
                                        .padding(.leading, 4)
                                        .transition(AnyTransition.opacity.combined(with: AnyTransition.move(edge: .top)))
                                }
                            }
                            .animation(FDS.Spring.standard, value: name.isEmpty)
                        }
                        .transition(.asymmetric(
                            insertion: AnyTransition.move(edge: .trailing).combined(with: .opacity),
                            removal:   AnyTransition.move(edge: .leading).combined(with: .opacity)
                        ))
                    } else {
                        VStack(alignment: .leading, spacing: 32) {
                            ForgeSectionHeader(
                                eyebrow: "Profile",
                                title: "How do\nyou identify?",
                                subtitle: "Used to personalize training and nutrition recommendations."
                            )
                            VStack(spacing: 10) {
                                ForEach(Gender.allCases) { gender in
                                    GenderSelectionCard(
                                        gender: gender,
                                        isSelected: selectedGender == gender,
                                        action: { selectedGender = gender; FDS.selectionHaptic() }
                                    )
                                }
                            }
                        }
                        .transition(.asymmetric(
                            insertion: AnyTransition.move(edge: .trailing).combined(with: .opacity),
                            removal:   AnyTransition.move(edge: .leading).combined(with: .opacity)
                        ))
                    }
                }
                .id(subStep)
                .animation(FDS.Spring.page, value: subStep)
                .padding(.horizontal, FDS.Spacing.lg)
                .padding(.bottom, 120)
            }

            ForgeCtaButton(
                label:     subStep == 0 ? "Continue"     : "Save Profile",
                icon:      subStep == 0 ? "arrow.right"  : "checkmark",
                isEnabled: canContinue
            ) {
                if subStep == 0 {
                    store.tempOnboardingProfile.name = name.trimmingCharacters(in: .whitespaces)
                    withAnimation(FDS.Spring.page) { subStep = 1 }
                } else {
                    store.tempOnboardingProfile.gender = selectedGender
                    onNext()
                }
            }
        }
        .background(Color.background).ignoresSafeArea(edges: .bottom)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { appeared = true } }
    }
}

// ============================================================
// MARK: - Body Metrics  (A's store + BMI, B's FDS tokens)
// ============================================================

struct BodyMetricsView: View {
    let onNext: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var heightCm:   Double = 170
    @State private var weightKg:   Double = 70
    @State private var useImperial = false
    @State private var appeared    = false

    private var heightDisplay: String {
        if useImperial {
            let total = Int(heightCm / 2.54); return "\(total / 12)' \(total % 12)\""
        }
        return "\(Int(heightCm)) cm"
    }
    private var weightDisplay: String {
        useImperial ? "\(Int(weightKg * 2.20462)) lbs" : "\(Int(weightKg)) kg"
    }
    private var bmi: Double { weightKg / pow(heightCm / 100, 2) }
    private var bmiCategory: (label: String, color: Color) {
        switch bmi {
        case ..<18.5: return ("Underweight", .warning)
        case 18.5..<25: return ("Healthy",   .success)
        case 25..<30:   return ("Overweight", .warning)
        default:        return ("Obese",      .danger)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeProgressHeader(currentStep: 2, totalSteps: 8) {}
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForgeSectionHeader(eyebrow: "Biometrics", title: "Your body\nmetrics",
                        subtitle: "Used to calibrate workout intensity, calorie burn, and nutritional targets.")
                        .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 36)

                    // Unit toggle
                    HStack {
                        Spacer()
                        HStack(spacing: 0) {
                            ForEach(["Metric", "Imperial"], id: \.self) { unit in
                                let selected = unit == (useImperial ? "Imperial" : "Metric")
                                Button(action: {
                                    withAnimation(FDS.Spring.snap) { useImperial = unit == "Imperial" }
                                    FDS.selectionHaptic()
                                }) {
                                    Text(unit)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(selected ? .white : .textMuted)
                                        .padding(.horizontal, 14).padding(.vertical, 7)
                                        .background(selected ? Color.ember : .clear)
                                        .cornerRadius(FDS.Radius.xs)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3).background(Color.surface).cornerRadius(11)
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.borderColor, lineWidth: 0.5))
                    }
                    .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 24)

                    MetricSliderCard(title: "Height", icon: "arrow.up.and.down",
                        displayValue: heightDisplay, sliderValue: $heightCm, range: 120...220, step: 1)
                        .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 16)

                    MetricSliderCard(title: "Weight", icon: "scalemass.fill",
                        displayValue: weightDisplay, sliderValue: $weightKg, range: 30...200, step: 0.5)
                        .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 24)

                    // BMI readout
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BMI").font(.system(size: 11, weight: .bold)).tracking(1.5)
                                .foregroundColor(.textMuted).textCase(.uppercase)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(String(format: "%.1f", bmi))
                                    .font(.system(size: 28, weight: .black, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                                Text(bmiCategory.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(bmiCategory.color)
                            }
                        }
                        Spacer()
                        VStack(spacing: 4) {
                            HStack(spacing: 2) {
                                ForEach(0..<4, id: \.self) { i in
                                    let cols: [Color] = [.steel, .success, .warning, .danger]
                                    let active = (i==0 && bmi<18.5)||(i==1 && bmi>=18.5 && bmi<25)||(i==2 && bmi>=25 && bmi<30)||(i==3 && bmi>=30)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(cols[i].opacity(active ? 1 : 0.25))
                                        .frame(width: 32, height: active ? 8 : 4)
                                        .animation(FDS.Spring.standard, value: bmi)
                                }
                            }
                            Text("BMI Scale").font(.system(size: 9, weight: .medium)).foregroundColor(.textMuted)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 18)
                    .background(Color.surface).cornerRadius(FDS.Radius.md)
                    .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(Color.borderColor, lineWidth: 0.5))
                    .padding(.horizontal, FDS.Spacing.lg)
                    .animation(FDS.Spring.standard, value: bmi)

                    Text("BMI is a general reference, not a diagnosis. ARIA uses your full biometric profile for personalized recommendations.")
                        .font(.system(size: 11)).foregroundColor(.textMuted).lineSpacing(3)
                        .padding(.horizontal, FDS.Spacing.lg).padding(.top, 12).padding(.bottom, 120)
                }
            }
            ForgeCtaButton(label: "Continue", icon: "arrow.right", isEnabled: true) {
                store.tempOnboardingProfile.heightCm = heightCm
                store.tempOnboardingProfile.weightKg = weightKg
                onNext()
            }
        }
        .background(Color.background).ignoresSafeArea(edges: .bottom)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { appeared = true } }
    }
}

struct MetricSliderCard: View {
    let title: String; let icon: String; let displayValue: String
    @Binding var sliderValue: Double; let range: ClosedRange<Double>; let step: Double

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 13)).foregroundColor(.ember)
                    Text(title).font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundColor(.textMuted).textCase(.uppercase)
                }
                Spacer()
                Text(displayValue).font(.system(size: 22, weight: .black, design: .monospaced)).foregroundColor(.textPrimary)
            }
            Slider(value: $sliderValue, in: range, step: step).tint(.ember)
        }
        .padding(20).background(Color.surface).cornerRadius(FDS.Radius.md)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(Color.borderColor, lineWidth: 0.5))
    }
}

// ============================================================
// MARK: - Device Connection  (A's full DeviceCard + store)
// ============================================================

struct DeviceConnectionView: View {
    let onNext: () -> Void
    @State private var connectedDevices: Set<String> = []
    @State private var appeared = false

    private let devices: [(name: String, icon: String, desc: String)] = [
        ("Apple Watch", "applewatch",            "Heart rate, activity rings & workouts"),
        ("Oura Ring",   "circle.circle.fill",    "Sleep stages, HRV & readiness score"),
        ("WHOOP",       "waveform.path.ecg",     "Strain, recovery & sleep performance"),
        ("Garmin",      "figure.run",             "Training load, VO2 max & performance"),
        ("Fitbit",      "heart.text.square.fill", "Daily activity, heart rate & sleep"),
        ("Polar",       "waveform",               "Advanced HR monitoring & training zones"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForgeProgressHeader(currentStep: 3, totalSteps: 8) {}
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForgeSectionHeader(eyebrow: "Sync", title: "Connect\nyour devices",
                        subtitle: "FORGE syncs real biometric data from your wearables to power ARIA's coaching.")
                        .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 24)

                    if !connectedDevices.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(.success)
                            Text("\(connectedDevices.count) device\(connectedDevices.count == 1 ? "" : "s") syncing")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.success)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.success.opacity(0.09)).cornerRadius(FDS.Radius.pill)
                        .overlay(Capsule().stroke(Color.success.opacity(0.25), lineWidth: 1))
                        .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 20)
                        .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.9)))
                    }

                    VStack(spacing: 10) {
                        ForEach(Array(devices.enumerated()), id: \.element.name) { index, device in
                            DeviceCard(
                                name: device.name, icon: device.icon, desc: device.desc,
                                isConnected: Binding(
                                    get: { connectedDevices.contains(device.name) },
                                    set: { if $0 { connectedDevices.insert(device.name) } else { connectedDevices.remove(device.name) } }
                                ),
                                index: index
                            )
                        }
                    }
                    .padding(.horizontal, FDS.Spacing.lg)

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").font(.system(size: 11)).foregroundColor(.textMuted)
                        Text("You can connect more devices later in Settings → Integrations")
                            .font(.system(size: 11)).foregroundColor(.textMuted)
                    }
                    .padding(.horizontal, FDS.Spacing.lg).padding(.top, 16).padding(.bottom, 120)
                }
            }
            ForgeCtaButton(
                label: connectedDevices.isEmpty ? "Skip for now" : "Continue",
                icon:  connectedDevices.isEmpty ? "arrow.right"  : "checkmark",
                isEnabled: true
            ) { onNext() }
        }
        .background(Color.background).ignoresSafeArea(edges: .bottom)
        .animation(FDS.Spring.standard, value: connectedDevices.count)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { appeared = true } }
    }
}

// A's DeviceCard — tappable button, staggered entrance, B's FDS polish
struct DeviceCard: View {
    let name: String; let icon: String; let desc: String
    @Binding var isConnected: Bool; let index: Int
    @State private var appeared = false

    var body: some View {
        Button(action: {
            withAnimation(FDS.Spring.standard) { isConnected.toggle() }
            FDS.selectionHaptic()
        }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isConnected ? Color.success.opacity(0.15) : Color.surfaceElevated)
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(isConnected ? .success : .textTertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isConnected ? .success : .textPrimary)
                    Text(desc).font(.system(size: 12)).foregroundColor(.textTertiary).lineLimit(2)
                }
                Spacer()
                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20)).foregroundColor(.success)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 20)).foregroundColor(.textMuted)
                }
            }
            .padding(14)
            .background(isConnected ? Color.success.opacity(0.06) : Color.surface)
            .cornerRadius(FDS.Radius.md)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md)
                .stroke(isConnected ? Color.success.opacity(0.45) : Color.borderColor,
                        lineWidth: isConnected ? 1.5 : 0.5))
            .shadow(color: isConnected ? Color.success.opacity(0.12) : .black.opacity(0.04), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .animation(FDS.Spring.standard, value: isConnected)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(Double(index) * 0.08)) { appeared = true }
        }
    }
}

// ============================================================
// MARK: - Goals  (A's store, B's FDS + forgeEntrance)
// ============================================================

struct GoalsView: View {
    let onNext: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var selectedGoals: Set<OnboardingFitnessGoal> = []
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ForgeProgressHeader(currentStep: 4, totalSteps: 8) {}
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForgeSectionHeader(eyebrow: "Goals", title: "What are you\ntraining for?",
                        subtitle: "Select all that apply. ARIA prioritizes your program around these targets.")
                        .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 32)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Array(OnboardingFitnessGoal.allCases.enumerated()), id: \.element) { i, goal in
                            GoalCard(
                                goal: goal,
                                isSelected: selectedGoals.contains(goal),
                                action: {
                                    if selectedGoals.contains(goal) { selectedGoals.remove(goal) }
                                    else { selectedGoals.insert(goal) }
                                    FDS.selectionHaptic()
                                }
                            )
                            .forgeEntrance(index: i, appeared: appeared)
                        }
                    }
                    .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 120)
                }
            }
            ForgeCtaButton(
                label: selectedGoals.isEmpty ? "Select at least one" : "Continue — \(selectedGoals.count) goal\(selectedGoals.count == 1 ? "" : "s")",
                icon: "arrow.right", isEnabled: !selectedGoals.isEmpty
            ) {
                store.tempOnboardingProfile.fitnessGoals = Array(selectedGoals)
                onNext()
            }
        }
        .background(Color.background).ignoresSafeArea(edges: .bottom)
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { appeared = true } }
    }
}

struct GoalCard: View {
    let goal: OnboardingFitnessGoal; let isSelected: Bool; let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
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
                            .transition(AnyTransition.scale.combined(with: .opacity))
                    }
                }
                Text(goal.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .textPrimary : .textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.ember.opacity(0.06) : Color.surface)
            .cornerRadius(FDS.Radius.md)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md)
                .stroke(isSelected ? Color.ember.opacity(0.45) : Color.borderColor,
                        lineWidth: isSelected ? 1.5 : 0.5))
            .shadow(color: isSelected ? Color.ember.opacity(0.12) : .black.opacity(0.06),
                    radius: isSelected ? 12 : 4, y: 3)
        }
        .buttonStyle(.plain).forgePress()
        .animation(FDS.Spring.standard, value: isSelected)
    }
}

// ============================================================
// MARK: - Experience Level  (A's store + B's level-specific colors)
// ============================================================

struct ExperienceLevelView: View {
    let onNext: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var experienceLevel: ExperienceLevel? = nil
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ForgeProgressHeader(currentStep: 5, totalSteps: 8) {}
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForgeSectionHeader(eyebrow: "Experience", title: "Where are you\nright now?",
                        subtitle: "Honest self-assessment unlocks the right starting intensity and progression speed.")
                        .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 32)

                    VStack(spacing: 12) {
                        ForEach(ExperienceLevel.allCases) { level in
                            ExperienceLevelButton(
                                level: level, isSelected: experienceLevel == level,
                                action: { experienceLevel = level; FDS.selectionHaptic() }
                            )
                        }
                    }
                    .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 120)
                }
            }
            ForgeCtaButton(
                label: experienceLevel == nil ? "Select your level" : "Continue",
                icon: "arrow.right", isEnabled: experienceLevel != nil
            ) {
                store.tempOnboardingProfile.experienceLevel = experienceLevel ?? .intermediate
                onNext()
            }
        }
        .background(Color.background).ignoresSafeArea(edges: .bottom)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { appeared = true } }
    }
}

// ============================================================
// MARK: - Workout Types  (A's OnboardingWorkoutType store)
// ============================================================

struct WorkoutTypesView: View {
    let onNext: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var selectedWorkouts: Set<OnboardingWorkoutType> = []
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ForgeProgressHeader(currentStep: 6, totalSteps: 8) {}
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForgeSectionHeader(eyebrow: "Training", title: "What do you\nlove training?",
                        subtitle: "ARIA builds programs around what you already enjoy — sustainability is the key to results.")
                        .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 32)

                    OnboardingFlowLayout(spacing: 10) {
                        ForEach(OnboardingWorkoutType.allCases) { type in
                            TogglePill(label: type.label, isSelected: selectedWorkouts.contains(type)) {
                                if selectedWorkouts.contains(type) { selectedWorkouts.remove(type) }
                                else { selectedWorkouts.insert(type) }
                                FDS.selectionHaptic()
                            }
                        }
                    }
                    .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 120)
                }
            }
            ForgeCtaButton(
                label: selectedWorkouts.isEmpty ? "Pick your favorites" : "Continue — \(selectedWorkouts.count) selected",
                icon: "arrow.right", isEnabled: !selectedWorkouts.isEmpty
            ) {
                store.tempOnboardingProfile.preferredWorkouts = Array(selectedWorkouts)
                onNext()
            }
        }
        .background(Color.background).ignoresSafeArea(edges: .bottom)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { appeared = true } }
    }
}

// ============================================================
// MARK: - Coaching Style  (A's toCoreProfile commit + B's polish)
// ============================================================

struct CoachingStyleView: View {
    let onFinish: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var selected:       OnboardingCoachingStyle = .balanced
    @State private var appeared        = false
    @State private var readyToLaunch   = false

    var body: some View {
        VStack(spacing: 0) {
            ForgeProgressHeader(currentStep: 7, totalSteps: 8) {}
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForgeSectionHeader(eyebrow: "ARIA Setup", title: "Choose your\ncoach.",
                        subtitle: "How should ARIA push you? This shapes every message, plan, and check-in.")
                        .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 32)

                    VStack(spacing: 12) {
                        ForEach(OnboardingCoachingStyle.allCases) { style in
                            CoachingStyleCard(style: style, isSelected: selected == style) {
                                selected = style; FDS.selectionHaptic()
                            }
                        }
                    }
                    .padding(.horizontal, FDS.Spacing.lg)

                    // ARIA live preview
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(FDS.Gradient.ember)
                                .frame(width: 28, height: 28)
                                .overlay(Text("A").font(.system(size: 12, weight: .black)).foregroundColor(.white))
                            Text("ARIA Preview")
                                .font(.system(size: 11, weight: .bold)).tracking(1.2)
                                .foregroundColor(.textMuted).textCase(.uppercase)
                        }
                        Text(ariaPreviewMessage)
                            .font(.system(size: 14)).foregroundColor(.textSecondary).lineSpacing(5)
                            .padding(16).background(Color.surface).cornerRadius(FDS.Radius.md)
                            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md)
                                .stroke(selected.color.opacity(0.3), lineWidth: 1))
                            .id(selected.rawValue)
                            .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.97)))
                            .animation(FDS.Spring.standard, value: selected)
                    }
                    .padding(.horizontal, FDS.Spacing.lg).padding(.top, 28).padding(.bottom, 120)
                }
            }

            // Launch button — A's toCoreProfile() commit + B's double shadow + inner specular
            VStack(spacing: 0) {
                LinearGradient(colors: [Color.background.opacity(0), Color.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 32)

                Button(action: {
                    store.tempOnboardingProfile.coachingStyle = selected
                    store.userProfile = store.tempOnboardingProfile.toCoreProfile()  // A's commit
                    FDS.haptic(.heavy)
                    withAnimation(FDS.Spring.snap) { readyToLaunch = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onFinish() }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "flame.fill").font(.system(size: 16))
                        Text("Start Training with ARIA").font(.system(size: 16, weight: .bold))
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 60)
                    .background(FDS.Gradient.emberDeep)
                    .cornerRadius(FDS.Radius.lg)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: FDS.Radius.lg)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.14), .clear],
                                startPoint: .top, endPoint: .center
                            ))
                            .frame(height: 30)
                    }
                    .shadow(color: Color.ember.opacity(0.55), radius: 24, y: 10)
                    .shadow(color: Color.ember.opacity(0.25), radius: 48, y: 18)
                    .scaleEffect(readyToLaunch ? 0.97 : 1.0)
                    .animation(FDS.Spring.snap, value: readyToLaunch)
                }
                .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 44)
            }
            .background(Color.background)
        }
        .background(Color.background).ignoresSafeArea(edges: .bottom)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { appeared = true } }
    }

    private var ariaPreviewMessage: String {
        switch selected {
        case .drill_sergeant: return "Day one starts NOW. No warm-up to failure philosophy — we push hard from the gate. You said you wanted results. Prove it."
        case .balanced:       return "Great choice on your goals. I've built this week's plan around progressive overload with smart recovery windows. Let's get after it."
        case .supportive:     return "I'm so proud of you for starting this journey. Every step counts, and I'm here with you for all of it. You've got this! 🌟"
        case .scientist:      return "Based on your HRV baseline (62ms) and training load from the past 7 days, I'm prescribing a Zone 2 session today with a target of 140-155 bpm."
        }
    }
}

// ============================================================
// MARK: - Auth Screen  (B's FDS + reduceMotion + PulsingRingView)
// ============================================================

struct AuthenticationScreen: View {
    let onAuthenticated: () -> Void
    @State private var appeared  = false
    @State private var pulseRing = false
    @State private var orbGlow   = false
    @State private var showEmail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarFieldView(size: geo.size)
                VStack(spacing: 0) {
                    Spacer()

                    // Hero orb
                    ZStack {
                        if !reduceMotion {
                            ForEach(0..<3, id: \.self) { i in
                                PulsingRingView(index: i, color: .ember, isAnimating: pulseRing)
                            }
                        }
                        Circle()
                            .fill(RadialGradient(
                                colors: [Color.ember.opacity(orbGlow ? 0.38 : 0.16), .clear],
                                center: .center, startRadius: 0, endRadius: 120
                            ))
                            .frame(width: 240, height: 240).blur(radius: 36)

                        // B's screen-blend bloom
                        Circle()
                            .fill(RadialGradient(
                                colors: [Color.white.opacity(orbGlow ? 0.08 : 0.02), .clear],
                                center: .center, startRadius: 0, endRadius: 100
                            ))
                            .frame(width: 200, height: 200).blur(radius: 20)
                            .blendMode(.screen)

                        ZStack {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 92, weight: .black))
                                .foregroundColor(.black.opacity(0.3)).blur(radius: 14).offset(y: 12)
                            Image(systemName: "flame.fill")
                                .font(.system(size: 92, weight: .black))
                                .foregroundStyle(LinearGradient(
                                    colors: [.white, Color(hex: "FF6A00"), Color(hex: "FF2200")],
                                    startPoint: .top, endPoint: .bottom
                                ))
                                .shadow(color: Color.ember.opacity(0.95), radius: 44)
                                .shadow(color: Color(hex: "FF2200").opacity(0.5), radius: 80)
                                .shadow(color: Color.white.opacity(0.3), radius: 12)
                        }
                        .scaleEffect(appeared ? 1 : 0.35)
                        .rotationEffect(.degrees(appeared ? 0 : -95))
                        .opacity(appeared ? 1 : 0)
                        .animation(FDS.adaptiveAnimation(FDS.Spring.floaty).delay(0.15), value: appeared)
                    }
                    .padding(.bottom, 44)

                    // Wordmark
                    VStack(spacing: 10) {
                        Text("FORGE")
                            .font(.system(size: 72, weight: .black, design: .rounded)).tracking(22)
                            .foregroundStyle(LinearGradient(
                                colors: [.white, Color.ember, Color(hex: "FF6A00"), .white.opacity(0.9)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .shadow(color: Color.ember.opacity(0.6), radius: 30, y: 5)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 26)
                            .animation(FDS.Spring.hero.delay(0.28), value: appeared)
                        Text("Forge Your Strongest Self")
                            .font(.system(size: 17, weight: .semibold)).tracking(1.2)
                            .foregroundColor(.textSecondary)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
                            .animation(FDS.Spring.hero.delay(0.36), value: appeared)
                    }
                    .padding(.bottom, 18)

                    // Ember rule
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, Color.ember.opacity(0.65)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: appeared ? 60 : 0, height: 1.5)
                        Circle().fill(Color.ember).frame(width: 5, height: 5)
                            .shadow(color: Color.ember.opacity(0.8), radius: 6).opacity(appeared ? 1 : 0)
                        Rectangle()
                            .fill(LinearGradient(colors: [Color.ember.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: appeared ? 60 : 0, height: 1.5)
                    }
                    .animation(FDS.Spring.hero.delay(0.44), value: appeared).padding(.bottom, 22)

                    HStack(spacing: 8) {
                        ForEach(["AI Coach", "Biometrics", "Adaptive Plans"], id: \.self) { feat in
                            Text(feat).font(.system(size: 11, weight: .semibold)).foregroundColor(.textMuted)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.white.opacity(0.05)).cornerRadius(FDS.Radius.pill)
                                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                        }
                    }
                    .opacity(appeared ? 1 : 0).animation(.easeOut(duration: 0.4).delay(0.50), value: appeared)

                    Spacer()

                    VStack(spacing: 14) {
                        SignInWithAppleButton(.signUp) { req in req.requestedScopes = [.fullName, .email] }
                        onCompletion: { result in if case .success = result { onAuthenticated() } }
                            .signInWithAppleButtonStyle(.white).frame(height: 58).cornerRadius(18)
                            .shadow(color: .black.opacity(0.25), radius: 28, y: 10)
                            .shadow(color: Color.ember.opacity(0.15), radius: 16, y: 4)
                            .padding(.horizontal, FDS.Spacing.lg)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 30)
                            .animation(FDS.Spring.hero.delay(0.60), value: appeared)

                        HStack(spacing: 14) {
                            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
                            Text("or continue with").font(.system(size: 12, weight: .medium)).foregroundColor(.textMuted).fixedSize()
                            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
                        }
                        .padding(.horizontal, FDS.Spacing.lg)
                        .opacity(appeared ? 0.8 : 0).animation(.easeOut(duration: 0.35).delay(0.68), value: appeared)

                        HStack(spacing: 12) {
                            OAuthRowButton(icon: "globe", label: "Google",
                                action: { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onAuthenticated() } })
                            OAuthRowButton(icon: "envelope.fill", label: "Email", action: { showEmail = true })
                        }
                        .padding(.horizontal, FDS.Spacing.lg)
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 24)
                        .animation(FDS.Spring.hero.delay(0.72), value: appeared)

                        Text("By continuing you agree to our Terms & Privacy Policy.")
                            .font(.system(size: 11)).foregroundColor(.textMuted.opacity(0.5))
                            .multilineTextAlignment(.center).padding(.horizontal, 44)
                            .opacity(appeared ? 1 : 0).animation(.easeOut(duration: 0.3).delay(0.82), value: appeared)
                    }
                    .padding(.bottom, 52)
                }
            }
        }
        .sheet(isPresented: $showEmail) { EmailAuthSheet(onAuthenticated: onAuthenticated) }
        .onAppear {
            appeared = true
            if !reduceMotion {
                withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false))  { pulseRing = true }
                withAnimation(.easeInOut(duration: FDS.Duration.breathe).repeatForever(autoreverses: true)) { orbGlow = true }
            }
        }
    }
}

// ============================================================
// MARK: - Shared Components  (B's FDS polish throughout)
// ============================================================

// GenderSelectionCard — B's radio ring + inner fill animation
struct GenderSelectionCard: View {
    let gender: Gender; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: { action(); FDS.selectionHaptic() }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(isSelected ? Color.ember.opacity(0.16) : Color.surfaceElevated).frame(width: 48, height: 48)
                    if isSelected { Circle().stroke(Color.ember.opacity(0.4), lineWidth: 1.5).frame(width: 48, height: 48) }
                    Image(systemName: gender.icon).font(.system(size: 18))
                        .foregroundColor(isSelected ? .ember : .textSecondary)
                        .scaleEffect(isSelected ? 1.1 : 1.0).animation(FDS.Spring.snap, value: isSelected)
                }
                Text(gender.label).font(.system(size: 15, weight: .medium)).foregroundColor(isSelected ? .ember : .textPrimary)
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
                if isSelected { RoundedRectangle(cornerRadius: FDS.Radius.md).fill(Color.ember.opacity(0.04)) }
            })
            .cornerRadius(FDS.Radius.md)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md)
                .stroke(isSelected ? Color.ember.opacity(0.5) : Color.borderColor, lineWidth: isSelected ? 1.5 : 0.5))
            .shadow(color: isSelected ? Color.ember.opacity(0.14) : .black.opacity(0.04), radius: isSelected ? 12 : 4, y: 3)
        }
        .buttonStyle(.plain).animation(FDS.Spring.standard, value: isSelected)
    }
}

// ExperienceLevelButton — B's level-specific colors per tier
struct ExperienceLevelButton: View {
    let level: ExperienceLevel; let isSelected: Bool; let action: () -> Void
    private var icon: String {
        switch level { case .beginner: "leaf.fill"; case .intermediate: "bolt.fill"; case .advanced: "flame.fill"; case .elite: "crown.fill" }
    }
    // B's per-level color system
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
                    Image(systemName: icon).font(.system(size: 20))
                        .foregroundColor(isSelected ? levelColor : .textTertiary)
                        .scaleEffect(isSelected ? 1.1 : 1.0).animation(FDS.Spring.snap, value: isSelected)
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
            .padding(15)
            .background(ZStack {
                Color.surface
                if isSelected { RoundedRectangle(cornerRadius: FDS.Radius.md).fill(levelColor.opacity(0.05)) }
            })
            .cornerRadius(FDS.Radius.md)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md)
                .stroke(isSelected ? levelColor.opacity(0.45) : Color.borderColor, lineWidth: isSelected ? 1.5 : 0.5))
            .shadow(color: isSelected ? levelColor.opacity(0.15) : .black.opacity(0.04), radius: isSelected ? 14 : 4, y: 3)
        }
        .buttonStyle(.plain).animation(FDS.Spring.standard, value: isSelected)
    }
}

// CoachingStyleCard — A's OnboardingCoachingStyle type + B's blurred ring glow
struct CoachingStyleCard: View {
    let style: OnboardingCoachingStyle; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: { action(); FDS.selectionHaptic() }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(isSelected ? style.color.opacity(0.20) : Color.surfaceElevated).frame(width: 52, height: 52)
                    if isSelected { Circle().stroke(style.color.opacity(0.4), lineWidth: 1.5).frame(width: 52, height: 52).blur(radius: 1) }
                    Image(systemName: style.icon).font(.system(size: 21))
                        .foregroundColor(isSelected ? style.color : .textTertiary)
                        .scaleEffect(isSelected ? 1.08 : 1.0).animation(FDS.Spring.snap, value: isSelected)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(style.label).font(.system(size: 15, weight: .semibold)).foregroundColor(isSelected ? style.color : .textPrimary)
                    Text(style.description).font(.system(size: 12)).foregroundColor(.textTertiary).lineLimit(2).lineSpacing(3)
                }
                Spacer()
                ZStack {
                    Circle().stroke(isSelected ? style.color : Color.borderColor, lineWidth: 2).frame(width: 22, height: 22)
                    if isSelected { Circle().fill(style.color).frame(width: 12, height: 12).transition(.scale.combined(with: .opacity)) }
                }
                .animation(FDS.Spring.snap, value: isSelected)
            }
            .padding(16)
            .background(ZStack {
                Color.surface
                if isSelected { RoundedRectangle(cornerRadius: FDS.Radius.lg).fill(style.color.opacity(0.06)) }
            })
            .cornerRadius(FDS.Radius.lg)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.lg)
                .stroke(isSelected ? style.color.opacity(0.55) : Color.borderColor, lineWidth: isSelected ? 1.5 : 0.5))
            .shadow(color: isSelected ? style.color.opacity(0.18) : .black.opacity(0.04),
                    radius: isSelected ? 16 : 4, y: isSelected ? 6 : 2)
        }
        .buttonStyle(.plain).animation(FDS.Spring.standard, value: isSelected)
    }
}

// TogglePill — B's forgePress drag gesture + scaleEffect
struct TogglePill: View {
    let label: String; let isSelected: Bool; let onTap: () -> Void
    @State private var pressed = false
    var body: some View {
        Button(action: { onTap(); FDS.selectionHaptic() }) {
            Text(label).font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .ember : .textSecondary)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(isSelected ? Color.ember.opacity(0.13) : Color.surface)
                .cornerRadius(FDS.Radius.pill)
                .overlay(Capsule().stroke(isSelected ? Color.ember.opacity(0.6) : Color.borderColor, lineWidth: isSelected ? 1.5 : 0.5))
                .shadow(color: isSelected ? Color.ember.opacity(0.18) : .clear, radius: 8, y: 2)
                .scaleEffect(pressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .animation(FDS.Spring.snap, value: isSelected)
        .animation(FDS.Spring.snap, value: pressed)
    }
}

// OAuthRowButton — B's inner specular
struct OAuthRowButton: View {
    let icon: String; let label: String; let action: () -> Void
    @State private var pressed = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                Text(label).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(Color.surface).cornerRadius(FDS.Radius.md)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(Color.borderColor, lineWidth: 0.5))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: FDS.Radius.md)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center))
                    .frame(height: 20)
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .scaleEffect(pressed ? 0.96 : 1.0).animation(FDS.Spring.snap, value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
    }
}

// ForgeTextField — B's icon scale on focus
struct ForgeTextField: View {
    let placeholder: String; @Binding var text: String; let icon: String
    var keyboardType: UIKeyboardType = .default; var isSecure: Bool = false
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16))
                .foregroundColor(focused ? .ember : .textMuted).frame(width: 22)
                .scaleEffect(focused ? 1.1 : 1.0).animation(FDS.Spring.snap, value: focused)
            ZStack(alignment: .leading) {
                if text.isEmpty { Text(placeholder).font(.system(size: 16)).foregroundColor(.textMuted).allowsHitTesting(false) }
                if isSecure { SecureField("", text: $text).font(.system(size: 16)).foregroundColor(.textPrimary).tint(.ember).focused($focused) }
                else { TextField("", text: $text).font(.system(size: 16)).foregroundColor(.textPrimary).tint(.ember)
                        .focused($focused).keyboardType(keyboardType).autocapitalization(.none).disableAutocorrection(true) }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 18)
        .background(ZStack {
            Color.surface
            if focused { RoundedRectangle(cornerRadius: FDS.Radius.md).fill(Color.ember.opacity(0.04)) }
        })
        .cornerRadius(FDS.Radius.md)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md)
            .stroke(focused ? Color.ember.opacity(0.65) : Color.borderColor, lineWidth: focused ? 1.5 : 0.5))
        .shadow(color: focused ? Color.ember.opacity(0.12) : .clear, radius: 12, y: 4)
        .animation(FDS.Spring.standard, value: focused)
    }
}

// StarFieldView — B's 65-star optimized version
private struct StarDatum: Identifiable {
    let id: Int; let x, y, size: CGFloat; let baseOpacity, phaseOffset: Double
}
struct StarFieldView: View {
    let size: CGSize
    @State private var stars: [StarDatum] = []
    @State private var globalPhase: Double = 0
    var body: some View {
        ZStack {
            ForEach(stars) { star in
                Circle().fill(Color.white).frame(width: star.size, height: star.size)
                    .position(x: star.x, y: star.y)
                    .opacity(star.baseOpacity * (0.3 + 0.7 * abs(sin(globalPhase + star.phaseOffset))))
            }
        }
        .onAppear {
            stars = (0..<65).map { i in
                StarDatum(id: i, x: .random(in: 0...size.width), y: .random(in: 0...size.height),
                          size: .random(in: 0.7...3.2), baseOpacity: .random(in: 0.08...0.5),
                          phaseOffset: .random(in: 0...(.pi * 2)))
            }
            withAnimation(.linear(duration: FDS.Duration.ambient * 0.5).repeatForever(autoreverses: false)) { globalPhase = .pi * 2 }
        }
    }
}

// Email auth sheet
struct EmailAuthSheet: View {
    let onAuthenticated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isSignUp = true
    @State private var email = ""; @State private var password = ""; @State private var name = ""
    @State private var isLoading = false
    var isValid: Bool { !email.isEmpty && !password.isEmpty && (isSignUp ? !name.isEmpty : true) }
    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        VStack(spacing: 12) {
                            Image(systemName: "flame.fill").font(.system(size: 44, weight: .black))
                                .foregroundStyle(FDS.Gradient.ember).shadow(color: Color.ember.opacity(0.5), radius: 16)
                            Text(isSignUp ? "Create Account" : "Welcome Back")
                                .font(.system(size: 30, weight: .bold)).foregroundColor(.textPrimary)
                            Text(isSignUp ? "Start your transformation" : "Continue your journey")
                                .font(.system(size: 15)).foregroundColor(.textSecondary)
                        }.padding(.top, 32)
                        VStack(spacing: 14) {
                            if isSignUp { ForgeTextField(placeholder: "Full Name", text: $name, icon: "person.fill") }
                            ForgeTextField(placeholder: "Email", text: $email, icon: "envelope.fill", keyboardType: .emailAddress)
                            ForgeTextField(placeholder: "Password", text: $password, icon: "lock.fill", isSecure: true)
                        }.padding(.horizontal, FDS.Spacing.lg)
                        Button(action: {
                            isLoading = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_200_000_000)
                                isLoading = false; dismiss(); onAuthenticated()
                            }
                        }) {
                            HStack(spacing: 8) {
                                if isLoading { ProgressView().tint(.white) }
                                else {
                                    Text(isSignUp ? "Create Account" : "Sign In").font(.system(size: 17, weight: .semibold))
                                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                                }
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 54)
                            .background(isValid ? AnyShapeStyle(FDS.Gradient.ember) : AnyShapeStyle(Color.borderColor.opacity(0.4)))
                            .cornerRadius(FDS.Radius.sm)
                            .shadow(color: isValid ? Color.ember.opacity(0.4) : .clear, radius: 14, y: 4)
                        }.disabled(!isValid || isLoading).padding(.horizontal, FDS.Spacing.lg)
                        Button(action: { withAnimation(FDS.Spring.standard) { isSignUp.toggle() } }) {
                            HStack(spacing: 4) {
                                Text(isSignUp ? "Already have an account?" : "Don't have an account?").foregroundColor(.textSecondary)
                                Text(isSignUp ? "Sign In" : "Sign Up").foregroundColor(.ember).fontWeight(.semibold)
                            }.font(.system(size: 15))
                        }.padding(.bottom, 24)
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.foregroundColor(.textSecondary) } }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Flow layout for workout pills
struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (i, sv) in subviews.enumerated() {
            sv.place(at: CGPoint(x: bounds.minX + result.positions[i].x, y: bounds.minY + result.positions[i].y), proposal: .unspecified)
        }
    }
    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0; var y: CGFloat = 0; var lineH: CGFloat = 0; var positions: [CGPoint] = []
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > maxWidth && x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
            positions.append(CGPoint(x: x, y: y)); lineH = max(lineH, sz.height); x += sz.width + spacing
        }
        return (CGSize(width: maxWidth, height: y + lineH), positions)
    }
}
