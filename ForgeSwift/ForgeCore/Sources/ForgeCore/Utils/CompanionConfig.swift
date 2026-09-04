import Foundation

// MARK: - CompanionConfig
//
// Parsing and classification for the configuration the iPhone pushes to the
// watch over WatchConnectivity, extracted from PhoneLinkService so the part
// that decides what is a secret can be tested without a paired device.
//
// This is a trust boundary. The payload arrives from another process, and
// where each value is written afterwards is a security decision: the session
// token belongs in the Keychain, while the base URL and first name belong in
// the shared App Group suite where the complications can read them. Getting
// that split wrong is how a token ends up in a plist, which is exactly what
// happened before.

public struct CompanionConfig: Equatable, Sendable {

    /// Values that must be written to a SecureStore.
    public static let secretKeys: Set<String> = [
        "forge.aria.authToken",
        "forge.aria.userId",
    ]

    /// Values that belong in the shared defaults suite.
    public static let preferenceKeys: Set<String> = [
        "forge.aria.baseURL",
        "forge.user.firstName",
        "forge.companion.syncedAt",
    ]

    /// The one nested form the iPhone may send instead of flat keys.
    public static let nestedKey = "forge.companion.config"

    public var secrets: [String: String]
    public var preferences: [String: String]

    public init(secrets: [String: String] = [:], preferences: [String: String] = [:]) {
        self.secrets = secrets
        self.preferences = preferences
    }

    public var isEmpty: Bool { secrets.isEmpty && preferences.isEmpty }

    /// Classifies a WatchConnectivity payload, or nil when it carries no
    /// configuration at all.
    ///
    /// Workout payloads travel the same channel in the other direction and are
    /// rejected outright rather than parsed — the watch is their sender, and
    /// treating one as configuration would be reading its own echo.
    ///
    /// Keys outside the two allowlists are dropped rather than passed through.
    /// An unrecognised key has no defined destination, and defaulting it to the
    /// plist is the failure mode this type exists to prevent.
    public static func parse(_ message: [String: Any]) -> CompanionConfig? {
        if message[WorkoutLinkKeys.state] != nil || message[WorkoutLinkKeys.ended] != nil {
            return nil
        }

        let source: [String: String]
        if let nested = message[nestedKey] as? [String: String] {
            source = nested
        } else {
            var flat: [String: String] = [:]
            for (key, value) in message {
                if let string = value as? String { flat[key] = string }
            }
            source = flat
        }

        var config = CompanionConfig()
        for (key, value) in source {
            if secretKeys.contains(key) {
                config.secrets[key] = value
            } else if preferenceKeys.contains(key) {
                config.preferences[key] = value
            }
        }
        return config.isEmpty ? nil : config
    }
}
