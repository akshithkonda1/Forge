import Foundation

/// Hobby Fit v1. Mentality is derived from the hobby path already computed
/// (social band, people-energy, working tendency). The enum stays on the
/// structured field. Speech uses the speak phrase only.
///
/// Lifestyle coach. Not a diagnosis. A dismissal is never cited.
public enum HobbyFit {

    public enum Signal: String, Codable, Sendable, Equatable {
        case quiet
        case open
        case drainedSocial = "drained_social"
        case restored
    }

    public enum Kind: String, Codable, Sendable, Equatable {
        case creative, social, outdoor, solo, learning
    }

    public enum Interest: String, Codable, Sendable, Equatable {
        case low, medium, high
    }

    public struct Hobby: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var label: String
        public var kind: Kind
        public var interest: Interest
        public var lastEngagedAt: String?

        public init(
            id: String,
            label: String,
            kind: Kind,
            interest: Interest,
            lastEngagedAt: String? = nil
        ) {
            self.id = id
            self.label = label
            self.kind = kind
            self.interest = interest
            self.lastEngagedAt = lastEngagedAt
        }
    }

    /// Gentle free-day trend — never a shaming score.
    public struct LifestyleTime: Codable, Equatable, Sendable {
        public var engagedThisWeek: Int
        public var trend: String
        public var line: String

        public init(engagedThisWeek: Int, trend: String, line: String) {
            self.engagedThisWeek = engagedThisWeek
            self.trend = trend
            self.line = line
        }
    }

    public struct DayContribution: Equatable, Sendable {
        public var habitWins: Int
        public var moveMinutes: Double
        public var trainSessions: Int
        public var mosaicTrack: StatsMosaic.Track?

        public init(
            habitWins: Int = 0,
            moveMinutes: Double = 0,
            trainSessions: Int = 0,
            mosaicTrack: StatsMosaic.Track? = nil
        ) {
            self.habitWins = habitWins
            self.moveMinutes = moveMinutes
            self.trainSessions = trainSessions
            self.mosaicTrack = mosaicTrack
        }
    }

    public struct SuggestionLog: Codable, Equatable, Sendable {
        public var accepted: [String]
        public var ignored: [String]
        public var cooldownUntil: [String: String]

        public static let storageKey = "forge.hobby.suggestionLog.v1"

        public init(
            accepted: [String] = [],
            ignored: [String] = [],
            cooldownUntil: [String: String] = [:]
        ) {
            self.accepted = accepted
            self.ignored = ignored
            self.cooldownUntil = cooldownUntil
        }
    }

    public struct LabeledSuggestion: Equatable, Sendable, Identifiable {
        public var id: String { hobby.id }
        public var hobby: Hobby
        public var why: String
        public var firstStep: String
        public var cooldownLine: String

        public init(hobby: Hobby, why: String, firstStep: String, cooldownLine: String = "") {
            self.hobby = hobby
            self.why = why
            self.firstStep = firstStep
            self.cooldownLine = cooldownLine
        }
    }

    public struct WorkoutHint: Equatable, Sendable {
        public var name: String
        public var type: String
        public var dateISO: String

        public init(name: String, type: String, dateISO: String) {
            self.name = name
            self.type = type
            self.dateISO = dateISO
        }
    }

    public struct LiveSignals: Equatable, Sendable {
        public var calendarEventsToday: Int?
        public var sleepHoursLastNight: Double?
        public var sleepHoursTypical: Double?
        public var hrvTrend: Double?
        public var activityMinutesToday: Double?
        public var hour: Int?
        public var conversation: [String]
        public var previous: Signal?
        public var previousAgeHours: Double?

        public static let empty = LiveSignals()

        public init(
            calendarEventsToday: Int? = nil,
            sleepHoursLastNight: Double? = nil,
            sleepHoursTypical: Double? = nil,
            hrvTrend: Double? = nil,
            activityMinutesToday: Double? = nil,
            hour: Int? = nil,
            conversation: [String] = [],
            previous: Signal? = nil,
            previousAgeHours: Double? = nil
        ) {
            self.calendarEventsToday = calendarEventsToday
            self.sleepHoursLastNight = sleepHoursLastNight
            self.sleepHoursTypical = sleepHoursTypical
            self.hrvTrend = hrvTrend
            self.activityMinutesToday = activityMinutesToday
            self.hour = hour
            self.conversation = conversation
            self.previous = previous
            self.previousAgeHours = previousAgeHours
        }
    }

    public struct Reading: Equatable, Sendable {
        public var signal: Signal
        public var confidence: Double
        public var speak: String
        public var sources: Int

        public init(signal: Signal, confidence: Double, speak: String, sources: Int) {
            self.signal = signal
            self.confidence = min(1, max(0, confidence))
            self.speak = speak
            self.sources = sources
        }
    }

    public static func signal(
        socialBand: HobbyPathEngine.SocialBand,
        peopleEnergy: HobbyPathEngine.PeopleEnergy,
        working: UserWorkingModel.Snapshot
    ) -> Signal {
        if socialBand == .burnedOut { return .drainedSocial }
        if socialBand == .reserved { return .quiet }
        if working.tendency == .rebuilding || working.stance == .rebuildTrust {
            return .restored
        }
        if peopleEnergy == .open || socialBand == .sociable { return .open }
        if peopleEnergy == .thin,
           working.predictedFeel == .flat
            || working.tendency == .overreacher
            || working.tendency == .weekendDrop {
            return .drainedSocial
        }
        if peopleEnergy == .thin { return .quiet }
        return .restored
    }

    public static func speak(_ signal: Signal) -> String {
        switch signal {
        case .quiet: return "quiet stretch"
        case .open: return "up for a little more"
        case .drainedSocial: return "lots on lately"
        case .restored: return "a calmer patch"
        }
    }

    public static func canonLine(
        signal: Signal,
        curious: Bool = false,
        skipGroups: Bool = false
    ) -> String {
        if signal == .drainedSocial, skipGroups {
            return "You've had a lot on. Want me to skip group stuff for now and pick one quiet thing for tonight?"
        }
        if signal == .quiet, curious {
            return "Quiet stretch lately, and honestly it suits you. If you get curious, pottery nights tend to be small, and nobody judges a lumpy bowl. No pressure either way."
        }
        switch signal {
        case .quiet:
            return "It's been a quieter stretch. Want to try something low-key with one other person this week, or keep it solo for now? Both count."
        case .drainedSocial:
            return "Lots on lately. Something solo might hit better tonight, like cooking just for you, a good book or a headphones walk."
        case .open:
            return "Up for a little more, if you want it. A small plan with one person counts — so does keeping it light."
        case .restored:
            return "A calmer patch. Keep the free-day you already like, or leave the calendar alone. Both count."
        }
    }

    /// Only after a cool-down. Dismissals use ``dismissalLine``.
    public static func coolDownLine(label: String) -> String {
        guard let clean = sanitizeLabel(label) else { return "" }
        if clean.lowercased() == "hike club" {
            return "Hike club's still around if you ever want another look. It's not going anywhere."
        }
        return "\(clean)'s still around if you ever want another look. It's not going anywhere."
    }

    /// A dismissal never counts against the user and is never cited.
    public static func dismissalLine(label: String) -> String {
        _ = label
        return ""
    }

    public static func hobbies(from living: [LivingHobby]) -> [Hobby] {
        var out: [Hobby] = []
        var seen: Set<String> = []
        for hobby in living {
            guard out.count < 8 else { break }
            let id = hobby.rawValue
            if seen.contains(id) { continue }
            seen.insert(id)
            let kind: Kind
            let interest: Interest
            switch hobby {
            case .cooking, .making, .music:
                kind = .creative
                interest = .medium
            case .outdoors:
                kind = .outdoor
                interest = .medium
            case .gym:
                // Gym is training / people-energy, not a restorative solo hobby.
                kind = .social
                interest = .medium
            case .reading, .games:
                kind = .solo
                interest = .medium
            case .rest:
                kind = .solo
                interest = .low
            }
            out.append(Hobby(id: id, label: hobby.title, kind: kind, interest: interest))
        }
        return out
    }

    public static func normalize(
        label raw: String,
        id hinted: String? = nil,
        kind rawKind: String? = nil,
        interest rawInterest: String? = nil,
        lastEngagedAt: String? = nil
    ) -> Hobby? {
        guard let label = sanitizeLabel(raw) else { return nil }
        let slug = slugify(label)
        let id: String
        if let hinted, hinted.range(of: "^[a-z0-9_]{1,32}$", options: .regularExpression) != nil {
            id = hinted
        } else {
            id = slug
        }
        guard !id.isEmpty else { return nil }
        let kind = Kind(rawValue: rawKind ?? "") ?? inferredKind(label)
        let interest = Interest(rawValue: rawInterest ?? "") ?? .medium
        let engaged = validDate(lastEngagedAt)
        return Hobby(id: id, label: label, kind: kind, interest: interest, lastEngagedAt: engaged)
    }

    public static func speechIsClean(_ text: String) -> Bool {
        let lower = text.lowercased()
        let banned = [
            "introvert", "isolated", "anxious", "feeling steadier",
            "social tank", "restorative", "energy's higher",
            "drained_social", "mentality_signal",
        ]
        if banned.contains(where: { lower.contains($0) }) { return false }
        if lower.range(of: #"\brestored\b"#, options: .regularExpression) != nil { return false }
        return true
    }

    static func sanitizeLabel(_ raw: String) -> String? {
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        if collapsed.contains("@") || collapsed.contains("http") || collapsed.contains(where: \.isNumber) {
            return nil
        }
        let kept = collapsed.split(separator: " ").filter { token in
            let lower = token.lowercased()
            return !lower.hasPrefix("partner_") && !lower.hasPrefix("cycle:")
                && !lower.hasPrefix("support_cycle:")
        }
        var text = kept.joined(separator: " ")
        if text.count > 48 { text = String(text.prefix(48)).trimmingCharacters(in: .whitespaces) }
        guard !text.isEmpty else { return nil }
        return text
    }

    private static func slugify(_ label: String) -> String {
        let lowered = label.lowercased()
        let mapped = lowered.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : "_"
        }
        let slug = String(mapped).split(separator: "_").joined(separator: "_")
        return String(slug.prefix(32))
    }

    private static func inferredKind(_ label: String) -> Kind {
        let lower = label.lowercased()
        if ["hike", "trail", "outdoor", "outside", "walk"].contains(where: { lower.contains($0) }) {
            return .outdoor
        }
        if ["class", "course", "learn", "study", "language"].contains(where: { lower.contains($0) }) {
            return .learning
        }
        if ["club", "group", "team", "friends", "gym"].contains(where: { lower.contains($0) }) {
            return .social
        }
        if ["yoga", "read", "book", "solo", "alone", "home"].contains(where: { lower.contains($0) }) {
            return .solo
        }
        if ["dance"].contains(where: { lower.contains($0) }) {
            return .social
        }
        if ["garden"].contains(where: { lower.contains($0) }) {
            return .outdoor
        }
        return .creative
    }

    private static func validDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard raw.range(
            of: #"^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2})?Z?)?$"#,
            options: .regularExpression
        ) != nil else { return nil }
        return raw
    }

    /// Port of Python `normalize_hobbies`. Strings or labeled rows; bad rows drop.
    public static func normalizeHobbies(_ raw: [Hobby]) -> [Hobby] {
        var out: [Hobby] = []
        var seen: Set<String> = []
        for item in raw {
            guard let clean = normalize(
                label: item.label,
                id: item.id,
                kind: item.kind.rawValue,
                interest: item.interest.rawValue,
                lastEngagedAt: item.lastEngagedAt
            ) else { continue }
            if seen.contains(clean.id) { continue }
            seen.insert(clean.id)
            out.append(clean)
            if out.count >= 8 { break }
        }
        return out
    }

    public static func normalizeHobbies(labels: [String]) -> [Hobby] {
        var out: [Hobby] = []
        var seen: Set<String> = []
        for label in labels {
            guard let hobby = normalize(label: label), !seen.contains(hobby.id) else { continue }
            seen.insert(hobby.id)
            out.append(hobby)
            if out.count >= 8 { break }
        }
        return out
    }

    public static func reading(
        socialBand: HobbyPathEngine.SocialBand,
        peopleEnergy: HobbyPathEngine.PeopleEnergy,
        working: UserWorkingModel.Snapshot,
        live: LiveSignals = .empty
    ) -> Reading {
        var signal = Self.signal(socialBand: socialBand, peopleEnergy: peopleEnergy, working: working)
        var votes: [Signal: Int] = [signal: 1]
        var sources = 1

        if let events = live.calendarEventsToday {
            sources += 1
            if events >= 5 { votes[.drainedSocial, default: 0] += 1 }
            else if events <= 1 { votes[.quiet, default: 0] += 1 }
        }
        if let night = live.sleepHoursLastNight, let typical = live.sleepHoursTypical, typical > 0 {
            sources += 1
            if night + 0.8 < typical { votes[.quiet, default: 0] += 1 }
        }
        if let hrv = live.hrvTrend {
            sources += 1
            if hrv <= -8 { votes[.quiet, default: 0] += 1 }
            else if hrv >= 5 { votes[.open, default: 0] += 1 }
        }
        if let minutes = live.activityMinutesToday, minutes >= 90, peopleEnergy == .thin {
            sources += 1
            votes[.drainedSocial, default: 0] += 1
        }
        if let hour = live.hour, hour >= 21, signal == .drainedSocial || signal == .quiet {
            sources += 1
            votes[signal, default: 0] += 1
        }
        let blob = live.conversation.joined(separator: " ").lowercased()
        if blob.contains("too many people") || blob.contains("need a night in") || blob.contains("lots on") {
            sources += 1
            votes[.drainedSocial, default: 0] += 1
        }
        if blob.contains("wanna go out") || blob.contains("up for") || blob.contains("have people over") {
            sources += 1
            votes[.open, default: 0] += 1
        }
        if let previous = live.previous, let age = live.previousAgeHours, age < 18 {
            votes[previous, default: 0] += 1
            sources += 1
        } else if let previous = live.previous, let age = live.previousAgeHours, age >= 36 {
            _ = previous
            sources += 1
        }

        if let top = votes.max(by: { $0.value < $1.value }) {
            signal = top.key
        }
        let confidence = min(0.92, 0.28 + 0.12 * Double(min(sources, 5)))
        return Reading(signal: signal, confidence: confidence, speak: speak(signal), sources: sources)
    }

    public static func lifestyleTime(
        hobbies: [Hobby],
        nowISODay: String,
        weekDays: [String]
    ) -> LifestyleTime {
        let engaged = hobbies.filter { hobby in
            guard let day = hobby.lastEngagedAt.map({ String($0.prefix(10)) }) else { return false }
            return weekDays.contains(day) || day == nowISODay
        }
        let count = engaged.count
        let trend: String
        if count == 0 { trend = "quieter" }
        else if count >= 3 { trend = "fuller" }
        else { trend = "steady" }
        let line: String
        switch trend {
        case "fuller":
            line = "A few free-day hours landed this week. That counts."
        case "steady":
            line = "A free day showed up. Both a walk and a night in count."
        default:
            line = "No free-day hours logged yet. The week is still open — not a verdict."
        }
        return LifestyleTime(engagedThisWeek: count, trend: trend, line: line)
    }

    public static func dayContribution(
        hobbies: [Hobby],
        todayISO: String
    ) -> DayContribution {
        var habit = 0
        var minutes = 0.0
        var train = 0
        var track: StatsMosaic.Track?
        for hobby in hobbies {
            let day = hobby.lastEngagedAt.map { String($0.prefix(10)) }
            guard day == todayISO else { continue }
            switch hobby.kind {
            case .outdoor:
                minutes += 20
                track = track ?? .move
            case .social where hobby.id == "gym":
                train += 1
                track = track ?? .train
            case .creative, .solo, .learning, .social:
                habit += 1
                track = track ?? .habits
            }
        }
        return DayContribution(
            habitWins: habit,
            moveMinutes: minutes,
            trainSessions: train,
            mosaicTrack: track
        )
    }

    public static func applyToMosaic(_ input: StatsMosaic.Input, contribution: DayContribution) -> StatsMosaic.Input {
        var next = input
        if contribution.habitWins > 0 {
            next.habitsDone += contribution.habitWins
        }
        if contribution.moveMinutes > 0, next.steps == nil {
            next.steps = Int(contribution.moveMinutes * 80)
            next.stepsManual = true
        }
        if contribution.trainSessions > 0 {
            next.workoutsThisWeek += contribution.trainSessions
        }
        return next
    }

    public static func engage(fromWorkouts workouts: [WorkoutHint], existing: [Hobby]) -> [Hobby] {
        // `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key. Home
        // concatenates persona chips + lifestyle-profile rows; both catalogs
        // use `LivingHobby.outdoors` → id "outdoors". Keep the first row.
        var byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for workout in workouts {
            guard let mapped = hobby(fromWorkout: workout) else { continue }
            if var current = byId[mapped.id] {
                if current.lastEngagedAt == nil || (mapped.lastEngagedAt ?? "") > (current.lastEngagedAt ?? "") {
                    current.lastEngagedAt = mapped.lastEngagedAt
                    byId[mapped.id] = current
                }
            } else {
                byId[mapped.id] = mapped
            }
        }
        return Array(byId.values).sorted { $0.label < $1.label }
    }

    public static func hobby(fromWorkout workout: WorkoutHint) -> Hobby? {
        let blob = (workout.name + " " + workout.type).lowercased()
        let date = validDate(workout.dateISO)
        if blob.contains("hike") || blob.contains("trail") {
            return Hobby(id: "outdoors", label: LivingHobby.outdoors.title, kind: .outdoor, interest: .medium, lastEngagedAt: date)
        }
        if blob.contains("walk") {
            return Hobby(id: "outdoors", label: LivingHobby.outdoors.title, kind: .outdoor, interest: .medium, lastEngagedAt: date)
        }
        if blob.contains("garden") {
            return normalize(label: "Gardening", kind: "outdoor", lastEngagedAt: date)
        }
        if blob.contains("yoga") || workout.type.lowercased() == "yoga" {
            return normalize(label: "Yoga", kind: "solo", lastEngagedAt: date)
        }
        if blob.contains("dance") {
            return normalize(label: "Dance", kind: "social", lastEngagedAt: date)
        }
        if blob.contains("gym") {
            return Hobby(id: "gym", label: LivingHobby.gym.title, kind: .social, interest: .medium, lastEngagedAt: date)
        }
        return nil
    }

    public static func rememberAccepted(_ log: SuggestionLog, id: String, nowISO: String) -> SuggestionLog {
        var next = log
        if !next.accepted.contains(id) { next.accepted.append(id) }
        next.ignored.removeAll { $0 == id }
        next.cooldownUntil[id] = nil
        _ = nowISO
        return next
    }

    public static func rememberIgnored(_ log: SuggestionLog, id: String, cooldownUntil: String) -> SuggestionLog {
        var next = log
        if !next.ignored.contains(id) { next.ignored.append(id) }
        next.cooldownUntil[id] = cooldownUntil
        return next
    }

    public static func shouldOffer(id: String, log: SuggestionLog, todayISO: String) -> Bool {
        if let until = log.cooldownUntil[id], until > todayISO { return false }
        return true
    }

    public static func suggestions(
        hobbies: [Hobby],
        path: HobbyPathEngine.Path,
        mentality: Signal,
        keepLight: Bool,
        log: SuggestionLog = SuggestionLog(),
        todayISO: String = ""
    ) -> [LabeledSuggestion] {
        let preferredKinds: [Kind]
        switch path {
        case .openGently:
            preferredKinds = [.creative, .outdoor, .learning]
        case .restoreQuiet:
            preferredKinds = [.solo, .creative]
        case .keepRhythm:
            preferredKinds = hobbies.map(\.kind)
        case .explore:
            preferredKinds = [.solo, .creative, .outdoor]
        }
        var picked: [Hobby] = hobbies.filter { preferredKinds.contains($0.kind) && shouldOffer(id: $0.id, log: log, todayISO: todayISO) }
        if keepLight || mentality == .drainedSocial {
            picked.removeAll { $0.id == "gym" }
        }
        if picked.isEmpty {
            picked = hobbies.filter { shouldOffer(id: $0.id, log: log, todayISO: todayISO) }
        }
        return picked.prefix(3).map { hobby in
            let cooled = log.ignored.contains(hobby.id) && (log.cooldownUntil[hobby.id].map { $0 <= todayISO } ?? false)
            return LabeledSuggestion(
                hobby: hobby,
                why: "Fits how you actually spend a free day.",
                firstStep: "Do the smallest version once this week.",
                cooldownLine: cooled ? coolDownLine(label: hobby.label) : ""
            )
        }
    }

    public static func homePreview(
        path: HobbyPathEngine.Path,
        speak: String,
        time: LifestyleTime
    ) -> String {
        "\(pathHeadline(path)) — \(speak). \(time.line)"
    }

    public static func pathHeadline(_ path: HobbyPathEngine.Path) -> String {
        switch path {
        case .openGently: return "A hobby you can start alone"
        case .restoreQuiet: return "Quieter is the work this week"
        case .keepRhythm: return "Keep the free-day you already like"
        case .explore: return "The healthiest version of you isn't only fitter"
        }
    }

    public static func chipToggle(selected: [String], tapping: String, cap: Int = 3) -> [String] {
        var next = selected
        if let idx = next.firstIndex(of: tapping) {
            next.remove(at: idx)
            return next
        }
        guard next.count < cap else { return next }
        next.append(tapping)
        return next
    }
}
