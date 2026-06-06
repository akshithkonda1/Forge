import Foundation

@MainActor
final class CognitoAuthManager: ObservableObject {
    static let shared = CognitoAuthManager()

    @Published private(set) var accessToken: String?
    @Published private(set) var isAuthenticated = false

    private init() {
        if !APIConfig.usesAuth {
            isAuthenticated = true
        }
    }

    func setAccessToken(_ token: String?) {
        accessToken = token
        isAuthenticated = token != nil || !APIConfig.usesAuth
    }

    func signOut() {
        accessToken = nil
        isAuthenticated = !APIConfig.usesAuth
    }

    var authorizationHeader: String? {
        guard APIConfig.usesAuth, let accessToken else { return nil }
        return "Bearer \(accessToken)"
    }
}
