import Foundation
import SwiftUI
import HealthKit

// MARK: - HealthKit State

enum HealthKitState: Equatable {
    case unknown, requesting, authorized, denied, unavailable

    var label: String {
        switch self {
        case .unknown:     return "Not connected"
        case .requesting:  return "Connecting…"
        case .authorized:  return "HealthKit live"
        case .denied:      return "Skipped"
        case .unavailable: return "Unavailable"
        }
    }

    var isLive: Bool { self == .authorized }
}

// MARK: - Interview steps

enum AriaInterviewStep: Int, CaseIterable, Hashable {
    case intro = 0
    case age
    case name
    case health
    case goals
    case experience
    case workouts
    case sleep
    case freeTime
    case trainingTheme
    case lifeContext
    case conditions
    case coaching
    case ready

    var progressLabel: String {
        switch self {
        case .intro:          return "Hello"
        case .age:            return "Safety"
        case .name:           return "Identity"
        case .health:         return "Signals"
        case .goals:          return "Goals"
        case .experience:     return "Level"
        case .workouts:       return "Training"
        case .sleep:          return "Sleep"
        case .freeTime:       return "Lifestyle"
        case .trainingTheme:  return "Style"
        case .lifeContext:    return "Context"
        case .conditions:     return "Boundaries"
        case .coaching:       return "Voice"
        case .ready:          return "Ready"
        }
    }
}

// MARK: - Transcript

enum AriaOnboardingRole: Equatable {
    case aria, user, system
}

struct AriaOnboardingMessage: Identifiable, Equatable {
    let id: String
    let role: AriaOnboardingRole
    let text: String

    init(role: AriaOnboardingRole, text: String) {
        self.id = UUID().uuidString
        self.role = role
        self.text = text
    }
}

// MARK: - Lifestyle / conditions enums

enum SleepRhythmBand: String, CaseIterable, Identifiable {
    case earlyBird, average, nightOwl, irregular
    var id: String { rawValue }
    var label: String {
        switch self {
        case .earlyBird: return "Early bird"
        case .average:   return "Average schedule"
        case .nightOwl:  return "Night owl"
        case .irregular: return "Irregular"
        }
    }
    var detail: String {
        switch self {
        case .earlyBird: return "In bed early · up with the morning"
        case .average:   return "Roughly 10–11pm · 6–7am"
        case .nightOwl:  return "Late nights · later mornings"
        case .irregular: return "Shift work or no fixed pattern"
        }
    }
    var tag: String { "sleep:\(rawValue)" }
}

enum LifestyleInterest: String, CaseIterable, Identifiable {
    case outdoors, gaming, reading, social, creative, family, deskWork, travel, music, cooking
    var id: String { rawValue }
    var label: String {
        switch self {
        case .outdoors:  return "Outdoors"
        case .gaming:    return "Gaming"
        case .reading:   return "Reading"
        case .social:    return "Social time"
        case .creative:  return "Creative work"
        case .family:    return "Family"
        case .deskWork:  return "Desk / deep work"
        case .travel:    return "Travel"
        case .music:     return "Music"
        case .cooking:   return "Cooking"
        }
    }
    var tag: String { "interest:\(rawValue)" }
}

enum LifeContextOption: String, CaseIterable, Identifiable {
    case single, partnered, familyHome, roommates, preferNot
    var id: String { rawValue }
    var label: String {
        switch self {
        case .single:      return "On my own"
        case .partnered:   return "Partnered"
        case .familyHome:  return "Family at home"
        case .roommates:   return "Roommates"
        case .preferNot:   return "Prefer not to say"
        }
    }
    var tag: String? {
        self == .preferNot ? nil : "life:\(rawValue)"
    }
}

enum ReportedCondition: String, CaseIterable, Identifiable {
    case adhd, epilepsy, anxietyDepression, injuryRehab, chronicIllness, mobility, sensory, other, none, preferNot
    var id: String { rawValue }
    var label: String {
        switch self {
        case .adhd:              return "ADHD"
        case .epilepsy:          return "Epilepsy"
        case .anxietyDepression: return "Anxiety / depression"
        case .injuryRehab:       return "Injury / rehab"
        case .chronicIllness:    return "Chronic illness"
        case .mobility:          return "Mobility"
        case .sensory:           return "Sensory"
        case .other:             return "Other"
        case .none:              return "None"
        case .preferNot:         return "Prefer not to say"
        }
    }
    /// True conditions that activate guidance-only coaching.
    var isConstraint: Bool {
        switch self {
        case .none, .preferNot: return false
        default: return true
        }
    }
    var tag: String? {
        isConstraint ? "condition:\(rawValue)" : nil
    }
}

// MARK: - Profile extension

extension OnboardingProfile {
    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
    }
    var firstName: String {
        trimmedName.split(separator: " ").first.map(String.init) ?? trimmedName
    }
}

// MARK: - Onboarding Coordinator

/// ARIA-led interview: questions, parallel HealthKit, progressive living-context seed.
@Observable
@MainActor
final class OnboardingCoordinator {

    // MARK: Interview

    var step: AriaInterviewStep = .intro
    var messages: [AriaOnboardingMessage] = []
    var isTyping = false
    var isCompleting = false
    var showAgeBlocked = false
    private var hasStarted = false

    // MARK: Profile

    var profile = OnboardingProfile()
    var freeText = ""

    // MARK: HealthKit

    var healthKitState: HealthKitState = HKHealthStore.isHealthDataAvailable() ? .unknown : .unavailable
    var healthProfile: UserHealthProfile?
    var healthSnapshot: HealthDataSnapshot?
    var healthPrefillNote: String?

    // MARK: Presence

    var ariaOrbState: AROrbState = .speaking
    var ariaMood: ARIAMood = .focused

    // MARK: Derived

    var progress: Double {
        Double(step.rawValue) / Double(max(1, AriaInterviewStep.allCases.count - 1))
    }
    var isUnderage: Bool { profile.ageYears < 13 }
    var canFinish: Bool {
        !profile.trimmedName.isEmpty
            && !profile.fitnessGoals.isEmpty
            && !profile.preferredWorkouts.isEmpty
            && !isCompleting
    }

    // MARK: - Start

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        seedFromSignUpDraft()
        Task { await runIntro() }
    }

    /// Pulls name + first quest chosen during immersive Day 0 sign-up.
    private func seedFromSignUpDraft() {
        let draft = AppStore._signUpDraftProfile
        if !draft.trimmedName.isEmpty {
            profile.name = draft.trimmedName
        }
        if !draft.fitnessGoals.isEmpty {
            profile.fitnessGoals = draft.fitnessGoals
        }
    }

    private func runIntro() async {
        let nameHint = profile.firstName
        if !nameHint.isEmpty {
            await ariaSay(
                "Welcome, \(nameHint). I'm Aria — your lifestyle coach. You already claimed a quest; now we forge the system around it.",
                mood: .energized
            )
        } else {
            await ariaSay(
                "I'm Aria — your lifestyle-based health coach. I learn how you move, sleep, stress, and live, then help you build plans that fit real life.",
                mood: .focused
            )
        }
        if let first = profile.fitnessGoals.first {
            await ariaSay(
                "Quest locked: \(first.label). I'm not a doctor — I coach structure, recovery, and habits. About a minute from here. HealthKit can load while we talk so day one already has signal.",
                mood: .calm
            )
        } else {
            await ariaSay(
                "I'm not a doctor. I don't diagnose or treat. I coach — structure, recovery, habits, and accountability. This takes about a minute. While we talk, I can load HealthKit in the background so day one already has signal.",
                mood: .calm
            )
        }
        await advanceTo(.age)
    }

    private func advanceTo(_ next: AriaInterviewStep) async {
        step = next
        freeText = ""
        switch next {
        case .intro:
            break
        case .age:
            await ariaSay("First — how old are you? I need this for safety and to calibrate intensity.", mood: .focused)
            ariaOrbState = .listening
        case .name:
            if !profile.trimmedName.isEmpty {
                // Already claimed during Day 0 sign-up — confirm and skip typing.
                await ariaSay(
                    "I'll keep calling you \(profile.firstName). Say the word if that's wrong later — for now we move.",
                    mood: .energized
                )
                appendUser(profile.trimmedName)
                AriaContextStore.shared.updateProfile(
                    lifestyleTags: ["onboarding:in_progress", "name:\(profile.trimmedName)"]
                )
                await advanceTo(.health)
                return
            }
            await ariaSay("What should I call you?", mood: .focused)
            ariaOrbState = .listening
        case .health:
            await ariaSay(
                "Want me to connect Apple Health? Sleep, HRV, and workouts make coaching far more accurate — I'll keep loading them while we finish talking.",
                mood: .energized
            )
            ariaOrbState = .listening
        case .goals:
            if profile.fitnessGoals.count == 1 {
                // First quest already locked at sign-up — let them confirm or add more.
                await ariaSay(
                    "You already locked \(profile.fitnessGoals[0].label). Keep it, or add a second goal before we continue.",
                    mood: .energized
                )
            } else {
                await ariaSay(personalizedGoalsPrompt(), mood: .focused)
            }
            ariaOrbState = .listening
        case .experience:
            await ariaSay(experiencePrompt(), mood: .focused)
            ariaOrbState = .listening
        case .workouts:
            await ariaSay(
                "What training do you actually enjoy? Pick what sticks — adherence beats perfect programming.",
                mood: .energized
            )
            ariaOrbState = .listening
        case .sleep:
            await ariaSay(
                "When do you usually sleep and wake? Your rhythm shapes when hard sessions and wind-down make sense.",
                mood: .calm
            )
            ariaOrbState = .listening
        case .freeTime:
            await ariaSay(
                "Outside training — how do you like to spend free time? This helps me design a life you can keep.",
                mood: .focused
            )
            ariaOrbState = .listening
        case .trainingTheme:
            let gamingHint = profile.freeTimeInterests.contains(.gaming) || profile.freeTimeInterests.contains(.reading)
                ? " Into stories or games? I can train you like Solo Leveling — daily quests, rank windows from readiness."
                : " Prefer classic coaching, or a world like Solo Leveling, Demon Slayer, or military ops?"
            await ariaSay(
                "How should your plans feel?\(gamingHint) Pick a style — or skip for classic.",
                mood: .energized
            )
            ariaOrbState = .listening
        case .lifeContext:
            await ariaSay(
                "Optional: anything about your living situation that affects time or energy? Skip anytime — Prefer not to say is always fine.",
                mood: .calm
            )
            ariaOrbState = .listening
        case .conditions:
            await ariaSay(
                "Do you have any conditions I should respect when coaching — ADHD, epilepsy, an injury, a chronic illness, a disability, or something else? Optional. I'm a lifestyle coach, not a doctor. I won't diagnose or treat; I'll only use this to keep guidance safer and more realistic.",
                mood: .focused
            )
            ariaOrbState = .listening
        case .coaching:
            await ariaSay("Last coaching choice: how should I talk to you day to day?", mood: .calm)
            ariaOrbState = .listening
        case .ready:
            await deliverReadinessSummary()
        }
    }

    // MARK: - Answers

    func confirmAge() {
        guard step == .age else { return }
        if isUnderage {
            FDS.notificationHaptic(.warning)
            withAnimation(FDS.Spring.hero) { showAgeBlocked = true }
            return
        }
        let years = profile.ageYears
        appendUser("I'm \(years)")
        FDS.haptic(.light)
        Task {
            await ariaSay(
                years < 18
                    ? "Got it. I'll keep programming age-appropriate and recovery-aware."
                    : "Age locked for eligibility and load math.",
                mood: .focused
            )
            await advanceTo(.name)
        }
    }

    func submitName() {
        guard step == .name else { return }
        let name = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        profile.name = name
        freeText = ""
        appendUser(name)
        FDS.haptic(.medium)
        AriaContextStore.shared.updateProfile(
            lifestyleTags: ["onboarding:in_progress", "name:\(name)"]
        )
        AriaContextStore.shared.addInsight("Met \(name) during onboarding interview.")
        Task {
            await ariaSay(
                "Great to meet you, \(profile.firstName). Let's get body signals online.",
                mood: .energized
            )
            await advanceTo(.health)
        }
    }

    func connectHealthKit() {
        guard step == .health else { return }
        appendUser("Connect HealthKit")
        FDS.haptic(.medium)
        Task {
            await requestHealthKit()
            await advanceTo(.goals)
        }
    }

    func skipHealthKit() {
        guard step == .health else { return }
        appendUser("Skip for now")
        if healthKitState != .authorized {
            healthKitState = healthKitState == .unavailable ? .unavailable : .denied
        }
        FDS.haptic(.light)
        Task {
            await ariaSay(
                "No problem — we can still build a strong plan. Connect HealthKit anytime and I'll fold recovery in.",
                mood: .calm
            )
            await advanceTo(.goals)
        }
    }

    func toggleGoal(_ goal: OnboardingFitnessGoal) {
        guard step == .goals else { return }
        FDS.selectionHaptic()
        if let i = profile.fitnessGoals.firstIndex(of: goal) {
            profile.fitnessGoals.remove(at: i)
        } else {
            profile.fitnessGoals.append(goal)
        }
        syncPartialContext()
    }

    func confirmGoals() {
        guard step == .goals, !profile.fitnessGoals.isEmpty else { return }
        let labels = profile.fitnessGoals.map(\.label).joined(separator: ", ")
        appendUser(labels)
        FDS.haptic(.light)
        syncPartialContext()
        Task {
            await ariaSay("Locked: \(labels). Primary outcomes set.", mood: .energized)
            await advanceTo(.experience)
        }
    }

    func selectExperience(_ level: ExperienceLevel) {
        guard step == .experience else { return }
        profile.experienceLevel = level
        appendUser(level.label)
        FDS.haptic(.light)
        syncPartialContext()
        Task {
            await ariaSay("Starting intensity: \(level.label.lowercased()).", mood: .focused)
            await advanceTo(.workouts)
        }
    }

    func toggleWorkout(_ workout: OnboardingWorkoutType) {
        guard step == .workouts else { return }
        FDS.selectionHaptic()
        if let i = profile.preferredWorkouts.firstIndex(of: workout) {
            profile.preferredWorkouts.remove(at: i)
        } else {
            profile.preferredWorkouts.append(workout)
        }
    }

    func confirmWorkouts() {
        guard step == .workouts, !profile.preferredWorkouts.isEmpty else { return }
        let labels = profile.preferredWorkouts.map(\.label).joined(separator: ", ")
        appendUser(labels)
        FDS.haptic(.light)
        syncPartialContext()
        Task {
            await ariaSay("I'll bias sessions toward \(labels).", mood: .energized)
            await advanceTo(.sleep)
        }
    }

    func selectSleepBand(_ band: SleepRhythmBand) {
        guard step == .sleep else { return }
        profile.sleepBand = band
        appendUser(band.label)
        FDS.haptic(.light)
        syncPartialContext()
        Task {
            await ariaSay(
                "Sleep rhythm noted: \(band.detail). I'll schedule hard work and recovery around that.",
                mood: .calm
            )
            await advanceTo(.freeTime)
        }
    }

    func toggleInterest(_ interest: LifestyleInterest) {
        guard step == .freeTime else { return }
        FDS.selectionHaptic()
        if let i = profile.freeTimeInterests.firstIndex(of: interest) {
            profile.freeTimeInterests.remove(at: i)
        } else {
            profile.freeTimeInterests.append(interest)
        }
    }

    func confirmInterests() {
        guard step == .freeTime else { return }
        if profile.freeTimeInterests.isEmpty {
            appendUser("Skip")
        } else {
            appendUser(profile.freeTimeInterests.map(\.label).joined(separator: ", "))
        }
        FDS.haptic(.light)
        syncPartialContext()
        Task {
            if profile.freeTimeInterests.isEmpty {
                await ariaSay("All good — we can learn your lifestyle as we go.", mood: .calm)
            } else {
                let labels = profile.freeTimeInterests.prefix(3).map(\.label).joined(separator: ", ")
                await ariaSay("I'll keep \(labels) in mind so training doesn't fight your life.", mood: .focused)
            }
            await advanceTo(.trainingTheme)
        }
    }

    func selectTrainingTheme(_ theme: AriaTrainingTheme) {
        guard step == .trainingTheme else { return }
        profile.trainingTheme = theme
        appendUser(theme.label)
        FDS.haptic(.light)
        syncPartialContext()
        Task {
            if theme == .classic {
                await ariaSay(
                    "Classic coaching it is — clear plans, no gimmicks. You can always say “train like Solo Leveling” later and I’ll switch.",
                    mood: .calm
                )
            } else if theme == .soloLeveling {
                await ariaSay(
                    "Solo Leveling locked. I’ll build daily quests, rank windows from readiness, and gate-clear sessions when your body can take it.",
                    mood: .energized
                )
            } else {
                await ariaSay(
                    "\(theme.label) it is — \(theme.tagline) Every plan will respect readiness while staying in that world.",
                    mood: .focused
                )
            }
            await advanceTo(.lifeContext)
        }
    }

    func skipTrainingTheme() {
        guard step == .trainingTheme else { return }
        profile.trainingTheme = .classic
        appendUser("Skip — classic coach")
        FDS.haptic(.light)
        Task {
            await ariaSay(
                "Classic for now. Tell me any franchise later — I’ll rewrite the plan in that style.",
                mood: .calm
            )
            await advanceTo(.lifeContext)
        }
    }

    func selectLifeContext(_ option: LifeContextOption) {
        guard step == .lifeContext else { return }
        profile.lifeContext = option
        appendUser(option.label)
        FDS.haptic(.light)
        syncPartialContext()
        Task {
            if option == .preferNot {
                await ariaSay("Respecting that. Moving on.", mood: .calm)
            } else {
                await ariaSay("Thanks — I'll respect your time and energy around that.", mood: .calm)
            }
            await advanceTo(.conditions)
        }
    }

    func skipLifeContext() {
        guard step == .lifeContext else { return }
        profile.lifeContext = .preferNot
        appendUser("Prefer not to say")
        FDS.haptic(.light)
        Task {
            await ariaSay("Totally fine. Next question.", mood: .calm)
            await advanceTo(.conditions)
        }
    }

    func toggleCondition(_ condition: ReportedCondition) {
        guard step == .conditions else { return }
        FDS.selectionHaptic()

        // Exclusive: none / preferNot clear others
        if condition == .none || condition == .preferNot {
            profile.reportedConditions = [condition]
            profile.guidanceOnlyMode = false
            return
        }

        profile.reportedConditions.removeAll { $0 == .none || $0 == .preferNot }
        if let i = profile.reportedConditions.firstIndex(of: condition) {
            profile.reportedConditions.remove(at: i)
        } else {
            profile.reportedConditions.append(condition)
        }
        profile.guidanceOnlyMode = profile.reportedConditions.contains(where: \.isConstraint)
    }

    func confirmConditions() {
        guard step == .conditions else { return }
        if profile.reportedConditions.isEmpty {
            profile.reportedConditions = [.preferNot]
            profile.guidanceOnlyMode = false
        }

        let labels = profile.reportedConditions.map(\.label).joined(separator: ", ")
        appendUser(labels)
        if profile.reportedConditions.contains(.other), !freeText.trimmingCharacters(in: .whitespaces).isEmpty {
            profile.conditionsNote = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
            freeText = ""
        }
        FDS.haptic(.medium)
        syncPartialContext()

        Task {
            if profile.guidanceOnlyMode {
                await ariaSay(
                    "Understood. I'll treat this as a coaching boundary — guidance and structure only. Never medical advice, diagnosis, or treatment plans. If something feels clinical, talk to a qualified professional.",
                    mood: .pushed
                )
            } else if profile.reportedConditions.contains(.none) {
                await ariaSay(
                    "Got it. I'll still coach as a lifestyle guide — not a clinician — and keep recovery front and center.",
                    mood: .focused
                )
            } else {
                await ariaSay("Noted. Privacy respected.", mood: .calm)
            }
            await advanceTo(.coaching)
        }
    }

    func selectCoachingStyle(_ style: OnboardingCoachingStyle) {
        guard step == .coaching else { return }
        profile.coachingStyle = style
        appendUser(style.label)
        FDS.haptic(.medium)
        Task {
            await ariaSay("Voice locked: \(style.label).", mood: AriaOnboardingGuide.mood(for: style))
            await advanceTo(.ready)
        }
    }

    // MARK: - HealthKit parallel

    func requestHealthKit() async {
        guard healthKitState != .authorized else {
            await refreshHealthDataQuietly()
            return
        }
        guard healthKitState != .unavailable else {
            await ariaSay("Health data isn't available on this device. Continuing manually.", mood: .calm)
            return
        }

        healthKitState = .requesting
        ariaOrbState = .processing

        do {
            try await HealthKitManager.shared.requestAuthorization()
            healthKitState = .authorized
            await ariaSay(
                "HealthKit connected. Pulling sleep, heart rate, and activity in the background while we finish.",
                mood: .energized
            )
            Task { await refreshHealthDataQuietly() }
        } catch {
            healthKitState = .denied
            await ariaSay(
                "Couldn't connect HealthKit just now. You can enable it later — continuing.",
                mood: .calm
            )
        }
    }

    private func refreshHealthDataQuietly() async {
        async let p = HealthKitManager.shared.fetchUserProfile()
        async let s = HealthKitManager.shared.fetchRecentSnapshot()
        let (prof, snap) = await (p, s)
        healthProfile = prof
        healthSnapshot = snap

        var prefill: [String] = []
        if let h = prof?.heightCm {
            profile.heightCm = h
            prefill.append("height \(Int(h)) cm")
        }
        if let w = prof?.weightKg {
            profile.weightKg = w
            prefill.append("weight \(Int(w)) kg")
        }
        if let vo2 = prof?.vo2Max {
            prefill.append(String(format: "VO₂max %.0f", vo2))
        }
        if let hrv = snap?.hrv, hrv > 0 {
            prefill.append("HRV \(Int(hrv)) ms")
        }
        if let sleep = snap?.sleepHours, sleep > 0 {
            prefill.append(String(format: "sleep %.1fh", sleep))
        }

        guard !prefill.isEmpty else { return }
        healthPrefillNote = prefill.joined(separator: " · ")
        AriaContextStore.shared.addInsight("HealthKit prefill: \(healthPrefillNote!)")
        syncPartialContext()

        if !messages.contains(where: { $0.role == .system && $0.text.contains("HealthKit") }) {
            messages.append(AriaOnboardingMessage(
                role: .system,
                text: "HealthKit loaded: \(healthPrefillNote!)"
            ))
        }
    }

    // MARK: - Ready / complete

    private func deliverReadinessSummary() async {
        let script = AriaOnboardingGuide.firstSessionScript(
            profile: profile,
            healthConnected: healthKitState == .authorized
        )
        await ariaSay(script, mood: AriaOnboardingGuide.mood(for: profile.coachingStyle))

        if let note = healthPrefillNote {
            await ariaSay(
                "Live signals already in: \(note). Your first plan won't start from zero.",
                mood: .energized
            )
        }

        if profile.guidanceOnlyMode {
            await ariaSay(
                "Reminder: with the conditions you shared, I stay in guidance mode only — lifestyle structure, pacing, and accountability. Not medical care.",
                mood: .pushed
            )
        }

        await ariaSay(
            "Ready when you are, \(profile.firstName.isEmpty ? "athlete" : profile.firstName). Tap below and we start together.",
            mood: .energized
        )
        ariaOrbState = .idle
    }

    func complete(in store: AppStore) {
        guard !isCompleting else { return }
        isCompleting = true
        ariaOrbState = .processing

        store.userProfile = profile.toCoreProfile()
        let healthConnected = healthKitState == .authorized

        AriaContextStore.shared.seedFromOnboarding(
            name: profile.trimmedName,
            goals: profile.fitnessGoals.map(\.label),
            experienceLevel: profile.experienceLevel.rawValue,
            preferredWorkouts: profile.preferredWorkouts.map(\.label),
            coachingStyle: profile.coachingStyle.label,
            healthConnected: healthConnected,
            lifestyleTags: profile.lifestyleTagsForContext(),
            constraints: profile.constraintsForContext(),
            trainingTheme: profile.trainingTheme
        )

        // Seed today's plan under the chosen theme so Home isn't stuck on mock upper body.
        if profile.trainingTheme != .classic || store.readiness.overall > 0 {
            let plan = AriaPlanEngine.evaluate(
                input: "Build my first \(profile.trainingTheme.label) training plan",
                context: store.makeTrainerContext()
            )
            store.todayWorkout = plan.workoutPlan
        }

        let welcome = AriaOnboardingGuide.welcomeChatMessage(
            profile: profile,
            healthConnected: healthConnected
        )
        store.seedAriaWelcomeFromOnboarding(message: welcome)
        AriaContextStore.shared.addInsight("Onboarding interview complete.")

        if healthConnected {
            Task { await store.refreshDailyData() }
        }

        FDS.haptic(.heavy)
        FDS.notificationHaptic(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            store.isOnboarded = true
        }
    }

    func resetAfterAgeBlock() {
        withAnimation(FDS.Spring.hero) { showAgeBlocked = false }
    }

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
        profile.sleepBand = .average
        profile.freeTimeInterests = [.outdoors, .deskWork]
        profile.lifeContext = .preferNot
        profile.reportedConditions = [.none]
        profile.guidanceOnlyMode = false
        step = .ready
        complete(in: store)
    }

    // MARK: - Helpers

    private func appendUser(_ text: String) {
        messages.append(AriaOnboardingMessage(role: .user, text: text))
    }

    private func ariaSay(_ text: String, mood: ARIAMood) async {
        isTyping = true
        ariaOrbState = .processing
        ariaMood = mood
        try? await Task.sleep(nanoseconds: 360_000_000)
        messages.append(AriaOnboardingMessage(role: .aria, text: text))
        isTyping = false
        ariaOrbState = .speaking
        try? await Task.sleep(nanoseconds: 180_000_000)
        ariaOrbState = .idle
        FDS.haptic(.soft)
    }

    private func personalizedGoalsPrompt() -> String {
        if !profile.firstName.isEmpty {
            return "\(profile.firstName), what are we building toward? Pick every outcome that matters."
        }
        return "What are we building toward? Pick every outcome that matters."
    }

    private func experiencePrompt() -> String {
        if let vo2 = healthProfile?.vo2Max, vo2 >= 45 {
            return "Your HealthKit VO₂max looks solid. How would you rate your training experience?"
        }
        return "How long have you been training seriously?"
    }

    private func syncPartialContext() {
        AriaContextStore.shared.updateProfile(
            goals: profile.fitnessGoals.map(\.label),
            constraints: profile.constraintsForContext(),
            lifestyleTags: profile.lifestyleTagsForContext() + ["onboarding:in_progress"]
        )
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

    // `step` is a 0-indexed conversation turn counter (0, 1, 2…), NOT OnboardingRoute.rawValue.
    // Passing the wrong index causes premature synthesis (default branch) after turn 0.
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
