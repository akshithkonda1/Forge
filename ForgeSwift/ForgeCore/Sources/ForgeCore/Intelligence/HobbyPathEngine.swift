import Foundation

// ============================================================
// MARK: - Hobby path
// ============================================================

/// Lifestyle hobby development that fits how this person works.
///
/// Fitness apps optimize training. This picks a free-day path from
/// social energy + the working model: reserved people get solo hobbies
/// that *can* open light contact later; over-social / burned-out weeks
/// get quieter restorative ones. It also names *tomorrow's people-energy*
/// and a circadian free-day window so a night owl is not handed a 6am
/// club. The healthiest version of you is not necessarily the most fit.
/// Lifestyle coach only — never a diagnosis.
public enum HobbyPathEngine {

    public enum SocialBand: String, Sendable {
        /// Low social energy — not a disorder, a preference.
        case reserved
        /// High contact, still has room.
        case sociable
        /// High contact that's costing them — quieter week.
        case burnedOut = "burned_out"
        case mixed
    }

    public enum Path: String, Sendable {
        /// Solo first, optional light contact later.
        case openGently = "open_gently"
        /// Restore quietly. Calendar is not the win.
        case restoreQuiet = "restore_quiet"
        /// Keep hobbies they already chose.
        case keepRhythm = "keep_rhythm"
        /// Not enough signal yet.
        case explore
    }

    /// How much people this person can take *tomorrow*. Not a wellness score.
    public enum PeopleEnergy: String, Sendable {
        case thin
        case enough
        case open
    }

    /// When a free day actually fits this clock. Fitness apps default to morning.
    public enum FreeDayWindow: String, Sendable {
        case morning
        case afternoon
        case evening
        case anytime
    }

    public struct Suggestion: Sendable, Identifiable, Equatable {
        public var id: String { hobby.rawValue }
        public var hobby: LivingHobby
        public var why: String
        public var firstStep: String

        public init(hobby: LivingHobby, why: String, firstStep: String) {
            self.hobby = hobby
            self.why = why
            self.firstStep = firstStep
        }
    }

    public struct Snapshot: Sendable {
        public var path: Path
        public var socialBand: SocialBand
        public var peopleEnergy: PeopleEnergy
        public var freeDayWindow: FreeDayWindow
        public var headline: String
        public var coachingLine: String
        public var suggestions: [Suggestion]

        public var ariaTags: [String] {
            var tags = [
                "hobby_path:\(path.rawValue)",
                "hobby_social:\(socialBand.rawValue)",
                "hobby_people:\(peopleEnergy.rawValue)",
                "hobby_window:\(freeDayWindow.rawValue)",
            ]
            for item in suggestions.prefix(3) {
                tags.append("hobby:\(item.hobby.rawValue)")
            }
            return tags
        }

        public var windowLine: String {
            switch (freeDayWindow, peopleEnergy) {
            case (.evening, .thin):
                return "Tomorrow's people-energy looks thin. A free-day after the world goes quiet fits you."
            case (.morning, .thin):
                return "Tomorrow's people-energy looks thin. Use your morning — not a crowded evening."
            case (.afternoon, .thin):
                return "Tomorrow's people-energy looks thin. The afternoon quiet is the work, not another plan."
            case (.anytime, .thin):
                return "Tomorrow's people-energy looks thin. Pick the quieter hobby, not a fuller calendar."
            case (.evening, _):
                return "Your clock leans later. Free-day belongs after the world goes quiet — not a 6am club."
            case (.morning, _):
                return "Your clock leans early. Free-day belongs in the morning, not a packed evening."
            case (.afternoon, _):
                return "The afternoon slump is a free-day window, not a gap to fill with people."
            case (.anytime, .open):
                return "People-energy is there if you want it — optional, not a quota."
            case (.anytime, .enough):
                return "A free day still counts when it isn't training."
            }
        }

        public var chatPrompt: String {
            "Help me pick a hobby that fits how I actually live, not a fitter version of me. \(coachingLine) \(windowLine)"
        }
    }

    public static func snapshot(
        socialEnergy0to10: Double?,
        currentHobbies: [LivingHobby],
        working: UserWorkingModel.Snapshot,
        tomorrowPosture: ReadinessForecastEngine.Posture? = nil,
        wakeHour: Double? = nil,
        knownPeople: [PeopleDirectory.Person] = []
    ) -> Snapshot {
        let band = socialBand(energy: socialEnergy0to10, working: working)
        let path = path(for: band, working: working, hobbies: currentHobbies)
        let energy = peopleEnergy(band: band, working: working, tomorrowPosture: tomorrowPosture)
        let window = freeDayWindow(wakeHour: wakeHour, path: path)
        let suggestions = suggestions(for: path, current: currentHobbies, window: window)
        return Snapshot(
            path: path,
            socialBand: band,
            peopleEnergy: energy,
            freeDayWindow: window,
            headline: headline(for: path),
            coachingLine: coachingLine(for: path, suggestions: suggestions)
                + PeopleDirectory.hobbySuffix(path: path, people: knownPeople),
            suggestions: suggestions
        )
    }

    public static func isHobbyQuestion(_ text: String) -> Bool {
        let lower = text.lowercased()
        let phrases = [
            "hobby",
            "hobbies",
            "free day",
            "free time",
            "something besides training",
            "besides the gym",
            "not just fitness",
            "not just training",
            "burned out socially",
            "too social",
            "don't like people",
            "dont like people",
            "anti-social",
            "antisocial",
            "quiet hobby",
            "how should i spend",
            "what should i do with my time",
            "people-energy",
            "people energy",
        ]
        return phrases.contains { lower.contains($0) }
    }

    // MARK: - Internals

    static func socialBand(
        energy: Double?,
        working: UserWorkingModel.Snapshot
    ) -> SocialBand {
        if let energy {
            if energy <= 3.5 { return .reserved }
            if energy >= 7.5 {
                if working.tendency == .overreacher
                    || working.predictedFeel == .flat
                    || working.tendency == .weekendDrop {
                    return .burnedOut
                }
                return .sociable
            }
            return .mixed
        }
        switch working.tendency {
        case .protector, .rebuilding: return .reserved
        case .overreacher, .weekendDrop: return .burnedOut
        case .steady: return .mixed
        case .unknown: return .mixed
        }
    }

    static func peopleEnergy(
        band: SocialBand,
        working: UserWorkingModel.Snapshot,
        tomorrowPosture: ReadinessForecastEngine.Posture?
    ) -> PeopleEnergy {
        if band == .reserved || band == .burnedOut { return .thin }
        if tomorrowPosture == .rest || tomorrowPosture == .protect { return .thin }
        if working.predictedFeel == .flat { return .thin }
        if band == .sociable, working.predictedFeel == .available {
            return .open
        }
        return .enough
    }

    static func freeDayWindow(wakeHour: Double?, path: Path) -> FreeDayWindow {
        if let wake = wakeHour {
            if wake >= 9 { return .evening }
            if wake <= 6.5 { return .morning }
            if path == .restoreQuiet { return .afternoon }
            if path == .openGently { return .evening }
            return .anytime
        }
        switch path {
        case .openGently: return .evening
        case .restoreQuiet: return .afternoon
        case .keepRhythm, .explore: return .anytime
        }
    }

    private static func path(
        for band: SocialBand,
        working: UserWorkingModel.Snapshot,
        hobbies: [LivingHobby]
    ) -> Path {
        switch band {
        case .reserved: return .openGently
        case .burnedOut: return .restoreQuiet
        case .sociable:
            return hobbies.isEmpty ? .explore : .keepRhythm
        case .mixed:
            if working.tendency == .overreacher { return .restoreQuiet }
            if hobbies.isEmpty { return .explore }
            return .keepRhythm
        }
    }

    private static func suggestions(
        for path: Path,
        current: [LivingHobby],
        window: FreeDayWindow
    ) -> [Suggestion] {
        let preferred: [LivingHobby]
        switch path {
        case .openGently:
            preferred = unique(current.filter(Self.gentleSocial.contains) + Self.gentleSocial)
        case .restoreQuiet:
            preferred = unique(current.filter(Self.quietRestore.contains) + Self.quietRestore)
        case .keepRhythm:
            preferred = current.isEmpty ? Array(Self.quietRestore.prefix(2)) : Array(current.prefix(3))
        case .explore:
            preferred = [.reading, .cooking, .outdoors]
        }
        return preferred.prefix(3).map { hobby in
            Suggestion(
                hobby: hobby,
                why: why(hobby, path: path),
                firstStep: firstStep(hobby, path: path) + windowClause(window)
            )
        }
    }

    private static let gentleSocial: [LivingHobby] = [.cooking, .outdoors, .making, .music]
    private static let quietRestore: [LivingHobby] = [.reading, .rest, .making, .music]

    private static func unique(_ hobbies: [LivingHobby]) -> [LivingHobby] {
        var seen = Set<LivingHobby>()
        return hobbies.filter { seen.insert($0).inserted }
    }

    private static func headline(for path: Path) -> String {
        switch path {
        case .openGently:
            return "A hobby you can start alone"
        case .restoreQuiet:
            return "Quieter is the work this week"
        case .keepRhythm:
            return "Keep the free-day you already like"
        case .explore:
            return "The healthiest version of you isn't only fitter"
        }
    }

    private static func coachingLine(
        for path: Path,
        suggestions: [Suggestion]
    ) -> String {
        let names = suggestions.prefix(2).map { $0.hobby.title.lowercased() }
        let listed = names.isEmpty ? "a small free-day" : names.joined(separator: " or ")
        switch path {
        case .openGently:
            return "The healthiest version of you isn't a new personality. Start \(listed) alone; light contact can come later if you want it."
        case .restoreQuiet:
            return "The healthiest version of you isn't the most fit, and it isn't the fullest calendar. Try \(listed) — quiet on purpose."
        case .keepRhythm:
            return "You already have a free-day shape. Keep \(listed) instead of adding a second identity."
        case .explore:
            return "Tell Lifestyle how a free day actually feels and I'll pick a hobby path that fits how you work — not a fitter costume."
        }
    }

    private static func windowClause(_ window: FreeDayWindow) -> String {
        switch window {
        case .morning: return " This fits your morning, not a crowded evening."
        case .afternoon: return " Use the afternoon quiet — not another plan."
        case .evening: return " This fits after the world goes quiet."
        case .anytime: return ""
        }
    }

    private static func why(_ hobby: LivingHobby, path: Path) -> String {
        switch (path, hobby) {
        case (.openGently, .cooking):
            return "Solo first. Sharing a plate is optional, later."
        case (.openGently, .outdoors):
            return "A walk with no audience. One person can join another week."
        case (.openGently, .making):
            return "Hands busy, nobody watching. A class is a later chapter."
        case (.openGently, .music):
            return "Headphones now. Playing with people is a maybe."
        case (.restoreQuiet, .reading):
            return "A chapter with the phone in another room."
        case (.restoreQuiet, .rest):
            return "An hour at home that isn't a workout or a plan."
        case (.restoreQuiet, .making):
            return "Quiet hands. No audience, no streak."
        case (.restoreQuiet, .music):
            return "Listen. Don't perform."
        default:
            return "Fits how you actually spend a free day."
        }
    }

    private static func firstStep(_ hobby: LivingHobby, path: Path) -> String {
        switch (path, hobby) {
        case (.openGently, .cooking):
            return "Cook one thing you'd actually eat. That's the whole win."
        case (.openGently, .outdoors):
            return "Fifteen minutes outside. No route PR."
        case (.openGently, .making):
            return "Twenty minutes with your hands. Stop while it's still pleasant."
        case (.openGently, .music):
            return "One album, headphones on."
        case (.restoreQuiet, .reading):
            return "Ten pages. Phone in another room."
        case (.restoreQuiet, .rest):
            return "Protect one hour at home. Not a nap protocol — just quieter."
        case (.restoreQuiet, .making):
            return "Make something nobody will see."
        case (.restoreQuiet, .music):
            return "Sit and listen once today."
        default:
            return "Do the smallest version once this week."
        }
    }
}
