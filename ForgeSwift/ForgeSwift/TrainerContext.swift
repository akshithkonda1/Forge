import Foundation
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

enum TabItem: String, CaseIterable, Identifiable {
    /// Order is visual nav order: Home · Train · Life · ARIA · Sleep · Stats · You
    case home, workout, lifestyle, chat, sleep, progress, profile
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: return "Home"
        case .workout: return "Workout"
        case .chat: return "ARIA"
        case .lifestyle: return "Lifestyle"
        case .sleep: return "Sleep"
        case .progress: return "Progress"
        case .profile: return "Profile"
        }
    }
    var systemImage: String {
        switch self {
        case .home:      return "house"
        case .chat:      return "message"
        case .workout:   return "dumbbell"
        case .lifestyle: return "leaf"
        case .sleep:     return "moon"
        case .progress:  return "chart.line.uptrend.xyaxis"
        case .profile:   return "person"
        }
    }
}

/// Protocol for AI response generators
protocol TrainerResponseGenerator {
    func generateResponse(for input: String, context: TrainerContext) async throws -> TrainerResponse
}

/// Context data passed to AI for response generation
struct TrainerContext {
    let userProfile: UserProfile
    let readiness: ReadinessData
    let dailyMetrics: DailyMetrics
    let sleepData: [SleepData]
    let workoutHistory: [WorkoutHistory]
    let currentTime: Date
    /// Recent turns only — older history is compressed into `conversationSummary`
    /// so prompts stay cheap without losing continuity.
    let conversationHistory: [ChatMessage]
    /// Total turns exchanged ever, including those trimmed out of
    /// `conversationHistory`. Use this (not `conversationHistory.count`) for any
    /// relationship-depth or "early conversation" heuristic.
    var totalMessageCount: Int = 0
    /// Compressed memory anchors for everything older than the recent window.
    var conversationSummary: String? = nil
    /// Living ARIA tags (lifestyle + training theme preference).
    var lifestyleTags: [String] = []
    /// Coach boundaries (conditions, guidance_only, etc.).
    var constraints: [String] = []
    /// Optional menstrual cycle snapshot when tracking is shared with ARIA.
    var cycleSnapshot: MenstrualCycleSnapshot? = nil
    /// Active supported person (selected / mentioned). Not "everyone as partner."
    var partnerCycleSnapshot: MenstrualCycleSnapshot? = nil
    var partnerCycleSettings: PartnerCycleSettings? = nil
    /// Every consented person ARIA may coach the user about.
    var supportedPeople: [(settings: PartnerCycleSettings, snapshot: MenstrualCycleSnapshot)] = []
    
    var hour: Int {
        Calendar.current.component(.hour, from: currentTime)
    }
    
    var isEarlyMorning: Bool { hour < 7 }
    var isLateNight: Bool { hour >= 22 }
    var averageWeeklySleepScore: Double {
        let scores = sleepData.prefix(7).map { Double($0.score) }
        return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }

    /// Resolved theme for this turn (profile + tags; chat input applied by plan engine).
    var preferredTrainingTheme: AriaTrainingTheme {
        AriaThemeResolver.resolve(
            preferred: userProfile.trainingTheme,
            lifestyleTags: lifestyleTags,
            freeTimeTags: userProfile.interestTags
        )
    }

    /// Effective readiness for programming: soft-lifts expected luteal/period dips so ARIA doesn't over-react.
    var programmingReadiness: Int {
        let bonus = cycleSnapshot.map { MenstrualCycleEngine.readinessInterpretationBonus(for: $0) } ?? 0
        return min(100, readiness.overall + bonus)
    }
}

/// The human plot the Test-Ready pack (or a real month) already wrote —
/// persona, how the morning felt, the sentence that ties last night to
/// today's body. Tags carry it; this is what ARIA actually says.
struct AriaLifeRead: Equatable {
    var persona: String?
    var felt: String?
    var story: String?
    var lastNightKind: String?
    var lastNightDrinks: Int = 0
    var lastNightLate: Bool = false

    var hasEvening: Bool { lastNightKind != nil || lastNightLate || lastNightDrinks > 0 }

    static func from(tags: [String]) -> AriaLifeRead {
        var read = AriaLifeRead()
        for tag in tags {
            if tag.hasPrefix("persona:") {
                read.persona = String(tag.dropFirst("persona:".count))
            } else if tag.hasPrefix("felt:") {
                read.felt = String(tag.dropFirst("felt:".count))
            } else if tag.hasPrefix("story:") {
                read.story = String(tag.dropFirst("story:".count))
            } else if tag.hasPrefix("lastnight:drinks:") {
                read.lastNightDrinks = Int(tag.dropFirst("lastnight:drinks:".count)) ?? 0
            } else if tag == "lastnight:late" {
                read.lastNightLate = true
            } else if tag.hasPrefix("lastnight:"), !tag.hasPrefix("lastnight:drinks:") {
                read.lastNightKind = String(tag.dropFirst("lastnight:".count))
            }
        }
        return read
    }

    /// A companion sentence. Prefers the pack's own story so ARIA never
    /// invents an evening the numbers contradict.
    func spokenLine(rng: inout AriaSeededRNG) -> String? {
        if let story, !story.isEmpty { return story }
        if lastNightLate || lastNightDrinks >= 3 {
            return rng.pick([
                "Last night ran late — the morning is still paying for it.",
                "The evening went long, so if today feels heavier, that tracks.",
            ])
        }
        if let felt, felt == "thin" || felt == "spent" || felt == "groggy" {
            return rng.pick([
                "The morning feels \(felt) — we'll work with that, not against it.",
                "You're coming in \(felt). That's information, not a verdict.",
            ])
        }
        return nil
    }
}

extension TrainerContext {
    var lifeRead: AriaLifeRead { AriaLifeRead.from(tags: lifestyleTags) }
}

struct TrainerResponse {
    let content: String
    let richCard: RichCardData?
    let suggestedActions: [String]?
    let confidence: Double // 0.0 to 1.0
    
    init(content: String, richCard: RichCardData? = nil, suggestedActions: [String]? = nil, confidence: Double = 1.0) {
        self.content = content
        self.richCard = richCard
        self.suggestedActions = suggestedActions
        self.confidence = confidence
    }
}
