import Foundation

enum CognitoAuthError: LocalizedError {
    case notConfigured
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Cognito is not configured. Add FORGE_COGNITO_CLIENT_ID to Info.plist."
        case .invalidResponse: return "Unexpected response from Cognito."
        case .service(let message): return message
        }
    }
}

struct CognitoAuthResult {
    let idToken: String
    let accessToken: String
    let refreshToken: String
}

@MainActor
final class CognitoAuthManager: ObservableObject {
    static let shared = CognitoAuthManager()

    @Published private(set) var idToken: String?
    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var lastError: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        if !APIConfig.usesAuth {
            isAuthenticated = true
        }
    }

    func setTokens(idToken: String?, accessToken: String? = nil, refreshToken: String? = nil) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        isAuthenticated = idToken != nil || !APIConfig.usesAuth
        lastError = nil
    }

    func signOut() {
        idToken = nil
        accessToken = nil
        refreshToken = nil
        isAuthenticated = !APIConfig.usesAuth
        lastError = nil
    }

    var authorizationHeader: String? {
        guard APIConfig.usesAuth, let idToken else { return nil }
        return "Bearer \(idToken)"
    }

    func signUp(email: String, password: String) async throws {
        try ensureConfigured()
        _ = try await invoke(
            target: "AWSCognitoIdentityProviderService.SignUp",
            payload: [
                "ClientId": APIConfig.cognitoClientId,
                "Username": email,
                "Password": password,
                "UserAttributes": [["Name": "email", "Value": email]],
            ]
        )
    }

    func confirmSignUp(email: String, code: String) async throws {
        try ensureConfigured()
        _ = try await invoke(
            target: "AWSCognitoIdentityProviderService.ConfirmSignUp",
            payload: [
                "ClientId": APIConfig.cognitoClientId,
                "Username": email,
                "ConfirmationCode": code,
            ]
        )
    }

    func signIn(email: String, password: String) async throws -> CognitoAuthResult {
        try ensureConfigured()
        let response = try await invoke(
            target: "AWSCognitoIdentityProviderService.InitiateAuth",
            payload: [
                "AuthFlow": "USER_PASSWORD_AUTH",
                "ClientId": APIConfig.cognitoClientId,
                "AuthParameters": [
                    "USERNAME": email,
                    "PASSWORD": password,
                ],
            ]
        )

        guard
            let result = response["AuthenticationResult"] as? [String: Any],
            let idToken = result["IdToken"] as? String,
            let accessToken = result["AccessToken"] as? String,
            let refreshToken = result["RefreshToken"] as? String
        else {
            throw CognitoAuthError.invalidResponse
        }

        setTokens(idToken: idToken, accessToken: accessToken, refreshToken: refreshToken)
        return CognitoAuthResult(idToken: idToken, accessToken: accessToken, refreshToken: refreshToken)
    }

    private func ensureConfigured() throws {
        guard !APIConfig.cognitoClientId.isEmpty else {
            throw CognitoAuthError.notConfigured
        }
    }

    private func invoke(target: String, payload: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: APIConfig.cognitoEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue(target, forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CognitoAuthError.invalidResponse
        }

        let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if (200...299).contains(http.statusCode) {
            return body
        }

        let message = (body["message"] as? String) ?? "Cognito request failed (\(http.statusCode))"
        lastError = message
        throw CognitoAuthError.service(message)
    }
}
