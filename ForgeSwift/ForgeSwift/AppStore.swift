import Foundation
import Combine

// MARK: - Tab Enum

enum TabItem: String, CaseIterable, Identifiable {
    case home, chat, workout, sleep, profile
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .home:    return "house.fill"
        case .chat:    return "message.fill"
        case .workout: return "dumbbell.fill"
        case .sleep:   return "moon.fill"
        case .profile: return "person.fill"
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
    @Published var chatMessages: [ChatMessage] = mockChatMessages

    // Sleep
    @Published var sleepData: [SleepData] = mockSleepData

    // History & Records
    @Published var workoutHistory: [WorkoutHistory] = mockWorkoutHistory
    @Published var personalRecords: [PersonalRecord] = mockPersonalRecords

    // Navigation
    @Published var activeTab: TabItem = .home

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

    // MARK: Simulated AI response (mirrors getTrainerResponse in chat-page.tsx)

    func trainerResponse(for text: String) -> (content: String, richCard: RichCardData?) {
        let lower = text.lowercased()

        if lower.contains("how should i train") || lower.contains("train today") {
            let label = readiness.overall >= 80 ? "primed" : readiness.overall >= 60 ? "solid" : "a bit low"
            return (
                "Your readiness is \(label) at \(readiness.overall)/100 — HRV is \(dailyMetrics.hrv)ms, resting HR \(dailyMetrics.restingHR)bpm. I've put together an Upper Body Power session that matches your recovery state. Let's get after it.",
                RichCardData(type:.workoutPlan, workoutName:"Upper Body Power", workoutDuration:55, workoutExercises:[
                    ("Barbell Bench Press",4,"6-8"), ("Weighted Pull-Ups",4,"6-8"),
                    ("Overhead Press",3,"8-10"), ("Barbell Rows",3,"8-10"),
                    ("Incline DB Press",3,"10-12"), ("Face Pulls",3,"15-20"),
                ])
            )
        }

        if lower.contains("not feeling") || lower.contains("tired") || lower.contains("low energy") {
            return (
                "Hey, I hear you — everyone has those days. Let's do a lighter mobility and recovery flow that'll help you bounce back faster for tomorrow.",
                RichCardData(type:.workoutPlan, workoutName:"Recovery Flow", workoutDuration:30, workoutExercises:[
                    ("Foam Rolling",1,"5 min"), ("World's Greatest Stretch",2,"8 each side"),
                    ("Band Pull-Aparts",3,"15"), ("Goblet Squats (light)",2,"10"),
                    ("Dead Hangs",3,"30 sec"),
                ])
            )
        }

        if lower.contains("sleep") || lower.contains("how did i sleep") {
            let lastSleep = sleepData.first
            let deepMin = lastSleep?.deepMinutes ?? dailyMetrics.deepSleep
            let totalHrs = lastSleep?.totalHours ?? Double(dailyMetrics.totalSleep) / 60
            let scores = sleepData.prefix(7).map { Double($0.score) }.reversed().map { $0 }
            let avg = scores.isEmpty ? 79 : scores.reduce(0, +) / Double(scores.count)
            return (
                "Last night you logged \(String(format:"%.1f", totalHrs)) hours with \(deepMin) minutes of deep sleep — that's \(deepMin >= 90 ? "above average" : "slightly below your best"). Deep sleep is where your muscles actually rebuild, so this directly impacts your training capacity.",
                RichCardData(type:.dataChart, chartTitle:"Sleep Quality (7-day)",
                             chartValues: scores.isEmpty ? [68,74,91,62,93,80,88] : scores,
                             chartInsight:"Your average sleep score this week is \(Int(avg)). \(deepMin >= 90 ? "Deep sleep is solid." : "Try getting to bed 30 minutes earlier.")",
                             chartColor:.steel)
            )
        }

        if lower.contains("adjust") || lower.contains("change my plan") || lower.contains("modify") {
            return ("Absolutely — your plan should work for you, not the other way around. I can shift today's focus: swap to lower-body, dial down intensity for active recovery, or pivot to HIIT. What sounds right?", nil)
        }

        if lower.contains("injury") || lower.contains("pain") || lower.contains("hurt") || lower.contains("sore") {
            return ("I want to take this seriously. Tell me more — where exactly is the pain? Is it sharp/acute or more of a dull ache? In the meantime, I'm pulling your workout plan and replacing any movements that could aggravate it. We'll work around it, not through it.", nil)
        }

        if lower.contains("progress") || lower.contains("how am i doing") || lower.contains("gains") {
            return (
                "You've been putting in the work, \(userProfile.name). Over the last 4 weeks: 18 workouts completed, 3 new personal records, and your recovery consistency is up 22%. Bench went from 205 to 225, squat hit 315. Let's keep this momentum rolling.",
                RichCardData(type:.dataChart, chartTitle:"Strength Progress (4 weeks)",
                             chartValues:[185,195,205,215,225],
                             chartInsight:"Bench press progression: +40 lbs over 4 weeks. Current 1RM estimate: 245 lbs.",
                             chartColor:.ember)
            )
        }

        let fallbacks = [
            "Good question, \(userProfile.name). Based on your current metrics — \(dailyMetrics.steps.formatted()) steps today, HRV at \(dailyMetrics.hrv)ms — you're tracking well. Keep the consistency going. What else can I help with?",
            "I'm on it, \(userProfile.name). Your training data shows solid progress this week. Recovery is looking \(readiness.recoveryScore >= 75 ? "strong" : "like it needs some attention"). What do you want to dive into?",
            "Fitness isn't about perfect days, it's about showing up consistently. And \(userProfile.name), your consistency has been on point. Let me know if you want to talk specifics about your program.",
        ]
        return (fallbacks.randomElement()!, nil)
    }
}
