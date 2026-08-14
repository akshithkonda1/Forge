import Foundation

/// Pulls ARIA's 6 AM / 6 PM notification copy from the live ledger.
@MainActor
final class TodayBriefSync {
    static let shared = TodayBriefSync()

    struct DueNotification: Decodable {
        var slot: String
        var title: String
        var body: String
        var destination: String?
        var hour: Int?
        var minute: Int?
    }

    private struct Envelope: Decodable {
        var notifications: [DueNotification]
    }

    func notifications() async -> [DueNotification] {
        var request = URLRequest(url: AriaService.shared.baseURL.appendingPathComponent("notifications/due"))
        request.timeoutInterval = 6
        if let token = UserDefaults.standard.string(forKey: "forge.aria.authToken"), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return []
        }
        return envelope.notifications
    }
}
