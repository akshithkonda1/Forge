import Foundation
import SwiftUI
import HealthKit

// MARK: - HealthKit State

enum HealthKitState: Equatable {
    case unknown, requesting, authorized, denied, unavailable
}

// MARK: - Onboarding Route

enum OnboardingRoute: Int, CaseIterable, Hashable {
    case welcome = 0, auth, profile, health, training, coach, chat

    var title: String {
        switch self {
        case .welcome:  return "Age Check"
        case .auth:     return "Account"
        case .profile:  return "Profile"
        case .health:   return "Health"
        case .training: return "Training"
        case .coach:    return "Coach"
        case .chat:     return "Meet ARIA"
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

    /// Coaching style chosen → hand off to the conversational ARIA stage, where
    /// the (currently simulated) coach plays through a short data-aware intake.
    func startChat() {
        FDS.haptic(.medium)
        withAnimation(FDS.Spring.page) { route = .chat }
        beginChatIfNeeded()
    }

    func complete(in store: AppStore) {
        guard !isCompleting else { return }
        isCompleting = true

        // userProfile + isOnboarded are persisted by AppStore's didSet. Seeding
        // ARIA's living context here means the coach is already accustomed to
        // this user (goals, constraints, chat answers) on the first real session.
        store.userProfile = profile.toCoreProfile()
        AriaContextStore.shared.updateProfile(
            goals: profile.fitnessGoals.map { $0.label },
            constraints: capturedConstraints.isEmpty ? nil : capturedConstraints,
            lifestyleTags: onboardingTags()
        )
        FDS.haptic(.heavy)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            store.isOnboarded = true
        }
    }

    private func onboardingTags() -> [String] {
        var tags = capturedTags
        tags.append("coaching_style:\(profile.coachingStyle.rawValue)")
        tags.append("experience:\(profile.experienceLevel.rawValue)")
        if let goal = profile.fitnessGoals.first { tags.append("primary_goal:\(goal.rawValue)") }
        if healthKitState == .authorized { tags.append("healthkit:connected") }
        return tags
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

    // MARK: - ARIA Onboarding Chat (simulated bot; swap for AriaService later)

    var chatMessages: [OnboardingChatMessage] = []
    var chatSuggestions: [String] = []
    var chatInput: String = ""
    var isAriaTyping: Bool = false
    var chatFinished: Bool = false

    private let bot = OnboardingAriaBot()
    private var chatStarted = false
    private var chatStep = 0
    private var chatAnswers: [String] = []
    private(set) var capturedTags: [String] = []
    private(set) var capturedConstraints: [String] = []

    /// Kicks off the conversation once (idempotent — safe to call on every appear).
    func beginChatIfNeeded() {
        guard !chatStarted else { return }
        chatStarted = true
        let turn = bot.opening(
            profile: profile,
            health: healthProfile,
            healthConnected: healthKitState == .authorized
        )
        Task { await play(turn) }
    }

    /// Send whatever is in the composer.
    func sendChat() {
        sendChat(chatInput)
    }

    /// Send an explicit string (a tapped suggestion or typed text).
    func sendChat(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAriaTyping, !chatFinished else { return }
        FDS.haptic(.light)
        chatMessages.append(OnboardingChatMessage(role: .user, text: text))
        chatAnswers.append(text)
        chatInput = ""
        chatSuggestions = []
        let turn = bot.reply(step: chatStep, input: text, answers: chatAnswers, profile: profile)
        chatStep += 1
        Task { await play(turn) }
    }

    /// Plays a bot turn: captures its data, then streams each line with a
    /// realistic typing pause so the simulated coach feels alive.
    private func play(_ turn: AriaTurn) async {
        capturedTags.append(contentsOf: turn.tags)
        capturedConstraints.append(contentsOf: turn.constraints)
        for (index, line) in turn.messages.enumerated() {
            isAriaTyping = true
            try? await Task.sleep(nanoseconds: index == 0 ? 450_000_000 : 850_000_000)
            isAriaTyping = false
            chatMessages.append(OnboardingChatMessage(role: .aria, text: line))
            FDS.selectionHaptic()
        }
        chatSuggestions = turn.suggestions
        if turn.finished { chatFinished = true }
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

// MARK: - ARIA Onboarding Chat Model

struct OnboardingChatMessage: Identifiable {
    enum Role { case aria, user }
    let id = UUID()
    let role: Role
    let text: String
    var timestamp: Date = Date()
}

/// One conversational turn: the lines ARIA should say, the quick-reply chips to
/// offer next, whether the intake is finished, and any data captured from the
/// user's answer (fed into ARIA's living context on completion).
struct AriaTurn {
    var messages: [String]
    var suggestions: [String] = []
    var finished: Bool = false
    var tags: [String] = []
    var constraints: [String] = []
}

/// Deterministic stand-in for the real ARIA coach during onboarding. It produces
/// scripted, data-aware turns so the flow is fully testable offline and needs no
/// network on first launch. When the live coach is ready, replace the bodies with
/// calls to `AriaService.shared.sendMessage(...)` — the coordinator contract
/// (opening + reply → AriaTurn) stays identical.
struct OnboardingAriaBot {

    func opening(profile: OnboardingProfile, health: UserHealthProfile?, healthConnected: Bool) -> AriaTurn {
        let intro = "Hey \(name(profile)) — I'm ARIA, your coach. I've been reading your setup while you filled it out."
        let context = "You're training at a \(profile.experienceLevel.label.lowercased()) level, aiming for \(goalPhrase(profile)). \(healthLine(health, connected: healthConnected))"
        let question = "To tailor day one — how many days a week can you realistically train?"
        return AriaTurn(messages: [intro, context, question],
                        suggestions: ["2–3 days", "4–5 days", "6+ days"])
    }

    func reply(step: Int, input: String, answers: [String], profile: OnboardingProfile) -> AriaTurn {
        switch step {
        case 0:
            return AriaTurn(
                messages: ["\(input) is a strong, sustainable base.",
                           "When do you usually have the most energy to move?"],
                suggestions: ["Mornings", "Evenings", "It varies"],
                tags: ["weekly_days:\(slug(input))"]
            )
        case 1:
            return AriaTurn(
                messages: ["Good — I'll bias your harder sessions toward \(input.lowercased()).",
                           "Last thing: what's usually gotten in the way before?"],
                suggestions: ["Time", "Motivation", "Past injuries", "Nothing major"],
                tags: ["energy:\(slug(input))"]
            )
        default:
            let injury = input.lowercased().contains("injur")
            return AriaTurn(
                messages: [synthesis(profile: profile, answers: answers, obstacle: input)],
                finished: true,
                tags: ["obstacle:\(slug(input))"],
                constraints: injury ? ["injury-aware programming"] : []
            )
        }
    }

    // MARK: helpers

    private func name(_ p: OnboardingProfile) -> String {
        p.trimmedName.isEmpty ? "there" : p.trimmedName
    }

    private func goalPhrase(_ p: OnboardingProfile) -> String {
        let goals = p.fitnessGoals.map { $0.label.lowercased() }
        switch goals.count {
        case 0:  return "overall fitness"
        case 1:  return goals[0]
        case 2:  return "\(goals[0]) and \(goals[1])"
        default: return "\(goals[0]), \(goals[1]), and more"
        }
    }

    private func healthLine(_ health: UserHealthProfile?, connected: Bool) -> String {
        guard connected else {
            return "Once you connect Apple Health, I'll tune everything to your recovery."
        }
        var facts: [String] = []
        if let weight = health?.weightKg { facts.append("\(Int(weight)) kg") }
        if let height = health?.heightCm { facts.append("\(Int(height)) cm") }
        if let vo2 = health?.vo2Max { facts.append("VO₂max ~\(Int(vo2))") }
        if facts.isEmpty {
            return "I can see your Apple Health data too, so recovery will shape your load."
        }
        return "I can already see \(facts.joined(separator: ", ")) from Apple Health — that anchors your baseline."
    }

    private func synthesis(profile p: OnboardingProfile, answers: [String], obstacle: String) -> String {
        let days = answers.first ?? "a few days"
        let obstacleLine: String
        switch obstacle.lowercased() {
        case let s where s.contains("time"):   obstacleLine = "I'll keep sessions tight so time is never the reason you skip."
        case let s where s.contains("motiv"):  obstacleLine = "I'll keep the wins visible so momentum carries you on the low days."
        case let s where s.contains("injur"):  obstacleLine = "I'll ramp load carefully and program around anything that flares up."
        default:                                obstacleLine = "I'll keep it adaptive so it fits whatever the week throws at you."
        }
        return "Here's the plan I'm forming, \(name(p)): a \(p.coachingStyle.label.lowercased()) approach built around \(goalPhrase(p)), \(days.lowercased()) a week, starting at \(p.experienceLevel.label.lowercased()) intensity. \(obstacleLine) Ready when you are."
    }

    private func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: " ", with: "_")
    }
}
