import Foundation
import ForgeCore

/// Gathers everything already on the phone into one `AriaSituationInput`.
///
/// The Dummy's senses, in one place: the live grounding stream (HealthKit /
/// Test-Ready pack), readiness, streak and last session, chronotype, cycle
/// phase (only when the person tracks it), calendar kinds and horizons
/// (never titles), the clock, the conversation thread, and the last cached
/// weather / air read. Names the phone knows are passed along only so the
/// privacy scrub can remove them from any outside query.
///
/// Network-free by design — like `AriaDummyOrchestrator` itself. The weather
/// read arrives as an argument (`AriaWebResearch.cachedEnvironment`).
@MainActor
enum AriaDummyPerception {

    static func input(
        prompt: String,
        store: AppStore,
        grounding: AriaLiveGroundingSnapshot,
        life: AriaLifeRead,
        environment: AriaEnvironmentRead?,
        now: Date = Date()
    ) -> AriaSituationInput {
        let sleepHours: Double? = {
            if let hours = grounding.sleepHours, hours > 0 { return hours }
            if let night = store.sleepData.first, night.totalHours > 0 { return night.totalHours }
            return nil
        }()
        let readiness: Int? = {
            if grounding.readiness > 0 { return grounding.readiness }
            return store.readiness.overall > 0 ? store.readiness.overall : nil
        }()
        let daysSinceWorkout: Int? = {
            if store.todayWorkout != nil, store.workoutHistory.isEmpty { return 0 }
            guard let last = store.workoutHistory.first,
                  let date = WorkoutHistoryWindow.parseDate(last.date) else { return nil }
            return max(0, Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0)
        }()
        let cycle = MenstrualHealthStore.shared
        let cyclePhase = cycle.settings.enabled ? cycle.snapshot.phase.rawValue : nil

        var privateTerms: [String] = []
        let name = store.userProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { privateTerms.append(name) }
        privateTerms.append(contentsOf: AriaPersonRegistry.shared.people.map(\.name))

        var prior = store.chatMessages
            .filter { $0.role == .user }
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let last = prior.last, last.caseInsensitiveCompare(prompt) == .orderedSame {
            prior.removeLast()
        }

        return AriaSituationInput(
            prompt: prompt,
            sleepHours: sleepHours,
            readiness: readiness,
            isOvertrained: false,
            trainingStreak: store.currentStreak,
            daysSinceWorkout: daysSinceWorkout,
            chronotype: HealthKitSleepService.shared.userProfile.chronotype.rawValue,
            localHour: Calendar.current.component(.hour, from: now),
            calendarHorizonTags: life.calendarHorizonTags,
            busyWindowsToday: life.calendarBusyToday,
            cyclePhase: cyclePhase,
            priorPrompts: Array(prior.suffix(4)),
            environment: environment,
            privateTerms: privateTerms
        )
    }
}
