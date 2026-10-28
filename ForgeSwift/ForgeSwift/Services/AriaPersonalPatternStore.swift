import Foundation
import ForgeCore

/// On-device pattern ledger. Ingests HealthKit, workouts, sleep, and calendar
/// summaries already on this phone. Never uploads the observations.
@MainActor
final class AriaPersonalPatternStore: ObservableObject {
    static let shared = AriaPersonalPatternStore()

    @Published private(set) var snapshot = AriaPersonalPatternEngine.Snapshot.empty
    @Published private(set) var lastCard: AriaMorningCardBuilder.Card?
    @Published private(set) var lastSafety = ForgeConditionSafety.Decision.none

    private let previousKey = "forge.aria.morning.numbers.v1"
    private let spokenDayKey = "forge.aria.morning.spoken.day.v1"
    private var lastSpokenDay: TimeInterval = 0

    private init() {
        snapshot = AriaPersonalPatternEngine.Store.load()
        lastSpokenDay = UserDefaults.standard.double(forKey: spokenDayKey)
    }

    func refresh(store: AppStore, now: Date = Date(), calendar: Calendar = .current) {
        let observation = Self.observation(from: store, now: now, calendar: calendar)
        snapshot = AriaPersonalPatternEngine.ingest(
            snapshot,
            observation: observation,
            now: now,
            calendar: calendar
        )
        if snapshot.userId.isEmpty {
            snapshot.userId = store.userProfile.name.isEmpty ? "local" : store.userProfile.name
        }
        AriaPersonalPatternEngine.Store.save(snapshot)

        lastSafety = ForgeConditionSafety.decide(
            .init(
                declared: store.userProfile.lifestyleProfile.healthConstraints,
                sleepHours: observation.sleepHours,
                heatRisk: store.lifestyleTagsContainHeat,
                moveNames: store.todayWorkout?.exercises.map(\.name) ?? []
            )
        )

        let numbers = AriaMorningCardBuilder.Numbers(
            sleepHours: observation.sleepHours,
            readiness: store.readiness.hasScore ? store.readiness.overall : nil,
            calendarBusyHours: observation.calendarBusyHours,
            habitCompletion: observation.habitCompletion
        )
        let previous = loadPreviousNumbers()
        let prefs = AriaCompanionPreferencesStore.load()
        lastCard = AriaMorningCardBuilder.build(
            .init(
                numbers: numbers,
                previous: previous,
                gymLabel: Self.gymLabel(store.userProfile.trainingEquipment),
                equipmentNotes: store.userProfile.equipmentNotes,
                patternChanges: snapshot.activeChanges,
                safetyChange: lastSafety.changeNote,
                safetyFlags: lastSafety.flags,
                talkativeness: prefs.talkativeness,
                quietMode: store.quietMode,
                hasLifeSignal: store.hasMeaningfulLifeSignal || observation.sleepHours != nil
            )
        )
        savePreviousNumbers(numbers)
    }

    private func loadPreviousNumbers() -> AriaMorningCardBuilder.Numbers? {
        guard let data = UserDefaults.standard.data(forKey: previousKey),
              let decoded = try? JSONDecoder().decode(StoredNumbers.self, from: data) else {
            return nil
        }
        return decoded.numbers
    }

    private func savePreviousNumbers(_ numbers: AriaMorningCardBuilder.Numbers) {
        let stored = StoredNumbers(numbers: numbers)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: previousKey)
        }
    }

    static func observation(
        from store: AppStore,
        now: Date,
        calendar: Calendar
    ) -> AriaPersonalPatternEngine.Observation {
        let night = SleepData.lastNight(in: store.sleepData, now: now, calendar: calendar)
        let sleepHours = night?.totalHours
            ?? (store.dailyMetrics.totalSleep > 0 ? Double(store.dailyMetrics.totalSleep) / 60.0 : nil)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        let yTrain = store.workoutHistory.first { session in
            guard let date = WorkoutHistoryWindow.parseDate(session.date, calendar: calendar),
                  let yesterday else { return false }
            return calendar.isDate(date, inSameDayAs: yesterday)
        }
        let life = AriaLifeRead.from(tags: AriaContextStore.shared.context.lifestyleTags)
        let habits = LifestyleWellbeingStore.loadHabits()
        let done = habits.filter(\.done).count
        let habitShare = habits.isEmpty ? nil : Double(done) / Double(habits.count)
        let caffeineHour: Int?
        if life.lastNightLate {
            caffeineHour = 16
        } else {
            caffeineHour = nil
        }
        return AriaPersonalPatternEngine.Observation(
            day: now,
            sleepHours: sleepHours,
            sleepQuality: night?.score,
            trainingLoad: yTrain.map { min(1, Double($0.duration) / 60.0) },
            trainingWentWell: yTrain.map { $0.duration >= 20 },
            calendarBusyHours: Double(life.calendarBusyToday),
            habitCompletion: habitShare,
            caffeineHour: caffeineHour,
            calendar: calendar
        )
    }

    /// One spoken morning line, at most once per day, only when a number moved.
    func consumeSpokenLine(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let card = lastCard, card.speak else { return nil }
        let line = card.spokenLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        guard !AriaCoachSpeechGuard.containsBanned(line) else { return nil }
        let day = calendar.startOfDay(for: now).timeIntervalSince1970
        if lastSpokenDay == day { return nil }
        lastSpokenDay = day
        UserDefaults.standard.set(day, forKey: spokenDayKey)
        return line
    }

    func applyConfirm(id: String) {
        snapshot = AriaPersonalPatternEngine.confirm(snapshot, id: id)
        AriaPersonalPatternEngine.Store.save(snapshot)
    }

    func applyCorrect(id: String, note: String) {
        snapshot = AriaPersonalPatternEngine.correct(snapshot, id: id, note: note)
        AriaPersonalPatternEngine.Store.save(snapshot)
    }

    func applyExpire(id: String) {
        snapshot = AriaPersonalPatternEngine.expire(snapshot, id: id)
        AriaPersonalPatternEngine.Store.save(snapshot)
    }

    static func gymLabel(_ equipment: TrainingEquipment) -> String {
        switch equipment {
        case .commercialGym: return "the gym"
        case .homeGym: return "home"
        case .industrialGym: return "the industrial gym"
        case .bodyweight: return "bodyweight"
        case .hotelGym: return "the hotel gym"
        case .crossfitBox: return "the box"
        case .other: return "your setup"
        }
    }
}

private struct StoredNumbers: Codable {
    var sleepHours: Double?
    var readiness: Int?
    var calendarBusyHours: Double?
    var habitCompletion: Double?

    var numbers: AriaMorningCardBuilder.Numbers {
        .init(
            sleepHours: sleepHours,
            readiness: readiness,
            calendarBusyHours: calendarBusyHours,
            habitCompletion: habitCompletion
        )
    }

    init(numbers: AriaMorningCardBuilder.Numbers) {
        sleepHours = numbers.sleepHours
        readiness = numbers.readiness
        calendarBusyHours = numbers.calendarBusyHours
        habitCompletion = numbers.habitCompletion
    }
}

private extension AppStore {
    var lifestyleTagsContainHeat: Bool {
        AriaContextStore.shared.context.lifestyleTags.contains {
            $0.lowercased().contains("heat") || $0.lowercased().contains("hot_day")
        }
    }
}
