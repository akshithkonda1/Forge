import SwiftUI
import AuthenticationServices

// MARK: - Authentication State

enum AuthenticationState {
    case unauthenticated
    case authenticated
}

// MARK: - Onboarding Container

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @State private var authState: AuthenticationState = .unauthenticated
    @State private var step: Int = 0

    var body: some View {
        ZStack {
            // Dynamic background that changes per step
            DynamicOnboardingBackground(step: authState == .authenticated ? step : -1)
                .ignoresSafeArea()

            if authState == .unauthenticated {
                AuthenticationScreen(
                    onAuthenticated: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            authState = .authenticated
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            } else {
                Group {
                    switch step {
                    case 0:
                        ProfileSetupView(onNext: { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { step = 1 } })
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    case 1:
                        DeviceConnectionView(onNext: { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { step = 2 } })
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    case 2:
                        CoachingStyleView(onFinish: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                store.isOnboarded = true 
                            }
                        })
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .scale(scale: 1.1).combined(with: .opacity)))
                    default:
                        EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: authState)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: step)
    }
}

// MARK: - Authentication Screen

struct AuthenticationScreen: View {
    let onAuthenticated: () -> Void
    
    @State private var showingAuth = false
    @State private var appear = false
    @State private var pulseAnimation = false
    @State private var floatingParticles: [ParticleData] = []
    @State private var backgroundGradientPhase: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Dynamic multi-layer animated background
            ZStack {
                // Base gradient that shifts
                LinearGradient(
                    colors: [
                        Color.black,
                        Color.ember.opacity(0.08),
                        Color.background,
                        Color.steel.opacity(0.06),
                        Color.background
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Animated mesh gradient overlay
                MeshGradientOverlay(phase: backgroundGradientPhase)
                    .opacity(0.4)
                
                // Floating particles
                ForEach(floatingParticles) { particle in
                    FloatingParticle(data: particle)
                }
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 80)
                
                // Hero section with enhanced 3D-like effects
                VStack(spacing: 0) {
                    // Multi-layer pulsing flame icon
                    ZStack {
                        // Outer ripple rings
                        ForEach(0..<4) { index in
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.ember.opacity(0.4),
                                            Color.ember.opacity(0.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                                .frame(width: 160 + CGFloat(index * 50), height: 160 + CGFloat(index * 50))
                                .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                                .opacity(pulseAnimation ? 0.0 : 0.7)
                                .animation(
                                    .easeInOut(duration: 2.5)
                                        .repeatForever(autoreverses: false)
                                        .delay(Double(index) * 0.4),
                                    value: pulseAnimation
                                )
                        }
                        
                        // Glow halos
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.ember.opacity(0.3),
                                        Color.ember.opacity(0.1),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 200, height: 200)
                            .blur(radius: 30)
                            .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: pulseAnimation)
                        
                        // Primary flame icon with depth
                        ZStack {
                            // Shadow layer
                            Image(systemName: "flame.fill")
                                .font(.system(size: 90, weight: .bold))
                                .foregroundColor(.black.opacity(0.3))
                                .blur(radius: 8)
                                .offset(y: 6)
                            
                            // Main icon with gradient
                            Image(systemName: "flame.fill")
                                .font(.system(size: 90, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color.white,
                                            Color.ember,
                                            Color.ember.opacity(0.7)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: Color.ember.opacity(0.8), radius: 30)
                                .shadow(color: Color.ember.opacity(0.6), radius: 15)
                        }
                        .scaleEffect(appear ? 1 : 0.3)
                        .rotationEffect(.degrees(appear ? 0 : -180))
                        .opacity(appear ? 1 : 0)
                        .rotation3DEffect(
                            .degrees(pulseAnimation ? 0 : 5),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: pulseAnimation)
                    }
                    .padding(.bottom, 48)
                    
                    // FORGE branding with enhanced typography
                    VStack(spacing: 12) {
                        Text("FORGE")
                            .font(.system(size: 72, weight: .black, design: .rounded))
                            .tracking(20)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.white,
                                        Color.ember,
                                        Color.ember.opacity(0.8),
                                        Color.white.opacity(0.9)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.ember.opacity(0.5), radius: 20, y: 4)
                            .shadow(color: Color.black.opacity(0.3), radius: 10, y: 2)
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 20)
                            .scaleEffect(appear ? 1 : 0.9)
                        
                        // Animated tagline
                        Text("Forge Your Strongest Self")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.textPrimary, Color.textSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 15)
                    }
                    .padding(.bottom, 20)
                    
                    // Accent divider
                    HStack(spacing: 12) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .ember, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: appear ? 60 : 0, height: 3)
                        
                        Circle()
                            .fill(Color.ember)
                            .frame(width: 6, height: 6)
                            .opacity(appear ? 1 : 0)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .ember, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: appear ? 60 : 0, height: 3)
                    }
                    .padding(.bottom, 32)
                    
                    // Value proposition with better copy
                    VStack(spacing: 16) {
                        Text("AI-Powered. Human-Centered.")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .opacity(appear ? 1 : 0)
                        
                        Text("Your personal AI coach analyzes your biometrics, adapts to your lifestyle, and designs the perfect training program to unlock your full potential.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .padding(.horizontal, 32)
                            .opacity(appear ? 1 : 0)
                    }
                    .offset(y: appear ? 0 : 20)
                }
                
                Spacer()
                
                // Enhanced authentication options
                VStack(spacing: 20) {
                    // Sign in with Apple (primary CTA)
                    SignInWithAppleButton(.signUp) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 58)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.15), radius: 20, y: 8)
                    .shadow(color: Color.ember.opacity(0.2), radius: 15, y: 4)
                    .padding(.horizontal, 28)
                    .scaleEffect(appear ? 1 : 0.9)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 30)
                    
                    // Elegant divider
                    HStack(spacing: 16) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .borderColor.opacity(0.5), .borderColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 1)
                        
                        Text("or")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textMuted)
                            .padding(.horizontal, 4)
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.borderColor, .borderColor.opacity(0.5), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 28)
                    .opacity(appear ? 0.8 : 0)
                    
                    // Enhanced OAuth buttons
                    HStack(spacing: 16) {
                        ModernOAuthButton(
                            icon: "g.circle.fill",
                            title: "Google",
                            color: .white,
                            action: { handleOAuth(provider: "Google") }
                        )
                        
                        ModernOAuthButton(
                            icon: "envelope.fill",
                            title: "Email",
                            color: .ember,
                            action: { showingAuth = true }
                        )
                    }
                    .padding(.horizontal, 28)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 30)
                    
                    // Terms with better styling
                    Text("By continuing, you agree to our [Terms](https://forge.app/terms) and [Privacy Policy](https://forge.app/privacy)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textMuted.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                        .opacity(appear ? 0.6 : 0)
                }
                .padding(.bottom, 60)
            }
        }
        .sheet(isPresented: $showingAuth) {
            EmailAuthSheet(onAuthenticated: onAuthenticated)
        }
        .onAppear {
            // Generate floating particles
            floatingParticles = (0..<15).map { _ in
                ParticleData(
                    x: CGFloat.random(in: 0...1),
                    y: CGFloat.random(in: 0...1),
                    size: CGFloat.random(in: 2...8),
                    opacity: Double.random(in: 0.1...0.4),
                    duration: Double.random(in: 15...30)
                )
            }
            
            withAnimation(.spring(response: 1.0, dampingFraction: 0.75).delay(0.2)) {
                appear = true
            }
            
            // Start animations
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                backgroundGradientPhase = 1.0
            }
            
            pulseAnimation = true
        }
    }
    
    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            print("Apple Sign In successful")
            onAuthenticated()
        case .failure(let error):
            print("Apple Sign In failed: \(error.localizedDescription)")
        }
    }
    
    func handleOAuth(provider: String) {
        print("OAuth with \(provider)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onAuthenticated()
        }
    }
}



// MARK: - Email Auth Sheet

struct EmailAuthSheet: View {
    let onAuthenticated: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var isSignUp = true
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(LinearGradient.ember)
                            
                            Text(isSignUp ? "Create Account" : "Welcome Back")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.textPrimary)
                            
                            Text(isSignUp ? "Start your transformation journey" : "Continue your journey")
                                .font(.system(size: 16))
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.top, 32)
                        
                        // Form
                        VStack(spacing: 16) {
                            if isSignUp {
                                FloatingTextField(
                                    placeholder: "Full Name",
                                    text: $name,
                                    icon: "person.fill"
                                )
                            }
                            
                            FloatingTextField(
                                placeholder: "Email",
                                text: $email,
                                icon: "envelope.fill",
                                keyboardType: .emailAddress
                            )
                            
                            FloatingTextField(
                                placeholder: "Password",
                                text: $password,
                                icon: "lock.fill",
                                isSecure: true
                            )
                        }
                        .padding(.horizontal, 24)
                        
                        // Submit button with glass effect
                        Button(action: handleSubmit) {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(isSignUp ? "Create Account" : "Sign In")
                                        .font(.system(size: 18, weight: .semibold))
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [Color.ember, Color.ember.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(14)
                            .shadow(color: Color.ember.opacity(0.4), radius: 16)
                        }
                        .disabled(isLoading || !isFormValid)
                        .opacity(isFormValid ? 1 : 0.5)
                        .padding(.horizontal, 24)
                        .modifier(SubmitButtonGlassEffect())
                        
                        // Toggle auth mode
                        Button(action: { withAnimation(.spring(response: 0.4)) { isSignUp.toggle() } }) {
                            HStack(spacing: 4) {
                                Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                                    .foregroundColor(.textSecondary)
                                Text(isSignUp ? "Sign In" : "Sign Up")
                                    .foregroundColor(.ember)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 15))
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.textSecondary)
                }
            }
        }
    }
    
    var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && (isSignUp ? !name.isEmpty : true)
    }
    
    func handleSubmit() {
        isLoading = true
        
        // Simulate API call
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isLoading = false
            dismiss()
            onAuthenticated()
        }
    }
}

// MARK: - Floating TextField with Glass Effect

struct FloatingTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isFocused ? .ember : .textMuted)
                .frame(width: 24)
            
            ZStack(alignment: .leading) {
                if isSecure {
                    SecureField("", text: $text)
                        .font(.system(size: 17))
                        .foregroundColor(.textPrimary)
                        .tint(.ember)
                        .focused($isFocused)
                        .textContentType(.password)
                } else {
                    TextField("", text: $text)
                        .font(.system(size: 17))
                        .foregroundColor(.textPrimary)
                        .tint(.ember)
                        .focused($isFocused)
                        .keyboardType(keyboardType)
                        .textContentType(keyboardType == .emailAddress ? .emailAddress : .none)
                        .autocapitalization(.none)
                }
                
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 17))
                        .foregroundColor(.textMuted)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isFocused ? Color.ember.opacity(0.6) : Color.borderColor, lineWidth: 1.5)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        .modifier(TextFieldGlassEffect())
    }
}

// MARK: - Profile Setup (Enhanced with Gender Selection)

struct ProfileSetupView: View {
    let onNext: () -> Void
    @EnvironmentObject var store: AppStore

    @State private var section = 0
    @State private var name = ""
    @State private var selectedGender: Gender = .preferNotToSay
    @State private var selectedGoals: Set<FitnessGoal> = []
    @State private var experienceLevel: ExperienceLevel? = nil
    @State private var selectedWorkouts: Set<WorkoutType> = []

    var canProceed: Bool {
        switch section {
        case 0: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return true // Gender selection - always can proceed (prefer not to say is default)
        case 2: return !selectedGoals.isEmpty
        case 3: return experienceLevel != nil
        case 4: return !selectedWorkouts.isEmpty
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<5) { i in
                    Capsule()
                        .fill(i == section ? Color.ember : i < section ? Color.ember.opacity(0.5) : Color.borderColor)
                        .frame(width: i == section ? 32 : 16, height: 4)
                        .animation(.spring(response: 0.4), value: section)
                }
            }
            .padding(.top, 60)
            .padding(.bottom, 8)

            // Section content
            ZStack {
                if section == 0 { nameSection.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if section == 1 { genderSection.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if section == 2 { goalsSection.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if section == 3 { experienceSection.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if section == 4 { workoutsSection.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
            }
            .animation(.easeInOut(duration: 0.35), value: section)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.top, 48)

            // Continue button
            Button(action: handleContinue) {
                Text("Continue")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(canProceed ? LinearGradient.ember : LinearGradient(colors: [Color.borderColor, Color.borderColor], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(14)
                    .shadow(color: canProceed ? Color.ember.opacity(0.35) : .clear, radius: 14)
                    .opacity(canProceed ? 1 : 0.4)
            }
            .disabled(!canProceed)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(Color.background.ignoresSafeArea())
    }

    func handleContinue() {
        if section < 4 {
            withAnimation(.easeInOut(duration: 0.35)) { section += 1 }
        } else {
            store.userProfile.name = name.trimmingCharacters(in: .whitespaces)
            store.userProfile.gender = selectedGender
            store.userProfile.fitnessGoals = Array(selectedGoals)
            store.userProfile.experienceLevel = experienceLevel ?? .intermediate
            store.userProfile.preferredWorkouts = Array(selectedWorkouts)
            onNext()
        }
    }

    // MARK: Section subviews

    var nameSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What's your name?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 8)
            Text("Your coach needs to know what to call you.")
                .font(.system(size: 15))
                .foregroundColor(.textTertiary)
                .padding(.bottom, 32)

            TextField("Enter your name", text: $name)
                .font(.system(size: 18))
                .foregroundColor(.textPrimary)
                .tint(.ember)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.surface)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(name.isEmpty ? Color.borderColor : Color.ember.opacity(0.5), lineWidth: 1)
                )
        }
    }
    
    var genderSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How do you identify?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("This helps us personalize your training and nutrition recommendations")
                    .font(.system(size: 15))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(4)
            }

            VStack(spacing: 12) {
                ForEach(Gender.allCases) { gender in
                    GenderSelectionCard(
                        gender: gender,
                        isSelected: selectedGender == gender,
                        action: { selectedGender = gender }
                    )
                }
            }
            .padding(.top, 12)
            
            Spacer()
        }
    }

    var goalsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What are your fitness goals?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 8)
            Text("Select all that apply. We'll tailor your training plan.")
                .font(.system(size: 15))
                .foregroundColor(.textTertiary)
                .padding(.bottom, 32)

            FlowLayout(spacing: 12) {
                ForEach(FitnessGoal.allCases) { goal in
                    TogglePill(label: goal.label, isSelected: selectedGoals.contains(goal)) {
                        if selectedGoals.contains(goal) { selectedGoals.remove(goal) } else { selectedGoals.insert(goal) }
                    }
                }
            }
        }
    }

    var experienceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Experience level?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 8)
            Text("This helps us calibrate the right intensity for you.")
                .font(.system(size: 15))
                .foregroundColor(.textTertiary)
                .padding(.bottom, 32)

            VStack(spacing: 12) {
                ForEach(ExperienceLevel.allCases) { level in
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { experienceLevel = level } }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(level.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(experienceLevel == level ? .ember : .textPrimary)
                            Text(level.description)
                                .font(.system(size: 13))
                                .foregroundColor(.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(experienceLevel == level ? Color.ember.opacity(0.1) : Color.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(experienceLevel == level ? Color.ember : Color.borderColor, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Preferred workout types?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 8)
            Text("Pick the types of training you enjoy most.")
                .font(.system(size: 15))
                .foregroundColor(.textTertiary)
                .padding(.bottom, 32)

            FlowLayout(spacing: 12) {
                ForEach(WorkoutType.allCases) { type in
                    TogglePill(label: type.label, isSelected: selectedWorkouts.contains(type)) {
                        if selectedWorkouts.contains(type) { selectedWorkouts.remove(type) } else { selectedWorkouts.insert(type) }
                    }
                }
            }
        }
    }
}


// MARK: - Device Connection (mirrors device-connection.tsx)

struct DeviceConnectionView: View {
    let onNext: () -> Void
    @State private var appleWatchConnected = false
    @State private var ouraConnected = false
    @State private var whoopConnected = false
    @State private var garminConnected = false
    @State private var fitbitConnected = false
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect Your Devices")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("Forge syncs with your wearables via HealthKit to personalize training based on real biometric data.")
                    .font(.system(size: 15))
                    .foregroundColor(.textTertiary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 80)
            .padding(.bottom, 32)

            // Device cards in scrollable list
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    DeviceCard(
                        name: "Apple Watch",
                        icon: "applewatch",
                        description: "Heart rate, activity rings & workouts",
                        isConnected: $appleWatchConnected
                    )
                    DeviceCard(
                        name: "Oura Ring",
                        icon: "circle.circle.fill",
                        description: "Sleep stages, HRV & readiness score",
                        isConnected: $ouraConnected
                    )
                    DeviceCard(
                        name: "WHOOP",
                        icon: "waveform.path.ecg",
                        description: "Strain, recovery & sleep performance",
                        isConnected: $whoopConnected
                    )
                    DeviceCard(
                        name: "Garmin",
                        icon: "figure.run",
                        description: "Training load, VO2 max & performance",
                        isConnected: $garminConnected
                    )
                    DeviceCard(
                        name: "Fitbit",
                        icon: "heart.text.square.fill",
                        description: "Daily activity, heart rate & sleep",
                        isConnected: $fitbitConnected
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            // Skip note
            Text("You can connect devices later in Settings.")
                .font(.system(size: 12))
                .foregroundColor(.textMuted)
                .padding(.top, 12)

            Spacer()

            // Continue
            Button(action: onNext) {
                Text("Continue")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(LinearGradient.ember)
                    .cornerRadius(14)
                    .shadow(color: Color.ember.opacity(0.35), radius: 14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(Color.background.ignoresSafeArea())
        .opacity(appear ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appear = true } }
    }
}

struct DeviceCard: View {
    let name: String
    let icon: String
    let description: String
    @Binding var isConnected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.steel.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.steel)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }

            Spacer()

            Button(action: { withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { isConnected.toggle() } }) {
                Text(isConnected ? "Connected" : "Connect")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isConnected ? .success : .ember)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(isConnected ? Color.success.opacity(0.1) : Color.ember.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isConnected ? Color.success.opacity(0.3) : Color.borderColor, lineWidth: 1)
        )
    }
}

// MARK: - Coaching Style (mirrors coaching-style.tsx)

struct CoachingStyleView: View {
    let onFinish: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var selected: CoachingStyle = .balanced
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose Your Coaching Style")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("How do you want Forge to push you? You can change this anytime.")
                    .font(.system(size: 15))
                    .foregroundColor(.textTertiary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 80)
            .padding(.bottom, 36)

            VStack(spacing: 12) {
                ForEach(CoachingStyle.allCases) { style in
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selected = style } }) {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(style.label)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(selected == style ? .ember : .textPrimary)
                                Text(style.description)
                                    .font(.system(size: 13))
                                    .foregroundColor(.textTertiary)
                            }
                            Spacer()
                            ZStack {
                                Circle()
                                    .stroke(selected == style ? Color.ember : Color.borderColor, lineWidth: 2)
                                    .frame(width: 22, height: 22)
                                if selected == style {
                                    Circle()
                                        .fill(Color.ember)
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                        .padding(16)
                        .background(selected == style ? Color.ember.opacity(0.08) : Color.surface)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selected == style ? Color.ember.opacity(0.5) : Color.borderColor, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: {
                store.userProfile.coachingStyle = selected
                onFinish()
            }) {
                HStack(spacing: 8) {
                    Text("Start Training")
                        .font(.system(size: 18, weight: .semibold))
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(LinearGradient.ember)
                .cornerRadius(14)
                .shadow(color: Color.ember.opacity(0.4), radius: 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(Color.background.ignoresSafeArea())
        .opacity(appear ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appear = true } }
    }
}

// MARK: - Shared helpers

struct TogglePill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .ember : .textSecondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(isSelected ? Color.ember.opacity(0.15) : Color.surface)
                .cornerRadius(100)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.ember : Color.borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
// MARK: - Glass Effect Modifiers (iOS 26.0+)

struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(true), in: .rect(cornerRadius: 16))
        } else {
            content
        }
    }
}

struct SubmitButtonGlassEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(true), in: .rect(cornerRadius: 14))
        } else {
            content
        }
    }
}

struct TextFieldGlassEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content
        }
    }
}

// MARK: - Gender Selection Card

struct GenderSelectionCard: View {
    let gender: Gender
    let isSelected: Bool
    let action: () -> Void
    
    var iconName: String {
        switch gender {
        case .male: return "person.fill"
        case .female: return "person.fill"
        case .nonBinary: return "person.2.fill"
        case .preferNotToSay: return "hand.raised.fill"
        case .other: return "person.crop.circle.fill"
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? .ember : .textSecondary)
                }
                
                Text(gender.label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .ember : .textPrimary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.ember)
                }
            }
            .padding(16)
            .background(Color.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.ember : Color.borderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dynamic Background System

struct DynamicOnboardingBackground: View {
    let step: Int
    @State private var phase: CGFloat = 0
    
    var colors: [Color] {
        switch step {
        case -1: // Auth screen
            return [.black, .ember.opacity(0.08), .background, .steel.opacity(0.06)]
        case 0: // Profile
            return [.background, .steel.opacity(0.08), .background, .ember.opacity(0.05)]
        case 1: // Devices
            return [.background, .ember.opacity(0.06), .steel.opacity(0.08), .background]
        case 2: // Coaching
            return [.ember.opacity(0.05), .background, .background, .ember.opacity(0.08)]
        default:
            return [.background, .background]
        }
    }
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Animated overlay
            RadialGradient(
                colors: [
                    Color.ember.opacity(0.03),
                    Color.clear,
                    Color.steel.opacity(0.02)
                ],
                center: UnitPoint(x: 0.5 + phase * 0.3, y: 0.5 + phase * 0.2),
                startRadius: 100,
                endRadius: 500
            )
            .opacity(0.6)
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
        .onChange(of: step) {
            // Subtle pulse on step change
            withAnimation(.easeInOut(duration: 0.6)) {
                phase = 0.5
            }
        }
    }
}

// MARK: - Particle System

struct ParticleData: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
    let duration: Double
}

struct FloatingParticle: View {
    let data: ParticleData
    @State private var offsetY: CGFloat = 0
    @State private var offsetX: CGFloat = 0
    @State private var opacity: Double = 0
    
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white, Color.ember.opacity(0.5), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: data.size / 2
                )
            )
            .frame(width: data.size, height: data.size)
            .opacity(opacity)
            .position(
                x: UIScreen.main.bounds.width * data.x + offsetX,
                y: UIScreen.main.bounds.height * data.y + offsetY
            )
            .blur(radius: data.size / 4)
            .onAppear {
                withAnimation(.easeIn(duration: 1.0)) {
                    opacity = data.opacity
                }
                
                withAnimation(
                    .linear(duration: data.duration)
                    .repeatForever(autoreverses: false)
                ) {
                    offsetY = -UIScreen.main.bounds.height * 0.3
                    offsetX = CGFloat.random(in: -50...50)
                }
            }
    }
}

// MARK: - Mesh Gradient Overlay

struct MeshGradientOverlay: View {
    let phase: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let colors: [Color] = [.ember, .steel, .clear, .ember.opacity(0.5), .clear]
                
                for i in 0..<5 {
                    let offsetX = sin(phase * .pi + Double(i) * 0.4) * 100
                    let offsetY = cos(phase * .pi + Double(i) * 0.5) * 100
                    
                    let center = CGPoint(
                        x: size.width * (0.2 + CGFloat(i) * 0.15) + offsetX,
                        y: size.height * (0.3 + CGFloat(i) * 0.12) + offsetY
                    )
                    
                    let gradient = Gradient(colors: [colors[i], .clear])
                    _
                    = RadialGradient(
                        gradient: gradient,
                        center: UnitPoint(x: center.x / size.width, y: center.y / size.height),
                        startRadius: 0,
                        endRadius: 200
                    )
                    
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - 100, y: center.y - 100, width: 200, height: 200)),
                        with: .linearGradient(
                            gradient,
                            startPoint: center,
                            endPoint: CGPoint(x: center.x + 100, y: center.y + 100)
                        )
                    )
                }
            }
        }
        .blur(radius: 80)
    }
}

// MARK: - Modern OAuth Button

struct ModernOAuthButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
                action()
            }
        }) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.surface)
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.black.opacity(0.1), radius: 12, y: 4)
                    
                    Circle()
                        .fill(color == .ember ? Color.ember.opacity(0.15) : Color.clear)
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(color)
                }
                .scaleEffect(isPressed ? 0.92 : 1.0)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

