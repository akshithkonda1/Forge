import SwiftUI

// MARK: - Onboarding Flow Container

struct OnboardingFlow: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            Color.forgeBackground.ignoresSafeArea()

            switch store.onboardingStep {
            case 0: WelcomeScreen()
            case 1: ProfileSetupView()
            case 2: DeviceConnectionView()
            case 3: CoachingStyleView()
            default: WelcomeScreen()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.onboardingStep)
    }
}

// MARK: - Progress Dots

struct OnboardingProgress: View {
    let current: Int
    let total: Int = 4

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.ember : (i < current ? Color.ember.opacity(0.4) : Color.forgeBorder))
                    .frame(width: i == current ? 32 : 12, height: 6)
                    .animation(.spring(response: 0.4), value: current)
            }
        }
    }
}

// MARK: - 1. Welcome Screen

struct WelcomeScreen: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Flame icon
            ZStack {
                Circle()
                    .fill(Color.ember.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .blur(radius: 30)

                Image(systemName: "flame.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(LinearGradient.emberGradient)
            }
            .padding(.bottom, 32)

            // FORGE
            Text("FORGE")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .tracking(8)
                .foregroundStyle(LinearGradient.emberGradient)

            Text("Your AI Training Partner")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.textSecondary)
                .padding(.top, 8)

            // Divider
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .ember, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 64, height: 1)
                .padding(.vertical, 32)

            Text("An AI coach that knows your body, adapts to your life, and pushes you to be your best.")
                .font(.system(size: 15))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()

            EmberButton(title: "Get Started") {
                store.onboardingStep = 1
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - 2. Profile Setup

struct ProfileSetupView: View {
    @EnvironmentObject var store: AppStore
    @State private var section = 0
    @State private var name = ""
    @State private var selectedGoals: Set<FitnessGoal> = []
    @State private var experienceLevel: ExperienceLevel?
    @State private var selectedWorkouts: Set<WorkoutType> = []

    private var canProceed: Bool {
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
            // Progress
            OnboardingProgress(current: 1)
                .padding(.top, 16)

            // Sub-progress
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i == section ? Color.ember : (i < section ? Color.ember.opacity(0.5) : Color.forgeBorder))
                        .frame(width: i == section ? 32 : 16, height: 4)
                }
            }
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch section {
                    case 0: nameSection
                    case 1: goalsSection
                    case 2: experienceSection
                    case 3: workoutTypesSection
                    default: EmptyView()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
            }

            Spacer()

            EmberButton(title: section < 3 ? "Continue" : "Continue") {
                if section < 3 {
                    withAnimation { section += 1 }
                } else {
                    store.userProfile.name = name.trimmingCharacters(in: .whitespaces)
                    store.userProfile.fitnessGoals = Array(selectedGoals)
                    store.userProfile.experienceLevel = experienceLevel ?? .intermediate
                    store.userProfile.preferredWorkouts = Array(selectedWorkouts)
                    store.onboardingStep = 2
                }
            }
            .disabled(!canProceed)
            .opacity(canProceed ? 1 : 0.4)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: Sub-sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's your name?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            Text("Your coach needs to know what to call you.")
                .font(.system(size: 15))
                .foregroundColor(.textTertiary)
                .padding(.bottom, 24)

            TextField("Enter your name", text: $name)
                .font(.system(size: 17))
                .foregroundColor(.white)
                .padding(16)
                .background(Color.forgeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(name.isEmpty ? Color.forgeBorder : Color.ember, lineWidth: 1)
                )
                .textInputAutocapitalization(.words)
        }
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fitness goals?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            Text("Select all that apply.")
                .font(.system(size: 15))
                .foregroundColor(.textTertiary)
                .padding(.bottom, 24)

            FlowLayout(spacing: 10) {
                ForEach(FitnessGoal.allCases) { goal in
                    let selected = selectedGoals.contains(goal)
                    Button {
                        if selected { selectedGoals.remove(goal) }
                        else { selectedGoals.insert(goal) }
                    } label: {
                        Text(goal.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selected ? .ember : .textSecondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(selected ? Color.ember.opacity(0.15) : Color.forgeSurface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(selected ? Color.ember : Color.forgeBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var experienceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Experience level?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            Text("This calibrates intensity for you.")
                .font(.system(size: 15))
                .foregroundColor(.textTertiary)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                ForEach(ExperienceLevel.allCases, id: \.self) { level in
                    let selected = experienceLevel == level
                    Button {
                        experienceLevel = level
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(level.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(selected ? .ember : .white)
                            Text(level.description)
                                .font(.system(size: 13))
                                .foregroundColor(.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(selected ? Color.ember.opacity(0.1) : Color.forgeSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selected ? Color.ember : Color.forgeBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var workoutTypesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preferred workout types?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            Text("Pick what you enjoy most.")
                .font(.system(size: 15))
                .foregroundColor(.textTertiary)
                .padding(.bottom, 24)

            FlowLayout(spacing: 10) {
                ForEach(WorkoutType.allCases.filter { $0 != .sportSpecific }) { type in
                    let selected = selectedWorkouts.contains(type)
                    Button {
                        if selected { selectedWorkouts.remove(type) }
                        else { selectedWorkouts.insert(type) }
                    } label: {
                        Text(type.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selected ? .ember : .textSecondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(selected ? Color.ember.opacity(0.15) : Color.forgeSurface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(selected ? Color.ember : Color.forgeBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 3. Device Connection

struct DeviceConnectionView: View {
    @EnvironmentObject var store: AppStore
    @State private var connected: Set<String> = []

    private let devices: [DeviceOption] = [
        DeviceOption(id: "apple-watch", name: "Apple Watch", iconName: "applewatch"),
        DeviceOption(id: "garmin", name: "Garmin", iconName: "watch.analog"),
        DeviceOption(id: "oura", name: "Oura Ring", iconName: "circle.circle"),
        DeviceOption(id: "fitbit", name: "Fitbit", iconName: "waveform.path.ecg.rectangle"),
        DeviceOption(id: "whoop", name: "Whoop", iconName: "heart.rectangle"),
        DeviceOption(id: "samsung", name: "Galaxy Watch", iconName: "clock.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgress(current: 2)
                .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect Your Devices")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("Forge uses your wearable data to personalize every workout")
                        .font(.system(size: 15))
                        .foregroundColor(.textTertiary)
                        .padding(.bottom, 24)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(devices) { device in
                            let isConnected = connected.contains(device.id)
                            Button {
                                if isConnected { connected.remove(device.id) }
                                else { connected.insert(device.id) }
                            } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: device.iconName)
                                        .font(.system(size: 26))
                                        .foregroundColor(isConnected ? .ember : .textTertiary)

                                    Text(device.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(isConnected ? .ember : .textSecondary)

                                    Text(isConnected ? "Connected" : "Not Connected")
                                        .font(.system(size: 11))
                                        .foregroundColor(isConnected ? .ember.opacity(0.7) : .textMuted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(isConnected ? Color.ember.opacity(0.1) : Color.forgeSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(isConnected ? Color.ember : Color.forgeBorder, lineWidth: 1)
                                )
                                .overlay(alignment: .topTrailing) {
                                    if isConnected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(.ember)
                                            .padding(8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
            }

            Text("You can connect devices later in Settings")
                .font(.system(size: 13))
                .foregroundColor(.textMuted)
                .padding(.bottom, 12)

            EmberButton(title: "Continue") {
                let names = devices.filter { connected.contains($0.id) }.map(\.name)
                if !names.isEmpty { store.userProfile.connectedDevices = names }
                store.onboardingStep = 3
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - 4. Coaching Style

struct CoachingStyleView: View {
    @EnvironmentObject var store: AppStore
    @State private var selected: CoachingStyle?

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgress(current: 3)
                .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How do you like to be coached?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("This shapes your AI trainer's personality.")
                        .font(.system(size: 15))
                        .foregroundColor(.textTertiary)
                        .padding(.bottom, 24)

                    VStack(spacing: 10) {
                        ForEach(CoachingStyle.allCases, id: \.self) { style in
                            let isSelected = selected == style
                            Button {
                                selected = style
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: style.iconName)
                                        .font(.system(size: 24))
                                        .foregroundColor(isSelected ? .ember : .textTertiary)
                                        .frame(width: 48, height: 48)
                                        .background(isSelected ? Color.ember.opacity(0.2) : Color.forgeSurfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(style.label)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(isSelected ? .ember : .white)
                                        Text(style.description)
                                            .font(.system(size: 13))
                                            .foregroundColor(.textTertiary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    Circle()
                                        .stroke(isSelected ? Color.ember : Color.forgeBorder, lineWidth: 2)
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            Circle()
                                                .fill(isSelected ? Color.ember : .clear)
                                                .frame(width: 10, height: 10)
                                        )
                                }
                                .padding(16)
                                .background(isSelected ? Color.ember.opacity(0.08) : Color.forgeSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(isSelected ? Color.ember : Color.forgeBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
            }

            Spacer()

            EmberButton(title: "Start Training") {
                if let selected {
                    store.userProfile.coachingStyle = selected
                }
                store.isOnboarded = true
            }
            .disabled(selected == nil)
            .opacity(selected == nil ? 0.4 : 1)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Flow Layout Helper

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
