import Foundation

// MARK: - WatchAriaConfigBridge
//
// The watch's ARIAWatchService reads its backend base URL and auth token
// from the shared App Group suite (`forge.aria.baseURL` /
// `forge.aria.authToken`) — see ForgeWatch/Managers/ARIAWatchService.swift.
// Nothing wrote those keys until now. This bridge mirrors the iOS app's
// existing config (AriaService.baseURL, AriaContextStore's stable user
// id) into the App Group on launch and whenever the base URL changes, so
// the watch's deeper-coaching call (`/watch/aria/suggest`) actually
// reaches the same backend the phone talks to.
//
// No real token store exists yet (soft-auth backend, matching
// `auth.extract_user_id`'s Cognito-or-test-user fallback) — the token key
// is only written once one exists, and the watch already treats it as
// optional.

enum WatchAriaConfigBridge {
    private static let appGroupID = "group.com.forge.ForgeSwift"
    private static let baseURLKey = "forge.aria.baseURL"
    private static let userIdKey = "forge.aria.userId"
    private static let authTokenKey = "forge.aria.authToken"

    @MainActor
    static func sync() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else { return }
        sharedDefaults.set(AriaService.shared.baseURL.absoluteString, forKey: baseURLKey)
        sharedDefaults.set(AriaContextStore.shared.context.userId, forKey: userIdKey)
        // Intentionally no authToken write yet — see note above.
    }
}
