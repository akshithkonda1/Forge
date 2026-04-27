import Foundation
import Combine

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

// MARK: - AppStore (mirrors useAppStore.ts / Zustand store)

final class AppStore: ObservableObject {

    // Onboarding
    @Published var isOnboarded: Bool = false
    @Published var onboardingStep: Int = 0

    // User Profile
    @Published var userProfile: UserProfile = mockProfile

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

    // Sleep
    @Published var sleepData: [SleepData] = []

    // History & Records
    @Published var workoutHistory: [WorkoutHistory] = []
    @Published var personalRecords: [PersonalRecord] = []

    // Navigation
    @Published var activeTab: TabItem = .home
    
    // Streak tracking
    @Published var currentStreak: Int = 7
    
    // MARK: Initialization
    
    init() {
        // Load mock data asynchronously to avoid blocking app launch
        Task { @MainActor in
            self.chatMessages = mockChatMessages
            self.sleepData = mockSleepData
            self.workoutHistory = mockWorkoutHistory
            self.personalRecords = mockPersonalRecords
        }
    }

    // MARK: Workout actions

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

    func endWorkout() {
        isWorkoutActive = false
        currentExerciseIndex = 0
        currentSet = 1
    }

    // MARK: Chat actions

    func addMessage(_ message: ChatMessage) {
        chatMessages.append(message)
    }
    
    // MARK: Data refresh
    
    func refreshDailyData() {
        // Simulate refreshing data from backend/HealthKit
        // In a real app, this would fetch latest metrics
        objectWillChange.send()
    }

    // MARK: Simulated AI response (mirrors getTrainerResponse in chat-page.tsx)

    func trainerResponse(for text: String) -> (content: String, richCard: RichCardData?) {
        let lower = text.lowercased()
        let hour = Calendar.current.component(.hour, from: Date())
        let isEarlyMorning = hour < 7
        let isLateNight = hour >= 22

        // Context-aware greetings
        if lower.contains("hello") || lower.contains("hey") || lower.contains("hi ") || lower.contains("what's up") || lower.contains("sup") {
            var greetings: [String] = []
            
            if isEarlyMorning {
                greetings = [
                    "Morning, \(userProfile.name). You're up early. Training or just couldn't sleep?",
                    "Damn, you're up. Feeling good or just restless?",
                    "Early bird today, huh? What's the plan?",
                ]
            } else if isLateNight {
                greetings = [
                    "Late night check-in? What's on your mind?",
                    "Can't sleep or just wired from today? Talk to me.",
                    "Yo. Everything good? Kinda late for you.",
                ]
            } else if readiness.overall < 65 {
                greetings = [
                    "Hey. Noticed you're at \(readiness.overall)% today — how you actually feeling?",
                    "What's up. Your numbers are a little off today, just checking in.",
                    "Hey \(userProfile.name). Body's telling me you might need an easy day — you feel that too?",
                ]
            } else {
                greetings = [
                    "Yo, what's good?",
                    "Hey \(userProfile.name), what do you need?",
                    "What's up, talk to me.",
                    "Hey. How's everything feeling today?",
                    "Yo. What are we working on?",
                ]
            }
            return (greetings.randomElement()!, nil)
        }
        
        // Training request with adaptive intelligence
        if lower.contains("what should i") || lower.contains("train today") || lower.contains("workout today") || lower.contains("what should we") {
            let responses: [(String, ClosedRange<Int>)]
            let workoutPlan: RichCardData
            
            // High readiness - push hard
            if readiness.overall >= 80 {
                responses = [
                    ("Alright so — you're at \(readiness.overall)/100, HRV came in at \(dailyMetrics.hrv), resting HR is \(dailyMetrics.restingHR). Body's ready for some damage. Let's go heavy today. Upper body power work, big compounds, low reps. Gonna feel amazing.", 80...100),
                ]
                workoutPlan = RichCardData(type:.workoutPlan, workoutName:"Upper Body Power", workoutDuration:55, workoutExercises:[
                    ("Barbell Bench Press",4,"6-8"), ("Weighted Pull-Ups",4,"6-8"),
                    ("Overhead Press",3,"8-10"), ("Barbell Rows",3,"8-10"),
                    ("Incline DB Press",3,"10-12"), ("Face Pulls",3,"15-20"),
                ])
            }
            // Moderate readiness
            else if readiness.overall >= 60 {
                responses = [
                    ("You're sitting at \(readiness.overall)/100. HRV's \(dailyMetrics.hrv), heart rate \(dailyMetrics.restingHR) — totally fine, not spectacular. We can work with this. Upper body but I'm pulling back the volume a bit. Quality reps, don't chase PRs today.", 60...79),
                ]
                workoutPlan = RichCardData(type:.workoutPlan, workoutName:"Upper Body Volume", workoutDuration:50, workoutExercises:[
                    ("Barbell Bench Press",3,"8-10"), ("Lat Pulldown",3,"10-12"),
                    ("Dumbbell Press",3,"10-12"), ("Cable Row",3,"10-12"),
                    ("Lateral Raises",3,"12-15"), ("Tricep Pushdowns",3,"12-15"),
                ])
            }
            // Low readiness
            else {
                responses = [
                    ("Yeah so... readiness is \(readiness.overall)/100. HRV at \(dailyMetrics.hrv), resting HR is \(dailyMetrics.restingHR). That's lower than I want to see. You stressed? Not sleeping well? Either way, we're backing off today. Light upper body work, more like movement practice than training. Save the real work for when your body's actually ready.", 0...59),
                ]
                workoutPlan = RichCardData(type:.workoutPlan, workoutName:"Active Recovery Upper", workoutDuration:35, workoutExercises:[
                    ("Push-Ups (controlled)",3,"12"), ("Band Pull-Aparts",3,"20"),
                    ("Dumbbell Press (light)",3,"15"), ("TRX Rows",3,"15"),
                    ("Shoulder Circles",2,"20"),
                ])
            }
            
            let response = responses.first { $0.1.contains(readiness.overall) }?.0 ?? responses[0].0
            return (response, workoutPlan)
        }
        
        // Low energy / not feeling it
        if lower.contains("not feeling") || lower.contains("tired") || lower.contains("exhausted") || lower.contains("low energy") || lower.contains("drained") {
            let empathy = [
                "Yeah, I hear you. Some days just hit different. Look — skipping entirely? Waste. Going hard anyway? Stupid. So we meet in the middle. 30 minutes, easy movement, get some blood flow going. You'll feel better after, trust me.",
                "Felt that way yesterday too, huh? Listen, your body's trying to tell you something. We're not doing anything heavy today. Recovery flow, stretch it out, move light. Think of it like... maintenance, not training. You'll bounce back faster.",
                "Okay real talk — there's tired, and then there's *tired*. Which one? Like, 'I stayed up late' tired or 'my body's wrecked' tired? Either way we're backing off, I just need to know how much.",
                "Gotcha. Days like this separate smart athletes from broken ones. We're going light. Mobility, blood flow, maybe some easy bodyweight stuff. No ego, no grinding. Just movement. Sound good?",
            ]
            
            let workoutPlan = RichCardData(type:.workoutPlan, workoutName:"Recovery Flow", workoutDuration:30, workoutExercises:[
                ("Foam Rolling",1,"5 min"), ("World's Greatest Stretch",2,"8 each side"),
                ("Band Pull-Aparts",3,"15"), ("Goblet Squats (light)",2,"10"),
                ("Dead Hangs",3,"30 sec"), ("Walk or Bike (easy)",1,"10 min"),
            ])
            return (empathy.randomElement()!, workoutPlan)
        }
        
        // Sleep analysis
        if lower.contains("sleep") || lower.contains("slept") || lower.contains("rest") && !lower.contains("restaurant") {
            let lastSleep = sleepData.first
            let deepMin = lastSleep?.deepMinutes ?? dailyMetrics.deepSleep
            let totalHrs = lastSleep?.totalHours ?? Double(dailyMetrics.totalSleep) / 60
            let scores = sleepData.prefix(7).map { Double($0.score) }.reversed().map { $0 }
            let avg = scores.isEmpty ? 79 : scores.reduce(0, +) / Double(scores.count)
            
            var analysis: String
            if deepMin >= 90 && totalHrs >= 7 {
                analysis = "Last night? \(String(format:"%.1f", totalHrs)) hours, \(deepMin) minutes deep. That's legit. Deep sleep is where you actually rebuild — muscles repair, hormones regulate, nervous system resets. You're doing it right. Keep this up and your training's gonna reflect it."
            } else if deepMin < 60 {
                analysis = "So... \(String(format:"%.1f", totalHrs)) hours total but only \(deepMin) minutes deep sleep. That's rough. Deep sleep is literally non-negotiable for recovery. Without it you're just breaking down without building back up. What's going on — stress? Late caffeine? Blue light before bed? We gotta fix this or your training's gonna stall."
            } else {
                analysis = "Slept \(String(format:"%.1f", totalHrs)) hours, got \(deepMin) minutes deep. Not bad, not great. You need more consistent sleep if you want real progress. I know life happens, but sleep is where the magic happens. Try to get to bed 30 minutes earlier tonight, see if that helps."
            }
            
            return (
                analysis,
                RichCardData(type:.dataChart, chartTitle:"Sleep Quality (7 days)",
                             chartValues: scores.isEmpty ? [68,74,91,62,93,80,88] : scores,
                             chartInsight:"Average sleep score this week: \(Int(avg))/100. \(avg >= 80 ? "Solid week." : avg >= 70 ? "Could be better." : "This needs work.")",
                             chartColor:.steel)
            )
        }
        
        // Pain / injury concern
        if lower.contains("injury") || lower.contains("pain") || lower.contains("hurt") || lower.contains("sore") && !lower.contains("not sore") {
            let isSorenessMention = lower.contains("sore") || lower.contains("doms")
            if isSorenessMention {
                return ("Soreness or actual pain? Big difference. DOMS from yesterday's workout? Normal, means you worked. Sharp pain when you move a certain way? Red flag. Which one we talking about?", nil)
            } else {
                return ("Whoa, stop. Where's the pain? Sharp or dull? Does it hurt when you move it or just when you load it? Need details before we do anything. If it's sharp, we're working around it completely. If it's just tight or achy, we can probably move through it carefully. Talk to me.", nil)
            }
        }
        
        // Modify / adjust plan
        if lower.contains("adjust") || lower.contains("change") || lower.contains("modify") || lower.contains("switch") && (lower.contains("plan") || lower.contains("workout") || lower.contains("program")) {
            return ("Yeah for sure, let's change it up. What's not working? Too much volume? Wrong split? Exercises you don't like? Life schedule changed? Just tell me what you need and we'll rebuild it. Your program works for you, not the other way around.", nil)
        }
        
        // Progress check
        if lower.contains("progress") || lower.contains("how am i doing") || lower.contains("gains") || lower.contains("getting stronger") {
            let encouragement = [
                "Bro you've been killing it. Last month alone — 18 workouts, 3 new PRs, recovery metrics up 22%. Bench went from 205 to 225, squat's at 315 now. That's not luck, that's showing up consistently. Keep this pace and you're gonna surprise yourself in 3 months.",
                "Let me check... yeah okay, you're doing better than you think. 18 sessions in 4 weeks, bench up 20 pounds, squat hit 315. Most people aren't consistent enough to see these numbers. You are. That's the whole game right there — just keep showing up and the results pile up.",
                "Pulled your stats. Last 30 days you've been ridiculously consistent. 18 workouts, zero missed sessions, 3 PRs. Bench jumped from 205 to 225. Squat's at 315. Your recovery's improving too — HRV trending up, sleep's been solid. This is what real progress looks like. Not flashy, just steady.",
            ]
            return (
                encouragement.randomElement()!,
                RichCardData(type:.dataChart, chartTitle:"Bench Press Progress (4 weeks)",
                             chartValues:[185,195,205,215,225],
                             chartInsight:"Bench: +40 lbs in 4 weeks. Estimated 1RM: 245 lbs. Strength is climbing fast.",
                             chartColor:.ember)
            )
        }
        
        // Gratitude response
        if lower.contains("thank") || lower.contains("appreciate") || lower.contains("grateful") {
            let gratitude = [
                "You're doing the work, I'm just here to keep you honest.",
                "Don't thank me yet, we're just getting started.",
                "Appreciate it. Now go hit that workout.",
                "All you, I'm just steering. Keep showing up.",
            ]
            return (gratitude.randomElement()!, nil)
        }
        
        // Motivation request
        if lower.contains("motivate") || lower.contains("pump me up") || lower.contains("need motivation") || lower.contains("inspire") {
            let motivation = [
                "Motivation? Nah. Motivation is temporary. You need discipline. Motivation gets you to the gym once. Discipline gets you there 200 times a year. Stop waiting to feel like it. Just show up. That's the secret nobody wants to hear.",
                "You don't need me to pump you up. You need to remember why you started. Write that down. Then go do the work even when you don't feel like it. That's how you build something real.",
                "Real talk — the best workouts happen on days you don't want to train. Those are the ones that count. Anyone can show up when they're motivated. You? You're gonna show up when you're not. That's what separates you.",
            ]
            return (motivation.randomElement()!, nil)
        }
        
        // Confused / unclear request
        let fallbacks = [
            "Not sure I follow. You asking about training? Recovery? Something specific bothering you? Just say it straight, I got you.",
            "Hmm, lost me a bit there. Rephrase that? Are we talking workouts, sleep, nutrition, or something else?",
            "I want to give you a real answer but I need more context. What specifically are you asking about?",
            "Hold up, clarify that for me. You mean today's workout or overall programming or...?",
            "Yeah I'm not quite tracking. Break it down for me — what do you actually need right now?",
        ]
        return (fallbacks.randomElement()!, nil)
    }
}
