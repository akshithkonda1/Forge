import Foundation
import ForgeCore

/// Optional short-lived S3 ticket for a client-encrypted Cycle report.
///
/// The PDF is generated and AES-GCM sealed on this iPhone. Lambda mints a
/// presigned PUT/GET for ciphertext only. The key never leaves in a body,
/// query, or header — it stays in the Keychain or a URL fragment (`#k=`).
@MainActor
enum CycleReportUploadClient {
    struct Ticket: Decodable, Equatable {
        var putUrl: URL
        var getUrl: URL
        var expiresAt: String
        var objectKey: String
    }

    static var isConfigured: Bool {
        ForgeAuthClient.shared.config.apiBaseURL.host != nil
            && ForgeAuthClient.shared.session != nil
    }

    static func requestTicket(
        byteLength: Int,
        windowMonths: Int
    ) async throws -> Ticket {
        guard let base = apiBase else { throw ForgeAPI.Failure.notConfigured }
        var request = URLRequest(url: base.appendingPathComponent("cycle/report-upload"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contentType": CycleReportCrypto.contentType,
            "encrypted": true,
            "byteLength": byteLength,
            "windowMonths": windowMonths,
        ])
        let (data, _) = try await ForgeAPI.send(request)
        return try JSONDecoder().decode(Ticket.self, from: data)
    }

    static func upload(envelope: CycleReportEnvelope, ticket: Ticket) async throws -> URL {
        var request = URLRequest(url: ticket.putUrl)
        request.httpMethod = "PUT"
        request.setValue(CycleReportCrypto.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = envelope.ciphertext
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ForgeAPI.Failure.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1, body: "ciphertext put failed")
        }
        return envelope.shareURL(base: ticket.getUrl)
    }

    private static var apiBase: URL? {
        if let saved = UserDefaults.standard.string(forKey: "forge.api.baseURL"),
           let url = URL(string: saved), !saved.isEmpty {
            return url
        }
        let url = ForgeAuthClient.shared.config.apiBaseURL
        return url.host == nil ? nil : url
    }
}
