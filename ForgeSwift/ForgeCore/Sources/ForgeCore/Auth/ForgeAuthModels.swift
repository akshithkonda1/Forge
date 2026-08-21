import Foundation

/// How this install is allowed to prove who the user is.
///
/// Production talks to Cognito. Debug builds may mint a local tester
/// session so a device or simulator can exercise the rest of the app
/// without AWS secrets. That path is compiled out of Release.
public enum ForgeAuthMode: String, Equatable, Sendable, Codable {
    case cognito
    case devOverride
}

public struct ForgeAuthConfig: Equatable, Sendable {
    public var apiBaseURL: URL
    public var cognitoRegion: String
    public var cognitoClientId: String
    public var cognitoUserPoolId: String
    /// `dev` / `test` / `local` / `ci` may use the tester account. Anything
    /// production-like must not, even in a debug binary pointed at prod.
    public var environment: String

    public init(
        apiBaseURL: URL,
        cognitoRegion: String = "",
        cognitoClientId: String = "",
        cognitoUserPoolId: String = "",
        environment: String = "dev"
    ) {
        self.apiBaseURL = apiBaseURL
        self.cognitoRegion = cognitoRegion
        self.cognitoClientId = cognitoClientId
        self.cognitoUserPoolId = cognitoUserPoolId
        self.environment = environment
    }

    public var cognitoConfigured: Bool {
        !cognitoRegion.isEmpty && !cognitoClientId.isEmpty
    }

    public var isProductionLike: Bool {
        ["prod", "production", "staging", "stage"].contains(environment.lowercased())
    }

    /// Matches `backend/infra/lambda/auth.py` `_TEST_USER_ID`.
    public static let testUserId = "test-user-00000000"
    public static let testEmail = "tester@forge.dev"

    public static let defaultLocalAPI = URL(string: "http://127.0.0.1:3001")!

    public static func fromInfoDictionary(_ info: [String: Any]) -> ForgeAuthConfig {
        let env = (info["FORGEEnvironment"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let api = (info["FORGEAPIBaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = (info["FORGECognitoRegion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = (info["FORGECognitoClientId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = (info["FORGECognitoUserPoolId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ForgeAuthConfig(
            apiBaseURL: URL(string: api ?? "") ?? defaultLocalAPI,
            cognitoRegion: region ?? "",
            cognitoClientId: client ?? "",
            cognitoUserPoolId: pool ?? "",
            environment: (env?.isEmpty == false ? env! : "dev")
        )
    }
}

public struct ForgeAuthSession: Equatable, Sendable, Codable {
    public var userId: String
    public var email: String
    public var displayName: String
    public var provider: String
    public var accessToken: String
    public var idToken: String?
    public var refreshToken: String?
    public var mode: ForgeAuthMode

    public init(
        userId: String,
        email: String,
        displayName: String,
        provider: String,
        accessToken: String,
        idToken: String? = nil,
        refreshToken: String? = nil,
        mode: ForgeAuthMode
    ) {
        self.userId = userId
        self.email = email
        self.displayName = displayName
        self.provider = provider
        self.accessToken = accessToken
        self.idToken = idToken
        self.refreshToken = refreshToken
        self.mode = mode
    }

    public var authorizationHeader: String { "Bearer \(accessToken)" }
}

public enum ForgeAuthPolicy {
    /// Compile-time gate. Release binaries cannot mint a tester session.
    public static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// The tester account is allowed only in a debug build pointed at a
    /// non-production environment, and only when the user (or a test) left
    /// the override switched on.
    public static func devOverrideAllowed(
        userEnabled: Bool,
        config: ForgeAuthConfig,
        debugBuild: Bool = isDebugBuild
    ) -> Bool {
        debugBuild && userEnabled && !config.isProductionLike
    }
}

/// Local identity the Lambda already accepts outside production
/// (`FORGE_TEST_USER_ID` / unsigned JWT `sub`).
public enum DevAuthOverride {
    public static let userId = ForgeAuthConfig.testUserId
    public static let email = ForgeAuthConfig.testEmail
    public static let displayName = "Tester"
    public static let provider = "dev-override"

    public static func session() -> ForgeAuthSession {
        ForgeAuthSession(
            userId: userId,
            email: email,
            displayName: displayName,
            provider: provider,
            accessToken: unsignedAccessToken(sub: userId, email: email),
            mode: .devOverride
        )
    }

    /// Three-part JWT with `alg: none`. The Lambda only reads `sub` in
    /// non-production; it never verifies the signature on this path.
    public static func unsignedAccessToken(sub: String, email: String) -> String {
        let header = base64URL(["alg": "none", "typ": "JWT"])
        let payload = base64URL([
            "sub": sub,
            "email": email,
            "token_use": "access",
            "iss": "forge-dev-override",
        ])
        return "\(header).\(payload)."
    }

    private static func base64URL(_ object: [String: String]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum CognitoPasswordAuth {
    public struct Result: Equatable, Sendable {
        public var accessToken: String
        public var idToken: String?
        public var refreshToken: String?
        public var userId: String
        public var email: String
    }

    public static func initiateAuthRequest(
        region: String,
        clientId: String,
        username: String,
        password: String
    ) throws -> URLRequest {
        guard !region.isEmpty, !clientId.isEmpty else {
            throw ForgeAuthError.cognitoNotConfigured
        }
        let url = URL(string: "https://cognito-idp.\(region).amazonaws.com/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.InitiateAuth", forHTTPHeaderField: "X-Amz-Target")
        let body: [String: Any] = [
            "AuthFlow": "USER_PASSWORD_AUTH",
            "ClientId": clientId,
            "AuthParameters": [
                "USERNAME": username,
                "PASSWORD": password,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public static func parseAuthResponse(_ data: Data, email: String) throws -> Result {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let type = object["__type"] as? String, type.lowercased().contains("exception") {
            let message = (object["message"] as? String) ?? "Sign-in failed."
            throw ForgeAuthError.cognitoRejected(message)
        }
        guard
            let result = object["AuthenticationResult"] as? [String: Any],
            let access = result["AccessToken"] as? String,
            !access.isEmpty
        else {
            throw ForgeAuthError.cognitoRejected("Cognito did not return tokens.")
        }
        let idToken = result["IdToken"] as? String
        let userId = jwtSubject(idToken) ?? jwtSubject(access) ?? email
        return Result(
            accessToken: access,
            idToken: idToken,
            refreshToken: result["RefreshToken"] as? String,
            userId: userId,
            email: email
        )
    }

    public static func jwtSubject(_ token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = payload.count % 4
        if pad > 0 { payload += String(repeating: "=", count: 4 - pad) }
        guard
            let data = Data(base64Encoded: payload),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (json["sub"] as? String) ?? (json["username"] as? String)
    }
}

public enum ForgeAuthError: Error, Equatable {
    case cognitoNotConfigured
    case cognitoRejected(String)
    case overrideDisabled
    case network
}
