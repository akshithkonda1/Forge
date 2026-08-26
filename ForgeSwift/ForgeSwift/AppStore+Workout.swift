import Foundation
import Combine
import UIKit
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

extension AppStore {

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
        recomputeStreak()

        Task {
            await FeedbackService.shared.processPlanOutcome(
                userId: AriaContextStore.shared.context.userId,
                planId: planId,
                completed: completed
            )
        }
    }

    // MARK: - Chat Actions

    func adoptWorkoutFromRichCard(_ card: RichCardData) {
        guard card.type == .workoutPlan,
              let name = card.workoutName,
              let duration = card.workoutDuration,
              let moves = card.workoutExercises else { return }
        let exercises = moves.enumerated().map { idx, move in
            Exercise(
                id: "aria-live-\(idx)",
                name: move.name,
                sets: move.sets,
                reps: move.reps,
                weight: nil,
                restSeconds: 60,
                notes: nil
            )
        }
        let intensity: WorkoutIntensity = {
            if duration >= 50 { return .high }
            if duration >= 35 { return .moderate }
            return .low
        }()
        todayWorkout = WorkoutPlan(
            id: "aria-today-\(UUID().uuidString.prefix(6))",
            name: name,
            type: .strength,
            duration: duration,
            intensity: intensity,
            exercises: exercises
        )
    }
    
    // MARK: - Data Management

    func recomputeStreak() {
        currentStreak = Self.consecutiveWorkoutStreak(workoutHistory)
    }

    /// A fact about today — not a streak to protect.
    var didTrainToday: Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return workoutHistory.contains { history in
            if let historyDate = ISO8601DateFormatter().date(from: history.date) {
                return cal.isDate(historyDate, inSameDayAs: today)
            }
            if history.date.count >= 10 {
                let f = DateFormatter()
                f.calendar = cal
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd"
                if let historyDate = f.date(from: String(history.date.prefix(10))) {
                    return cal.isDate(historyDate, inSameDayAs: today)
                }
            }
            return false
        }
    }

    private static func consecutiveWorkoutStreak(_ history: [WorkoutHistory], now: Date = Date()) -> Int {
        let cal = Calendar.current
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withInternetDateTime, .withFractionalSeconds]
        let dayFormatter = ISO8601DateFormatter()
        dayFormatter.formatOptions = [.withFullDate]

        func dayStart(_ raw: String) -> Date? {
            if let date = formatter.date(from: raw) ?? dayFormatter.date(from: String(raw.prefix(10))) {
                return cal.startOfDay(for: date)
            }
            if raw.count >= 10 {
                let slice = String(raw.prefix(10))
                let f = DateFormatter()
                f.calendar = cal
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd"
                return f.date(from: slice).map { cal.startOfDay(for: $0) }
            }
            return nil
        }

        let days = Set(history.compactMap { dayStart($0.date) })
        guard !days.isEmpty else { return 0 }
        var cursor = cal.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

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
