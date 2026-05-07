import Foundation
import SwiftUI
import HealthKit

// MARK: - HealthKit State

enum HealthKitState: Equatable {
    case unknown, requesting, authorized, denied, unavailable
}

// MARK: - Onboarding Route

enum OnboardingRoute: Int, CaseIterable, Hashable {
    case welcome = 0, auth, profile, health, training, coach

    var title: String {
        switch self {
        case .welcome:  return "Age Check"
        case .auth:     return "Account"
        case .profile:  return "Profile"
        case .health:   return "Health"
        case .training: return "Training"
        case .coach:    return "Coach"
        }
    }
}

// MARK: - OnboardingProfile Extension

extension OnboardingProfile {
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
}

// MARK: - Onboarding Coordinator

@Observable
@MainActor
final class OnboardingCoordinator {

    // MARK: Navigation

    var route: OnboardingRoute = .welcome
    var showAgeBlocked = false
    var isCompleting = false

    // MARK: Profile

    var profile = OnboardingProfile()

    // MARK: HealthKit

    var healthKitState: HealthKitState = HKHealthStore.isHealthDataAvailable() ? .unknown : .unavailable
    var healthProfile: UserHealthProfile?
    var healthSnapshot: HealthDataSnapshot?

    var hasHealthData: Bool { healthProfile?.hasData == true }

    // MARK: Derived

    var currentStep: Int { route.rawValue + 1 }
    var totalSteps: Int { OnboardingRoute.allCases.count }

    var canGoBack: Bool {
        route.rawValue > 0 && route != .auth
    }

    var age: Int {
        Calendar.current.dateComponents([.year], from: profile.birthday, to: Date()).year ?? 0
    }

    var isUnderage: Bool { age < 13 }

    var profileCanContinue: Bool { !profile.trimmedName.isEmpty }

    var trainingCanContinue: Bool {
        !profile.fitnessGoals.isEmpty && !profile.preferredWorkouts.isEmpty
    }

    // MARK: - Navigation Actions

    func goBack() {
        guard canGoBack, let previous = OnboardingRoute(rawValue: route.rawValue - 1) else { return }
        FDS.haptic(.light)
        withAnimation(FDS.Spring.page) { route = previous }
    }

    func continueFromWelcome() {
        guard !isUnderage else {
            FDS.notificationHaptic(.warning)
            withAnimation(FDS.Spring.hero) { showAgeBlocked = true }
            return
        }

        FDS.haptic(.light)
        withAnimation(FDS.Spring.page) { route = .auth }
    }

    func markAuthenticated() {
        FDS.haptic(.medium)
        withAnimation(FDS.Spring.page) { route = .profile }
    }

    func continueFromProfile() {
        FDS.haptic(.light)
        withAnimation(FDS.Spring.page) { route = .health }
    }

    func requestHealthKit() async {
        guard healthKitState != .authorized && healthKitState != .requesting else { return }
        healthKitState = .requesting

        do {
            try await HealthKitManager.shared.requestAuthorization()
            healthKitState = .authorized
            await fetchHealthData()
        } catch {
            healthKitState = HKHealthStore.isHealthDataAvailable() ? .denied : .unavailable
        }
    }

    func continueFromHealth() {
        FDS.haptic(.light)
        withAnimation(FDS.Spring.page) { route = .training }
    }

    func skipHealthKit() {
        FDS.haptic(.light)
        withAnimation(FDS.Spring.page) { route = .training }
    }

    func continueFromTraining() {
        FDS.haptic(.light)
        withAnimation(FDS.Spring.page) { route = .coach }
    }

    func complete(in store: AppStore) {
        guard !isCompleting else { return }
        isCompleting = true
        store.userProfile = profile.toCoreProfile()
        FDS.haptic(.heavy)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            store.isOnboarded = true
        }
    }

    func resetAfterAgeBlock() {
        withAnimation(FDS.Spring.hero) { showAgeBlocked = false }
    }

    // MARK: - Collection Toggles

    func toggleGoal(_ goal: OnboardingFitnessGoal) {
        FDS.selectionHaptic()

        if let index = profile.fitnessGoals.firstIndex(of: goal) {
            profile.fitnessGoals.remove(at: index)
        } else {
            profile.fitnessGoals.append(goal)
        }
    }

    func toggleWorkout(_ workout: OnboardingWorkoutType) {
        FDS.selectionHaptic()

        if let index = profile.preferredWorkouts.firstIndex(of: workout) {
            profile.preferredWorkouts.remove(at: index)
        } else {
            profile.preferredWorkouts.append(workout)
        }
    }

    // MARK: - HealthKit Data

    func refreshHealthPrefillIfAvailable() async {
        guard healthKitState == .authorized else { return }
        await fetchHealthData()
    }

    private func fetchHealthData() async {
        async let profile = HealthKitManager.shared.fetchUserProfile()
        async let snapshot = HealthKitManager.shared.fetchRecentSnapshot()
        let (healthProfile, healthSnapshot) = await (profile, snapshot)

        self.healthProfile = healthProfile
        self.healthSnapshot = healthSnapshot

        if let height = healthProfile?.heightCm {
            self.profile.heightCm = height
        }

        if let weight = healthProfile?.weightKg {
            self.profile.weightKg = weight
        }
    }

    // MARK: - Dev Testing Bypass

    func devSkipToEnd(in store: AppStore) {
        profile.name = "Dev User"
        profile.birthday = Calendar.current.date(byAdding: .year, value: -28, to: Date()) ?? Date()
        profile.gender = .male
        profile.heightCm = 178
        profile.weightKg = 82
        profile.fitnessGoals = [.buildMuscle, .improveEndurance]
        profile.experienceLevel = .intermediate
        profile.preferredWorkouts = [.weightlifting, .hiit, .running]
        profile.coachingStyle = .balanced
        complete(in: store)
    }
}
