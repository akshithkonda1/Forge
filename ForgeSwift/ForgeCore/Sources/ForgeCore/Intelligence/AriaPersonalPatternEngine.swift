import Foundation

/// Learns *this* person's patterns from sleep, training, calendar, and habits.
///
/// On-device only. A pattern is shown only after a minimum-data bar and a
/// confidence bar. Each visible pattern names the evidence and the change it
/// made. The person can confirm, correct, or let it expire. ARIA never
/// invents a condition from a pattern.
public enum AriaPersonalPatternEngine: Sendable {

    public static let storageKey = "forge.aria.personal.patterns.v1"
    public static let backupExcluded = true
    public static let minSamples = 5
    public static let minConfidence = 0.62
    public static let maxObservations = 90
    public static let expireAfterDays = 21
    public static let confirmedHoldDays = 90

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case lateCaffeineShortSleep
        case shortSleepThenTraining
        case heavyCalendarHabitSlip
        case weekdayTrainingFocus
    }

    public enum Status: String, Codable, CaseIterable, Sendable {
        case candidate
        case surfaced
        case confirmed
        case corrected
        case expired
    }

    public struct Observation: Codable, Equatable, Sendable {
        public var day: Date
        public var sleepHours: Double?
        public var sleepQuality: Int?
        public var trainingLoad: Double?
        public var trainingWentWell: Bool?
        public var calendarBusyHours: Double?
        public var habitCompletion: Double?
        public var caffeineHour: Int?
        public var weekday: Int

        public init(
            day: Date,
            sleepHours: Double? = nil,
            sleepQuality: Int? = nil,
            trainingLoad: Double? = nil,
            trainingWentWell: Bool? = nil,
            calendarBusyHours: Double? = nil,
            habitCompletion: Double? = nil,
            caffeineHour: Int? = nil,
            weekday: Int? = nil,
            calendar: Calendar = .current
        ) {
            self.day = calendar.startOfDay(for: day)
            self.sleepHours = sleepHours
            self.sleepQuality = sleepQuality
            self.trainingLoad = trainingLoad
            self.trainingWentWell = trainingWentWell
            self.calendarBusyHours = calendarBusyHours
            self.habitCompletion = habitCompletion
            self.caffeineHour = caffeineHour
            self.weekday = weekday ?? calendar.component(.weekday, from: day)
        }
    }

    public struct Pattern: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var kind: Kind
        public var title: String
        public var evidence: String
        public var changed: String
        public var confidence: Double
        public var sampleCount: Int
        public var supportingCount: Int
        public var status: Status
        public var createdAt: Date
        public var updatedAt: Date
        public var expiresAt: Date
        public var correction: String

        public var isActive: Bool {
            status == .surfaced || status == .confirmed || status == .candidate
        }

        public var passesBar: Bool {
            sampleCount >= AriaPersonalPatternEngine.minSamples
                && confidence + 0.0001 >= AriaPersonalPatternEngine.minConfidence
        }

        public var isVisible: Bool {
            (status == .surfaced || status == .confirmed) && passesBar
        }

        public init(
            id: String = UUID().uuidString,
            kind: Kind,
            title: String,
            evidence: String,
            changed: String,
            confidence: Double,
            sampleCount: Int,
            supportingCount: Int,
            status: Status = .candidate,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            expiresAt: Date = Date().addingTimeInterval(
                Double(AriaPersonalPatternEngine.expireAfterDays) * 86_400
            ),
            correction: String = ""
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.evidence = evidence
            self.changed = changed
            self.confidence = min(1, max(0, confidence))
            self.sampleCount = max(0, sampleCount)
            self.supportingCount = max(0, supportingCount)
            self.status = status
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.expiresAt = expiresAt
            self.correction = correction
        }
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public var userId: String
        public var observations: [Observation]
        public var patterns: [Pattern]

        public static let empty = Snapshot(userId: "", observations: [], patterns: [])

        public init(
            userId: String = "",
            observations: [Observation] = [],
            patterns: [Pattern] = []
        ) {
            self.userId = userId
            self.observations = observations
            self.patterns = patterns
        }

        public var visible: [Pattern] {
            patterns.filter(\.isVisible).sorted { $0.confidence > $1.confidence }
        }

        public var activeChanges: [String] {
            visible.map(\.changed)
        }
    }

    public struct Store: Sendable {
        public static func load(defaults: UserDefaults = .standard) -> Snapshot {
            guard let data = defaults.data(forKey: AriaPersonalPatternEngine.storageKey),
                  let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) else {
                return .empty
            }
            return decoded
        }

        public static func save(_ snap: Snapshot, defaults: UserDefaults = .standard) {
            if let data = try? JSONEncoder().encode(snap) {
                defaults.set(data, forKey: AriaPersonalPatternEngine.storageKey)
            }
        }
    }

    // MARK: - Mutating API

    public static func ingest(
        _ snap: Snapshot,
        observation: Observation,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Snapshot {
        var next = snap
        let day = calendar.startOfDay(for: observation.day)
        next.observations.removeAll { calendar.startOfDay(for: $0.day) == day }
        next.observations.append(observation)
        next.observations.sort { $0.day < $1.day }
        if next.observations.count > maxObservations {
            next.observations = Array(next.observations.suffix(maxObservations))
        }
        return learn(next, now: now, calendar: calendar)
    }

    public static func confirm(
        _ snap: Snapshot,
        id: String,
        now: Date = Date()
    ) -> Snapshot {
        mutate(snap, id: id, now: now) { pattern in
            pattern.status = .confirmed
            pattern.expiresAt = now.addingTimeInterval(Double(confirmedHoldDays) * 86_400)
        }
    }

    public static func correct(
        _ snap: Snapshot,
        id: String,
        note: String,
        now: Date = Date()
    ) -> Snapshot {
        mutate(snap, id: id, now: now) { pattern in
            pattern.status = .corrected
            pattern.correction = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
            pattern.expiresAt = now
        }
    }

    public static func expire(
        _ snap: Snapshot,
        id: String,
        now: Date = Date()
    ) -> Snapshot {
        mutate(snap, id: id, now: now) { pattern in
            pattern.status = .expired
            pattern.expiresAt = now
        }
    }

    public static func learn(
        _ snap: Snapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Snapshot {
        var next = snap
        next.patterns = next.patterns.map { pattern in
            var copy = pattern
            if copy.status == .confirmed { return copy }
            if copy.status == .corrected { return copy }
            if copy.expiresAt <= now {
                copy.status = .expired
            }
            return copy
        }

        let drafts = [
            detectLateCaffeine(next.observations, now: now),
            detectShortSleepTraining(next.observations, now: now, calendar: calendar),
            detectHeavyCalendarHabits(next.observations, now: now),
            detectWeekdayFocus(next.observations, now: now, calendar: calendar),
        ].compactMap { $0 }

        for draft in drafts {
            if let index = next.patterns.firstIndex(where: { $0.kind == draft.kind }) {
                var existing = next.patterns[index]
                if existing.status == .corrected || existing.status == .expired {
                    continue
                }
                existing.title = draft.title
                existing.evidence = draft.evidence
                existing.changed = draft.changed
                existing.confidence = draft.confidence
                existing.sampleCount = draft.sampleCount
                existing.supportingCount = draft.supportingCount
                existing.updatedAt = now
                if existing.status == .candidate, draft.passesBar {
                    existing.status = .surfaced
                    existing.expiresAt = now.addingTimeInterval(Double(expireAfterDays) * 86_400)
                }
                next.patterns[index] = existing
            } else {
                var fresh = draft
                if fresh.passesBar {
                    fresh.status = .surfaced
                }
                next.patterns.append(fresh)
            }
        }
        return next
    }

    /// Computed facts a remote model may see — never raw HealthKit samples.
    public static func remoteFacts(_ snap: Snapshot) -> [String] {
        snap.visible.map { pattern in
            "pattern:\(pattern.kind.rawValue):\(slug(pattern.changed))"
        }
    }

    public static func containsBannedSpeech(_ text: String) -> Bool {
        AriaCoachSpeechGuard.containsBanned(text)
    }

    // MARK: - Detectors

    private static func detectLateCaffeine(
        _ observations: [Observation],
        now: Date
    ) -> Pattern? {
        let rows = observations.filter { $0.caffeineHour != nil && $0.sleepHours != nil }
        let late = rows.filter { ($0.caffeineHour ?? 0) >= 15 }
        guard late.count >= minSamples else { return nil }
        let supporting = late.filter { ($0.sleepHours ?? 9) < 6.5 }
        let confidence = Double(supporting.count) / Double(late.count)
        guard supporting.count >= 3 else { return nil }
        let worst = supporting.compactMap(\.sleepHours).sorted().prefix(3)
        let title = "Late caffeine came before your \(supporting.count) worst nights"
        let evidence = "\(supporting.count) of \(late.count) nights after coffee after 3 PM ran short"
            + (worst.isEmpty ? "." : String(format: " (down to %.1fh).", worst.first ?? 0))
        let changed = "Coffee moves before 1 PM today"
        return make(
            kind: .lateCaffeineShortSleep,
            title: title,
            evidence: evidence,
            changed: changed,
            confidence: confidence,
            sampleCount: late.count,
            supportingCount: supporting.count,
            now: now
        )
    }

    private static func detectShortSleepTraining(
        _ observations: [Observation],
        now: Date,
        calendar: Calendar
    ) -> Pattern? {
        let sorted = observations.sorted { $0.day < $1.day }
        var pairs = 0
        var supporting = 0
        var shortHours: [Double] = []
        for index in sorted.indices.dropLast() {
            let night = sorted[index]
            let nextDay = sorted[index + 1]
            guard let hours = night.sleepHours, nextDay.trainingWentWell != nil else { continue }
            let gap = calendar.dateComponents([.day], from: night.day, to: nextDay.day).day ?? 0
            guard gap == 1 else { continue }
            pairs += 1
            if hours < 6.5, nextDay.trainingWentWell == false {
                supporting += 1
                shortHours.append(hours)
            }
        }
        guard pairs >= minSamples else { return nil }
        let confidence = Double(supporting) / Double(pairs)
        guard supporting >= 3 else { return nil }
        let avg = shortHours.isEmpty ? 0 : shortHours.reduce(0, +) / Double(shortHours.count)
        let title = "Short sleep came before harder training days"
        let evidence = String(
            format: "%d of %d sessions after a short night felt off (avg %.1fh).",
            supporting, pairs, avg
        )
        let changed = "Today's session stays easier after a short night"
        return make(
            kind: .shortSleepThenTraining,
            title: title,
            evidence: evidence,
            changed: changed,
            confidence: confidence,
            sampleCount: pairs,
            supportingCount: supporting,
            now: now
        )
    }

    private static func detectHeavyCalendarHabits(
        _ observations: [Observation],
        now: Date
    ) -> Pattern? {
        let rows = observations.filter { $0.calendarBusyHours != nil && $0.habitCompletion != nil }
        let heavy = rows.filter { ($0.calendarBusyHours ?? 0) >= 4 }
        guard heavy.count >= minSamples else { return nil }
        let supporting = heavy.filter { ($0.habitCompletion ?? 1) < 0.5 }
        let confidence = Double(supporting.count) / Double(heavy.count)
        guard supporting.count >= 3 else { return nil }
        let title = "Habits slip in heavy calendar weeks"
        let evidence = "\(supporting.count) of \(heavy.count) busy days left habits under half done."
        let changed = "Habits shrink to one check-in on a packed day"
        return make(
            kind: .heavyCalendarHabitSlip,
            title: title,
            evidence: evidence,
            changed: changed,
            confidence: confidence,
            sampleCount: heavy.count,
            supportingCount: supporting.count,
            now: now
        )
    }

    private static func detectWeekdayFocus(
        _ observations: [Observation],
        now: Date,
        calendar: Calendar
    ) -> Pattern? {
        let todayWeekday = calendar.component(.weekday, from: now)
        let rows = observations.filter { $0.weekday == todayWeekday && $0.trainingLoad != nil }
        guard rows.count >= minSamples else { return nil }
        let trained = rows.filter { ($0.trainingLoad ?? 0) >= 0.4 }
        let confidence = Double(trained.count) / Double(rows.count)
        guard trained.count >= 3 else { return nil }
        let name = calendar.weekdaySymbols[todayWeekday - 1]
        let title = "\(name) is usually a training day"
        let evidence = "\(trained.count) of \(rows.count) \(name)s had a real session."
        let changed = "Keep today's session on the calendar"
        return make(
            kind: .weekdayTrainingFocus,
            title: title,
            evidence: evidence,
            changed: changed,
            confidence: confidence,
            sampleCount: rows.count,
            supportingCount: trained.count,
            now: now
        )
    }

    private static func make(
        kind: Kind,
        title: String,
        evidence: String,
        changed: String,
        confidence: Double,
        sampleCount: Int,
        supportingCount: Int,
        now: Date
    ) -> Pattern? {
        let pattern = Pattern(
            kind: kind,
            title: title,
            evidence: evidence,
            changed: changed,
            confidence: confidence,
            sampleCount: sampleCount,
            supportingCount: supportingCount,
            status: .candidate,
            createdAt: now,
            updatedAt: now,
            expiresAt: now.addingTimeInterval(Double(expireAfterDays) * 86_400)
        )
        if containsBannedSpeech(pattern.title)
            || containsBannedSpeech(pattern.evidence)
            || containsBannedSpeech(pattern.changed) {
            return nil
        }
        return pattern
    }

    private static func mutate(
        _ snap: Snapshot,
        id: String,
        now: Date,
        _ body: (inout Pattern) -> Void
    ) -> Snapshot {
        var next = snap
        guard let index = next.patterns.firstIndex(where: { $0.id == id }) else { return snap }
        var pattern = next.patterns[index]
        body(&pattern)
        pattern.updatedAt = now
        next.patterns[index] = pattern
        return next
    }

    private static func slug(_ text: String) -> String {
        let allowed = text.lowercased().map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : "_"
        }
        let collapsed = String(allowed)
            .split(separator: "_")
            .joined(separator: "_")
        return String(collapsed.prefix(48))
    }
}
