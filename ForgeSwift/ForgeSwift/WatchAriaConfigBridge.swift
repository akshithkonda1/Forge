import Foundation
import WatchConnectivity

// MARK: - WatchAriaConfigBridge
//
// Mirrors iPhone ARIA/backend config into the shared App Group **and** pushes
// it over WatchConnectivity. Simulators often do not share App Group data
// reliably between iPhone and Watch — WCSession application context is the
// reliable companion path for testing in Xcode.

enum WatchAriaConfigBridge {
    static let appGroupID = "group.com.forge.ForgeSwift"

    enum Keys {
        static let baseURL = "forge.aria.baseURL"
        static let userId = "forge.aria.userId"
        static let authToken = "forge.aria.authToken"
        static let firstName = "forge.user.firstName"
        /// ISO8601 stamp so the watch can ignore stale contexts.
        static let syncedAt = "forge.companion.syncedAt"
    }

    /// Payload keys used inside WCSession applicationContext / transferUserInfo.
    enum WC {
        static let config = "forge.companion.config"
    }

    @MainActor
    static func sync(firstName: String? = nil) {
        let baseURL = AriaService.shared.baseURL.absoluteString
        let userId = AriaContextStore.shared.context.userId
        let name = firstName
            ?? UserDefaults.standard.string(forKey: Keys.firstName)

        var payload: [String: String] = [
            Keys.baseURL: baseURL,
            Keys.userId: userId,
            Keys.syncedAt: ISO8601DateFormatter().string(from: Date()),
        ]
        if let name, !name.isEmpty {
            payload[Keys.firstName] = name
        }
        // Intentionally no authToken write yet — soft-auth backend tolerates missing Bearer.

        // 1) App Group (works on device when both apps share the suite)
        if let shared = UserDefaults(suiteName: appGroupID) {
            for (k, v) in payload { shared.set(v, forKey: k) }
        }

        // 2) Local defaults fallback (debug visibility on phone)
        for (k, v) in payload {
            UserDefaults.standard.set(v, forKey: k)
        }

        // 3) WatchConnectivity — reliable for paired simulator + device
        pushOverWatchConnectivity(payload)
    }

    private static func pushOverWatchConnectivity(_ payload: [String: String]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // Only the iPhone side should push companion config.
        #if os(iOS)
        let envelope: [String: Any] = [WC.config: payload]
        // Merge with any in-flight workout context so we don't clobber Live Activity state.
        var merged = session.applicationContext
        merged[WC.config] = payload
        do {
            try session.updateApplicationContext(merged)
        } catch {
            // Context can fail if not activated yet or rate-limited — best effort.
            session.transferUserInfo(envelope)
        }
        if session.isReachable {
            session.sendMessage(envelope, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(envelope)
            })
        } else {
            // Guaranteed delivery when the watch next wakes.
            session.transferUserInfo(envelope)
        }
        #endif
    }

    /// Apply a config dictionary received on the watch (or mirrored back).
    static func applyReceivedConfig(_ payload: [String: String]) {
        if let shared = UserDefaults(suiteName: appGroupID) {
            for (k, v) in payload { shared.set(v, forKey: k) }
        }
        for (k, v) in payload {
            UserDefaults.standard.set(v, forKey: k)
        }
    }

    /// Extract config from a WCSession message / context dictionary.
    static func config(from message: [String: Any]) -> [String: String]? {
        if let nested = message[WC.config] as? [String: String] {
            return nested
        }
        // Flat fallback
        var flat: [String: String] = [:]
        for key in [Keys.baseURL, Keys.userId, Keys.authToken, Keys.firstName, Keys.syncedAt] {
            if let v = message[key] as? String { flat[key] = v }
        }
        return flat.isEmpty ? nil : flat
    }
}
