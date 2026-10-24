import Foundation
import ForgeCore

/// Optional short-lived S3 ticket for an Apple Cycle PDF.
///
/// The PDF is generated on this iPhone. Lambda never sees the bytes — it only
/// mints a presigned PUT/GET. Nothing is written to DynamoDB. Objects live
/// under `cycle-reports/` and expire in a day so the cloud bill stays small.
///
/// `@MainActor` because `ForgeAuthClient.shared` is main-actor isolated;
/// callers (`CycleRhythmReportView`) already are.
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
            "contentType": "application/pdf",
            "byteLength": byteLength,
            "windowMonths": windowMonths,
        ])
        let (data, _) = try await ForgeAPI.send(request)
        return try JSONDecoder().decode(Ticket.self, from: data)
    }

    static func upload(pdf: Data, ticket: Ticket) async throws {
        // Cycle PDFs are health data. They stay on this iPhone.
        _ = pdf
        _ = ticket
        throw ForgeAPI.Failure.http(status: 451, body: ForgePrivacyCopy.healthStaysOnDevice)
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
