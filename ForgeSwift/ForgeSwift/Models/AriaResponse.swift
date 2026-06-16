import Foundation

/// Structured response from ARIA backend or local engine.
struct AriaResponse: Codable, Equatable {
    var message: String
    var richCard: RichCardPayload?
    var suggestedActions: [String]?
    var contextUpdates: [String: Int]?
    var confidence: Double?
    var memoryReference: String?

    enum CodingKeys: String, CodingKey {
        case message
        case richCard = "rich_card"
        case suggestedActions = "suggested_actions"
        case contextUpdates = "context_updates"
        case confidence
        case memoryReference = "memory_reference"
    }
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