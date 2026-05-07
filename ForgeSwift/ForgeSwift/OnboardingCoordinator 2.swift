import SwiftUI
import Foundation

// MARK: - Fallback types if they don't exist in the project

#if canImport(Foundation)
#else
// Define minimal stubs if Foundation is unavailable (unlikely)
#endif

// Gender, ExperienceLevel, CoachingStyle, WorkoutType, UserProfile, AppStore, HealthKitState
// Only define fallback for HealthKitState and AppStore, since others are likely enums or structs from OnboardingView.swift

#if !canImport(HealthKitState)
/// Minimal HealthKitState fallback
enum HealthKitState {
  case unknown
  case requesting
  case authorized
  case denied
  case unavailable
}
#endif

// NOTE: `canImport` checks modules, not types. If your project already defines `AppStore`,
// the old `#if !canImport(AppStore)` would not prevent this stub from compiling, causing
// a redeclaration error. Use the `ONBOARDING_STUBS` flag only in isolation or previews.
#if ONBOARDING_STUBS
/// Minimal AppStore stub to satisfy usage in this file
final class AppStore {
  /// Placeholder for onboarding profile storage
  var onboardingProfile: OnboardingProfile?
  /// Placeholder for main user profile storage
  var userProfile: UserProfile?

  func saveOnboardingProfile(_ profile: OnboardingProfile) {
    onboardingProfile = profile
  }

  func promoteOnboardingProfileToUserProfile() {
    if let onboarding = onboardingProfile {
      // A simple promotion step copying data
      userProfile = UserProfile(profile: onboarding)
      onboardingProfile = nil
    }
  }
}
#endif

// If UserProfile does not exist, define minimal stub to allow promoteOnboardingProfileToUserProfile
#if ONBOARDING_STUBS
struct UserProfile {
  // Simple init from OnboardingProfile
  init(profile: OnboardingProfile) {
    // No-op
  }
}
#endif

// MARK: - OnboardingRoute
enum OnboardingRoute: Int, CaseIterable {
  case welcome = 0
  case auth = 1
  case profile = 2
  case health = 3
  case training = 4
  case coach = 5

  var title: String {
    switch self {
    case .welcome:
      return "Welcome"
    case .auth:
      return "Authentication"
    case .profile:
      return "Profile"
    case .health:
      return "Health Data"
    case .training:
      return "Training"
    case .coach:
      return "Coach"
    }
  }
}

// MARK: - HealthSnapshot minimal stub
struct HealthSnapshot {
  let restingHeartRate: Double
  let vo2Max: Double
  // Add more fields if needed for UI (simple placeholder)
  init(restingHeartRate: Double = 60, vo2Max: Double = 45) {
    self.restingHeartRate = restingHeartRate
    self.vo2Max = vo2Max
  }
}

// MARK: - OnboardingCoordinator

final class OnboardingCoordinator: ObservableObject {
  // MARK: Published properties used by OnboardingView and subviews
  @Published var route: OnboardingRoute = .welcome
  @Published var showAgeBlocked: Bool = false
  @Published var profile: OnboardingProfile = OnboardingProfile()
  @Published var healthKitState: HealthKitState = .unknown
  @Published var healthProfile: (heightCm: Double?, weightKg: Double?, vo2Max: Double?)? = nil
  @Published var healthSnapshot: HealthSnapshot? = nil
  @Published var isCompleting: Bool = false

  // MARK: Computed helpers

  var currentStep: Int {
    route.rawValue + 1
  }

  var totalSteps: Int {
    OnboardingRoute.allCases.count
  }

  var canGoBack: Bool {
    route != .welcome
  }

  var age: Int {
    // Support both optional and non-optional birthday definitions
    // If `birthday` is optional, compute its age, otherwise use the non-optional directly.
    (profile.birthday as Date?)?.age ?? 0
  }

  var isUnderage: Bool {
    age < 13
  }

  var hasHealthData: Bool {
    healthProfile != nil
  }

  var trainingCanContinue: Bool {
    !profile.fitnessGoals.isEmpty && !profile.preferredWorkouts.isEmpty
  }

  var profileCanContinue: Bool {
    !profile.trimmedName.isEmpty
  }

  // MARK: Navigation methods

  func goBack() {
    guard let previous = OnboardingRoute(rawValue: route.rawValue - 1) else { return }
    route = previous
  }

  func continueFromWelcome() {
    if isUnderage {
      showAgeBlocked = true
    } else {
      route = .auth
    }
  }

  func resetAfterAgeBlock() {
    showAgeBlocked = false
    route = .welcome
  }

  func markAuthenticated() {
    route = .profile
  }

  func continueFromProfile() {
    route = .health
  }

  func skipHealthKit() {
    healthKitState = .denied
    route = .training
  }

  func continueFromHealth() {
    switch healthKitState {
    case .unknown, .requesting:
      // Do nothing - waiting for permission
      break
    default:
      route = .training
    }
  }

  func continueFromTraining() {
    route = .coach
  }

  func complete(in store: AppStore) {
    isCompleting = true

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }
      // Write temp onboarding profile to store
      store.saveOnboardingProfile(self.profile)
      // Promote to real profile if needed
      store.promoteOnboardingProfileToUserProfile()
      self.isCompleting = false
    }
  }

  #if DEBUG
  func devSkipToEnd(in store: AppStore) {
    // Fast forward all states
    route = .coach
    profile = OnboardingProfile(
      name: "Debug User",
      birthday: Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? <#default value#>!,
      fitnessGoals: ["Build Strength"],
      preferredWorkouts: ["Running"]
    )
    healthKitState = .authorized
    healthProfile = (heightCm: 180, weightKg: 75, vo2Max: 50)
    healthSnapshot = HealthSnapshot(restingHeartRate: 55, vo2Max: 50)
    complete(in: store)
  }
  #endif

  // MARK: HealthKit stubs

  func requestHealthKit() async {
    DispatchQueue.main.async {
      self.healthKitState = .requesting
    }

    try? await Task.sleep(nanoseconds: 1_000_000_000) // simulate delay 1s

    DispatchQueue.main.async {
      self.healthKitState = .authorized
      self.healthProfile = (heightCm: 175, weightKg: 70, vo2Max: 48)
      self.healthSnapshot = HealthSnapshot(restingHeartRate: 58, vo2Max: 48)
    }
  }

  func refreshHealthPrefillIfAvailable() async {
    guard healthKitState == .authorized else { return }
    DispatchQueue.main.async {
      self.healthProfile = (heightCm: 175, weightKg: 70, vo2Max: 48)
    }
  }
}

// MARK: - OnboardingProfile extension

extension OnboardingProfile {
  var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

// MARK: - Date age calculation helper

extension Date {
  var age: Int {
    let calendar = Calendar.current
    let now = Date()
    let components = calendar.dateComponents([.year, .month, .day], from: self, to: now)
    return components.year ?? 0
  }
}

