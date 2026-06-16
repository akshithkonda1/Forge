import Foundation

/// Structured response from ARIA backend or local engine.
///
/// The first group mirrors the v1.0 ARIA response envelope
/// (`services/aria_engine.py` / `shared/api-contracts.ts`); the second group is
/// the chat-surface compatibility layer. All envelope fields are optional so a
/// response from either the new engine or the legacy path decodes cleanly.
struct AriaResponse: Codable, Equatable {
    // --- v1.0 envelope ---
    var schemaVersion: String? = nil
    var responseType: String? = nil  // insight | recommendation | plan | summary | clarification
    var confidenceReason: String? = nil
    /// 1–3 sentence prose; spoken verbatim by the voice orb (cards suppressed).
    var proseSummary: String? = nil
    /// Model the live path routed to (claude-opus-4-8 | claude-sonnet-4-6).
    var model: String? = nil

    // --- compatibility layer ---
    var message: String
    var richCard: RichCardPayload? = nil
    var suggestedActions: [String]? = nil
    var contextUpdates: [String: Int]? = nil
    var confidence: Double? = nil
    var memoryReference: String? = nil
    var missingFields: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case responseType = "response_type"
        case confidenceReason = "confidence_reason"
        case proseSummary = "prose_summary"
        case model
        case message
        case richCard = "rich_card"
        case suggestedActions = "suggested_actions"
        case contextUpdates = "context_updates"
        case confidence
        case memoryReference = "memory_reference"
        case missingFields = "missing_fields"
    }

    /// Best single line for the voice orb: the dedicated prose summary when the
    /// backend supplies it, otherwise the chat message.
    var voiceLine: String { proseSummary ?? message }
}

struct RichCardPayload: Codable, Equatable {
    var type: String
    var title: String?
    var values: [Double]?
    var insight: String?
    var workoutName: String?
    var durationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case type, title, values, insight
        case workoutName = "workout_name"
        case durationMinutes = "duration_minutes"
    }

    func toRichCardData() -> RichCardData? {
        switch type {
        case "workout-plan", "workout_plan":
            return RichCardData(
                type: .workoutPlan,
                workoutName: workoutName ?? title,
                workoutDuration: durationMinutes,
                workoutExercises: nil
            )
        case "data-chart", "data_chart":
            return RichCardData(
                type: .dataChart,
                chartTitle: title,
                chartValues: values,
                chartInsight: insight,
                chartColor: .steel
            )
        default:
            return nil
        }
    }
}

struct AriaChatRequest: Codable {
    let userId: String
    let message: String
    let recentMetrics: [String: Double]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case message
        case recentMetrics = "recent_metrics"
    }
}