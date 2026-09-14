import Foundation
import WatchConnectivity
import ForgeCore

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
        if let token = ForgeAuthClient.shared.session?.accessToken, !token.isEmpty {
            payload[Keys.authToken] = token
        }

        // Persist non-secrets only. Auth tokens / user ids are secrets
        // (`CompanionConfig.secretKeys`) and must never land in App Group or
        // standard UserDefaults plists (those ride along in backups). The
        // watch still receives secrets over the encrypted WCSession channel
        // and stores them in Keychain via PhoneLinkService.
        let preferencePayload = payload.filter { CompanionConfig.preferenceKeys.contains($0.key) }
        if let shared = UserDefaults(suiteName: appGroupID) {
            for (k, v) in preferencePayload { shared.set(v, forKey: k) }
            for secret in CompanionConfig.secretKeys {
                shared.removeObject(forKey: secret)
            }
        }
        for (k, v) in preferencePayload {
            UserDefaults.standard.set(v, forKey: k)
        }
        for secret in CompanionConfig.secretKeys {
            UserDefaults.standard.removeObject(forKey: secret)
        }

        // WatchConnectivity — reliable for paired simulator + device.
        // Full payload (including secrets) is pushed here only.
        pushOverWatchConnectivity(payload)
    }

    private static func pushOverWatchConnectivity(_ payload: [String: String]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // Only the iPhone side should push companion config.
        #if os(iOS)
        // Simulator / unpaired phone: no Watch app → updateApplicationContext
        // spam `WCErrorCodeWatchAppNotInstalled` and "Application context data is nil".
        guard session.isPaired, session.isWatchAppInstalled else { return }

        let envelope: [String: Any] = [WC.config: payload]
        // Merge with any in-flight workout context so we don't clobber Live Activity state.
        var merged = session.applicationContext
        merged[WC.config] = payload
        do {
            try session.updateApplicationContext(merged)
        } catch {
            // Context can fail if not activated yet or rate-limited — best effort.
            // Do not fall back to transferUserInfo when the watch app is missing;
            // that path logs the same WCError noise.
            guard session.isWatchAppInstalled else { return }
            session.transferUserInfo(envelope)
        }
        guard session.isWatchAppInstalled else { return }
        if session.isReachable {
            session.sendMessage(envelope, replyHandler: nil, errorHandler: { _ in
                guard WCSession.default.isWatchAppInstalled else { return }
                WCSession.default.transferUserInfo(envelope)
            })
        } else {
            // Guaranteed delivery when the watch next wakes.
            session.transferUserInfo(envelope)
        }
        #endif
    }

    /// Apply a config dictionary received on the watch (or mirrored back).
    static func applyReceivedConfig(_ payload: [String: String]) {
        // Mirror the phone-side rule: preferences may live in defaults;
        // secrets never do. Watch Keychain ingestion is owned by PhoneLinkService.
        let preferencePayload = payload.filter { CompanionConfig.preferenceKeys.contains($0.key) }
        if let shared = UserDefaults(suiteName: appGroupID) {
            for (k, v) in preferencePayload { shared.set(v, forKey: k) }
            for secret in CompanionConfig.secretKeys {
                shared.removeObject(forKey: secret)
            }
        }
        for (k, v) in preferencePayload {
            UserDefaults.standard.set(v, forKey: k)
        }
        for secret in CompanionConfig.secretKeys {
            UserDefaults.standard.removeObject(forKey: secret)
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
