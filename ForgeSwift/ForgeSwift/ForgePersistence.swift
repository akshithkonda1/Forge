import Foundation

enum ForgePersistence {
    private static let onboardedKey = "forge.isOnboarded"
    private static let idTokenKey = "forge.auth.idToken"
    private static let accessTokenKey = "forge.auth.accessToken"
    private static let refreshTokenKey = "forge.auth.refreshToken"

    static var isOnboarded: Bool {
        UserDefaults.standard.bool(forKey: onboardedKey)
    }

    static func setOnboarded(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: onboardedKey)
    }

    static func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: onboardedKey)
    }

    static func saveAuthTokens(idToken: String?, accessToken: String?, refreshToken: String?) {
        let defaults = UserDefaults.standard
        if let idToken { defaults.set(idToken, forKey: idTokenKey) } else { defaults.removeObject(forKey: idTokenKey) }
        if let accessToken { defaults.set(accessToken, forKey: accessTokenKey) } else { defaults.removeObject(forKey: accessTokenKey) }
        if let refreshToken { defaults.set(refreshToken, forKey: refreshTokenKey) } else { defaults.removeObject(forKey: refreshTokenKey) }
    }

    static func loadAuthTokens() -> (id: String?, access: String?, refresh: String?) {
        let defaults = UserDefaults.standard
        return (
            defaults.string(forKey: idTokenKey),
            defaults.string(forKey: accessTokenKey),
            defaults.string(forKey: refreshTokenKey)
        )
    }

    static func clearAuthTokens() {
        saveAuthTokens(idToken: nil, accessToken: nil, refreshToken: nil)
    }
}