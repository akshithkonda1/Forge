import Foundation
import SwiftUI
import ForgeCore

/// Structured response from ARIA backend or local engine.
///
/// The first group mirrors the v1.1 ARIA response envelope
/// (`services/aria_engine.py` / `shared/api-contracts.ts`); the second group is
/// the chat-surface compatibility layer. All envelope fields are optional so a
/// response from either the new engine or the legacy path decodes cleanly.
struct AriaResponse: Codable, Equatable {
    // --- v1.1 envelope ---
    var schemaVersion: String? = nil
    var responseType: String? = nil  // insight | recommendation | plan | summary | clarification
    var confidenceReason: String? = nil
    /// 1–3 sentence prose; spoken verbatim by the voice orb (cards suppressed).
    var proseSummary: String? = nil
    /// Domains the user turned off for this turn (redacted before reasoning).
    var restrictedDomains: [String]? = nil
    /// Model the live path routed to (Opus for multi-signal, Sonnet for fast).
    var model: String? = nil
    /// v1.1 structured card (insight / recommendation / summary / clarification).
    var card: AriaCardPayload? = nil

    // --- compatibility layer ---
    var message: String
    var richCard: CloudRichCard? = nil
    var suggestedActions: [String]? = nil
    var contextUpdates: [String: Int]? = nil
    var confidence: Double? = nil
    var memoryReference: String? = nil
    var missingFields: [String]? = nil
    var toolCallsMade: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case responseType = "response_type"
        case confidenceReason = "confidence_reason"
        case proseSummary = "prose_summary"
        case restrictedDomains = "restricted_domains"
        case model
        case card
        case message
        case richCard = "rich_card"
        case richCardCamel = "richCard"
        case suggestedActions = "suggested_actions"
        case contextUpdates = "context_updates"
        case confidence
        case memoryReference = "memory_reference"
        case missingFields = "missing_fields"
        case toolCallsMade = "tool_calls_made"
        case toolCallsMadeCamel = "toolCallsMade"
    }

    init(
        schemaVersion: String? = nil,
        responseType: String? = nil,
        confidenceReason: String? = nil,
        proseSummary: String? = nil,
        restrictedDomains: [String]? = nil,
        model: String? = nil,
        card: AriaCardPayload? = nil,
        message: String,
        richCard: CloudRichCard? = nil,
        suggestedActions: [String]? = nil,
        contextUpdates: [String: Int]? = nil,
        confidence: Double? = nil,
        memoryReference: String? = nil,
        missingFields: [String]? = nil,
        toolCallsMade: [String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.responseType = responseType
        self.confidenceReason = confidenceReason
        self.proseSummary = proseSummary
        self.restrictedDomains = restrictedDomains
        self.model = model
        self.card = card
        self.message = message
        self.richCard = richCard
        self.suggestedActions = suggestedActions
        self.contextUpdates = contextUpdates
        self.confidence = confidence
        self.memoryReference = memoryReference
        self.missingFields = missingFields
        self.toolCallsMade = toolCallsMade
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(String.self, forKey: .schemaVersion)
        responseType = try c.decodeIfPresent(String.self, forKey: .responseType)
        confidenceReason = try c.decodeIfPresent(String.self, forKey: .confidenceReason)
        proseSummary = try c.decodeIfPresent(String.self, forKey: .proseSummary)
        restrictedDomains = try c.decodeIfPresent([String].self, forKey: .restrictedDomains)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        card = try c.decodeIfPresent(AriaCardPayload.self, forKey: .card)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        richCard = try c.decodeIfPresent(CloudRichCard.self, forKey: .richCard)
            ?? c.decodeIfPresent(CloudRichCard.self, forKey: .richCardCamel)
        suggestedActions = try c.decodeIfPresent([String].self, forKey: .suggestedActions)
        contextUpdates = try c.decodeIfPresent([String: Int].self, forKey: .contextUpdates)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        memoryReference = try c.decodeIfPresent(String.self, forKey: .memoryReference)
        missingFields = try c.decodeIfPresent([String].self, forKey: .missingFields)
        toolCallsMade = try c.decodeIfPresent([String].self, forKey: .toolCallsMade)
            ?? c.decodeIfPresent([String].self, forKey: .toolCallsMadeCamel)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(responseType, forKey: .responseType)
        try c.encodeIfPresent(confidenceReason, forKey: .confidenceReason)
        try c.encodeIfPresent(proseSummary, forKey: .proseSummary)
        try c.encodeIfPresent(restrictedDomains, forKey: .restrictedDomains)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(card, forKey: .card)
        try c.encode(message, forKey: .message)
        try c.encodeIfPresent(richCard, forKey: .richCard)
        try c.encodeIfPresent(suggestedActions, forKey: .suggestedActions)
        try c.encodeIfPresent(contextUpdates, forKey: .contextUpdates)
        try c.encodeIfPresent(confidence, forKey: .confidence)
        try c.encodeIfPresent(memoryReference, forKey: .memoryReference)
        try c.encodeIfPresent(missingFields, forKey: .missingFields)
        try c.encodeIfPresent(toolCallsMade, forKey: .toolCallsMade)
    }

    /// Best single line for the voice orb: the dedicated prose summary when the
    /// backend supplies it, otherwise the chat message.
    var voiceLine: String { proseSummary ?? message }

    func toRichCardData() -> RichCardData? {
        if let richCard, let mapped = richCard.toRichCardData() { return mapped }
        return card?.toRichCardData()
    }
}

/// Decodes any v1.1 card shape from the engine.
struct AriaCardPayload: Codable, Equatable {
    var metric: String?
    var currentValue: String?
    var vsBaseline: String?
    var interpretation: String?
    var priority: String?
    var action: String?
    var rationale: String?
    var timing: String?
    var expectedEffect: String?
    var periodDays: Int?
    var headline: String?
    var win: String?
    var risk: String?
    var recommendation: String?
    var question: String?
    var why: String?

    enum CodingKeys: String, CodingKey {
        case metric
        case currentValue = "current_value"
        case vsBaseline = "vs_baseline"
        case interpretation, priority, action, rationale, timing
        case expectedEffect = "expected_effect"
        case periodDays = "period_days"
        case headline, win, risk, recommendation, question, why
    }

    func toRichCardData() -> RichCardData? {
        if let metric, let currentValue {
            return RichCardData(
                type: .dataChart,
                chartTitle: metric,
                chartValues: nil,
                chartInsight: [currentValue, vsBaseline, interpretation].compactMap { $0 }.joined(separator: " · "),
                chartColor: .steel
            )
        }
        if let action {
            return RichCardData(
                type: .workoutPlan,
                workoutName: action,
                workoutDuration: nil,
                workoutExercises: nil
            )
        }
        if let headline {
            return RichCardData(
                type: .dataChart,
                chartTitle: headline,
                chartValues: nil,
                chartInsight: [win, risk, recommendation].compactMap { $0 }.joined(separator: "\n"),
                chartColor: .success
            )
        }
        if let question {
            return RichCardData(
                type: .dataChart,
                chartTitle: question,
                chartValues: nil,
                chartInsight: why,
                chartColor: .warning
            )
        }
        return nil
    }
}

typealias RichCardPayload = CloudRichCard

extension CloudRichCard {
    func toRichCardData() -> RichCardData? {
        if isWorkoutPlan {
            let moves = exercises.map {
                RichCardExercise(name: $0.name, sets: $0.sets, reps: $0.reps)
            }
            return RichCardData(
                type: .workoutPlan,
                workoutName: workoutName ?? title,
                workoutDuration: durationMinutes,
                workoutExercises: moves.isEmpty ? nil : moves
            )
        }
        if isDataChart {
            let mappedColor: Color? = {
                guard let color, !color.isEmpty else { return .steel }
                return Color(hex: color)
            }()
            return RichCardData(
                type: .dataChart,
                chartTitle: title,
                chartValues: values,
                chartInsight: insight,
                chartColor: mappedColor
            )
        }
        return nil
    }
}

extension CloudChatMessage {
    func toChatMessage() -> ChatMessage? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || richCard != nil else { return nil }
        let mappedRole: MessageRole = role == "user" ? .user : .trainer
        return ChatMessage(
            id: id,
            role: mappedRole,
            content: trimmed,
            timestamp: timestamp,
            richCard: richCard?.toRichCardData(),
            toolCallsMade: toolCallsMade.isEmpty ? nil : toolCallsMade
        )
    }
}

struct AriaChatRequest: Codable {
    let userId: String
    let message: String
    var context: ARIAContextPayload?
    var recentMetrics: [String: Double]?
    var permissions: [String: Bool]?
    var voiceMode: Bool?
    /// `insight` = short Lifestyle card. Backend skips Bedrock + Dynamo writes.
    var mode: String? = nil
    /// Specialist coach (`aria` / `train` / `recover` / `fuel` / `life` / `cycle`).
    var agent: String? = nil
    /// Every specialist on this turn. One live call covers the list.
    var agents: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case message
        case context
        case recentMetrics = "recent_metrics"
        case permissions
        case voiceMode = "voice_mode"
        case mode
        case agent
        case agents
    }
}

// MARK: - Biometrics (POST /ai/observe)

/// One raw reading. `type` may be our name, an Apple Health identifier, or a
/// third-party label — the server resolves it to a canonical metric.
struct HealthSample: Codable, Equatable {
    var type: String
    var value: Double
    var unit: String?
    var timestamp: String?
    var source: String?
    var stage: String?      // for sleep-stage samples: "deep" | "rem" | "light" | "awake"

    init(type: String, value: Double, unit: String? = nil,
         timestamp: String? = nil, source: String? = nil, stage: String? = nil) {
        self.type = type
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.source = source
        self.stage = stage
    }
}

struct ObserveRequest: Codable {
    let userId: String
    let samples: [HealthSample]
    var includeStored: Bool? = true
    var ageYears: Double? = nil
    var permissions: [String: Bool]? = nil
    var message: String? = nil
    var voiceMode: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case samples
        case includeStored = "include_stored"
        case ageYears = "age_years"
        case permissions
        case message
        case voiceMode = "voice_mode"
    }
}

struct ObserveResponse: Codable {
    var classification: ClassificationSummary
    var snapshot: BodySnapshot
    var restrictedDomains: [String]?
    var ariaResponse: AriaResponse?

    enum CodingKeys: String, CodingKey {
        case classification, snapshot
        case restrictedDomains = "restricted_domains"
        case ariaResponse = "aria_response"
    }
}

struct ClassificationSummary: Codable {
    var accepted: Int
    var rejected: Int
}

struct BodySnapshot: Codable {
    var confidence: Double
    var observationCount: Int
    var sources: [String]
    var systems: [String: SystemStateDTO]
    var derived: [String: BiometricEstimate]
    var anomalies: [BiometricAnomaly]

    enum CodingKeys: String, CodingKey {
        case confidence
        case observationCount = "observation_count"
        case sources, systems, derived, anomalies
    }
}

/// A physiological system's fused state. Extra server keys (per-metric detail)
/// are intentionally ignored — this is the UI-facing subset.
struct SystemStateDTO: Codable {
    var system: String
    var status: String
    var summary: String
    var confidence: Double
}

struct BiometricEstimate: Codable, Identifiable {
    var name: String
    var value: Double?
    var state: String
    var confidence: Double
    var method: String
    var detail: String

    var id: String { name }
}

struct BiometricAnomaly: Codable, Identifiable {
    var metric: String
    var value: Double?
    var detail: String

    var id: String { metric }
}