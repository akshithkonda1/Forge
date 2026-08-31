import Foundation

/// One-habit builder feedback — did the breaker work?
/// Stored locally, read by Lifestyle next morning to ask "Did it work? yeah/nah"
/// and fed back into ARIA as an insight so the next breaker shrinks if needed.
public struct TriedHabit: Codable, Equatable, Sendable {
    public var habitId: String
    public var breaker: String
    public var triedAt: Date
    public var feedback: String? // "yeah" / "nah" / nil

    public init(habitId: String, breaker: String, triedAt: Date = Date(), feedback: String? = nil) {
        self.habitId = habitId; self.breaker = breaker; self.triedAt = triedAt; self.feedback = feedback
    }
}

public enum HabitFeedbackStore: Sendable {
    private static let key = "forge.habits.tried.v2"
    private static let feedbackKey = "forge.habits.feedback.v2"

    public static func tried() -> [TriedHabit] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TriedHabit].self, from: data) else { return [] }
        return decoded
    }

    public static func markTried(_ habit: DeepHabit) {
        var all = tried()
        // Don't duplicate same habit same day
        let today = Calendar.current.startOfDay(for: Date())
        if all.contains(where: { $0.habitId == habit.id && Calendar.current.isDate($0.triedAt, inSameDayAs: today) }) { return }
        all.append(TriedHabit(habitId: habit.id, breaker: habit.breaker))
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func pendingFeedback() -> TriedHabit? {
        let all = tried()
        // Most recent tried without feedback, tried yesterday or earlier
        for h in all.reversed() where h.feedback == nil {
            if !Calendar.current.isDateInToday(h.triedAt) { return h }
        }
        return nil
    }

    public static func submitFeedback(habitId: String, answer: String) {
        var all = tried()
        if let idx = all.firstIndex(where: { $0.habitId == habitId && $0.feedback == nil }) {
            all[idx].feedback = answer
            if let data = try? JSONEncoder().encode(all) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    public static func feedbackInsight(for habit: DeepHabit, answer: String) -> String {
        if answer == "yeah" {
            return "Habit breaker worked: \(habit.id) — \(habit.breaker) — user said yeah, keep it."
        } else {
            return "Habit breaker too big: \(habit.id) — \(habit.breaker) — user said nah, next breaker should be smaller (just \(habit.breakerAction.lowercased()) without extra)."
        }
    }
}
