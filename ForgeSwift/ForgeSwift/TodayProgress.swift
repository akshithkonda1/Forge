import Foundation

/// Today's Progress — how the day is filling in, not a medical score.
///
/// Home lost the progress ring when the hero became a kinetic readiness field.
/// This snapshot is the day itself: sleep, train, water, movement, habits.
/// Readiness is the vibe chrome around that ring, never a diagnosis.
enum TodayProgress {
    struct Track: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let done: Bool
    }

    struct Snapshot: Equatable {
        var percent: Int
        var completed: Int
        var total: Int
        var tracks: [Track]
        var vibeScore: Int
        var vibeLabel: String
        var vibeLine: String

        var empty: Bool { completed == 0 }
        var remaining: Int { max(0, total - completed) }

        var voiceOverLabel: String {
            if empty {
                return "Today's progress 0 out of 100. Nothing logged yet. Readiness vibe \(vibeScore) out of 100, \(vibeLabel). \(vibeLine)"
            }
            return "Today's progress \(percent) out of 100. \(completed) of \(total) tracks done. Readiness vibe \(vibeScore) out of 100, \(vibeLabel). \(vibeLine)"
        }
    }

    struct Input: Equatable {
        var readiness: Int
        var sleepHours: Double?
        var didTrain: Bool
        var isWorkoutActive: Bool
        var hasSession: Bool
        var waterGlasses: Double
        var steps: Int
        var habitDone: Int
        var habitTotal: Int
        var hasLifeSignal: Bool
    }

    static let trackCount = 5
    static let headerTitle = "TODAY'S PROGRESS"
    static let emptyLine = "Nothing logged yet — that's fine."
    static let bannedPhrases = ["diagnos", "treat", "prescribe", "cure", "medical advice"]

    static func snapshot(_ input: Input) -> Snapshot {
        let sleep = sleepTrack(hours: input.sleepHours)
        let train = trainTrack(
            didTrain: input.didTrain,
            active: input.isWorkoutActive,
            hasSession: input.hasSession
        )
        let water = waterTrack(glasses: input.waterGlasses)
        let move = moveTrack(steps: input.steps)
        let habits = habitTrack(done: input.habitDone, total: input.habitTotal)
        let tracks = [sleep, train, water, move, habits]
        let completed = tracks.filter(\.done).count
        let percent = Int((Double(completed) / Double(tracks.count) * 100).rounded())
        let vibe = min(max(input.readiness, 0), 100)
        return Snapshot(
            percent: percent,
            completed: completed,
            total: tracks.count,
            tracks: tracks,
            vibeScore: vibe,
            vibeLabel: HomeReadiness.label(vibe),
            vibeLine: vibeLine(score: vibe, empty: completed == 0, hasLife: input.hasLifeSignal)
        )
    }

    static func vibeLine(score: Int, empty: Bool, hasLife: Bool) -> String {
        if empty && !hasLife {
            return emptyLine
        }
        switch score {
        case 85...:
            return empty
                ? "You look ready — log the day when you want."
                : "Peak vibe. Keep the day moving, don't overfill it."
        case 70..<85:
            return empty
                ? "Solid vibe. A real session still fits."
                : "Good vibe. Finish what's open, skip the extras."
        case 55..<70:
            return empty
                ? "Fair vibe. Keep today light and honest."
                : "Fair vibe. Protect the easy pieces."
        default:
            return empty
                ? "Low vibe. Easy day is still a day."
                : "Low vibe. Showing up easy still counts."
        }
    }

    private static func sleepTrack(hours: Double?) -> Track {
        if let hours, hours > 0 {
            return Track(
                id: "sleep",
                title: "Sleep",
                detail: String(format: "%.1fh in", hours),
                icon: "moon.fill",
                done: true
            )
        }
        return Track(id: "sleep", title: "Sleep", detail: "Not in yet", icon: "moon.fill", done: false)
    }

    private static func trainTrack(didTrain: Bool, active: Bool, hasSession: Bool) -> Track {
        if didTrain {
            return Track(id: "train", title: "Train", detail: "Logged today", icon: "checkmark", done: true)
        }
        if active {
            return Track(id: "train", title: "Train", detail: "In session", icon: "figure.strengthtraining.traditional", done: true)
        }
        if hasSession {
            return Track(id: "train", title: "Train", detail: "On the board", icon: "dumbbell.fill", done: false)
        }
        return Track(id: "train", title: "Train", detail: "Not yet", icon: "dumbbell.fill", done: false)
    }

    private static func waterTrack(glasses: Double) -> Track {
        if glasses > 0 {
            return Track(
                id: "water",
                title: "Water",
                detail: String(format: "%.1f glasses", glasses),
                icon: "drop.fill",
                done: true
            )
        }
        return Track(id: "water", title: "Water", detail: "Not logged", icon: "drop.fill", done: false)
    }

    private static func moveTrack(steps: Int) -> Track {
        if steps > 0 {
            return Track(id: "move", title: "Move", detail: steps.formatted(), icon: "figure.walk", done: true)
        }
        return Track(id: "move", title: "Move", detail: "No steps yet", icon: "figure.walk", done: false)
    }

    private static func habitTrack(done: Int, total: Int) -> Track {
        if total <= 0 {
            return Track(id: "habits", title: "Habits", detail: "Open Lifestyle", icon: "leaf.fill", done: false)
        }
        if done > 0 {
            return Track(id: "habits", title: "Habits", detail: "\(done)/\(total) done", icon: "leaf.fill", done: true)
        }
        return Track(id: "habits", title: "Habits", detail: "0/\(total) done", icon: "leaf.fill", done: false)
    }
}

@MainActor
extension TodayProgress.Input {
    static func from(store: AppStore, waterGlasses: Double, habits: [DailyHabit]) -> TodayProgress.Input {
        let hours = store.sleepData.first?.totalHours
            ?? (store.dailyMetrics.totalSleep > 0 ? Double(store.dailyMetrics.totalSleep) / 60.0 : nil)
        return TodayProgress.Input(
            readiness: store.readiness.overall,
            sleepHours: hours,
            didTrain: store.didTrainToday,
            isWorkoutActive: store.isWorkoutActive,
            hasSession: store.todayWorkout != nil,
            waterGlasses: waterGlasses,
            steps: store.dailyMetrics.steps,
            habitDone: habits.filter(\.done).count,
            habitTotal: habits.count,
            hasLifeSignal: store.hasMeaningfulLifeSignal
        )
    }
}
