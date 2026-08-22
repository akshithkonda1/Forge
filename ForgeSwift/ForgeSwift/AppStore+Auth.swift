import Foundation
import Combine
import UIKit
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

extension AppStore {

    /// Rehydrates auth + completed onboarding on cold launch.
    func restoreOnboardingState() {
        if let session = ForgeAuthClient.shared.session {
            isAuthenticated = true
            authProvider = session.provider
            authEmail = session.email
            AriaContextStore.shared.configure(userId: session.userId)
        } else {
            isAuthenticated = UserDefaults.standard.bool(forKey: Self.authDefaultsKey)
            authProvider = UserDefaults.standard.string(forKey: Self.authProviderKey) ?? ""
            authEmail = UserDefaults.standard.string(forKey: Self.authEmailKey) ?? ""
        }
        // Legacy: onboarded users from before auth gate count as signed in —
        // but only in a debug tester build, never as a silent production login.
        if !isAuthenticated,
           UserDefaults.standard.bool(forKey: Self.onboardedDefaultsKey),
           ForgeAuthClient.shared.canUseDevOverride {
            isAuthenticated = true
            authProvider = authProvider.isEmpty ? "legacy" : authProvider
        }
        guard UserDefaults.standard.bool(forKey: Self.onboardedDefaultsKey) else { return }
        if let data = UserDefaults.standard.data(forKey: Self.profileDefaultsKey),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: data) {
            userProfile = saved
        }
        isOnboarded = true
    }

    /// Sign-up path: mark authenticated then run onboarding (HealthKit + profile).
    func beginSignUp() {
        isAuthenticated = true
        authProvider = "signup"
        UserDefaults.standard.set("signup", forKey: Self.authProviderKey)
        isOnboarded = false
        onboardingStep = 0
    }

    func applyAuthSession(_ session: ForgeAuthSession, isNewAccount: Bool) {
        authenticate(
            provider: session.provider,
            email: session.email,
            displayName: session.displayName,
            isNewAccount: isNewAccount
        )
        AriaContextStore.shared.configure(userId: session.userId)
        WatchAriaConfigBridge.sync(firstName: session.displayName.split(separator: " ").first.map(String.init))
    }

    /// Completes auth for returning or new social/email users.
    func authenticate(provider: String, email: String, displayName: String, isNewAccount: Bool) {
        isAuthenticated = true
        authProvider = provider
        authEmail = email
        UserDefaults.standard.set(provider, forKey: Self.authProviderKey)
        UserDefaults.standard.set(email, forKey: Self.authEmailKey)
        if !displayName.isEmpty, userProfile.name.isEmpty || userProfile.name == "Alex" || isNewAccount {
            userProfile.name = displayName
        }
        if isNewAccount || !UserDefaults.standard.bool(forKey: Self.onboardedDefaultsKey) {
            isOnboarded = false
            onboardingStep = 0
        } else {
            isOnboarded = true
            Task { await refreshDailyData() }
        }
    }

    func updateProfile(
        name: String? = nil,
        coachingStyle: CoachingStyle? = nil,
        fitnessGoals: [UserFitnessGoal]? = nil,
        experienceLevel: ExperienceLevel? = nil,
        preferredWorkouts: [WorkoutType]? = nil,
        weeklySchedule: [Int]? = nil,
        trainingEquipment: TrainingEquipment? = nil,
        connectedDevices: [String]? = nil,
        age: Int? = nil,
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        gender: Gender? = nil,
        biologicalSex: BiologicalSex? = nil,
        trainingTheme: AriaTrainingTheme? = nil,
        interestTags: [String]? = nil
    ) {
        if let name = name { userProfile.name = name }
        if let style = coachingStyle { userProfile.coachingStyle = style }
        if let goals = fitnessGoals { userProfile.fitnessGoals = goals }
        if let level = experienceLevel { userProfile.experienceLevel = level }
        if let preferredWorkouts { userProfile.preferredWorkouts = preferredWorkouts }
        if let weeklySchedule { userProfile.weeklySchedule = weeklySchedule.sorted() }
        if let trainingEquipment { userProfile.trainingEquipment = trainingEquipment }
        if let connectedDevices { userProfile.connectedDevices = connectedDevices }
        if let age { userProfile.age = age }
        if let weightKg { userProfile.weight = weightKg }
        if let heightCm { userProfile.height = heightCm }
        if let gender { userProfile.gender = gender }
        if let biologicalSex {
            userProfile.biologicalSex = biologicalSex
            MenstrualHealthStore.shared.enableForBiologicalSexIfNeeded(biologicalSex)
        }
        if let interestTags { userProfile.interestTags = interestTags }
        if let trainingTheme {
            setTrainingTheme(trainingTheme, source: "profile")
            return
        }
        objectWillChange.send()
    }

    /// Stores a new profile photo on disk and records its filename on the profile.
    /// Returns false when the image could not be written.
    @discardableResult
    func setProfilePhoto(_ image: UIImage) -> Bool {
        guard let fileName = ProfileAvatarStore.shared.save(
            image,
            replacing: userProfile.avatarFileName
        ) else { return false }
        userProfile.avatarFileName = fileName
        objectWillChange.send()
        return true
    }

    func removeProfilePhoto() {
        ProfileAvatarStore.shared.delete(userProfile.avatarFileName)
        userProfile.avatarFileName = nil
        objectWillChange.send()
    }
    
    // MARK: - Sleep Management
}
