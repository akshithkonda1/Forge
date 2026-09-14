import Foundation
import Observation
import WatchConnectivity
import ForgeCore

// MARK: - CompanionGate
//
// Observable reachability + auth-config gate for Forge Watch. Standalone
// glanceables stay unlocked; phone-required actions ask through `allows(_:)`.

@MainActor
@Observable
final class CompanionGate {
    private(set) var availability: CompanionAvailability = .unknown
    private(set) var hasAuthConfig: Bool = false

    /// Calm one-liner when the Watch is independent of a nearby iPhone.
    var independenceBanner: String? {
        PhoneDependency.independenceBanner(for: availability)
    }

    func allows(_ capability: WatchCapability) -> Bool {
        PhoneDependency.allows(
            capability,
            availability: availability,
            hasAuthConfig: hasAuthConfig
        )
    }

    func explanation(for capability: WatchCapability) -> String? {
        PhoneDependency.explanation(
            for: capability,
            availability: availability,
            hasAuthConfig: hasAuthConfig
        )
    }

    /// Refresh from WCSession + Keychain / App Group preferences.
    func refresh(secureStore: SecureStore = KeychainStore()) {
        hasAuthConfig = Self.readHasAuthConfig(secureStore: secureStore)
        availability = Self.readAvailability()
    }

    static func readAvailability(
        session: WCSession? = WCSession.isSupported() ? .default : nil
    ) -> CompanionAvailability {
        guard let session else { return .unavailable }
        switch session.activationState {
        case .notActivated, .inactive:
            return .unknown
        case .activated:
            break
        @unknown default:
            return .unknown
        }
        #if os(watchOS)
        if !session.isCompanionAppInstalled {
            return .unavailable
        }
        #endif
        return session.isReachable ? .reachable : .linkedButUnreachable
    }

    static func readHasAuthConfig(
        secureStore: SecureStore = KeychainStore(),
        defaults: UserDefaults? = UserDefaults(suiteName: WatchSnapshotStore.appGroupID)
    ) -> Bool {
        let token = (try? secureStore.string(forKey: "forge.aria.authToken")) ?? ""
        let base = defaults?.string(forKey: "forge.aria.baseURL")
            ?? UserDefaults.standard.string(forKey: "forge.aria.baseURL")
            ?? ""
        return !token.isEmpty && !base.isEmpty
    }
}
