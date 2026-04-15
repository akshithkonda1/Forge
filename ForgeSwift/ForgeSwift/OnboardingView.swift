import SwiftUI

// MARK: - Onboarding Container (mirrors /src/app/onboarding/page.tsx)

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @State private var step: Int = 0

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            switch step {
            case 0:
                WelcomeScreen(onNext: { withAnimation(.easeInOut(duration: 0.35)) { step = 1 } })
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case 1:
                ProfileSetupView(onNext: { withAnimation(.easeInOut(duration: 0.35)) { step = 2 } })
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case 2:
                DeviceConnectionView(onNext: { withAnimation(.easeInOut(duration: 0.35)) { step = 3 } })
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case 3:
                CoachingStyleView(onFinish: {
                    withAnimation(.easeInOut(duration: 0.35)) { store.isOnboarded = true }
                })
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: step)
    }
}

// MARK: - Step 1: Welcome Screen (mirrors welcome-screen.tsx)

struct WelcomeScreen: View {
    let onNext: () -> Void
    @State private var appear = false

    var body: some View {
        ZStack {
            // Ambient background glow
            RadialGradient(
                colors: [Color.ember.opacity(0.08), Color.clear],
                center: .init(x: 0.5, y: 0.4),
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Flame icon
                ZStack {
                    // Glow behind
                    Circle()
                        .fill(Color.ember.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .blur(radius: 30)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(LinearGradient.ember)
                        .scaleEffect(appear ? 1 : 0.8)
                        .opacity(appear ? 1 : 0)
                }
                .padding(.bottom, 32)

                // FORGE title
                Text("FORGE")
                    .font(.system(size: 56, weight: .black))
                    .tracking(12)
                    .foregroundStyle(LinearGradient.ember)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)
                    .padding(.bottom, 12)

                // Tagline
                Text("Your AI Training Partner")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)
                    .padding(.bottom, 24)

                // Divider
                Rectangle()
                    .fill(
                        LinearGradient(colors: [.clear, .ember, .clear],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: 64, height: 1)
                    .opacity(appear ? 1 : 0)
                    .padding(.bottom, 24)

                // Description
                Text("An AI coach that knows your body, adapts to your life, and pushes you to be your best.")
                    .font(.system(size: 16))
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)

                Spacer()
                Spacer()

                // Get Started button
                Button(action: onNext) {
                    Text("Get Started")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(LinearGradient.ember)
                        .cornerRadius(14)
                        .shadow(color: Color.ember.opacity(0.4), radius: 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 20)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) { appear = true }
        }
    }
}

// MARK: - Step 2: Profile Setup (mirrors profile-setup.tsx)

struct ProfileSetupView: View {
    let onNext: () -> Void
    @EnvironmentObject var store: AppStore

    @State private var section = 0
    @State private var name = ""
    @State private var selectedGoals: Set<FitnessGoal> = []
    @State private var experienceLevel: ExperienceLevel? = nil
    @State private var selectedWorkouts: Set<WorkoutType> = []

    var canProceed: Bool {
        switch section {
        case 0: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return !selectedGoals.isEmpty
        case 2: return experienceLevel != nil
        case 3: return !selectedWorkouts.isEmpty
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<4) { i in
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
                if section == 1 { goalsSection.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if section == 2 { experienceSection.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                if section == 3 { workoutsSection.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
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
        if section < 3 {
            withAnimation(.easeInOut(duration: 0.35)) { section += 1 }
        } else {
            store.userProfile.name = name.trimmingCharacters(in: .whitespaces)
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

// MARK: - Step 3: Device Connection (mirrors device-connection.tsx)

struct DeviceConnectionView: View {
    let onNext: () -> Void
    @State private var appleWatchConnected = false
    @State private var ouraConnected = false
    @State private var appear = false

    let devices: [(name: String, icon: String, description: String)] = [
        ("Apple Watch", "applewatch", "Heart rate, activity rings, workouts"),
        ("Oura Ring", "circle.circle.fill", "Sleep stages, HRV, readiness score"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect Your Devices")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("Forge syncs with your wearables to personalize training based on real biometric data.")
                    .font(.system(size: 15))
                    .foregroundColor(.textTertiary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 80)
            .padding(.bottom, 40)

            // Device cards
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
            }
            .padding(.horizontal, 24)

            // Skip note
            Text("You can connect devices later in Settings.")
                .font(.system(size: 12))
                .foregroundColor(.textMuted)
                .padding(.top, 20)

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

// MARK: - Step 4: Coaching Style (mirrors coaching-style.tsx)

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

// Simple flow/wrap layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width && rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
