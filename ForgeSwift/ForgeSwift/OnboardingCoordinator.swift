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

    /// Bumped when the human interrupts (back, mic, a tap). In-flight think
    /// beats drop so ARIA never talks over an answer she already heard.
    private var utteranceGeneration = 0

    func goBack() {
        guard canGoBack, let prev = OnboardingGraph.previous(of: step.graph) else { return }
        interruptInterviewVoice()
        FDS.haptic(.light)
        step = AriaInterviewStep(prev)
        freeText = ""
        ariaOrbState = .listening
        Task {
            let line = AriaInterviewVoice.prompt(
                step,
                profile: profile,
                healthAuthorized: healthKitState == .authorized,
                healthPrefill: !profile.healthSourcedFields.isEmpty,
                vo2Max: healthProfile?.vo2Max
            )
            guard !line.isEmpty else { return }
            await ariaSay(line, mood: .focused)
        }
    }

    /// Cut speech, drop a pending think beat, and treat the next line as a
    /// fresh turn. Interview composers call this before applying an answer.
    func interruptInterviewVoice() {
        utteranceGeneration += 1
        isTyping = false
        AriaPresence.shared.stopSpeaking()
        AriaPresence.shared.setThinking(false)
        ariaOrbState = .listening
    }

    func replayLastAriaLine() {
        guard let line = messages.last(where: { $0.role == .aria })?.text else { return }
        AriaPresence.shared.speak(line, interrupt: true)
        ariaOrbState = .listening
        FDS.haptic(.soft)
    }

    func stopInterviewVoice() {
        interruptInterviewVoice()
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
        await ariaSay(
            AriaInterviewVoice.introLine(
                firstName: profile.firstName,
                questLabel: profile.fitnessGoals.first?.label
            ),
            mood: profile.firstName.isEmpty ? .focused : .energized
        )
        await advanceTo(.name)
    }

    private func advanceTo(_ next: AriaInterviewStep) async {
        step = next
        freeText = ""
        let line = AriaInterviewVoice.prompt(
            next,
            profile: profile,
            healthAuthorized: healthKitState == .authorized,
            healthPrefill: !profile.healthSourcedFields.isEmpty,
            vo2Max: healthProfile?.vo2Max
        )
        switch next {
        case .intro:
            break
        case .details:
            showingEducationalCyclePrompt = false
            await ariaSay(line, mood: .focused, interrupt: false)
            ariaOrbState = .listening
        case .ready:
            await deliverReadinessSummary()
        case .health, .workouts:
            await ariaSay(line, mood: .energized, interrupt: false)
            ariaOrbState = .listening
        case .sleep, .coaching:
            await ariaSay(line, mood: .calm, interrupt: false)
            ariaOrbState = .listening
        case .name, .goals, .experience, .freeTime, .conditions:
            await ariaSay(line, mood: .focused, interrupt: false)
            ariaOrbState = .listening
        }
    }

    // MARK: - Answers

    func submitName() {
        guard step == .name else { return }
        guard profile.isPreferredNameValid else { return }
        interruptInterviewVoice()
        let spoken = profile.profileDisplayName
        appendUser(spoken)
        FDS.haptic(.medium)
        AriaContextStore.shared.updateProfile(
            lifestyleTags: ["onboarding:in_progress", "name:\(profile.trimmedName)"]
        )
        AriaContextStore.shared.addInsight("Met \(profile.trimmedName) during onboarding interview.")
        Task {
            await ariaSay(AriaInterviewVoice.acknowledgeName(profile.firstName), mood: .energized)
            await advanceTo(.health)
        }
    }

    func confirmDetails() {
        guard step == .details else { return }
        if isUnderage {
            FDS.notificationHaptic(.warning)
            withAnimation(FDS.Spring.hero) { showAgeBlocked = true }
            return
        }
        guard profile.hasConfirmedDetails else { return }
        interruptInterviewVoice()
        appendUser(profile.detailsSummaryLine)
        FDS.haptic(.light)
        syncPartialContext()
        Task {
            await ariaSay(AriaInterviewVoice.acknowledgeDetails(), mood: .focused)
            await advanceTo(.goals)
        }
    }

    func continueFromHealth() {
        guard step == .health else { return }
        interruptInterviewVoice()
        appendUser(healthKitState == .authorized && calendarState == .authorized ? "Connected both" : healthKitState == .authorized ? "Health connected" : calendarState == .authorized ? "Calendar connected" : "Continue")
        FDS.haptic(.light)
        Task {
            await ariaSay(
                AriaInterviewVoice.acknowledgeHealthContinue(health: healthKitState, calendar: calendarState),
                mood: .focused
            )
            await advanceTo(.details)
        }
    }

    func skipHealthAndContinue() {
        guard step == .health else { return }
        interruptInterviewVoice()
        if healthKitState != .authorized {
            healthKitState = healthKitState == .unavailable ? .unavailable : .denied
        }
        appendUser("I'll add it later")
        FDS.haptic(.light)
        Task {
            await ariaSay(AriaInterviewVoice.acknowledgeHealthSkip(), mood: .calm)
            await advanceTo(.details)
        }
    }

    func connectHealthKit() {
        guard step == .health else { return }
        interruptInterviewVoice()
        appendUser("Connect Apple Health")
        FDS.haptic(.medium)
        Task { await requestHealthKit() }
    }

    func skipHealthKit() {
        guard step == .health else { return }
        interruptInterviewVoice()
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
        interruptInterviewVoice()
        let labels = profile.fitnessGoals.map(\.label)
        appendUser(labels.joined(separator: ", "))
        FDS.haptic(.light)
        syncPartialContext()
        Task {
            await ariaSay(AriaInterviewVoice.acknowledgeGoals(labels), mood: .energized)
            await advanceTo(.experience)
        }
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
        interruptInterviewVoice()
        profile.experienceLevel = level
        appendUser(level.label)
        FDS.haptic(.light)
        syncPartialContext()
        Task {
            await ariaSay(AriaInterviewVoice.acknowledgeExperience(level), mood: .focused)
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
        interruptInterviewVoice()
        let labels = profile.preferredWorkouts.map(\.label)
        appendUser(labels.joined(separator: ", "))
        FDS.haptic(.light)
        syncPartialContext()
        Task {
            await ariaSay(AriaInterviewVoice.acknowledgeWorkouts(labels), mood: .energized)
            await advanceTo(.sleep)
        }
    }

    func selectSleepBand(_ band: SleepRhythmBand) {
        guard step == .sleep else { return }
        interruptInterviewVoice()
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
        Task {
            await ariaSay(AriaInterviewVoice.acknowledgeSleep(band), mood: .calm)
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
        interruptInterviewVoice()
        let labels = profile.freeTimeInterests.map(\.label)
        if labels.isEmpty {
            appendUser("Skip")
        } else {
            appendUser(labels.joined(separator: ", "))
        }
        FDS.haptic(.light)
        // Collapse: trainingTheme + lifeContext are now answered here — default to classic / preferNot
        // so we can skip two screens and keep the interview feeling like one human ask.
        // trainingTheme is already `.classic`; lifeContext is optional and must not
        // be force-read via `.rawValue` (that is what blocked the #168 compile).
        if profile.lifeContext == nil { profile.lifeContext = .preferNot }
        syncPartialContext()
        Task {
            await ariaSay(AriaInterviewVoice.acknowledgeInterests(labels), mood: .focused)
            await advanceTo(AriaInterviewStep(OnboardingGraph.next(after: .confirmInterests)))
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
        interruptInterviewVoice()
        if profile.reportedConditions.isEmpty {
            profile.reportedConditions = [.preferNot]
            profile.guidanceOnlyMode = false
        }

        let labels = profile.reportedConditions.map(\.label)
        appendUser(labels.joined(separator: ", "))
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
                await ariaSay("Noted. Privacy respected. That stays between us.", mood: .calm)
            }
            await advanceTo(AriaInterviewStep(OnboardingGraph.next(after: .confirmConditions)))
        }
    }

    func selectCoachingStyle(_ style: OnboardingCoachingStyle) {
        guard step == .coaching else { return }
        interruptInterviewVoice()
        profile.coachingStyle = style
        appendUser(style.label)
        FDS.haptic(.medium)
        Task {
            await ariaSay(AriaInterviewVoice.acknowledgeCoaching(style), mood: AriaOnboardingGuide.mood(for: style))
            await advanceTo(AriaInterviewStep(OnboardingGraph.next(after: .selectCoachingStyle)))
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
        ariaOrbState = .listening
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
        script += " I'll be here tomorrow morning. Ready when you are."
        await ariaSay(script, mood: AriaOnboardingGuide.mood(for: profile.coachingStyle))
        ariaOrbState = .listening
    }

    func complete(in store: AppStore) {
        guard OnboardingGraph.allowsFinish(canFinish: canFinish, hasAgreedToTerms: hasAgreedToTerms) else { return }
        guard !isCompleting else { return }
        isCompleting = true
        interruptInterviewVoice()
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

    // MARK: - Suggested replies + spoken turns

    func applySuggestedReply(_ reply: AriaInterviewVoice.Reply) {
        switch reply.kind {
        case .startTalking:
            break
        case .confirmName:
            submitName()
        case .connectHealth:
            connectHealthKit()
        case .skipHealthAndContinue:
            skipHealthAndContinue()
        case .continueHealth:
            continueFromHealth()
        case .experience(let level):
            selectExperience(level)
        case .sleep(let band):
            selectSleepBand(band)
        case .coaching(let style):
            selectCoachingStyle(style)
        case .confirmGoals:
            confirmGoals()
        case .confirmWorkouts:
            confirmWorkouts()
        case .skipInterests, .confirmInterests:
            confirmInterests()
        case .skipConditions:
            profile.reportedConditions = [.preferNot]
            profile.guidanceOnlyMode = false
            confirmConditions()
        case .noneConditions:
            profile.reportedConditions = [.none]
            profile.guidanceOnlyMode = false
            confirmConditions()
        }
    }

    func handleSpokenReply(_ text: String) {
        guard let match = AriaInterviewVoice.matchSpoken(text, step: step, profile: profile) else { return }
        switch match {
        case .missed:
            Task { await ariaSay(AriaInterviewVoice.missedLine(), mood: .calm) }
        case .fillName(let spoken):
            applySpokenName(spoken)
        case .confirmName:
            submitName()
        case .connectHealth:
            connectHealthKit()
        case .skipHealthAndContinue:
            skipHealthAndContinue()
        case .continueHealth:
            continueFromHealth()
        case .experience(let level):
            selectExperience(level)
        case .sleep(let band):
            selectSleepBand(band)
        case .coaching(let style):
            selectCoachingStyle(style)
        case .toggleGoals(let goals):
            for goal in goals where !profile.fitnessGoals.contains(goal) {
                toggleGoal(goal)
            }
        case .confirmGoals:
            confirmGoals()
        case .toggleWorkouts(let workouts):
            for workout in workouts where !profile.preferredWorkouts.contains(workout) {
                toggleWorkout(workout)
            }
        case .confirmWorkouts:
            confirmWorkouts()
        case .toggleInterests(let interests):
            for interest in interests where !profile.freeTimeInterests.contains(interest) {
                toggleInterest(interest)
            }
        case .skipInterests, .confirmInterests:
            confirmInterests()
        case .skipConditions:
            profile.reportedConditions = [.preferNot]
            profile.guidanceOnlyMode = false
            confirmConditions()
        case .noneConditions:
            profile.reportedConditions = [.none]
            profile.guidanceOnlyMode = false
            confirmConditions()
        case .fillConditionsNote(let note):
            freeText = note
            if !profile.reportedConditions.contains(.other) {
                toggleCondition(.other)
            }
        }
    }

    func applySpokenName(_ spoken: String) {
        let parts = spoken.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            profile.name = parts[0]
            profile.lastName = parts.dropFirst().joined(separator: " ")
        } else {
            profile.name = spoken
        }
    }

    // MARK: - Helpers

    private func appendUser(_ text: String) {
        appendTranscript(AriaOnboardingMessage(role: .user, text: text))
    }

    /// One short beat so the orb can flip to thinking — long enough to feel
    /// like a person, short enough that a 12-step interview does not stall.
    /// Pass `interrupt: false` to queue behind a line already in the air
    /// (acknowledgment → next question).
    private func ariaSay(_ text: String, mood: ARIAMood, interrupt: Bool = true) async {
        let gen = utteranceGeneration
        let alreadySpeaking = AriaPresence.shared.isSpeaking && !interrupt
        isTyping = true
        ariaOrbState = .processing
        ariaMood = mood
        if !alreadySpeaking {
            AriaPresence.shared.setThinking(true)
            try? await Task.sleep(nanoseconds: AriaInterviewVoice.thinkBeatNanoseconds)
        }
        guard gen == utteranceGeneration else { return }
        appendTranscript(AriaOnboardingMessage(role: .aria, text: text))
        isTyping = false
        AriaPresence.shared.setThinking(false)
        AriaPresence.shared.speak(text, interrupt: interrupt)
        ariaOrbState = .listening
        FDS.haptic(.soft)
    }

    /// Keep the last dozen turns. Older chips are already captured on the
    /// profile — holding the full transcript just costs layout on every step.
    private func appendTranscript(_ message: AriaOnboardingMessage) {
        messages.append(message)
        let cap = 16
        if messages.count > cap {
            messages.removeFirst(messages.count - cap)
        }
    }

    private func syncPartialContext() {
        AriaContextStore.shared.updateProfile(
            goals: profile.fitnessGoals.map(\.label),
            constraints: profile.constraintsForContext(),
            lifestyleTags: profile.lifestyleTagsForContext() + ["onboarding:in_progress"]
        )
    }
}
