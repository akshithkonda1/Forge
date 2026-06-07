import Foundation

enum APIConfig {
    static var baseURL: URL {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "FORGE_API_BASE_URL") as? String)
            ?? "http://127.0.0.1:3001"
        return resolveURL(raw)
    }

    static var displayHost: String {
        let host = baseURL.host ?? baseURL.absoluteString
        if let port = baseURL.port, port != 80 && port != 443 {
            return "\(host):\(port)"
        }
        return host
    }

    private static func resolveURL(_ raw: String) -> URL {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("localhost") {
            value = value.replacingOccurrences(of: "localhost", with: "127.0.0.1")
        }
        if let url = URL(string: value) { return url }
        return URL(string: "http://127.0.0.1:3001")!
    }

    static var usesAuth: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "FORGE_USE_AUTH") as? String) != "false"
    }

    static var cognitoRegion: String {
        Bundle.main.object(forInfoDictionaryKey: "FORGE_COGNITO_REGION") as? String ?? "us-east-1"
    }

    static var cognitoClientId: String {
        Bundle.main.object(forInfoDictionaryKey: "FORGE_COGNITO_CLIENT_ID") as? String ?? ""
    }

    static var cognitoEndpoint: URL {
        URL(string: "https://cognito-idp.\(cognitoRegion).amazonaws.com/")!
    }

    /// Release builds with auth enabled must ship a real API URL and Cognito client ID.
    static var configurationError: String? {
        #if DEBUG
        return nil
        #else
        guard usesAuth else { return nil }

        if cognitoClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return """
            Cognito is not configured for this Release build.
            Run scripts/generate_client_config.py after terraform apply, then archive again.
            See docs/PRODUCTION-CLIENTS.md.
            """
        }

        let host = baseURL.host ?? ""
        if host.isEmpty || host == "127.0.0.1" || host == "localhost" {
            return """
            Production API URL is missing for this Release build.
            Generate Forge-Production.xcconfig from Terraform output before archiving.
            See docs/PRODUCTION-CLIENTS.md.
            """
        }

        return nil
        #endif
    }
}