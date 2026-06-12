import Foundation
import Combine
import FoundationModels
import HealthKit

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
    @Published var isOnboarded: Bool = ForgePersistence.isOnboarded
    @Published var onboardingStep: Int = 0

    // User Profile
    @Published var userProfile: UserProfile = emptyProfile

    // Readiness & Metrics
    @Published var readiness: ReadinessData = emptyReadiness
    @Published var dailyMetrics: DailyMetrics = emptyMetrics
    @Published var dataConclusions: DataConclusions?
    @Published var dailyScores: DailyScores?
    @Published var biologicalAge: BiologicalAge?
    @Published var cycleEvents: [CycleEvent] = []
    @Published var ariaBrief: ARIABrief?
    @Published var eveningBrief: ARIABrief?
    @Published var postWorkoutBrief: ARIABrief?
    @Published var briefNotificationsEnabled: Bool = ForgePersistence.loadBriefNotificationSettings().enabled

    /// Brief shown on Home — evening after 5pm, post-workout for 2h, else morning.
    var activeBrief: ARIABrief? {
        if let postWorkoutBrief,
           Date().timeIntervalSince(postWorkoutBrief.generatedAt) < 2 * 3600 {
            return postWorkoutBrief
        }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 17, let eveningBrief { return eveningBrief }
        return ariaBrief
    }

    // Today's Workout
    @Published var todayWorkout: WorkoutPlan?
    @Published var planInsightText: String?

    // Active Workout State
    @Published var isWorkoutActive: Bool = false
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSet: Int = 1

    // Chat
    @Published var chatMessages: [ChatMessage] = []
    @Published var isGeneratingResponse: Bool = false
    @Published var lastARIAToolCalls: [String] = []

    // Sleep
    @Published var sleepData: [SleepData] = []

    // History & Records
    @Published var workoutHistory: [WorkoutHistory] = []
    @Published var personalRecords: [PersonalRecord] = []

    // Navigation
    @Published var activeTab: TabItem = .home
    /// When set, ProfileTabView opens this sub-tab (e.g. "Lifestyle") then clears.
    @Published var pendingProfileSubTab: String?
    
    // Streak tracking
    @Published var currentStreak: Int = 0

    // Progress insights
    @Published var progressSummary: ProgressSummarySnapshot?
    @Published var coachingInsights: [CoachingInsight] = []
    @Published var connections: [IntegrationConnection] = []
    @Published var deviceServiceStatus: DeviceServiceStatus?
    @Published var weeklyHealthTrends: [WeeklyHealthTrend] = []

    // AI Configuration
    @Published var aiModelAvailable: Bool = false
    @Published var dataLoadState: DataLoadState = .idle

    // MARK: - Private Properties
    
    private var responseGenerator: TrainerResponseGenerator
    private let repository = ForgeRepository.shared
    private var cancellables = Set<AnyCancellable>()
    private var hasServerReadiness = false
    
    // MARK: - Initialization
    
    init() {
        // Initialize AI response generator
        if #available(iOS 26.0, *) {
            let foundationModelsGenerator = FoundationModelsResponseGenerator()
            self.aiModelAvailable = foundationModelsGenerator.isAvailable
            self.responseGenerator = foundationModelsGenerator.isAvailable ? 
                foundationModelsGenerator : RuleBasedResponseGenerator()
        } else {
            self.responseGenerator = RuleBasedResponseGenerator()
            self.aiModelAvailable = false
        }
        
    }

    // MARK: - API Bootstrap

    func loadDashboardFromAPI() async {
        if APIConfig.usesAuth, CognitoAuthManager.shared.requiresSignIn {
            return
        }

        dataLoadState = .loading
        do {
            async let dashboardTask = repository.fetchDashboard()
            async let conversationTask = repository.fetchConversation()
            async let progressTask = repository.fetchProgressSummary(days: 30)
            async let insightsTask = repository.fetchInsights(days: 7)
            async let connectionsTask = repository.fetchConnections()
            async let deviceStatusTask = repository.fetchDeviceServiceStatus()

            let snapshot = try await dashboardTask
            applyDashboardSnapshot(snapshot)

            if let conversation = try? await conversationTask, !conversation.isEmpty {
                chatMessages = conversation
            }

            if let summary = try? await progressTask {
                progressSummary = summary
            }

            if let insights = try? await insightsTask {
                coachingInsights = insights
            }

            if let linked = try? await connectionsTask {
                connections = linked
                syncConnectedDevicesFromConnections(linked)
            }

            deviceServiceStatus = try? await deviceStatusTask

            await syncHealthKitIfAvailable()
            await refreshCloudConclusions()
            await refreshProactiveBriefs(scheduleNotifications: true)
            ForgeSharedData.syncFromStore(self)
            dataLoadState = .loaded
        } catch {
            #if DEBUG
            if sleepData.isEmpty && workoutHistory.isEmpty {
                loadMockFallback()
                dataLoadState = .offlineFallback
            } else {
                dataLoadState = .error(Self.userFacingAPIError(error))
            }
            #else
            dataLoadState = .error(Self.userFacingAPIError(error))
            #endif
            print("Forge API unavailable: \(error)")
        }
    }

    func ensureChatHistoryLoaded() async {
        guard chatMessages.isEmpty else { return }
        if let conversation = try? await repository.fetchConversation(), !conversation.isEmpty {
            chatMessages = conversation
        }
    }

    func applyOnboardingHealthSnapshot(_ snapshot: HealthDataSnapshot) {
        updateMetrics(
            steps: snapshot.steps,
            activeCalories: snapshot.activeCalories,
            hrv: snapshot.hrv.map { Int($0.rounded()) },
            restingHR: snapshot.restingHeartRate
        )
        if let hours = snapshot.sleepHours {
            dailyMetrics.totalSleep = Int(hours * 60)
            if !hasServerReadiness { recalculateReadiness() }
            refreshWellnessScores()
        }
    }

    private static func userFacingAPIError(_ error: Error) -> String {
        if let apiError = error as? ForgeAPIError {
            return apiError.errorDescription ?? "Request failed"
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
                #if DEBUG
                return "Can't connect to \(APIConfig.displayHost). Start the backend with npm run backend:dev."
                #else
                return "Can't reach the Forge API at \(APIConfig.displayHost). Check your connection and try again."
                #endif
            case NSURLErrorTimedOut:
                return "Request timed out reaching \(APIConfig.displayHost)."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    func refreshConnections() async {
        do {
            let linked = try await repository.fetchConnections()
            connections = linked
            syncConnectedDevicesFromConnections(linked)
            deviceServiceStatus = try? await repository.fetchDeviceServiceStatus()
        } catch {
            print("Failed to refresh connections: \(error)")
        }
    }

    func refreshSleepData(days: Int = 14) async {
        do {
            sleepData = try await repository.fetchExtendedSleep(days: days)
        } catch {
            print("Failed to refresh sleep data: \(error)")
        }
    }

    func syncHealthKitIfAvailable() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        await HealthKitManager.shared.fetchWeeklyTrends()
        weeklyHealthTrends = HealthKitManager.shared.weeklyTrends
        await HealthSyncCoordinator.shared.syncAll()

        let snapshot = await HealthKitManager.shared.fetchRecentSnapshot()
        updateMetrics(
            steps: snapshot?.steps,
            activeCalories: snapshot?.activeCalories,
            hrv: snapshot?.hrv.map { Int($0.rounded()) },
            restingHR: snapshot?.restingHeartRate
        )

        let events = await HealthKitManager.shared.fetchRecentCycleEvents(days: 90)
        cycleEvents = events

        refreshLocalConclusions()

        if let refreshed = try? await repository.fetchDashboard() {
            applyDashboardSnapshot(refreshed)
            ForgeSharedData.syncFromStore(self)
        } else {
            refreshWellnessScores()
            ForgeSharedData.syncFromStore(self)
        }
    }

    func refreshLocalConclusions() {
        dataConclusions = ConclusionsEngine.evaluate(
            readiness: readiness,
            dailyMetrics: dailyMetrics,
            sleepData: sleepData,
            workoutHistory: workoutHistory
        )
        refreshWellnessScores()
    }

    func refreshCloudConclusions() async {
        if let remote = try? await repository.fetchConclusions() {
            dataConclusions = remote
            refreshWellnessScores()
        } else {
            refreshLocalConclusions()
        }
    }

    func refreshProactiveBriefs(scheduleNotifications: Bool = false) async {
        async let morningTask = repository.fetchARIABrief(focus: "morning")
        async let eveningTask = repository.fetchARIABrief(focus: "evening")

        if let morning = try? await morningTask {
            ariaBrief = morning
        } else {
            ariaBrief = ARIABrief.localFallback(
                focus: .morning,
                dailyScores: dailyScores,
                conclusions: dataConclusions,
                trainingDecision: dailyScores?.trainingDecision ?? .activeRest
            )
        }

        if let evening = try? await eveningTask {
            eveningBrief = evening
        } else {
            eveningBrief = ARIABrief.localFallback(
                focus: .evening,
                dailyScores: dailyScores,
                conclusions: dataConclusions,
                trainingDecision: dailyScores?.trainingDecision ?? .activeRest
            )
        }

        if scheduleNotifications, briefNotificationsEnabled {
            let settings = ForgePersistence.loadBriefNotificationSettings()
            await ForgeNotificationCoordinator.shared.scheduleProactiveBriefs(
                morning: ariaBrief,
                evening: eveningBrief,
                settings: settings
            )
        }
        ForgeSharedData.syncFromStore(self)
    }

    func refreshPostWorkoutBrief(deliverNotification: Bool = true) async {
        let brief: ARIABrief
        if let remote = try? await repository.fetchARIABrief(focus: "post-workout") {
            brief = remote
        } else {
            brief = ARIABrief.localFallback(
                focus: .postWorkout,
                dailyScores: dailyScores,
                conclusions: dataConclusions,
                trainingDecision: dailyScores?.trainingDecision ?? .activeRest
            )
        }
        postWorkoutBrief = brief
        ForgeSharedData.syncFromStore(self)
        if deliverNotification, briefNotificationsEnabled {
            await ForgeNotificationCoordinator.shared.deliverImmediateBrief(brief)
        }
    }

    func setBriefNotificationsEnabled(_ enabled: Bool) {
        briefNotificationsEnabled = enabled
        var settings = ForgePersistence.loadBriefNotificationSettings()
        settings.enabled = enabled
        ForgePersistence.saveBriefNotificationSettings(settings)
        Task {
            if enabled {
                await ForgeNotificationCoordinator.shared.requestAuthorizationIfNeeded()
                await refreshProactiveBriefs(scheduleNotifications: true)
            } else {
                ForgeNotificationCoordinator.shared.cancelBriefNotifications()
            }
        }
    }

    func refreshTodayWorkoutPlan() async {
        do {
            if let plan = try await repository.refreshCoachWorkoutPlan() {
                todayWorkout = plan
            } else if let planText = try? await repository.generateDailyPlan(focus: "auto"),
                      !planText.isEmpty {
                planInsightText = planText
            }
        } catch {
            print("Failed to refresh workout plan: \(error)")
        }
    }

    func applyWorkoutFromRichCard(_ card: RichCardData) {
        guard card.type == .workoutPlan,
              let name = card.workoutName,
              let exercises = card.workoutExercises else { return }
        todayWorkout = WorkoutPlan(
            id: UUID().uuidString,
            name: name,
            type: .strength,
            duration: card.workoutDuration ?? 45,
            intensity: readiness.overall >= 75 ? .high : .moderate,
            exercises: exercises.enumerated().map { index, item in
                Exercise(
                    id: "rich-\(index)",
                    name: item.name,
                    sets: item.sets,
                    reps: item.reps,
                    weight: nil,
                    restSeconds: 90,
                    notes: nil,
                    videoURL: nil,
                    has3DModel: false
                )
            }
        )
    }

    private func syncConnectedDevicesFromConnections(_ linked: [IntegrationConnection]) {
        let names = linked
            .filter { $0.status == .connected || $0.status == .syncing }
            .map(\.displayName)
        if !names.isEmpty {
            userProfile.connectedDevices = names
        }
    }

    var sleepInsightText: String {
        if let sleepInsight = coachingInsights.first(where: { $0.type == "sleep" }) {
            return "\(sleepInsight.observation) \(sleepInsight.recommendation)"
        }
        if let summary = progressSummary?.summary, !summary.isEmpty {
            return summary
        }
        guard let latest = sleepData.first else {
            return "Connect a device or Apple Health to unlock personalized sleep coaching."
        }
        let deep = "\(latest.deepMinutes / 60 > 0 ? "\(latest.deepMinutes / 60)hr " : "")\(latest.deepMinutes % 60)min"
        if latest.score >= 85 {
            return "Excellent recovery. \(deep) of deep sleep has you primed for a heavy session today."
        }
        if latest.score >= 70 {
            return "Good sleep — \(deep) of deep sleep. Cut screens 45 minutes before bed to push this score higher."
        }
        return "Only \(deep) of deep sleep last night. Consider a lighter session and an earlier bedtime tonight."
    }

    private func applyDashboardSnapshot(_ snapshot: DashboardSnapshot) {
        userProfile = snapshot.profile
        readiness = snapshot.readiness
        dailyMetrics = snapshot.dailyMetrics
        todayWorkout = snapshot.todayWorkout
        sleepData = snapshot.sleepData
        workoutHistory = snapshot.workoutHistory
        personalRecords = snapshot.personalRecords
        currentStreak = calculateWorkoutStreak(from: snapshot.workoutHistory)
        hasServerReadiness = snapshot.readiness.overall > 0

        if let remote = snapshot.dailyScores {
            dailyScores = remote
        }
        if let remote = snapshot.biologicalAge {
            biologicalAge = remote
        }

        refreshWellnessScores(
            preferServerScores: snapshot.dailyScores != nil,
            preferServerBioAge: snapshot.biologicalAge != nil
        )
    }

    func refreshWellnessScores(preferServerScores: Bool = false, preferServerBioAge: Bool = false) {
        let cycle = DailyScoresEngine.inferCyclePhase(from: cycleEvents)
        let flags = dataConclusions?.compoundFlags ?? []

        if !preferServerScores || dailyScores == nil {
            dailyScores = DailyScoresEngine.compute(
                readiness: readiness,
                dailyMetrics: dailyMetrics,
                sleepData: sleepData,
                workoutHistory: workoutHistory,
                compoundFlags: flags,
                cycleContext: cycle
            )
        } else if var scores = dailyScores {
            scores.cycleContext = cycle
            dailyScores = scores
        }

        if !preferServerBioAge || biologicalAge == nil {
            biologicalAge = DailyScoresEngine.computeBiologicalAge(
                profile: userProfile,
                readiness: readiness,
                dailyMetrics: dailyMetrics,
                sleepData: sleepData
            )
        }
    }

    private func loadMockFallback() {
        #if DEBUG
        userProfile = mockProfile
        readiness = mockReadiness
        dailyMetrics = mockMetrics
        todayWorkout = mockWorkout
        chatMessages = mockChatMessages
        sleepData = mockSleepData
        workoutHistory = mockWorkoutHistory
        personalRecords = mockPersonalRecords
        currentStreak = calculateWorkoutStreak(from: mockWorkoutHistory)
        refreshWellnessScores()
        progressSummary = ProgressSummarySnapshot(
            periodDays: 30,
            workoutsCompleted: mockWorkoutHistory.count,
            newPRCount: mockPersonalRecords.count,
            recoveryDelta: 22,
            summary: "Strong month. You've been consistent with your Mon/Wed/Fri schedule and hit new personal records."
        )
        #endif
    }

    private func resetToEmptyState() {
        userProfile = emptyProfile
        readiness = emptyReadiness
        dailyMetrics = emptyMetrics
        todayWorkout = nil
        planInsightText = nil
        chatMessages = []
        sleepData = []
        workoutHistory = []
        personalRecords = []
        currentStreak = 0
        progressSummary = nil
        coachingInsights = []
        connections = []
        deviceServiceStatus = nil
        weeklyHealthTrends = []
        lastARIAToolCalls = []
        dailyScores = nil
        biologicalAge = nil
        cycleEvents = []
        dataConclusions = nil
        ariaBrief = nil
        eveningBrief = nil
        postWorkoutBrief = nil
        hasServerReadiness = false
    }

    private func calculateWorkoutStreak(from history: [WorkoutHistory]) -> Int {
        let formatter = ISO8601DateFormatter()
        let calendar = Calendar.current
        let workoutDays = Set(
            history.compactMap { item -> Date? in
                if let date = formatter.date(from: item.date) {
                    return calendar.startOfDay(for: date)
                }
                let parts = item.date.split(separator: "-")
                guard parts.count == 3,
                      let year = Int(parts[0]),
                      let month = Int(parts[1]),
                      let day = Int(parts[2]) else { return nil }
                return calendar.date(from: DateComponents(year: year, month: month, day: day))
            }
        )

        var streak = 0
        var cursor = calendar.startOfDay(for: Date())
        while workoutDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    // MARK: - Workout Actions

    func startWorkout() {
        currentExerciseIndex = 0
        currentSet = 1
        isWorkoutActive = true
        if let workout = todayWorkout, let first = workout.exercises.first {
            WorkoutLiveActivityManager.start(
                workoutName: workout.name,
                exerciseName: first.name,
                totalSets: first.sets
            )
        }
    }

    func nextSet() {
        currentSet += 1
    }

    func nextExercise() {
        currentExerciseIndex += 1
        currentSet = 1
    }

    func endWorkout(avgHeartRate: Int? = nil, peakHeartRate: Int? = nil) {
        isWorkoutActive = false
        currentExerciseIndex = 0
        currentSet = 1
        WorkoutLiveActivityManager.end()
        guard let workout = todayWorkout else { return }
        let volume = workout.exercises.reduce(0) { $0 + ($1.sets * ($1.weight ?? 0)) }
        let history = WorkoutHistory(
            id: UUID().uuidString,
            date: ISO8601DateFormatter().string(from: Date()),
            name: workout.name,
            type: workout.type,
            duration: workout.duration,
            volume: volume,
            intensity: workout.intensity
        )
        workoutHistory.insert(history, at: 0)
        currentStreak = calculateWorkoutStreak(from: workoutHistory)

        Task {
            refreshWellnessScores()
            await refreshPostWorkoutBrief(deliverNotification: briefNotificationsEnabled)
            do {
                try await repository.logWorkout(
                    workout,
                    volume: volume,
                    avgHeartRate: avgHeartRate,
                    peakHeartRate: peakHeartRate
                )
            } catch {
                print("Failed to log workout: \(error)")
            }
        }
    }

    // MARK: - Chat Actions

    func addMessage(_ message: ChatMessage) {
        chatMessages.append(message)
    }
    
    /// Send a message and get AI response
    func sendMessage(_ text: String) async {
        // Add user message
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: text,
            timestamp: Date()
        )
        chatMessages.append(userMessage)
        
        // Set loading state
        isGeneratingResponse = true
        
        do {
            let result = try await repository.sendChatMessage(text)
            var trainerMessage = result.message
            if trainerMessage.toolCallsMade == nil, !result.toolCalls.isEmpty {
                trainerMessage.toolCallsMade = result.toolCalls
            }
            chatMessages.append(trainerMessage)
            lastARIAToolCalls = result.toolCalls
        } catch {
            let fallback = dataConclusions?.offlineTemplates.chat
                ?? ConclusionsEngine.evaluate(
                    readiness: readiness,
                    dailyMetrics: dailyMetrics,
                    sleepData: sleepData,
                    workoutHistory: workoutHistory
                ).offlineTemplates.chat
            if fallback.isEmpty {
                appendChatUnavailableMessage()
            } else {
                chatMessages.append(ChatMessage(
                    id: UUID().uuidString,
                    role: .trainer,
                    content: fallback,
                    timestamp: Date()
                ))
            }
            print("Error generating AI response: \(error)")
        }

        isGeneratingResponse = false
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
        await syncHealthKitIfAvailable()
        await loadDashboardFromAPI()
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
        
        if !hasServerReadiness {
            recalculateReadiness()
        }
        refreshWellnessScores()
    }
    
    /// Local readiness estimate when server scores are unavailable.
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
        experienceLevel: ExperienceLevel? = nil
    ) {
        if let name = name { userProfile.name = name }
        if let style = coachingStyle { userProfile.coachingStyle = style }
        if let goals = fitnessGoals { userProfile.fitnessGoals = goals }
        if let level = experienceLevel { userProfile.experienceLevel = level }

        Task {
            do {
                try await repository.saveProfile(userProfile)
            } catch {
                print("Failed to save profile: \(error)")
            }
        }
    }

    private func appendChatUnavailableMessage() {
        let errorMessage = ChatMessage(
            id: UUID().uuidString,
            role: .trainer,
            content: "Sorry, I'm having trouble reaching ARIA right now. Can you try again?",
            timestamp: Date()
        )
        chatMessages.append(errorMessage)
    }

    func completeOnboarding(syncHealth: Bool = false) {
        isOnboarded = true
        ForgePersistence.setOnboarded(true)
        Task {
            if APIConfig.usesAuth, CognitoAuthManager.shared.requiresSignIn {
                return
            }
            do {
                try await repository.saveProfile(userProfile)
                if syncHealth {
                    try? await repository.syncHealthMetrics(
                        steps: dailyMetrics.steps,
                        activeCalories: dailyMetrics.activeCalories,
                        hrv: dailyMetrics.hrv,
                        restingHR: dailyMetrics.restingHR
                    )
                }
                await loadDashboardFromAPI()
                await ForgeNotificationCoordinator.shared.requestAuthorizationIfNeeded()
                await refreshProactiveBriefs(scheduleNotifications: true)
            } catch {
                dataLoadState = .error(Self.userFacingAPIError(error))
                print("Failed to persist onboarding profile: \(error)")
            }
        }
    }

    func signOut() {
        CognitoAuthManager.shared.signOut()
        ForgePersistence.resetOnboarding()
        isOnboarded = false
        onboardingStep = 0
        resetToEmptyState()
        dataLoadState = .idle
    }

    func connectAppleHealth() async {
        do {
            try await HealthKitManager.shared.requestAuthorization()
            let snapshot = await HealthKitManager.shared.fetchRecentSnapshot()
            updateMetrics(
                steps: snapshot?.steps,
                activeCalories: snapshot?.activeCalories,
                hrv: snapshot?.hrv.map { Int($0.rounded()) },
                restingHR: snapshot?.restingHeartRate
            )

            if !userProfile.connectedDevices.contains("Apple Health") {
                userProfile.connectedDevices.append("Apple Health")
            }
            try await repository.saveProfile(userProfile)
            try await repository.syncHealthMetrics(
                steps: snapshot?.steps,
                activeCalories: snapshot?.activeCalories,
                hrv: snapshot?.hrv.map { Int($0.rounded()) } ?? dailyMetrics.hrv,
                restingHR: snapshot?.restingHeartRate
            )
            await loadDashboardFromAPI()
        } catch {
            print("Apple Health connection failed: \(error)")
        }
    }
    
    // MARK: - Sleep Management
    
    func addSleepData(_ sleep: SleepData) {
        sleepData.insert(sleep, at: 0)
        
        // Update daily metrics
        dailyMetrics.totalSleep = Int(sleep.totalHours * 60)
        dailyMetrics.deepSleep = sleep.deepMinutes
        
        if !hasServerReadiness { recalculateReadiness() }
        refreshWellnessScores()
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
    var primaryTrainingInsight: CoachingInsight? {
        coachingInsights.first { $0.type == "training" || $0.type == "recovery" }
            ?? coachingInsights.first
    }

    enum MetricTrendKind {
        case steps, activeCalories, hrv, restingHR
    }

    func metricTrend(for kind: MetricTrendKind) -> (TrendDir, String)? {
        guard weeklyHealthTrends.count >= 2 else { return nil }

        let latest = weeklyHealthTrends.last!
        let prior = weeklyHealthTrends.dropLast()
        guard !prior.isEmpty else { return nil }

        let current: Double
        let average: Double
        let lowerIsBetter: Bool

        switch kind {
        case .steps:
            current = Double(latest.steps)
            average = Double(prior.map(\.steps).reduce(0, +)) / Double(prior.count)
            lowerIsBetter = false
        case .activeCalories:
            current = Double(latest.activeCalories)
            average = Double(prior.map(\.activeCalories).reduce(0, +)) / Double(prior.count)
            lowerIsBetter = false
        case .hrv:
            current = latest.avgHRV
            average = prior.map(\.avgHRV).reduce(0, +) / Double(prior.count)
            lowerIsBetter = false
        case .restingHR:
            current = latest.avgRestingHR > 0 ? latest.avgRestingHR : Double(dailyMetrics.restingHR)
            let restingSamples = prior.filter { $0.avgRestingHR > 0 }
            guard !restingSamples.isEmpty else { return nil }
            average = restingSamples.map(\.avgRestingHR).reduce(0, +) / Double(restingSamples.count)
            lowerIsBetter = true
        }

        guard average > 0 else { return nil }
        let delta = ((current - average) / average) * 100
        guard abs(delta) >= 1 else { return nil }

        let improved = lowerIsBetter ? delta < 0 : delta > 0
        let direction: TrendDir = improved ? .up : .down
        let sign = delta > 0 ? "+" : ""
        return (direction, "\(sign)\(Int(delta.rounded()))%")
    }

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
