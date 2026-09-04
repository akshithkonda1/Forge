import SwiftUI

// MARK: - Smart Profile Setup View (Data-Driven)

struct SmartProfileSetupView: View {
    let onNext: () -> Void
    @EnvironmentObject var store: AppStore
    @StateObject private var dataManager = OnboardingDataManager.shared
    
    @State private var section = 0
    @State private var name = ""
    @State private var selectedGender: Gender = .preferNotToSay
    @State private var selectedGoals: Set<UserFitnessGoal> = []
    @State private var experienceLevel: ExperienceLevel? = nil
    @State private var selectedWorkouts: Set<WorkoutType> = []
    
    // HealthKit-derived data
    @State private var age: Int?
    @State private var weight: Double?
    @State private var height: Double?
    @State private var dataLoadedFromHealthKit = false

    private let totalSections = 5

    var canContinue: Bool {
        switch section {
        case 0: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 2: return !selectedGoals.isEmpty
        case 3: return experienceLevel != nil
        case 4: return !selectedWorkouts.isEmpty
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            HStack {
                Button {
                    if section > 0 {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { section -= 1 }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(section > 0 ? .textSecondary : .clear)
                }
                .frame(width: 32)

                HStack(spacing: 6) {
                    ForEach(0..<totalSections, id: \.self) { i in
                        Capsule()
                            .fill(i <= section ? Color.ember : Color.borderColor)
                            .frame(width: i == section ? 28 : 14, height: 4)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: section)
                    }
                }
                .frame(maxWidth: .infinity)

                Text("\(section + 1)/\(totalSections)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 36)

            // Section content
            Group {
                switch section {
                case 0: nameAndBasicsSection
                case 1: genderSection
                case 2: goalsSection
                case 3: smartExperienceSection
                case 4: workoutsSection
                default: EmptyView()
                }
            }
            .id(section)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: section)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)

            // CTA
            Button(action: handleContinue) {
                HStack(spacing: 8) {
                    Text(section == totalSections - 1 ? "Finish Profile" : "Continue")
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: section == totalSections - 1 ? "checkmark" : "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(canContinue ? AnyShapeStyle(LinearGradient.emberGradient) : AnyShapeStyle(Color.borderColor.opacity(0.35)))
                .cornerRadius(16)
                .shadow(color: canContinue ? Color.ember.opacity(0.4) : .clear, radius: 14, y: 5)
                .opacity(canContinue ? 1 : 0.5)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canContinue)
            }
            .disabled(!canContinue)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(Color.background)
        .ignoresSafeArea()
        .task {
            await loadHealthKitData()
        }
    }
    
    // MARK: - Load HealthKit Data
    
    private func loadHealthKitData() async {
        guard dataManager.healthKitAuthorized else { return }
        
        if let profile = dataManager.healthProfile {
            await MainActor.run {
                age = profile.age
                weight = profile.weightKg
                height = profile.heightCm
                dataLoadedFromHealthKit = true
                
                // Smart experience level suggestion
                if let suggestedLevel = dataManager.generatePersonalizedRecommendations().suggestedExperienceLevel {
                    experienceLevel = suggestedLevel
                }
            }
        }
    }

    private func handleContinue() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if section < totalSections - 1 {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { section += 1 }
        } else {
            store.userProfile.name = name.trimmingCharacters(in: .whitespaces)
            store.userProfile.gender = selectedGender
            store.userProfile.fitnessGoals = Array(selectedGoals)
            store.userProfile.experienceLevel = experienceLevel ?? .intermediate
            store.userProfile.preferredWorkouts = Array(selectedWorkouts)
            
            // Save HealthKit data if available
            if let age = age { store.userProfile.age = age }
            if let weight = weight { store.userProfile.weight = weight }
            if let height = height { store.userProfile.height = height }
            
            onNext()
        }
    }

    // MARK: - Section Views

    private var nameAndBasicsSection: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                ForgeSectionHeader(
                    eyebrow: "Profile",
                    title: "Tell us about yourself",
                    subtitle: "We'll use this to personalize your training."
                )
                
                ForgeTextField(placeholder: "Your name", text: $name, icon: "person.fill")
                
                // Show HealthKit data if available
                if dataLoadedFromHealthKit {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.success)
                            Text("Data from Apple Health")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.success)
                            Spacer()
                        }
                        .padding(.top, 8)
                        
                        if let age = age {
                            HealthDataRow(label: "Age", value: "\(age) years", icon: "calendar")
                        }
                        if let weight = weight {
                            HealthDataRow(label: "Weight", value: String(format: "%.1f kg", weight), icon: "scalemass")
                        }
                        if let height = height {
                            HealthDataRow(label: "Height", value: String(format: "%.0f cm", height), icon: "ruler")
                        }
                    }
                    .padding(14)
                    .background(Color.success.opacity(0.06))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.success.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
    }

    private var genderSection: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForgeSectionHeader(
                    eyebrow: "Identity",
                    title: "How do you identify?",
                    subtitle: "Helps us personalize training and nutrition recommendations."
                )
                .padding(.bottom, 28)

                VStack(spacing: 10) {
                    ForEach(Gender.allCases) { gender in
                        GenderSelectionCard(
                            gender: gender,
                            isSelected: selectedGender == gender,
                            action: {
                                selectedGender = gender
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        )
                    }
                }
            }
        }
    }

    private var goalsSection: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForgeSectionHeader(
                    eyebrow: "Goals",
                    title: "What are your goals?",
                    subtitle: "Select all that apply — we'll tailor your program."
                )
                .padding(.bottom, 28)

                OnboardingFlowLayout(spacing: 10) {
                    ForEach(UserFitnessGoal.allCases) { goal in
                        TogglePill(label: goal.label, isSelected: selectedGoals.contains(goal)) {
                            if selectedGoals.contains(goal) { selectedGoals.remove(goal) } else { selectedGoals.insert(goal) }
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                }
            }
        }
    }

    private var smartExperienceSection: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForgeSectionHeader(
                    eyebrow: "Experience",
                    title: "Experience level?",
                    subtitle: "Calibrates intensity and progression speed."
                )
                .padding(.bottom, 20)
                
                // Show smart recommendation if available
                if let recommendation = dataManager.generatePersonalizedRecommendations().suggestedExperienceLevel {
                    SmartRecommendationBanner(
                        title: "Based on your health data",
                        suggestion: "We recommend starting at \(recommendation.label)",
                        icon: "sparkles"
                    )
                    .padding(.bottom, 20)
                }

                VStack(spacing: 10) {
                    ForEach(ExperienceLevel.allCases) { level in
                        ExperienceLevelCard(
                            level: level,
                            isSelected: experienceLevel == level,
                            isRecommended: dataManager.generatePersonalizedRecommendations().suggestedExperienceLevel == level
                        ) {
                            experienceLevel = level
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                }
            }
        }
    }

    private var workoutsSection: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForgeSectionHeader(
                    eyebrow: "Training",
                    title: "Preferred workouts?",
                    subtitle: "Pick the training you enjoy most."
                )
                .padding(.bottom, 28)

                OnboardingFlowLayout(spacing: 10) {
                    ForEach(WorkoutType.allCases) { type in
                        TogglePill(label: type.label, isSelected: selectedWorkouts.contains(type)) {
                            if selectedWorkouts.contains(type) { selectedWorkouts.remove(type) } else { selectedWorkouts.insert(type) }
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Health Data Row

struct HealthDataRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.success)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
    }
}

// MARK: - Smart Recommendation Banner

struct SmartRecommendationBanner: View {
    let title: String
    let suggestion: String
    let icon: String
    @State private var appeared = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.ember)
                .symbolEffect(.pulse)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                Text(suggestion)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.ember)
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color.ember.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.ember.opacity(0.3), lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.2)) {
                appeared = true
            }
        }
    }
}

// MARK: - Enhanced Experience Level Card

struct ExperienceLevelCard: View {
    let level: ExperienceLevel
    let isSelected: Bool
    let isRecommended: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                        .frame(width: 44, height: 44)
                    Image(systemName: levelIcon(level))
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? .ember : .textTertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(level.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isSelected ? .ember : .textPrimary)
                        
                        if isRecommended {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.ember)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.ember.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    Text(level.description)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.ember)
                }
            }
            .padding(14)
            .background(isSelected ? Color.ember.opacity(0.07) : Color.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.ember.opacity(0.5) : (isRecommended ? Color.ember.opacity(0.3) : Color.borderColor),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
    }
    
    private func levelIcon(_ level: ExperienceLevel) -> String {
        switch level {
        case .beginner: return "leaf.fill"
        case .intermediate: return "bolt.fill"
        case .advanced: return "flame.fill"
        case .elite: return "crown.fill"
        }
    }
}
