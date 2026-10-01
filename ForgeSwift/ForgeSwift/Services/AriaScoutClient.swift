import Foundation
import ForgeCore

/// ARIA's line to Scout — the agentic, always-on research computer.
///
/// Scout lives on one small EC2 box behind Forge's API Gateway
/// (`POST /scout/research`, Cognito JWT). It runs SearXNG over Google, Bing,
/// DuckDuckGo, Brave and friends, reads the best pages, and has Grok on
/// Bedrock write a short cited brief. ARIA calls it only when the situation
/// read says a question needs the open web.
///
/// What leaves the phone is the scrubbed keyword query and a topic word —
/// never the message, names, numbers, health samples, or location. What comes
/// back is untrusted outside data (`AriaWebEvidence`), never user facts.
///
/// Returns nil — and the Dummy falls back to the keyless health sources —
/// when there is no signed-in session (Device Hub dev override), the API is a
/// loopback URL, Scout is switched off, or anything fails. Called only from
/// `AriaWebResearch` (`scripts/check-aria-web-research.py`).
@MainActor
enum AriaScoutClient {

    /// Settings / DEBUG kill-switch. Missing means on.
    static let enabledKey = "forge.aria.scout.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // Scout's own budget is 24 s under API Gateway's 29 s ceiling.
        config.timeoutIntervalForRequest = 28
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// True when a remote call could succeed: enabled, an https non-loopback
    /// API, and a signed-in session to carry the Cognito JWT.
    static var isAvailable: Bool {
        isEnabled && endpoint() != nil && ForgeAuthClient.shared.authorizationHeader() != nil
    }

    static func endpoint() -> URL? {
        let base = AriaService.shared.baseURL
        guard base.scheme == "https",
              let host = base.host,
              host != "localhost", host != "127.0.0.1", host != "::1" else { return nil }
        return base.appendingPathComponent("scout/research")
    }

    static func research(query: String, topic: String) async -> AriaWebEvidence? {
        let clean = AriaQueryPrivacy.scrub(query)
        guard isEnabled, !clean.isEmpty, let url = endpoint() else { return nil }
        // No session → no JWT → API Gateway would 401 and ForgeAPI would try a
        // refresh that cannot succeed. Skip straight to the keyless sources.
        guard ForgeAuthClient.shared.authorizationHeader() != nil else { return nil }
        guard let body = try? JSONSerialization.data(withJSONObject: ["query": clean, "topic": topic]) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let result = try? await ForgeAPI.send(request, session: session) else { return nil }
        return AriaWebParsers.scoutBrief(result.0)
    }
}
