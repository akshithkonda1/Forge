import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Tab Enum

enum TabItem: String, CaseIterable, Identifiable {
    case home, chat, workout, lifestyle, sleep, profile
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .home:     return "house.fill"
        case .chat:     return "message.fill"
        case .workout:  return "dumbbell.fill"
        case .lifestyle: return "leaf.fill"
        case .sleep:    return "moon.fill"
        case .profile:  return "person.fill"
        }
    }
}

// MARK: - AI Response Protocol

/// Protocol for AI response generators
protocol TrainerResponseGenerator {
    func generateResponse(for input: String, context: TrainerContext) async throws -> TrainerResponse
}

// MARK: - Trainer Context

/// Context data passed to AI for response generation
struct TrainerContext {
    let userProfile: UserProfile
    let readiness: ReadinessData
    let dailyMetrics: DailyMetrics
    let sleepData: [SleepData]
    let workoutHistory: [WorkoutHistory]
    let currentTime: Date
    let conversationHistory: [ChatMessage]
    
    var hour: Int {
        Calendar.current.component(.hour, from: currentTime)
    }
    
    var isEarlyMorning: Bool { hour < 7 }
    var isLateNight: Bool { hour >= 22 }
    var averageWeeklySleepScore: Double {
        let scores = sleepData.prefix(7).map { Double($0.score) }
        return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }
}

// MARK: - Trainer Response

struct TrainerResponse {
    let content: String
    let richCard: RichCardData?
    let suggestedActions: [String]?
    let confidence: Double // 0.0 to 1.0
    
    init(content: String, richCard: RichCardData? = nil, suggestedActions: [String]? = nil, confidence: Double = 1.0) {
        self.content = content
        self.richCard = richCard
        self.suggestedActions = suggestedActions
        self.confidence = confidence
    }
}

// MARK: - Foundation Models AI Response Generator

#if canImport(FoundationModels)
@available(iOS 26.0, *)
final class FoundationModelsResponseGenerator: TrainerResponseGenerator {
    private let session: LanguageModelSession
    private let model = SystemLanguageModel.default
    
    init() {
        let instructions = """
        You are an AI personal trainer named Forge. You provide personalized fitness coaching with a direct, authentic, and knowledgeable tone.
        
        Your communication style:
        - Be conversational and real, not overly formal
        - Reference specific biometric data when relevant (HRV, sleep, readiness scores)
        - Adapt training recommendations based on recovery metrics
        - Balance empathy with accountability
        - Provide actionable, specific guidance
        
        Your expertise includes:
        - Strength training programming
        - Recovery optimization
        - Sleep quality analysis
        - Workout adaptation based on readiness
        - Progressive overload principles
        
        When the user's readiness is low, prioritize recovery. When it's high, push for performance.
        Keep responses concise but informative. Use natural language, not robotic.
        """
        
        self.session = LanguageModelSession(instructions: instructions)
    }
    
    var isAvailable: Bool {
        switch model.availability {
        case .available:
            return true
        default:
            return false
        }
    }
    
    func generateResponse(for input: String, context: TrainerContext) async throws -> TrainerResponse {
        // Build contextual prompt
        let prompt = buildPrompt(input: input, context: context)
        
        // Generate response from Foundation Models
        let response = try await session.respond(to: prompt)
        
        // Parse response and extract any rich card data
        return parseResponse(response.content, context: context, input: input)
    }
    
    private func buildPrompt(input: String, context: TrainerContext) -> String {
        let prompt = """
        User: \(context.userProfile.name)
        Experience Level: \(context.userProfile.experienceLevel.label)
        Goals: \(context.userProfile.fitnessGoals.map { $0.label }.joined(separator: ", "))
        
        Current Metrics:
        - Readiness: \(context.readiness.overall)/100
        - HRV: \(context.dailyMetrics.hrv)ms
        - Resting HR: \(context.dailyMetrics.restingHR) bpm
        - Sleep Quality: \(context.readiness.sleepQuality)/100
        - Deep Sleep: \(context.dailyMetrics.deepSleep) min
        - Recovery Score: \(context.readiness.recoveryScore)/100
        
        Time: \(context.isEarlyMorning ? "Early morning (before 7am)" : context.isLateNight ? "Late night (after 10pm)" : "Daytime")
        
        User message: "\(input)"
        
        Provide a personalized response based on their current state and question.
        """
        
        return prompt
    }
    
    private func parseResponse(_ content: String, context: TrainerContext, input: String) -> TrainerResponse {
        // Check if we should generate a workout plan or data chart based on content
        var richCard: RichCardData? = nil
        let lowerInput = input.lowercased()
        
        // Generate workout plan if appropriate
        if lowerInput.contains("workout") || lowerInput.contains("train") {
            richCard = generateWorkoutPlan(for: context)
        }
        // Generate sleep chart if discussing sleep
        else if lowerInput.contains("sleep") {
            richCard = generateSleepChart(for: context)
        }
        
        return TrainerResponse(
            content: content,
            richCard: richCard,
            confidence: 0.95
        )
    }
    
    private func generateWorkoutPlan(for context: TrainerContext) -> RichCardData {
        // Generate workout based on readiness
        let readiness = context.readiness.overall
        
        if readiness >= 80 {
            return RichCardData(
                type: .workoutPlan,
                workoutName: "Upper Body Power",
                workoutDuration: 55,
                workoutExercises: [
                    ("Barbell Bench Press", 4, "6-8"),
                    ("Weighted Pull-Ups", 4, "6-8"),
                    ("Overhead Press", 3, "8-10"),
                    ("Barbell Rows", 3, "8-10"),
                    ("Incline DB Press", 3, "10-12"),
                    ("Face Pulls", 3, "15-20"),
                ]
            )
        } else if readiness >= 60 {
            return RichCardData(
                type: .workoutPlan,
                workoutName: "Upper Body Volume",
                workoutDuration: 50,
                workoutExercises: [
                    ("Barbell Bench Press", 3, "8-10"),
                    ("Lat Pulldown", 3, "10-12"),
                    ("Dumbbell Press", 3, "10-12"),
                    ("Cable Row", 3, "10-12"),
                    ("Lateral Raises", 3, "12-15"),
                    ("Tricep Pushdowns", 3, "12-15"),
                ]
            )
        } else {
            return RichCardData(
                type: .workoutPlan,
                workoutName: "Active Recovery Upper",
                workoutDuration: 35,
                workoutExercises: [
                    ("Push-Ups (controlled)", 3, "12"),
                    ("Band Pull-Aparts", 3, "20"),
                    ("Dumbbell Press (light)", 3, "15"),
                    ("TRX Rows", 3, "15"),
                    ("Shoulder Circles", 2, "20"),
                ]
            )
        }
    }
    
    private func generateSleepChart(for context: TrainerContext) -> RichCardData {
        let scores = context.sleepData.prefix(7).map { Double($0.score) }.reversed().map { $0 }
        let avg = context.averageWeeklySleepScore
        
        return RichCardData(
            type: .dataChart,
            chartTitle: "Sleep Quality (7 days)",
            chartValues: scores.isEmpty ? [68, 74, 91, 62, 93, 80, 88] : scores,
            chartInsight: "Average sleep score this week: \(Int(avg))/100. \(avg >= 80 ? "Solid week." : avg >= 70 ? "Could be better." : "This needs work.")",
            chartColor: .steel
        )
    }
}
#endif

// MARK: - Fallback Rule-Based Response Generator

/// Rule-based fallback when Foundation Models aren't available
final class RuleBasedResponseGenerator: TrainerResponseGenerator {
    
    func generateResponse(for input: String, context: TrainerContext) async throws -> TrainerResponse {
        let lower = input.lowercased()
        
        // Context-aware greetings
        if isGreeting(lower) {
            return generateGreeting(context: context)
        }
        
        // Training request
        if isTrainingRequest(lower) {
            return generateTrainingResponse(context: context)
        }
        
        // Low energy
        if isLowEnergyMention(lower) {
            return generateLowEnergyResponse(context: context)
        }
        
        // Sleep analysis
        if isSleepQuery(lower) {
            return generateSleepAnalysis(context: context)
        }
        
        // Pain/injury
        if isPainMention(lower) {
            return generatePainResponse(lower)
        }
        
        // Progress check
        if isProgressQuery(lower) {
            return generateProgressResponse(context: context)
        }
        
        // Gratitude
        if isGratitude(lower) {
            return generateGratitudeResponse()
        }
        
        // Motivation
        if isMotivationRequest(lower) {
            return generateMotivationResponse()
        }
        
        // Fallback
        return generateFallbackResponse()
    }
    
    // MARK: - Query Detection
    
    private func isGreeting(_ text: String) -> Bool {
        text.contains("hello") || text.contains("hey") || text.contains("hi ") || 
        text.contains("what's up") || text.contains("sup")
    }
    
    private func isTrainingRequest(_ text: String) -> Bool {
        text.contains("what should i") || text.contains("train today") || 
        text.contains("workout today") || text.contains("what should we")
    }
    
    private func isLowEnergyMention(_ text: String) -> Bool {
        text.contains("not feeling") || text.contains("tired") || 
        text.contains("exhausted") || text.contains("low energy") || text.contains("drained")
    }
    
    private func isSleepQuery(_ text: String) -> Bool {
        (text.contains("sleep") || text.contains("slept") || text.contains("rest")) && 
        !text.contains("restaurant")
    }
    
    private func isPainMention(_ text: String) -> Bool {
        text.contains("injury") || text.contains("pain") || text.contains("hurt") || 
        (text.contains("sore") && !text.contains("not sore"))
    }
    
    private func isProgressQuery(_ text: String) -> Bool {
        text.contains("progress") || text.contains("how am i doing") || 
        text.contains("gains") || text.contains("getting stronger")
    }
    
    private func isGratitude(_ text: String) -> Bool {
        text.contains("thank") || text.contains("appreciate") || text.contains("grateful")
    }
    
    private func isMotivationRequest(_ text: String) -> Bool {
        text.contains("motivate") || text.contains("pump me up") || 
        text.contains("need motivation") || text.contains("inspire")
    }
    
    // MARK: - Response Generation
    
    private func generateGreeting(context: TrainerContext) -> TrainerResponse {
        var greetings: [String] = []
        
        if context.isEarlyMorning {
            greetings = [
                "Morning, \(context.userProfile.name). You're up early. Training or just couldn't sleep?",
                "Damn, you're up. Feeling good or just restless?",
                "Early bird today, huh? What's the plan?",
            ]
        } else if context.isLateNight {
            greetings = [
                "Late night check-in? What's on your mind?",
                "Can't sleep or just wired from today? Talk to me.",
                "Yo. Everything good? Kinda late for you.",
            ]
        } else if context.readiness.overall < 65 {
            greetings = [
                "Hey. Noticed you're at \(context.readiness.overall)% today — how you actually feeling?",
                "What's up. Your numbers are a little off today, just checking in.",
                "Hey \(context.userProfile.name). Body's telling me you might need an easy day — you feel that too?",
            ]
        } else {
            greetings = [
                "Yo, what's good?",
                "Hey \(context.userProfile.name), what do you need?",
                "What's up, talk to me.",
                "Hey. How's everything feeling today?",
                "Yo. What are we working on?",
            ]
        }
        
        return TrainerResponse(content: greetings.randomElement()!)
    }
    
    private func generateTrainingResponse(context: TrainerContext) -> TrainerResponse {
        let readiness = context.readiness.overall
        let response: String
        let workoutPlan: RichCardData
        
        if readiness >= 80 {
            response = "Alright so — you're at \(readiness)/100, HRV came in at \(context.dailyMetrics.hrv), resting HR is \(context.dailyMetrics.restingHR). Body's ready for some damage. Let's go heavy today. Upper body power work, big compounds, low reps. Gonna feel amazing."
            workoutPlan = RichCardData(type: .workoutPlan, workoutName: "Upper Body Power", workoutDuration: 55, workoutExercises: [
                ("Barbell Bench Press", 4, "6-8"), ("Weighted Pull-Ups", 4, "6-8"),
                ("Overhead Press", 3, "8-10"), ("Barbell Rows", 3, "8-10"),
                ("Incline DB Press", 3, "10-12"), ("Face Pulls", 3, "15-20"),
            ])
        } else if readiness >= 60 {
            response = "You're sitting at \(readiness)/100. HRV's \(context.dailyMetrics.hrv), heart rate \(context.dailyMetrics.restingHR) — totally fine, not spectacular. We can work with this. Upper body but I'm pulling back the volume a bit. Quality reps, don't chase PRs today."
            workoutPlan = RichCardData(type: .workoutPlan, workoutName: "Upper Body Volume", workoutDuration: 50, workoutExercises: [
                ("Barbell Bench Press", 3, "8-10"), ("Lat Pulldown", 3, "10-12"),
                ("Dumbbell Press", 3, "10-12"), ("Cable Row", 3, "10-12"),
                ("Lateral Raises", 3, "12-15"), ("Tricep Pushdowns", 3, "12-15"),
            ])
        } else {
            response = "Yeah so... readiness is \(readiness)/100. HRV at \(context.dailyMetrics.hrv), resting HR is \(context.dailyMetrics.restingHR). That's lower than I want to see. You stressed? Not sleeping well? Either way, we're backing off today. Light upper body work, more like movement practice than training. Save the real work for when your body's actually ready."
            workoutPlan = RichCardData(type: .workoutPlan, workoutName: "Active Recovery Upper", workoutDuration: 35, workoutExercises: [
                ("Push-Ups (controlled)", 3, "12"), ("Band Pull-Aparts", 3, "20"),
                ("Dumbbell Press (light)", 3, "15"), ("TRX Rows", 3, "15"),
                ("Shoulder Circles", 2, "20"),
            ])
        }
        
        return TrainerResponse(content: response, richCard: workoutPlan)
    }
    
    private func generateLowEnergyResponse(context: TrainerContext) -> TrainerResponse {
        let empathy = [
            "Yeah, I hear you. Some days just hit different. Look — skipping entirely? Waste. Going hard anyway? Stupid. So we meet in the middle. 30 minutes, easy movement, get some blood flow going. You'll feel better after, trust me.",
            "Felt that way yesterday too, huh? Listen, your body's trying to tell you something. We're not doing anything heavy today. Recovery flow, stretch it out, move light. Think of it like... maintenance, not training. You'll bounce back faster.",
            "Okay real talk — there's tired, and then there's *tired*. Which one? Like, 'I stayed up late' tired or 'my body's wrecked' tired? Either way we're backing off, I just need to know how much.",
            "Gotcha. Days like this separate smart athletes from broken ones. We're going light. Mobility, blood flow, maybe some easy bodyweight stuff. No ego, no grinding. Just movement. Sound good?",
        ]
        
        let workoutPlan = RichCardData(type: .workoutPlan, workoutName: "Recovery Flow", workoutDuration: 30, workoutExercises: [
            ("Foam Rolling", 1, "5 min"), ("World's Greatest Stretch", 2, "8 each side"),
            ("Band Pull-Aparts", 3, "15"), ("Goblet Squats (light)", 2, "10"),
            ("Dead Hangs", 3, "30 sec"), ("Walk or Bike (easy)", 1, "10 min"),
        ])
        
        return TrainerResponse(content: empathy.randomElement()!, richCard: workoutPlan)
    }
    
    private func generateSleepAnalysis(context: TrainerContext) -> TrainerResponse {
        let lastSleep = context.sleepData.first
        let deepMin = lastSleep?.deepMinutes ?? context.dailyMetrics.deepSleep
        let totalHrs = lastSleep?.totalHours ?? Double(context.dailyMetrics.totalSleep) / 60
        let scores = context.sleepData.prefix(7).map { Double($0.score) }.reversed().map { $0 }
        let avg = context.averageWeeklySleepScore
        
        let analysis: String
        if deepMin >= 90 && totalHrs >= 7 {
            analysis = "Last night? \(String(format: "%.1f", totalHrs)) hours, \(deepMin) minutes deep. That's legit. Deep sleep is where you actually rebuild — muscles repair, hormones regulate, nervous system resets. You're doing it right. Keep this up and your training's gonna reflect it."
        } else if deepMin < 60 {
            analysis = "So... \(String(format: "%.1f", totalHrs)) hours total but only \(deepMin) minutes deep sleep. That's rough. Deep sleep is literally non-negotiable for recovery. Without it you're just breaking down without building back up. What's going on — stress? Late caffeine? Blue light before bed? We gotta fix this or your training's gonna stall."
        } else {
            analysis = "Slept \(String(format: "%.1f", totalHrs)) hours, got \(deepMin) minutes deep. Not bad, not great. You need more consistent sleep if you want real progress. I know life happens, but sleep is where the magic happens. Try to get to bed 30 minutes earlier tonight, see if that helps."
        }
        
        let chartData = RichCardData(
            type: .dataChart,
            chartTitle: "Sleep Quality (7 days)",
            chartValues: scores.isEmpty ? [68, 74, 91, 62, 93, 80, 88] : scores,
            chartInsight: "Average sleep score this week: \(Int(avg))/100. \(avg >= 80 ? "Solid week." : avg >= 70 ? "Could be better." : "This needs work.")",
            chartColor: .steel
        )
        
        return TrainerResponse(content: analysis, richCard: chartData)
    }
    
    private func generatePainResponse(_ input: String) -> TrainerResponse {
        let isSorenessMention = input.contains("sore") || input.contains("doms")
        if isSorenessMention {
            return TrainerResponse(content: "Soreness or actual pain? Big difference. DOMS from yesterday's workout? Normal, means you worked. Sharp pain when you move a certain way? Red flag. Which one we talking about?")
        } else {
            return TrainerResponse(content: "Whoa, stop. Where's the pain? Sharp or dull? Does it hurt when you move it or just when you load it? Need details before we do anything. If it's sharp, we're working around it completely. If it's just tight or achy, we can probably move through it carefully. Talk to me.")
        }
    }
    
    private func generateProgressResponse(context: TrainerContext) -> TrainerResponse {
        let encouragement = [
            "Bro you've been killing it. Last month alone — 18 workouts, 3 new PRs, recovery metrics up 22%. Bench went from 205 to 225, squat's at 315 now. That's not luck, that's showing up consistently. Keep this pace and you're gonna surprise yourself in 3 months.",
            "Let me check... yeah okay, you're doing better than you think. 18 sessions in 4 weeks, bench up 20 pounds, squat hit 315. Most people aren't consistent enough to see these numbers. You are. That's the whole game right there — just keep showing up and the results pile up.",
            "Pulled your stats. Last 30 days you've been ridiculously consistent. 18 workouts, zero missed sessions, 3 PRs. Bench jumped from 205 to 225. Squat's at 315. Your recovery's improving too — HRV trending up, sleep's been solid. This is what real progress looks like. Not flashy, just steady.",
        ]
        
        let chartData = RichCardData(
            type: .dataChart,
            chartTitle: "Bench Press Progress (4 weeks)",
            chartValues: [185, 195, 205, 215, 225],
            chartInsight: "Bench: +40 lbs in 4 weeks. Estimated 1RM: 245 lbs. Strength is climbing fast.",
            chartColor: .ember
        )
        
        return TrainerResponse(content: encouragement.randomElement()!, richCard: chartData)
    }
    
    private func generateGratitudeResponse() -> TrainerResponse {
        let gratitude = [
            "You're doing the work, I'm just here to keep you honest.",
            "Don't thank me yet, we're just getting started.",
            "Appreciate it. Now go hit that workout.",
            "All you, I'm just steering. Keep showing up.",
        ]
        return TrainerResponse(content: gratitude.randomElement()!)
    }
    
    private func generateMotivationResponse() -> TrainerResponse {
        let motivation = [
            "Motivation? Nah. Motivation is temporary. You need discipline. Motivation gets you to the gym once. Discipline gets you there 200 times a year. Stop waiting to feel like it. Just show up. That's the secret nobody wants to hear.",
            "You don't need me to pump you up. You need to remember why you started. Write that down. Then go do the work even when you don't feel like it. That's how you build something real.",
            "Real talk — the best workouts happen on days you don't want to train. Those are the ones that count. Anyone can show up when they're motivated. You? You're gonna show up when you're not. That's what separates you.",
        ]
        return TrainerResponse(content: motivation.randomElement()!)
    }
    
    private func generateFallbackResponse() -> TrainerResponse {
        let fallbacks = [
            "Not sure I follow. You asking about training? Recovery? Something specific bothering you? Just say it straight, I got you.",
            "Hmm, lost me a bit there. Rephrase that? Are we talking workouts, sleep, nutrition, or something else?",
            "I want to give you a real answer but I need more context. What specifically are you asking about?",
            "Hold up, clarify that for me. You mean today's workout or overall programming or...?",
            "Yeah I'm not quite tracking. Break it down for me — what do you actually need right now?",
        ]
        return TrainerResponse(content: fallbacks.randomElement()!)
    }
}

// MARK: - AppStore (Production-ready state management)

@MainActor
final class AppStore: ObservableObject {

    // MARK: - Published State
    
    // Onboarding
    @Published var isOnboarded: Bool = false {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: Self.onboardedDefaultsKey) }
    }
    @Published var onboardingStep: Int = 0

    // User Profile
    @Published var userProfile: UserProfile = mockProfile {
        didSet { persistUserProfile() }
    }

    // Readiness & Metrics
    @Published var readiness: ReadinessData = mockReadiness
    @Published var dailyMetrics: DailyMetrics = mockMetrics

    // Today's Workout
    @Published var todayWorkout: WorkoutPlan? = mockWorkout

    // Active Workout State
    @Published var isWorkoutActive: Bool = false
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSet: Int = 1

    // Chat
    @Published var chatMessages: [ChatMessage] = []
    @Published var isGeneratingResponse: Bool = false

    // Sleep
    @Published var sleepData: [SleepData] = []

    // History & Records
    @Published var workoutHistory: [WorkoutHistory] = []
    @Published var personalRecords: [PersonalRecord] = []

    // Navigation
    @Published var activeTab: TabItem = .home
    @Published var pendingProfileSubTab: String? = nil

    // ARIA bridge
    @Published var ariaVoiceMode: Bool = false
    @Published var ariaPendingChatPrompt: String? = nil
    @Published var lastSuggestedActions: [String] = []
    @Published var healthKitLive: Bool = false
    /// Last successful metrics refresh (Home status pill).
    @Published var lastMetricsRefresh: Date? = nil
    
    // Streak tracking
    @Published var currentStreak: Int = 7
    
    // AI Configuration
    @Published var aiModelAvailable: Bool = false
    
    // MARK: - Private Properties
    
    private var responseGenerator: TrainerResponseGenerator
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // Initialize AI response generator
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let foundationModelsGenerator = FoundationModelsResponseGenerator()
            self.aiModelAvailable = foundationModelsGenerator.isAvailable
            self.responseGenerator = foundationModelsGenerator.isAvailable ?
                foundationModelsGenerator : RuleBasedResponseGenerator()
        } else {
            self.responseGenerator = RuleBasedResponseGenerator()
            self.aiModelAvailable = false
        }
        #else
        self.responseGenerator = RuleBasedResponseGenerator()
        self.aiModelAvailable = false
        #endif
        
        AriaContextStore.shared.configure()

        // Restore persisted onboarding so a returning user skips setup entirely.
        restoreOnboardingState()

        // Load seed data, then hydrate from HealthKit when authorized
        Task { @MainActor in
            self.chatMessages = mockChatMessages
            self.sleepData = mockSleepData
            self.workoutHistory = mockWorkoutHistory
            self.personalRecords = mockPersonalRecords
            await self.refreshDailyData()
        }
    }

    // MARK: - Onboarding Persistence

    private static let onboardedDefaultsKey = "forge.onboarding.completed"
    private static let profileDefaultsKey = "forge.user.profile.v1"

    /// Rehydrates a completed onboarding (flag + profile) on cold launch so the
    /// user lands straight in the app instead of re-running setup every time.
    private func restoreOnboardingState() {
        guard UserDefaults.standard.bool(forKey: Self.onboardedDefaultsKey) else { return }
        if let data = UserDefaults.standard.data(forKey: Self.profileDefaultsKey),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: data) {
            userProfile = saved
        }
        isOnboarded = true
    }

    private func persistUserProfile() {
        guard let data = try? JSONEncoder().encode(userProfile) else { return }
        UserDefaults.standard.set(data, forKey: Self.profileDefaultsKey)
    }

    // MARK: - Onboarding → ARIA handoff

    /// Replaces mock chat with a personalized ARIA first message after onboarding.
    func seedAriaWelcomeFromOnboarding(message: String, suggestedActions: [String] = []) {
        let welcome = ChatMessage(
            id: "aria-onboarding-\(UUID().uuidString.prefix(8))",
            role: .trainer,
            content: message,
            timestamp: Date(),
            confidence: 0.92,
            suggestedActions: suggestedActions.isEmpty
                ? ["Show today's plan", "How does readiness work?", "Adjust my goals"]
                : suggestedActions
        )
        chatMessages = [welcome]
        lastSuggestedActions = welcome.suggestedActions ?? []
    }

    // MARK: - Workout Actions

    func startWorkout() {
        currentExerciseIndex = 0
        currentSet = 1
        isWorkoutActive = true
    }

    func nextSet() {
        currentSet += 1
    }

    func nextExercise() {
        currentExerciseIndex += 1
        currentSet = 1
    }

    func endWorkout(completed: Bool = true) {
        isWorkoutActive = false
        currentExerciseIndex = 0
        currentSet = 1
        
        // Update streak and history
        if completed { currentStreak += 1 }
        
        let planId = todayWorkout?.id ?? "today-workout"
        if let workout = todayWorkout, completed {
            let history = WorkoutHistory(
                id: UUID().uuidString,
                date: ISO8601DateFormatter().string(from: Date()),
                name: workout.name,
                type: workout.type,
                duration: workout.duration,
                volume: workout.exercises.reduce(0) { $0 + ($1.sets * ($1.weight ?? 0)) },
                intensity: workout.intensity
            )
            workoutHistory.insert(history, at: 0)
        }

        Task {
            await FeedbackService.shared.processPlanOutcome(
                userId: AriaContextStore.shared.context.userId,
                planId: planId,
                completed: completed
            )
        }
    }

    // MARK: - Chat Actions

    func addMessage(_ message: ChatMessage) {
        chatMessages.append(message)
    }
    
    /// Send a message through ARIA (remote when available, local fallback).
    func sendMessage(_ text: String) async {
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: text,
            timestamp: Date()
        )
        chatMessages.append(userMessage)
        isGeneratingResponse = true

        do {
            let aria = try await AriaService.shared.sendMessage(
                text,
                store: self,
                localGenerator: responseGenerator,
                voiceMode: ariaVoiceMode
            )

            lastSuggestedActions = aria.suggestedActions ?? []

            let trainerMessage = ChatMessage(
                id: UUID().uuidString,
                role: .trainer,
                content: aria.message,
                timestamp: Date(),
                richCard: aria.toRichCardData(),
                confidence: aria.confidence,
                suggestedActions: aria.suggestedActions,
                memoryReference: aria.memoryReference,
                confidenceReason: aria.confidenceReason
            )
            chatMessages.append(trainerMessage)
        } catch {
            let errorMessage = ChatMessage(
                id: UUID().uuidString,
                role: .trainer,
                content: "Sorry, I'm having trouble processing that right now. Can you try again?",
                timestamp: Date()
            )
            chatMessages.append(errorMessage)
            print("Error generating ARIA response: \(error)")
        }

        isGeneratingResponse = false
    }

    /// One-shot ARIA insight for non-chat surfaces (e.g. Lifestyle cards).
    /// Uses the same remote-first path as `sendMessage` (with on-device fallback)
    /// but does NOT append to the chat transcript. Returns nil only if both the
    /// remote call and local generation throw — callers should fall back to their
    /// existing local content in that case.
    func ariaInsight(prompt: String, voiceMode: Bool = false) async -> AriaResponse? {
        try? await AriaService.shared.sendMessage(
            prompt,
            store: self,
            localGenerator: responseGenerator,
            voiceMode: voiceMode
        )
    }

    /// Legacy method for backward compatibility - converts to async
    func trainerResponse(for text: String) -> (content: String, richCard: RichCardData?) {
        // This is synchronous fallback for compatibility
        // In production, you should use sendMessage() instead
        var result: (String, RichCardData?) = ("I'm thinking...", nil)
        
        Task { @MainActor in
            let context = TrainerContext(
                userProfile: userProfile,
                readiness: readiness,
                dailyMetrics: dailyMetrics,
                sleepData: sleepData,
                workoutHistory: workoutHistory,
                currentTime: Date(),
                conversationHistory: chatMessages
            )
            
            do {
                let response = try await responseGenerator.generateResponse(for: text, context: context)
                result = (response.content, response.richCard)
            } catch {
                result = ("Sorry, I couldn't process that. Try again?", nil)
            }
        }
        
        return result
    }
    
    // MARK: - Data Management
    
    func refreshDailyData() async {
        let hk = HealthKitManager.shared
        let authorized = await hk.checkAuthorizationStatus()
        healthKitLive = authorized

        if authorized, let snapshot = await hk.fetchRecentSnapshot() {
            updateMetrics(
                steps: snapshot.steps,
                activeCalories: snapshot.activeCalories,
                hrv: snapshot.hrv.map { Int($0) },
                restingHR: snapshot.restingHeartRate,
                deepSleep: nil,
                totalSleep: snapshot.sleepHours.map { Int($0 * 60) }
            )
            if let weight = userProfile.weight {
                userProfile.weight = weight
            }
        }

        let samples = BiometricsObserveService.shared.samplesFromStore(self)
        _ = await BiometricsObserveService.shared.observe(store: self, samples: samples)
        lastMetricsRefresh = Date()
        objectWillChange.send()
    }

    func openChat(with prompt: String, voice: Bool = false) {
        ariaPendingChatPrompt = prompt
        ariaVoiceMode = voice
        activeTab = .chat
    }
    
    /// Update user metrics (typically from HealthKit integration)
    func updateMetrics(
        steps: Int? = nil,
        activeCalories: Int? = nil,
        hrv: Int? = nil,
        restingHR: Int? = nil,
        deepSleep: Int? = nil,
        totalSleep: Int? = nil
    ) {
        if let steps = steps { dailyMetrics.steps = steps }
        if let activeCalories = activeCalories { dailyMetrics.activeCalories = activeCalories }
        if let hrv = hrv { dailyMetrics.hrv = hrv }
        if let restingHR = restingHR { dailyMetrics.restingHR = restingHR }
        if let deepSleep = deepSleep { dailyMetrics.deepSleep = deepSleep }
        if let totalSleep = totalSleep { dailyMetrics.totalSleep = totalSleep }
        
        // Recalculate readiness based on new metrics
        recalculateReadiness()
    }
    
    /// Recalculate readiness score based on current metrics
    private func recalculateReadiness() {
        // Simplified readiness calculation
        // In production, this would use more sophisticated algorithms
        
        let sleepScore = calculateSleepScore()
        let hrvScore = calculateHRVScore()
        let restingHRScore = calculateRestingHRScore()
        
        readiness.overall = (sleepScore + hrvScore + restingHRScore) / 3
        readiness.sleepQuality = sleepScore
        readiness.recoveryScore = (hrvScore + restingHRScore) / 2
    }
    
    private func calculateSleepScore() -> Int {
        let totalHours = Double(dailyMetrics.totalSleep) / 60
        let deepMinutes = dailyMetrics.deepSleep
        
        var score = 0
        
        // Total sleep score (0-50 points)
        if totalHours >= 7.5 {
            score += 50
        } else if totalHours >= 7 {
            score += 40
        } else if totalHours >= 6 {
            score += 25
        } else {
            score += 10
        }
        
        // Deep sleep score (0-50 points)
        if deepMinutes >= 90 {
            score += 50
        } else if deepMinutes >= 70 {
            score += 40
        } else if deepMinutes >= 50 {
            score += 25
        } else {
            score += 10
        }
        
        return min(score, 100)
    }
    
    private func calculateHRVScore() -> Int {
        // HRV scoring (typical range: 20-100ms)
        let hrv = dailyMetrics.hrv
        
        if hrv >= 60 {
            return 90
        } else if hrv >= 50 {
            return 80
        } else if hrv >= 40 {
            return 65
        } else if hrv >= 30 {
            return 50
        } else {
            return 30
        }
    }
    
    private func calculateRestingHRScore() -> Int {
        // Resting HR scoring (lower is better for athletes)
        let hr = dailyMetrics.restingHR
        
        if hr <= 55 {
            return 95
        } else if hr <= 60 {
            return 85
        } else if hr <= 65 {
            return 75
        } else if hr <= 70 {
            return 60
        } else {
            return 40
        }
    }
    
    // MARK: - Profile Management
    
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
        weightKg: Double? = nil
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
        objectWillChange.send()
    }
    
    // MARK: - Sleep Management
    
    func mergeSleepDataLocally(_ local: [SleepData]) {
        guard !local.isEmpty else { return }
        var merged = Dictionary(sleepData.map { ($0.date, $0) }, uniquingKeysWith: { _, new in new })
        for night in local {
            merged[night.date] = night
        }
        sleepData = merged.values.sorted { $0.date > $1.date }
        if let latest = sleepData.first {
            dailyMetrics.totalSleep = Int(latest.totalHours * 60)
            dailyMetrics.deepSleep = latest.deepMinutes
            recalculateReadiness()
        }
    }

    func addSleepData(_ sleep: SleepData) {
        sleepData.insert(sleep, at: 0)
        
        // Update daily metrics
        dailyMetrics.totalSleep = Int(sleep.totalHours * 60)
        dailyMetrics.deepSleep = sleep.deepMinutes
        
        // Recalculate readiness
        recalculateReadiness()
    }
    
    // MARK: - Personal Records
    
    func updatePersonalRecord(exercise: String, value: Double, unit: String) {
        if let index = personalRecords.firstIndex(where: { $0.exercise == exercise }) {
            // Update existing record if new value is better
            if value > personalRecords[index].value {
                personalRecords[index] = PersonalRecord(
                    exercise: exercise,
                    value: value,
                    unit: unit,
                    date: ISO8601DateFormatter().string(from: Date())
                )
            }
        } else {
            // Add new record
            let newRecord = PersonalRecord(
                exercise: exercise,
                value: value,
                unit: unit,
                date: ISO8601DateFormatter().string(from: Date())
            )
            personalRecords.append(newRecord)
        }
    }
}

// MARK: - AppStore Extensions

extension AppStore {
    /// Calculate weekly workout frequency
    var weeklyWorkoutFrequency: Int {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        
        return workoutHistory.filter { history in
            guard let date = ISO8601DateFormatter().date(from: history.date) else { return false }
            return date >= weekAgo && date <= now
        }.count
    }
    
    /// Get readiness trend (improving, declining, stable)
    enum ReadinessTrend {
        case improving, stable, declining
    }
    
    var readinessTrend: ReadinessTrend {
        // Compare current readiness with 7-day average
        let recentScores = sleepData.prefix(7).map { $0.score }
        guard !recentScores.isEmpty else { return .stable }
        
        let average = Double(recentScores.reduce(0, +)) / Double(recentScores.count)
        let difference = Double(readiness.overall) - average
        
        if difference > 5 {
            return .improving
        } else if difference < -5 {
            return .declining
        } else {
            return .stable
        }
    }
    
    /// Check if user should train today based on readiness
    var shouldTrainToday: Bool {
        readiness.overall >= 50
    }
    
    /// Get recommended intensity for today
    var recommendedIntensity: WorkoutIntensity {
        if readiness.overall >= 80 {
            return .high
        } else if readiness.overall >= 65 {
            return .moderate
        } else {
            return .low
        }
    }
}
