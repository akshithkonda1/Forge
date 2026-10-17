import Foundation

/// Whole-life profile Forge adapts to — movement is one pillar, not the product.
///
/// Weights, goals, routine, constraints, plus optional social / relational
/// and health-constraint fields. Built from onboarding, ARIA conversation,
/// and HealthKit; editable, skippable, deletable. On-device first.
/// Health conditions and relationship data are never sold, never used for
/// ads, and are redacted from server context unless the user opts in
/// (Rowan / `apply_permissions` pattern).
public enum ForgeLifestyleProfile: Sendable {

    public static let storageKey = "forge.lifestyle.profile.v1"

    public enum Pillar: String, Codable, CaseIterable, Sendable {
        case movement, sleep, nutrition, mind, habits

        public var label: String {
            switch self {
            case .movement: return "Movement"
            case .sleep: return "Sleep"
            case .nutrition: return "Nutrition"
            case .mind: return "Stress & mind"
            case .habits: return "Habits"
            }
        }

        public var mosaicTrack: StatsMosaic.Track? {
            switch self {
            case .sleep: return .sleep
            case .movement: return .move
            case .nutrition: return .water
            case .habits: return .habits
            case .mind: return nil
            }
        }
    }

    public enum RelationshipStatus: String, Codable, CaseIterable, Sendable {
        case single, partnered, married, complicated, skipped

        public var label: String {
            switch self {
            case .single: return "Single"
            case .partnered: return "In a relationship"
            case .married: return "Married"
            case .complicated: return "It's complicated"
            case .skipped: return "Skipped"
            }
        }
    }

    public struct SocialLife: Codable, Equatable, Sendable {
        public var goesOut: Bool?
        public var drinks: Bool?
        public var parties: Bool?
        public var closeFriends: Bool?
        public var note: String

        public init(
            goesOut: Bool? = nil,
            drinks: Bool? = nil,
            parties: Bool? = nil,
            closeFriends: Bool? = nil,
            note: String = ""
        ) {
            self.goesOut = goesOut
            self.drinks = drinks
            self.parties = parties
            self.closeFriends = closeFriends
            self.note = note
        }

        public var isEmpty: Bool {
            goesOut == nil && drinks == nil && parties == nil && closeFriends == nil && note.isEmpty
        }
    }

    public enum HealthConstraint: String, Codable, CaseIterable, Sendable {
        case seizures, epilepsy, adhd, anxiety, injury, chronic, mobility, other

        public var label: String {
            switch self {
            case .seizures: return "Seizures"
            case .epilepsy: return "Epilepsy"
            case .adhd: return "ADHD"
            case .anxiety: return "Anxiety"
            case .injury: return "Injury"
            case .chronic: return "Chronic condition"
            case .mobility: return "Mobility"
            case .other: return "Other"
            }
        }

        /// Safer activity framing. Never identity.
        public var saferFraming: String {
            switch self {
            case .seizures, .epilepsy:
                return "Keep sessions grounded and predictable. No medical advice — if anything feels off, run it past a doctor."
            case .injury:
                return "Size the session to the joint that's complaining. Lifestyle only."
            case .adhd:
                return "Short, clear next moves. No lecture."
            case .anxiety:
                return "Low-pressure days are valid days. Coach, not clinician."
            case .chronic, .mobility, .other:
                return "Work with the body that's here. Anything medical, that's a doctor."
            }
        }
    }

    /// Rowan-aligned share gates. Default off — redacted from server context.
    public struct SharePolicy: Codable, Equatable, Sendable {
        public var shareConditions: Bool
        public var shareRelationship: Bool
        public var shareSocial: Bool

        public static let onDeviceOnly = SharePolicy(
            shareConditions: false,
            shareRelationship: false,
            shareSocial: false
        )

        public init(
            shareConditions: Bool = false,
            shareRelationship: Bool = false,
            shareSocial: Bool = false
        ) {
            self.shareConditions = shareConditions
            self.shareRelationship = shareRelationship
            self.shareSocial = shareSocial
        }
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public var weights: [Pillar: Double]
        public var goals: [String]
        public var routineNote: String
        public var constraints: [String]
        public var relationship: RelationshipStatus?
        public var social: SocialLife
        public var healthConstraints: [HealthConstraint]
        public var healthNote: String
        public var share: SharePolicy
        public var userLocked: Bool
        public var hobbies: [HobbyFit.Hobby]
        public var socialEnergy0to10: Double?

        public static let storageKey = ForgeLifestyleProfile.storageKey

        public init(
            weights: [Pillar: Double] = Snapshot.balancedWeights,
            goals: [String] = [],
            routineNote: String = "",
            constraints: [String] = [],
            relationship: RelationshipStatus? = nil,
            social: SocialLife = SocialLife(),
            healthConstraints: [HealthConstraint] = [],
            healthNote: String = "",
            share: SharePolicy = .onDeviceOnly,
            userLocked: Bool = false,
            hobbies: [HobbyFit.Hobby] = [],
            socialEnergy0to10: Double? = nil
        ) {
            self.weights = Snapshot.normalized(weights)
            self.goals = goals
            self.routineNote = routineNote
            self.constraints = constraints
            self.relationship = relationship
            self.social = social
            self.healthConstraints = healthConstraints
            self.healthNote = healthNote
            self.share = share
            self.userLocked = userLocked
            self.hobbies = HobbyFit.normalizeHobbies(hobbies)
            self.socialEnergy0to10 = socialEnergy0to10
        }

        public static let balancedWeights: [Pillar: Double] = [
            .movement: 0.20, .sleep: 0.20, .nutrition: 0.20, .mind: 0.20, .habits: 0.20,
        ]

        public var dominantPillar: Pillar {
            weights.max(by: { $0.value < $1.value })?.key ?? .habits
        }

        public var deEmphasizesWorkouts: Bool {
            (weights[.movement] ?? 0) < 0.16
        }

        public var hasSeizureConstraint: Bool {
            healthConstraints.contains(.seizures) || healthConstraints.contains(.epilepsy)
        }

        public var isSociallyActive: Bool {
            social.goesOut == true || social.parties == true || social.drinks == true
        }

        public mutating func clearRelationship() { relationship = nil }
        public mutating func clearSocial() { social = SocialLife() }
        public mutating func clearHealthConstraints() {
            healthConstraints = []
            healthNote = ""
        }

        public mutating func removeHealthConstraint(_ constraint: HealthConstraint) {
            healthConstraints.removeAll { $0 == constraint }
        }
    }

    public enum ConversationBeat: String, CaseIterable, Sendable {
        case relationship
        case socialLife
        case healthConstraints

        public var skipLabel: String { "Skip" }

        public var ariaAsk: String {
            switch self {
            case .relationship:
                return "If you want, tell me whether you're building a life with someone — or skip. Optional, on this phone, never an ad."
            case .socialLife:
                return "Nights out, drinks, friends, parties — how do you actually live? No judgment. Skip is fine."
            case .healthConstraints:
                return "Anything I should respect when we pick a session — seizures, an injury, something chronic? Optional. I'll keep it on this phone unless you opt in. I won't make it who you are."
            }
        }
    }

    public struct Signals: Equatable, Sendable {
        public var goals: [String]
        public var workouts: [String]
        public var habits: [String]
        public var conversation: [String]
        public var sleepNights: Int
        public var workoutsThisWeek: Int
        public var conditions: [HealthConstraint]
        public var relationship: RelationshipStatus?
        public var social: SocialLife

        public init(
            goals: [String] = [],
            workouts: [String] = [],
            habits: [String] = [],
            conversation: [String] = [],
            sleepNights: Int = 0,
            workoutsThisWeek: Int = 0,
            conditions: [HealthConstraint] = [],
            relationship: RelationshipStatus? = nil,
            social: SocialLife = SocialLife()
        ) {
            self.goals = goals
            self.workouts = workouts
            self.habits = habits
            self.conversation = conversation
            self.sleepNights = sleepNights
            self.workoutsThisWeek = workoutsThisWeek
            self.conditions = conditions
            self.relationship = relationship
            self.social = social
        }
    }

    /// Derive (or evolve) a profile. If `current.userLocked`, only fill empty
    /// optional fields — the person owns the edit.
    public static func evolve(current: Snapshot? = nil, signals: Signals) -> Snapshot {
        var snap = current ?? Snapshot()
        if !snap.userLocked {
            snap.weights = weights(from: signals)
            snap.goals = signals.goals
        }
        if snap.relationship == nil { snap.relationship = signals.relationship }
        if snap.social.isEmpty { snap.social = signals.social }
        if snap.healthConstraints.isEmpty { snap.healthConstraints = signals.conditions }
        return snap
    }

    public static func weights(from signals: Signals) -> [Pillar: Double] {
        var raw: [Pillar: Double] = [
            .movement: 1, .sleep: 1, .nutrition: 1, .mind: 1, .habits: 1,
        ]
        let blob = (signals.goals + signals.workouts + signals.habits + signals.conversation)
            .joined(separator: " ")
            .lowercased()
        if blob.contains("sleep") || blob.contains("night") { raw[.sleep, default: 1] += 3 }
        if blob.contains("stress") || blob.contains("anxiet") || blob.contains("mind") {
            raw[.mind, default: 1] += 3
        }
        if blob.contains("nutrition") || blob.contains("food") || blob.contains("eat") {
            raw[.nutrition, default: 1] += 2.5
        }
        if blob.contains("habit") { raw[.habits, default: 1] += 2 }
        if blob.contains("strength") || blob.contains("muscle") || blob.contains("train")
            || blob.contains("workout") {
            raw[.movement, default: 1] += 3
        }
        if signals.sleepNights >= 5 { raw[.sleep, default: 1] += 1 }
        if signals.workoutsThisWeek == 0 && !blob.contains("train") && !blob.contains("muscle") {
            raw[.movement, default: 1] *= 0.35
        }
        if !signals.conditions.isEmpty {
            raw[.mind, default: 1] += 1.5
            raw[.movement, default: 1] *= 0.7
        }
        return Snapshot.normalized(raw)
    }

    public static func mosaicTracks(_ snap: Snapshot) -> [StatsMosaic.Track] {
        let ranked = Pillar.allCases.sorted { (snap.weights[$0] ?? 0) > (snap.weights[$1] ?? 0) }
        var tracks: [StatsMosaic.Track] = []
        for pillar in ranked {
            if let track = pillar.mosaicTrack, !tracks.contains(track) {
                tracks.append(track)
            }
        }
        if snap.deEmphasizesWorkouts {
            tracks.removeAll { $0 == .train }
            tracks.append(.train)
        } else if !tracks.contains(.train) {
            tracks.insert(.train, at: min(1, tracks.count))
        }
        for leftover in StatsMosaic.Track.allCases where !tracks.contains(leftover) {
            tracks.append(leftover)
        }
        return tracks
    }

    public static func homeSections(
        _ snap: Snapshot,
        hobbyPath: HobbyPathEngine.Path? = nil
    ) -> [ForgePersonalization.HomeSection] {
        if hobbyPath == .restoreQuiet || snap.deEmphasizesWorkouts {
            return [.todayHero, .briefing, .lifestyle, .mosaic, .story, .forecast, .widgets, .rest]
        }
        if hobbyPath == .openGently {
            return [.todayHero, .mosaic, .lifestyle, .briefing, .forecast, .widgets, .story, .rest]
        }
        if snap.isSociallyActive && snap.relationship == .partnered {
            return [.todayHero, .forecast, .lifestyle, .briefing, .mosaic, .widgets, .story, .rest]
        }
        let focus: ForgePersonalization.Focus
        switch snap.dominantPillar {
        case .sleep, .mind: focus = .sleep
        case .movement: focus = .strength
        case .nutrition, .habits: focus = .lifestyle
        }
        return ForgePersonalization.homeSections(focus: focus, daypart: .morning)
    }

    public static func ariaEmphasis(
        _ snap: Snapshot,
        personality: ForgeCoachingPersonality.Choice = .init()
    ) -> String {
        var parts: [String] = []
        parts.append(ForgeCoachingPersonality.promptDirective(personality))
        let ranked = Pillar.allCases.sorted { (snap.weights[$0] ?? 0) > (snap.weights[$1] ?? 0) }
        let lead = ranked.prefix(2).map(\.label).joined(separator: " and ")
        parts.append("This person's Forge is weighted toward \(lead.lowercased()). Goals are not universal.")
        if snap.deEmphasizesWorkouts {
            parts.append("They barely train and that is fine. Do not push workouts. Sleep, food, stress, and habits lead.")
        }
        if let rel = snap.relationship, rel != .skipped {
            parts.append("Relational context: \(rel.label). Use it as life texture, never gossip, never an ad.")
        }
        if snap.social.drinks == true || snap.social.goesOut == true || snap.social.parties == true {
            parts.append("Social life includes nights out. Non-judgmental. Work with how they actually live — do not moralize drinking.")
        }
        if !snap.hobbies.isEmpty {
            let names = snap.hobbies.prefix(3).map(\.label).joined(separator: ", ")
            parts.append("Free days include \(names). Those hours count toward the day — not decoration.")
        }
        if snap.hasSeizureConstraint {
            parts.append("They live with seizures. Safer, predictable activity. Suggest a doctor for anything medical. Never diagnose. Never treat the condition as who they are.")
        } else if !snap.healthConstraints.isEmpty {
            let names = snap.healthConstraints.map(\.label).joined(separator: ", ")
            parts.append("Respect \(names) as a constraint on the day, not as who they are. Coach, not doctor.")
        }
        parts.append("Never sell this. Never use it for ads.")
        return parts.joined(separator: " ")
    }

    public static func tutorialHighlight(_ snap: Snapshot) -> StatsMosaic.Track {
        if let track = HobbyFit.dayContribution(
            hobbies: snap.hobbies,
            todayISO: ""
        ).mosaicTrack {
            return track
        }
        if snap.deEmphasizesWorkouts { return .sleep }
        if snap.dominantPillar == .nutrition { return .water }
        if snap.dominantPillar == .habits { return .habits }
        if snap.dominantPillar == .movement { return .train }
        return .sleep
    }

    public static func tutorialPrompt(beat: ForgeTutorial.Beat, profile: Snapshot) -> String {
        let track = tutorialHighlight(profile)
        switch beat {
        case .welcome:
            if profile.deEmphasizesWorkouts {
                return "Your Health data has been sitting unused. Forge will weight sleep, food, and stress for how you actually live — not a training cult. Tap Got it."
            }
            if profile.isSociallyActive {
                return "Your Health data has been sitting unused. Forge fits the life you already have — nights out included. Tap Got it."
            }
            return beat.prompt
        case .seeHistory:
            return "Open Progress. That's the unused picture — weighted toward \(track.title.lowercased()) for you."
        case .personalIndex:
            return "Read the \(track.title) tile. That's your index, from your own days."
        case .askAria:
            if profile.hasSeizureConstraint {
                return "Ask ARIA how you're doing. She'll keep activity safer and never make a condition who they are."
            }
            return beat.prompt
        case .mosaicWin:
            return "First win is the \(track.title) tile. Tap it."
        case .done:
            return beat.prompt
        }
    }

    public static func onboardingBeats(_ snap: Snapshot) -> [ConversationBeat] {
        var beats: [ConversationBeat] = []
        if snap.relationship == nil { beats.append(.relationship) }
        if snap.social.isEmpty { beats.append(.socialLife) }
        if snap.healthConstraints.isEmpty { beats.append(.healthConstraints) }
        return beats
    }

    public static func activityFraming(_ snap: Snapshot) -> String {
        if snap.hasSeizureConstraint {
            return HealthConstraint.seizures.saferFraming
        }
        if snap.deEmphasizesWorkouts {
            return "A walk, a night, a meal — that's the work. No workout push."
        }
        if snap.social.drinks == true {
            return "If you're going out, we plan around the night you actually have — no lecture."
        }
        return "Size the session to the day in front of you."
    }

    /// Server payload. Sensitive fields omitted unless the matching opt-in is on.
    public static func serverContext(_ snap: Snapshot) -> [String: String] {
        var out: [String: String] = [:]
        out["lifestyle_weights"] = Pillar.allCases
            .map { "\($0.rawValue):\(String(format: "%.2f", snap.weights[$0] ?? 0))" }
            .joined(separator: ",")
        if !snap.goals.isEmpty { out["goals"] = snap.goals.joined(separator: ",") }
        if snap.share.shareRelationship, let rel = snap.relationship, rel != .skipped {
            out["relationship"] = rel.rawValue
        }
        if snap.share.shareSocial, !snap.social.isEmpty {
            if let drinks = snap.social.drinks { out["social_drinks"] = drinks ? "yes" : "no" }
            if let outNights = snap.social.goesOut { out["social_goes_out"] = outNights ? "yes" : "no" }
        }
        if snap.share.shareConditions, !snap.healthConstraints.isEmpty {
            out["health_constraints"] = snap.healthConstraints.map(\.rawValue).joined(separator: ",")
        }
        return out
    }

    public static func containsSensitiveServerLeak(_ payload: [String: String], policy: SharePolicy) -> Bool {
        if !policy.shareConditions && payload["health_constraints"] != nil { return true }
        if !policy.shareRelationship && payload["relationship"] != nil { return true }
        if !policy.shareSocial && (payload["social_drinks"] != nil || payload["social_goes_out"] != nil) {
            return true
        }
        return false
    }

    fileprivate static func normalized(_ raw: [Pillar: Double]) -> [Pillar: Double] {
        let clipped = Dictionary(uniqueKeysWithValues: Pillar.allCases.map { pillar in
            (pillar, max(0, raw[pillar] ?? 0))
        })
        let sum = clipped.values.reduce(0, +)
        guard sum > 0 else { return Snapshot.balancedWeights }
        return clipped.mapValues { $0 / sum }
    }
}

extension ForgeLifestyleProfile.Snapshot {
    fileprivate static func normalized(_ raw: [ForgeLifestyleProfile.Pillar: Double]) -> [ForgeLifestyleProfile.Pillar: Double] {
        ForgeLifestyleProfile.normalized(raw)
    }
}

/// Two 26-year-old fixtures — same age, different lives.
public enum ForgeLifestylePersonas: Sendable {
    public static let seizuresSleepCare = ForgeLifestyleProfile.Snapshot(
        weights: [.movement: 0.08, .sleep: 0.32, .nutrition: 0.24, .mind: 0.24, .habits: 0.12],
        goals: ["better sleep", "less stress", "eat honestly"],
        routineNote: "Desk days, early nights when they land.",
        constraints: ["condition:seizures"],
        relationship: nil,
        social: .init(),
        healthConstraints: [.seizures],
        healthNote: "",
        share: .onDeviceOnly
    )

    public static let socialPartnered = ForgeLifestyleProfile.Snapshot(
        weights: [.movement: 0.28, .sleep: 0.16, .nutrition: 0.16, .mind: 0.14, .habits: 0.26],
        goals: ["stay active", "keep weekends"],
        routineNote: "Gym a few days, out with friends, partnered.",
        constraints: [],
        relationship: .partnered,
        social: .init(goesOut: true, drinks: true, parties: true, closeFriends: true),
        healthConstraints: [],
        share: .onDeviceOnly
    )
}
