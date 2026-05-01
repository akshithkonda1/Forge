import Foundation
import SwiftUI

@Observable
final class AppStore {
    // MARK: - Onboarding
    var isOnboarded = false
    var onboardingStep = 0

    // MARK: - Navigation
    var activeTab: Tab = .home

    enum Tab: String, CaseIterable {
        case home, chat, workout, sleep, profile
    }

    // MARK: - User Profile
    var userProfile = UserProfile(
        name: "Akshith",
        fitnessGoals: [.buildMuscle],
        experienceLevel: .intermediate,
        preferredWorkouts: [.strength, .hiit],
        coachingStyle: .pushHard,
        connectedDevices: ["Apple Watch", "Oura Ring"],
        weeklySchedule: [1, 3, 5]
    )

    // MARK: - Readiness
    var readiness = ReadinessData(
        overall: 82, sleepQuality: 88, recoveryScore: 79,
        stressLevel: 24, energyBank: 76
    )

    // MARK: - Daily Metrics
    var dailyMetrics = DailyMetrics(
        steps: 3241, activeCalories: 186, hrv: 52,
        restingHR: 58, deepSleep: 102, totalSleep: 432
    )

    // MARK: - Workout
    var todayWorkout: WorkoutPlan? = WorkoutPlan(
        id: "w1", name: "Upper Body Power", type: .strength,
        duration: 55, intensity: .high,
        exercises: [
            Exercise(id: "e1", name: "Barbell Bench Press", sets: 4, reps: "6-8", weight: 185, restSeconds: 120, notes: "Focus on controlled eccentric"),
            Exercise(id: "e2", name: "Weighted Pull-Ups", sets: 4, reps: "6-8", weight: 25, restSeconds: 120),
            Exercise(id: "e3", name: "Overhead Press", sets: 3, reps: "8-10", weight: 115, restSeconds: 90),
            Exercise(id: "e4", name: "Barbell Rows", sets: 3, reps: "8-10", weight: 155, restSeconds: 90),
            Exercise(id: "e5", name: "Incline Dumbbell Press", sets: 3, reps: "10-12", weight: 65, restSeconds: 60),
            Exercise(id: "e6", name: "Face Pulls", sets: 3, reps: "15-20", weight: 30, restSeconds: 60),
        ]
    )

    // MARK: - Active Workout State
    var isWorkoutActive = false
    var currentExerciseIndex = 0
    var currentSet = 1
    var workoutElapsed = 0

    func startWorkout() {
        isWorkoutActive = true
        currentExerciseIndex = 0
        currentSet = 1
        workoutElapsed = 0
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
    }

    // MARK: - Chat
    var chatMessages: [ChatMessage] = Self.mockChatMessages

    func addMessage(_ msg: ChatMessage) {
        chatMessages.append(msg)
    }

    func sendUserMessage(_ text: String) {
        let userMsg = ChatMessage(
            id: "user-\(Date().timeIntervalSince1970)",
            role: .user, content: text, timestamp: Date()
        )
        addMessage(userMsg)

        // Simulate trainer response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let response = self.generateTrainerResponse(text)
            let trainerMsg = ChatMessage(
                id: "trainer-\(Date().timeIntervalSince1970)",
                role: .trainer, content: response.content,
                timestamp: Date(), richCard: response.richCard
            )
            self.addMessage(trainerMsg)
        }
    }

    // MARK: - Sleep
    var sleepData: [SleepData] = Self.mockSleepData

    // MARK: - History
    var workoutHistory: [WorkoutHistory] = Self.mockHistory
    var personalRecords: [PersonalRecord] = Self.mockPRs

    // MARK: - Trainer AI Response

    private func generateTrainerResponse(_ text: String) -> (content: String, richCard: RichCard?) {
        let lower = text.lowercased()

        if lower.contains("how should i train") || lower.contains("train today") {
            return (
                "Your readiness is at \(readiness.overall)/100 — HRV is \(dailyMetrics.hrv)ms. I've put together an Upper Body Power session that matches your recovery state. Let's get after it.",
                RichCard(type: .workoutPlan, workoutData: WorkoutCardData(
                    name: "Upper Body Power", duration: 55,
                    exercises: [
                        ("Barbell Bench Press", 4, "6-8"),
                        ("Weighted Pull-Ups", 4, "6-8"),
                        ("Overhead Press", 3, "8-10"),
                        ("Barbell Rows", 3, "8-10"),
                    ]
                ))
            )
        }

        if lower.contains("not feeling it") || lower.contains("tired") {
            return (
                "Hey, I hear you — everyone has those days. Let's do a lighter mobility and recovery flow that'll help you bounce back faster for tomorrow.",
                RichCard(type: .workoutPlan, workoutData: WorkoutCardData(
                    name: "Recovery Flow", duration: 30,
                    exercises: [
                        ("Foam Rolling", 1, "5 min"),
                        ("World's Greatest Stretch", 2, "8 each"),
                        ("Band Pull-Aparts", 3, "15"),
                        ("Dead Hangs", 3, "30 sec"),
                    ]
                ))
            )
        }

        if lower.contains("sleep") {
            let latest = sleepData.first!
            let scores = sleepData.prefix(7).reversed().map { Double($0.score) }
            return (
                "Last night you logged \(String(format: "%.1f", latest.totalHours)) hours with \(latest.deepMinutes) minutes of deep sleep. Your sleep quality has been \(latest.score >= 80 ? "trending well" : "a bit uneven lately").",
                RichCard(type: .dataChart, chartData: ChartCardData(
                    title: "Sleep Quality (7-day)",
                    values: Array(scores),
                    insight: "Avg score: \(Int(scores.reduce(0, +) / Double(scores.count)))",
                    color: "3B82F6"
                ))
            )
        }

        if lower.contains("progress") || lower.contains("pr") {
            return (
                "Over the last 4 weeks: 18 workouts completed, 3 new personal records, and recovery consistency up 22%. Your bench went from 205 to 225. The data says you're in a growth phase.",
                RichCard(type: .dataChart, chartData: ChartCardData(
                    title: "Strength Progress (4 weeks)",
                    values: [185, 195, 205, 215, 225],
                    insight: "Bench press: +40 lbs over 4 weeks.",
                    color: "FF4D00"
                ))
            )
        }

        return (
            "Based on your current metrics — \(dailyMetrics.steps) steps today, HRV at \(dailyMetrics.hrv)ms — you're tracking well. Keep the consistency going, \(userProfile.name). What else can I help with?",
            nil
        )
    }
}

// MARK: - Mock Data

extension AppStore {
    static let mockChatMessages: [ChatMessage] = [
        ChatMessage(id: "m1", role: .trainer,
                    content: "Hey Akshith, welcome to Forge. I'm your AI training partner. I've synced up with your Apple Watch and Oura Ring — already pulling in your biometrics. Let's build something serious together.",
                    timestamp: Date(timeIntervalSinceNow: -172800)),
        ChatMessage(id: "m2", role: .user,
                    content: "Excited to get started. I've been training for about 2 years but feel like I've plateaued.",
                    timestamp: Date(timeIntervalSinceNow: -172740)),
        ChatMessage(id: "m3", role: .trainer,
                    content: "Plateaus are normal — and breakable. Your training history shows solid consistency but your programming might need periodization. I'll structure progressive overload cycles. First things first: let's establish your baseline this week.",
                    timestamp: Date(timeIntervalSinceNow: -172680)),
        ChatMessage(id: "m12", role: .trainer,
                    content: "Morning Akshith! Your deep sleep was solid last night — 1hr 42min. HRV is up 12% from yesterday. You're primed for a heavy session today. Ready to hit upper body?",
                    timestamp: Date(timeIntervalSinceNow: -3600)),
        ChatMessage(id: "m13", role: .user,
                    content: "Yeah I'm feeling good today. What's the plan?",
                    timestamp: Date(timeIntervalSinceNow: -3500)),
        ChatMessage(id: "m14", role: .trainer,
                    content: "Love the energy. I've got an Upper Body Power session lined up — bench press, weighted pull-ups, OHP, rows. About 55 minutes, high intensity. Want me to break it down?",
                    timestamp: Date(timeIntervalSinceNow: -3400),
                    richCard: RichCard(type: .workoutPlan, workoutData: WorkoutCardData(
                        name: "Upper Body Power", duration: 55,
                        exercises: [
                            ("Barbell Bench Press", 4, "6-8"),
                            ("Weighted Pull-Ups", 4, "6-8"),
                            ("Overhead Press", 3, "8-10"),
                            ("Barbell Rows", 3, "8-10"),
                            ("Incline DB Press", 3, "10-12"),
                            ("Face Pulls", 3, "15-20"),
                        ]
                    ))),
        ChatMessage(id: "m15", role: .user,
                    content: "Looks perfect. Let's go!",
                    timestamp: Date(timeIntervalSinceNow: -3300)),
    ]

    static let mockSleepData: [SleepData] = [
        SleepData(date: "2026-02-10", totalHours: 7.2, deepMinutes: 102, remMinutes: 95, lightMinutes: 215, awakeMinutes: 20, score: 88),
        SleepData(date: "2026-02-09", totalHours: 6.8, deepMinutes: 78, remMinutes: 88, lightMinutes: 225, awakeMinutes: 17, score: 74),
        SleepData(date: "2026-02-08", totalHours: 7.5, deepMinutes: 110, remMinutes: 100, lightMinutes: 220, awakeMinutes: 20, score: 91),
        SleepData(date: "2026-02-07", totalHours: 6.2, deepMinutes: 65, remMinutes: 72, lightMinutes: 210, awakeMinutes: 25, score: 62),
        SleepData(date: "2026-02-06", totalHours: 7.8, deepMinutes: 115, remMinutes: 105, lightMinutes: 228, awakeMinutes: 20, score: 93),
        SleepData(date: "2026-02-05", totalHours: 7.0, deepMinutes: 88, remMinutes: 92, lightMinutes: 218, awakeMinutes: 22, score: 80),
        SleepData(date: "2026-02-04", totalHours: 6.5, deepMinutes: 72, remMinutes: 80, lightMinutes: 208, awakeMinutes: 30, score: 68),
        SleepData(date: "2026-02-03", totalHours: 7.4, deepMinutes: 98, remMinutes: 96, lightMinutes: 222, awakeMinutes: 18, score: 85),
        SleepData(date: "2026-02-02", totalHours: 6.9, deepMinutes: 82, remMinutes: 84, lightMinutes: 216, awakeMinutes: 32, score: 70),
        SleepData(date: "2026-02-01", totalHours: 7.6, deepMinutes: 108, remMinutes: 102, lightMinutes: 224, awakeMinutes: 22, score: 90),
        SleepData(date: "2026-01-31", totalHours: 5.8, deepMinutes: 55, remMinutes: 65, lightMinutes: 195, awakeMinutes: 33, score: 55),
        SleepData(date: "2026-01-30", totalHours: 7.1, deepMinutes: 95, remMinutes: 90, lightMinutes: 218, awakeMinutes: 23, score: 82),
        SleepData(date: "2026-01-29", totalHours: 7.3, deepMinutes: 100, remMinutes: 94, lightMinutes: 220, awakeMinutes: 24, score: 84),
        SleepData(date: "2026-01-28", totalHours: 6.6, deepMinutes: 70, remMinutes: 78, lightMinutes: 212, awakeMinutes: 36, score: 65),
    ]

    static let mockHistory: [WorkoutHistory] = [
        WorkoutHistory(id: "h1", date: "2026-02-10", name: "Lower Body Strength", type: .strength, duration: 62, volume: 18500, intensity: "high"),
        WorkoutHistory(id: "h2", date: "2026-02-08", name: "HIIT Conditioning", type: .hiit, duration: 30, volume: 0, intensity: "max"),
        WorkoutHistory(id: "h3", date: "2026-02-07", name: "Upper Body Hypertrophy", type: .strength, duration: 58, volume: 22400, intensity: "moderate"),
        WorkoutHistory(id: "h4", date: "2026-02-05", name: "Full Body Power", type: .strength, duration: 65, volume: 24000, intensity: "high"),
        WorkoutHistory(id: "h5", date: "2026-02-03", name: "Cardio + Core", type: .cardio, duration: 45, volume: 0, intensity: "moderate"),
        WorkoutHistory(id: "h6", date: "2026-02-01", name: "Push Day", type: .strength, duration: 52, volume: 19800, intensity: "high"),
        WorkoutHistory(id: "h7", date: "2026-01-31", name: "Pull Day", type: .strength, duration: 55, volume: 21000, intensity: "high"),
        WorkoutHistory(id: "h8", date: "2026-01-29", name: "Leg Day", type: .strength, duration: 60, volume: 26500, intensity: "high"),
    ]

    static let mockPRs: [PersonalRecord] = [
        PersonalRecord(exercise: "Bench Press", value: 225, unit: "lbs", date: "2026-01-28"),
        PersonalRecord(exercise: "Squat", value: 315, unit: "lbs", date: "2026-02-01"),
        PersonalRecord(exercise: "Deadlift", value: 365, unit: "lbs", date: "2026-01-15"),
        PersonalRecord(exercise: "Mile Run", value: 6.45, unit: "min", date: "2026-02-05"),
        PersonalRecord(exercise: "Pull-Ups", value: 18, unit: "reps", date: "2026-02-08"),
    ]
}
