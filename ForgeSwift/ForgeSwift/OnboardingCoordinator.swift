import Foundation
import SwiftUI
import HealthKit
import ForgeCore

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
    var showingEducationalCyclePrompt = false
    private var hasStarted = false

    // MARK: Profile

    var profile = OnboardingProfile()
    var freeText = ""

    // MARK: HealthKit

    var healthKitState: HealthKitState = HKHealthStore.isHealthDataAvailable() ? .unknown : .unavailable
    var healthProfile: UserHealthProfile?
    var healthSnapshot: HealthDataSnapshot?
    var healthPrefillNote: String?
    var showHealthSourceBadge = false // optional — user taps "Show where this came from" if they want it

    var calendarState: HealthKitState = .unknown
    var calendarBusyToday: Int = 0

    // MARK: Presence

    var ariaOrbState: AROrbState = .speaking
    var ariaMood: ARIAMood = .focused

    // MARK: Derived

    // Progress over the active flow only (legacy steps not counted).
    // Count and fraction come from OnboardingGraph so the header cannot
    // drift back to AriaInterviewStep.allCases (theme + lifeContext).
    var progress: Double { OnboardingGraph.progress(at: step.graph) }
    var progressStepIndex: Int { OnboardingGraph.displayIndex(for: step.graph) }
    var progressStepCount: Int { OnboardingGraph.displayCount }
    var hasAgreedToTerms: Bool = false
    var isUnderage: Bool { profile.ageYears < 13 }
    var canFinish: Bool {
        profile.isPreferredNameValid
            && profile.hasConfirmedDetails
            && !profile.fitnessGoals.isEmpty
            && !profile.preferredWorkouts.isEmpty
            && hasAgreedToTerms
            && !isCompleting
    }

    /// Back walks the active graph. Intro and Name have no predecessor —
    /// leaving the interview is sign-out, not a silent return to the splash.
    var canGoBack: Bool {
        !isCompleting && OnboardingGraph.previous(of: step.graph) != nil
    }

    func goBack() {
        guard canGoBack, let prev = OnboardingGraph.previous(of: step.graph) else { return }
        FDS.haptic(.light)
        step = AriaInterviewStep(prev)
        freeText = ""
        isTyping = false
        ariaOrbState = .listening
    }

    // MARK: - Start

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        seedFromSignUpDraft()
        Task { await runIntro() }
    }

    /// Pulls name, last name, and first quest chosen during Day 0 sign-up.
    private func seedFromSignUpDraft() {
        let draft = AppStore._signUpDraftProfile
        if !draft.trimmedName.isEmpty {
            profile.name = draft.trimmedName
        }
        if !draft.trimmedLastName.isEmpty {
            profile.lastName = draft.trimmedLastName
        }
        if !draft.fitnessGoals.isEmpty {
            profile.fitnessGoals = draft.fitnessGoals
        }
    }

    private func runIntro() async {
        let nameHint = profile.firstName
        let quest = profile.fitnessGoals.first.map { " Quest: \($0.label)." } ?? ""
        if !nameHint.isEmpty {
            await ariaSay(
                "Welcome, \(nameHint). I'm ARIA — lifestyle coach, not a doctor. Small changes that fit the life you already have.\(quest) About a minute.",
                mood: .energized
            )
        } else {
            await ariaSay(
                "I'm Aria. I learn how you move, sleep, and live, then build plans that fit — not a doctor. About a minute.",
                mood: .focused
            )
        }
        await advanceTo(.name)
    }

    private func advanceTo(_ next: AriaInterviewStep) async {
        step = next
        freeText = ""
        switch next {
        case .intro:
            break
        case .name:
            if profile.isPreferredNameValid {
                await ariaSay(
                    "I have you as \(profile.firstName) from sign-up. Confirm the spelling, add a last name if you want it on your profile, then continue.",
                    mood: .focused
                )
            } else {
                await ariaSay(
                    "What should I call you? Your first name is enough — that's what I'll use in coaching. Last name is optional and stays on your profile.",
                    mood: .focused
                )
            }
            ariaOrbState = .listening
        case .health:
            await ariaSay(
                "First Health, then your calendar — so I can fit training around your day, not the other way around. Health first: sleep, heart, and activity.",
                mood: .energized
            )
            ariaOrbState = .listening
        case .details:
            showingEducationalCyclePrompt = false
            if healthKitState == .authorized, !profile.healthSourcedFields.isEmpty {
                await ariaSay(
                    "Apple Health already has some of your details. Check date of birth, biological sex, height, and weight — change anything that's off.",
                    mood: .focused
                )
            } else {
                await ariaSay(
                    "Your details next — date of birth, biological sex, height, and weight. I use these for heart-rate zones, calories, and Cycle Health. This is not gender.",
                    mood: .focused
                )
            }
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

    func submitName() {
        guard step == .name else { return }
        guard profile.isPreferredNameValid else { return }
        let spoken = profile.profileDisplayName
        appendUser(spoken)
        FDS.haptic(.medium)
        AriaContextStore.shared.updateProfile(
            lifestyleTags: ["onboarding:in_progress", "name:\(profile.trimmedName)"]
        )
        AriaContextStore.shared.addInsight("Met \(profile.trimmedName) during onboarding interview.")
        Task { await advanceTo(.health) }
    }

    func confirmDetails() {
        guard step == .details else { return }
        if isUnderage {
            FDS.notificationHaptic(.warning)
            withAnimation(FDS.Spring.hero) { showAgeBlocked = true }
            return
        }
        guard profile.hasConfirmedDetails else { return }
        appendUser(profile.detailsSummaryLine)
        FDS.haptic(.light)
        syncPartialContext()
        Task { await advanceTo(.goals) }
    }

    func continueFromHealth() {
        guard step == .health else { return }
        appendUser(healthKitState == .authorized && calendarState == .authorized ? "Connected both" : healthKitState == .authorized ? "Health connected" : calendarState == .authorized ? "Calendar connected" : "Continue")
        Task { await advanceTo(.details) }
    }

    func connectHealthKit() {
        guard step == .health else { return }
        appendUser("Connect Apple Health")
        FDS.haptic(.medium)
        Task { await requestHealthKit() }
    }

    func skipHealthKit() {
        guard step == .health else { return }
        appendUser("Skip for now")
        if healthKitState != .authorized {
            healthKitState = healthKitState == .unavailable ? .unavailable : .denied
        }
        FDS.haptic(.light)
    }

    func connectCalendar() async {
        await requestCalendar()
    }

    func skipCalendar() {
        calendarState = .denied
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
        Task { await advanceTo(.experience) }
    }

    func selectBiologicalSex(_ sex: BiologicalSex) {
        guard step == .details else { return }
        profile.biologicalSex = sex
        profile.healthSourcedFields.remove(.sex)
        FDS.selectionHaptic()
        if sex.cycleAutoEnabled {
            showingEducationalCyclePrompt = false
        } else if sex == .male {
            showingEducationalCyclePrompt = true
        } else {
            showingEducationalCyclePrompt = false
        }
    }

    func selectEducationalCycleMode(_ enabled: Bool) {
        guard step == .details else { return }
        profile.educationalCycleMode = enabled
        showingEducationalCyclePrompt = false
        FDS.haptic(.light)
    }

    func selectExperience(_ level: ExperienceLevel) {
        guard step == .experience else { return }
        profile.experienceLevel = level
        appendUser(level.label)
        FDS.haptic(.light)
        syncPartialContext()
        Task { await advanceTo(.workouts) }
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
        Task { await advanceTo(.sleep) }
    }

    func selectSleepBand(_ band: SleepRhythmBand) {
        guard step == .sleep else { return }
        profile.sleepBand = band
        appendUser(band.label)
        FDS.haptic(.light)
        syncPartialContext()
        // Habit seed — first loop from sleep rhythm so day-one Lifestyle isn't empty.
        // SleepRhythmBand is `.irregular`, not `.inconsistent` (that case does not exist).
        if OnboardingGraph.seedsSleepVariance(bandRawValue: band.rawValue) {
            let habit = DeepHabit(
                id: OnboardingGraph.sleepVarianceHabitId, title: "Wobbly wind-down",
                cue: "Evening at home after 22:00", routine: "Phone stays with you → late scroll",
                payoff: "Felt productive", cost: "Deep sleep cut",
                category: .sleep, confidence: 0.72,
                evidence: "Sleep rhythm \(band.label) — first habit seeded",
                breaker: "Tonight, leave phone charging in the kitchen at 22:00.",
                breakerAction: "Try kitchen-phone"
            )
            AriaContextStore.shared.context.deepHabits = [habit]
        }
        Task { await advanceTo(.freeTime) }
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
        // Collapse: trainingTheme + lifeContext are now answered here — default to classic / preferNot
        // so we can skip two screens and keep the interview feeling like one human ask.
        // trainingTheme is already `.classic`; lifeContext is optional and must not
        // be force-read via `.rawValue` (that is what blocked the #168 compile).
        if profile.lifeContext == nil { profile.lifeContext = .preferNot }
        syncPartialContext()
        Task { await advanceTo(AriaInterviewStep(OnboardingGraph.next(after: .confirmInterests))) }
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
            await advanceTo(.lifeContext)
        }
    }

    func selectLifeContext(_ option: LifeContextOption) {
        guard step == .lifeContext else { return }
        profile.lifeContext = option
        appendUser(option.label)
        FDS.haptic(.light)
        syncPartialContext()
        Task { await advanceTo(.conditions) }
    }

    func skipLifeContext() {
        guard step == .lifeContext else { return }
        profile.lifeContext = .preferNot
        appendUser("Prefer not to say")
        FDS.haptic(.light)
        Task { await advanceTo(.conditions) }
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
            await advanceTo(AriaInterviewStep(OnboardingGraph.next(after: .confirmConditions)))
        }
    }

    func selectCoachingStyle(_ style: OnboardingCoachingStyle) {
        guard step == .coaching else { return }
        profile.coachingStyle = style
        appendUser(style.label)
        FDS.haptic(.medium)
        Task { await advanceTo(AriaInterviewStep(OnboardingGraph.next(after: .selectCoachingStyle))) }
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
            try await connectAppleHealthForFirstTime()
            healthKitState = .authorized
            await refreshHealthDataQuietly()
            let snap = briefingSnapshot()
            await ariaSay(
                AriaFirstHealthBriefing.onboardingConnectedLine(snapshot: snap),
                mood: .energized
            )
        } catch {
            healthKitState = .denied
            await ariaSay(
                "Couldn't connect Apple Health just now. You can enable it later — continuing.",
                mood: .calm
            )
        }
    }

    func requestCalendar() async {
        calendarState = .requesting
        ariaOrbState = .processing
        do {
            try await CalendarManager.shared.requestAccess()
            calendarState = .authorized
            await CalendarManager.shared.fetchUpcoming()
            calendarBusyToday = CalendarManager.shared.busyWindowsToday
            // ARIA sees busy windows, not titles
            let tags = CalendarManager.shared.calendarTags
            AriaContextStore.shared.updateProfile(lifestyleTags: tags)
            await ariaSay(
                "Calendar connected — I see \(calendarBusyToday) busy windows today. I'll fit training around them, not on top of them. Titles stay on your phone.",
                mood: .energized
            )
        } catch {
            calendarState = .denied
            await ariaSay(
                "Calendar not connected — no problem. You can add it later in Settings → Privacy → Calendars and I'll use it then.",
                mood: .calm
            )
        }
        ariaOrbState = .idle
    }

    /// System Health sheet first, then (on the sim) write the Test-Ready pack
    /// into HealthKit so the read-back is a real first integration.
    private func connectAppleHealthForFirstTime() async throws {
        #if targetEnvironment(simulator)
        if AriaService.shouldUseTestReadyDummy {
            try await HealthKitManager.shared.requestTestReadyPackAuthorization()
            try await HealthKitManager.shared.replaceTestReadyPack(FakeHealthPack.generate(seed: AppStore.testReadySessionSeed))
            return
        }
        #endif
        try await HealthKitManager.shared.requestAuthorization()
    }

    private func briefingSnapshot() -> AriaFirstHealthBriefing.Snapshot {
        AriaFirstHealthBriefing.Snapshot(
            sleepHours: healthSnapshot?.sleepHours,
            sleepScore: nil,
            hrvMs: healthSnapshot?.hrv.map { Int($0) },
            restingHR: healthSnapshot?.restingHeartRate,
            readiness: nil,
            steps: healthSnapshot?.steps,
            lastWorkoutName: nil,
            fromHealthKit: healthKitState == .authorized
        )
    }

    private func refreshHealthDataQuietly() async {
        async let p = HealthKitManager.shared.fetchUserProfile()
        async let s = HealthKitManager.shared.fetchRecentSnapshot()
        let (prof, snap) = await (p, s)
        healthProfile = prof
        healthSnapshot = snap

        var prefill: [String] = []
        if profile.birthday == nil, let dob = prof?.dateOfBirth {
            profile.birthday = dob
            profile.healthSourcedFields.insert(.birthday)
            prefill.append("born \(profile.ageYears)")
        }
        if profile.biologicalSex == nil, let raw = prof?.biologicalSex {
            switch raw {
            case "Female": profile.biologicalSex = .female
            case "Male": profile.biologicalSex = .male
            default: break
            }
            if profile.biologicalSex != nil {
                profile.healthSourcedFields.insert(.sex)
                prefill.append(raw)
            }
        }
        if profile.heightCm == nil, let h = prof?.heightCm {
            profile.heightCm = h
            profile.healthSourcedFields.insert(.height)
            prefill.append("height \(Int(h)) cm")
        }
        if profile.weightKg == nil, let w = prof?.weightKg {
            profile.weightKg = w
            profile.healthSourcedFields.insert(.weight)
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
        AriaContextStore.shared.addInsight("Apple Health prefill: \(healthPrefillNote!)")
        syncPartialContext()

        if !messages.contains(where: { $0.role == .system && ($0.text.contains("HealthKit") || $0.text.contains("Apple Health")) }) {
            messages.append(AriaOnboardingMessage(
                role: .system,
                text: "Apple Health is in — I already have a night and a morning to coach from."
            ))
        }
    }

    // MARK: - Ready / complete

    private func deliverReadinessSummary() async {
        var script = AriaOnboardingGuide.firstSessionScript(
            profile: profile,
            healthConnected: healthKitState == .authorized
        )
        if healthPrefillNote != nil {
            script += " Live signals already in — day one isn't starting from zero."
        }
        if profile.guidanceOnlyMode {
            script += " Guidance mode only: structure and pacing, not medical care."
        }
        script += " Ready when you are."
        await ariaSay(script, mood: AriaOnboardingGuide.mood(for: profile.coachingStyle))
        ariaOrbState = .idle
    }

    func complete(in store: AppStore) {
        guard OnboardingGraph.allowsFinish(canFinish: canFinish, hasAgreedToTerms: hasAgreedToTerms) else { return }
        guard !isCompleting else { return }
        isCompleting = true
        ariaOrbState = .processing

        store.userProfile = profile.toCoreProfile()
        if let sex = profile.biologicalSex {
            MenstrualHealthStore.shared.enableForBiologicalSexIfNeeded(sex)
        }
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

        FDS.haptic(.heavy)
        FDS.notificationHaptic(.success)

        Task { @MainActor in
            if healthConnected {
                await store.refreshDailyData()
            }
            store.learnFromFirstHealthConnectIfNeeded()
            if profile.trainingTheme != .classic || store.readiness.overall > 0 {
                let plan = AriaPlanEngine.evaluate(
                    input: "Build my first \(profile.trainingTheme.label) training plan",
                    context: store.makeTrainerContext()
                )
                store.todayWorkout = plan.workoutPlan
            }
            AriaContextStore.shared.addInsight("Onboarding interview complete.")
            store.activeTab = .chat
            store.isOnboarded = true
        }
    }

    func resetAfterAgeBlock() {
        withAnimation(FDS.Spring.hero) { showAgeBlocked = false }
    }

    func devSkipToEnd(in store: AppStore) {
        profile.name = "Dev User"
        profile.lastName = "Forge"
        profile.birthday = Calendar.current.date(byAdding: .year, value: -28, to: Date())
        profile.gender = .male
        profile.biologicalSex = .male
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
        hasAgreedToTerms = true
        step = .ready
        complete(in: store)
    }

    // MARK: - Helpers

    private func appendUser(_ text: String) {
        appendTranscript(AriaOnboardingMessage(role: .user, text: text))
    }

    /// One short beat so the orb can flip to thinking — long enough to feel
    /// human, short enough that a 12-step interview does not stall.
    private func ariaSay(_ text: String, mood: ARIAMood) async {
        isTyping = true
        ariaOrbState = .processing
        ariaMood = mood
        try? await Task.sleep(nanoseconds: 140_000_000)
        appendTranscript(AriaOnboardingMessage(role: .aria, text: text))
        isTyping = false
        ariaOrbState = .idle
        FDS.haptic(.soft)
    }

    /// Keep the last dozen turns. Older chips are already captured on the
    /// profile — holding the full transcript just costs layout on every step.
    private func appendTranscript(_ message: AriaOnboardingMessage) {
        messages.append(message)
        let cap = 12
        if messages.count > cap {
            messages.removeFirst(messages.count - cap)
        }
    }

    private func personalizedGoalsPrompt() -> String {
        if !profile.firstName.isEmpty {
            return "\(profile.firstName), what are we building toward? Pick every outcome that matters."
        }
        return "What are we building toward? Pick every outcome that matters."
    }

    private func experiencePrompt() -> String {
        if let vo2 = healthProfile?.vo2Max, vo2 >= 45 {
            return "Your Apple Health VO₂max looks solid. How would you rate your training experience?"
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
