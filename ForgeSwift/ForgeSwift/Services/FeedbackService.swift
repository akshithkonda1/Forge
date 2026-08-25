import Foundation

/// Layer 3 client — reactions and outcomes feed back into ARIA context.
@MainActor
final class FeedbackService {
    static let shared = FeedbackService()

    private let contextStore = AriaContextStore.shared
    private var baseURL: URL { AriaService.shared.baseURL }

    private init() {}

    func processReaction(userId: String, messageId: String, reaction: String) async {
        if reaction == "🔥" || reaction == "💪" {
            let nextLevel = min(10, contextStore.context.relationshipLevel + 1)
            contextStore.applyUpdates(["relationship_level": nextLevel])
        }

        let payload: [String: Any] = [
            "user_id": userId,
            "message_id": messageId,
            "reaction": reaction,
        ]
        await postFeedback(path: "ai/feedback/reaction", body: payload)
    }

    func processPlanOutcome(userId: String, planId: String, completed: Bool, feedback: String? = nil) async {
        if completed {
            contextStore.addInsight("Completed plan: \(planId)")
        } else {
            contextStore.addInsight("Skipped plan: \(planId)")
        }

        var payload: [String: Any] = [
            "user_id": userId,
            "plan_id": planId,
            "completed": completed,
        ]
        if let feedback { payload["feedback"] = feedback }
        await postFeedback(path: "ai/feedback/plan-outcome", body: payload)
    }

    private func postFeedback(path: String, body: [String: Any]) async {
        guard let url = URL(string: path, relativeTo: baseURL),
              JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        _ = try? await ForgeAPI.send(request)
    }
}