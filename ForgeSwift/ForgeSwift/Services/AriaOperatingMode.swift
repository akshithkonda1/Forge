import Foundation
import ForgeCore

/// Which ARIA the app is actually talking to.
///
/// This is the seam between the local testing experience, the deterministic
/// Dummy orchestra (tune without AI), and the real backend. Chat consults it
/// in `AriaService.sendMessage`, after the Test-Ready dummy gate. The voice
/// session uses those same gates in `AriaVoiceTransport.resolve` — dummy
/// first, so Device Hub cannot fall through to live ConvAI.
enum AriaOperatingMode: String, CaseIterable, Identifiable {

    /// Deterministic Dummy orchestra — no Bedrock, no cloud LLM.
    /// Canonical path for tuning ARIA before live AI.
    case dummy

    /// On-device local testing brain (separate from Dummy). HealthKit /
    /// wearables stay here; Claude/Grok never receive the warehouse.
    case localTesting

    /// Claude / Grok via `AriaService.postChat`. Health samples still stay on
    /// this iPhone (`AriaOnDeviceHealthPolicy`).
    case liveBackend

    var id: String { rawValue }

    /// Persisted override. Empty / missing → resolve from auth + environment.
    private static let overrideKey = "forge.aria.operatingMode"

    /// `@MainActor` because every reader is already main-actor isolated.
    @MainActor
    static var current: AriaOperatingMode = .resolveFromBundle()

    /// Re-read auth / env / override. Call after tester install or Settings change.
    @MainActor
    @discardableResult
    static func refresh() -> AriaOperatingMode {
        let next = resolve()
        current = next
        return next
    }

    /// Explicit DEBUG/Settings choice. Pass `nil` to clear and re-resolve.
    @MainActor
    static func setOverride(_ mode: AriaOperatingMode?) {
        if let mode {
            UserDefaults.standard.set(mode.rawValue, forKey: overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: overrideKey)
        }
        refresh()
    }

    @MainActor
    static var hasOverride: Bool {
        UserDefaults.standard.string(forKey: overrideKey) != nil
    }

    /// Bundle / Info.plist only — safe during `ForgeAuthClient` init.
    static func resolveFromBundle() -> AriaOperatingMode {
        let config = ForgeAuthConfig.fromInfoDictionary(Bundle.main.infoDictionary ?? [:])
        #if DEBUG
        if config.environment.lowercased() == "dummy" || config.apiIsLoopback {
            return .dummy
        }
        #endif
        return .localTesting
    }

    @MainActor
    static func resolve() -> AriaOperatingMode {
        if let raw = UserDefaults.standard.string(forKey: overrideKey),
           let mode = AriaOperatingMode(rawValue: raw) {
            return mode
        }
        // Session-aware when auth client is ready.
        let client = ForgeAuthClient.shared
        if client.canUseDevOverride,
           (client.session?.mode == .devOverride
            || client.config.environment.lowercased() == "dummy"
            || client.config.apiIsLoopback
            || ForgeAuthPolicy.isXcodeDeviceHubLaunch) {
            return .dummy
        }
        return resolveFromBundle()
    }

    /// Offline coaches (Dummy + Local) never hit Bedrock.
    var isOfflineCoach: Bool {
        self == .dummy || self == .localTesting
    }

    var isLocalTesting: Bool { self == .localTesting }
    var isDummy: Bool { self == .dummy }

    var badge: String {
        switch self {
        case .dummy:
            return "Dummy orchestra — deterministic, no cloud AI."
        case .localTesting:
            return "Local testing — on-device ARIA, no cloud."
        case .liveBackend:
            return "Live backend."
        }
    }

    var settingsLabel: String {
        switch self {
        case .dummy: return "Dummy (tune without AI)"
        case .localTesting: return "Local testing"
        case .liveBackend: return "Live backend"
        }
    }
}
