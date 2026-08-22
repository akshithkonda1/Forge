import Foundation
import ForgeCore

// ============================================================
// MARK: - The one way the app talks to its backend
// ============================================================

/// Every request to Forge's API goes through `send`.
///
/// Before this existed, one of six request sites attached a bearer token. The
/// other five — archetype, feedback, biometric observe, weekly review, and the
/// second call inside `AriaService` — went out bare and 401'd against Forge's
/// own authorizer. Nothing surfaced, because each caller wrapped its call in
/// `try?` and fell back to locally generated content.
///
/// That combination is worse than an outage. An outage looks like an outage; a
/// silent permanent fallback looks like the product working, while every answer
/// is rule-based and no request has ever reached the server.
enum ForgeAPI {

    enum Failure: Error {
        /// The server answered, and said no.
        case http(status: Int, body: String)
        /// The request never completed.
        case transport(Error)
        /// Signed out, or a refresh Cognito refused.
        case auth(ForgeAuthError)
        case notConfigured

        var userMessage: String {
            switch self {
            case .http(let status, _) where status >= 500:
                return "Forge's server had a problem. Try again in a moment."
            case .http(let status, _) where status == 429:
                return "Too many requests just now. Give it a minute."
            case .http:
                return "Forge couldn't complete that request."
            case .transport:
                return "Couldn't reach Forge. Check your connection."
            case .auth(let error):
                return error.userMessage
            case .notConfigured:
                return "This build isn't pointed at a Forge server."
            }
        }

        /// Whether falling back to on-device generation is honest here.
        ///
        /// A transport failure, yes — the user is offline and local output is
        /// the best available. A 401 or a 500, no: those are Forge's problem,
        /// and hiding them behind plausible text is how they stay unfixed.
        var deservesOfflineFallback: Bool {
            switch self {
            case .transport: return true
            case .auth(let error): return error == .network
            default: return false
            }
        }
    }

    /// Attach the current bearer token, if there is one.
    @MainActor
    static func authorize(_ request: inout URLRequest) {
        if let header = ForgeAuthClient.shared.authorizationHeader() {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }
    }

    /// Send an already-built request with authentication and one 401 recovery.
    ///
    /// On 401 the access token is refreshed once and the request retried once.
    /// Twice would be a loop: if a freshly minted token is still rejected, the
    /// problem is not the token.
    ///
    /// Callers keep their own decoding — the shapes here are genuinely different
    /// — but none of them has to remember the header again.
    @discardableResult
    static func send(_ request: URLRequest,
                     session: URLSession = .shared) async throws -> (Data, HTTPURLResponse) {
        try await send(request, session: session, isRetry: false)
    }

    private static func send(_ original: URLRequest,
                             session: URLSession,
                             isRetry: Bool) async throws -> (Data, HTTPURLResponse) {
        var request = original
        await MainActor.run { authorize(&request) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw Failure.http(status: -1, body: "No HTTP response.")
        }

        if http.statusCode == 401 && !isRetry {
            do {
                _ = try await ForgeAuthClient.shared.refreshSession()
            } catch let error as ForgeAuthError {
                throw Failure.auth(error)
            }
            return try await send(original, session: session, isRetry: true)
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw Failure.auth(.signedOut) }
            let text = String(data: data, encoding: .utf8) ?? ""
            throw Failure.http(status: http.statusCode, body: String(text.prefix(400)))
        }

        return (data, http)
    }
}
