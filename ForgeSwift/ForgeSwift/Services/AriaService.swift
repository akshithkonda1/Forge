import Foundation

/// Layer 1 bridge — talks to ARIA backend with graceful local fallback.
@MainActor
final class AriaService {
    static let shared = AriaService()

    var baseURL: URL {
        if let saved = UserDefaults.standard.string(forKey: Self.baseURLKey),
           let url = URL(string: saved) {
            return url
        }
        return URL(string: "http://127.0.0.1:3001")!
    }

    private static let baseURLKey = "forge.api.baseURL"
    private let contextStore = AriaContextStore.shared

    private init() {}

    func setBaseURL(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: Self.baseURLKey)
    }

    func sendMessage(
        _ text: String,
        store: AppStore,
        localGenerator: TrainerResponseGenerator
    ) async throws -> AriaResponse {
        let rich = contextStore.buildRichContext(from: store)
        let request = AriaChatRequest(
            userId: rich.userId,
            message: text,
            recentMetrics: rich.recentMetrics
        )

        if let remote = try? await postChat(request) {
            if let updates = remote.contextUpdates {
                contextStore.applyUpdates(updates)
            }
            var response = remote
            if response.memoryReference == nil {
                response.memoryReference = contextStore.memoryReference(for: text)
            }
            return response
        }

        return try await generateLocally(
            text: text,
            store: store,
            generator: localGenerator,
            rich: rich
        )
    }

    func fetchProactiveMessage(store: AppStore) async -> String? {
        contextStore.refreshProactiveInsight(from: store)
        return contextStore.lastProactiveInsight
    }

    private func postChat(_ payload: AriaChatRequest) async throws -> AriaResponse {
        let url = baseURL.appendingPathComponent("ai/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AriaServiceError.badResponse
        }
        return try JSONDecoder().decode(AriaResponse.self, from: data)
    }

    private func generateLocally(
        text: String,
        store: AppStore,
        generator: TrainerResponseGenerator,
        rich: AriaRichContext
    ) async throws -> AriaResponse {
        let trainerContext = TrainerContext(
            userProfile: store.userProfile,
            readiness: store.readiness,
            dailyMetrics: store.dailyMetrics,
            sleepData: store.sleepData,
            workoutHistory: store.workoutHistory,
            currentTime: Date(),
            conversationHistory: store.chatMessages
        )

        let local = try await generator.generateResponse(for: text, context: trainerContext)
        let memory = contextStore.memoryReference(for: text)

        var message = local.content
        if let memory, local.confidence >= 0.85 {
            message = "\(memory)\n\n\(local.content)"
        }

        return AriaResponse(
            message: message,
            richCard: nil,
            suggestedActions: local.suggestedActions,
            contextUpdates: ["relationship_level": min(10, rich.relationshipLevel + 1)],
            confidence: local.confidence,
            memoryReference: memory
        )
    }
}

enum AriaServiceError: Error {
    case badResponse
}