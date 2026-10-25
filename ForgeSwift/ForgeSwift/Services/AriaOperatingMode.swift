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
    /// Pass `client` when the caller is that client (or is still constructing
    /// it) so resolution never reads `ForgeAuthClient.shared`.
    @MainActor
    @discardableResult
    static func refresh(using client: ForgeAuthClient? = nil) -> AriaOperatingMode {
        let next = resolve(using: client)
        current = next
        return next
    }

    /// Explicit DEBUG/Settings choice. Pass `nil` to clear and re-resolve.
    /// `.dummy` is refused (treated as "clear") when the Dummy is compiled out.
    @MainActor
    static func setOverride(_ mode: AriaOperatingMode?) {
        if let mode, mode.isAvailable {
            UserDefaults.standard.set(mode.rawValue, forKey: overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: overrideKey)
        }
        refresh()
    }

    @MainActor
    static var hasOverride: Bool {
        guard let raw = UserDefaults.standard.string(forKey: overrideKey),
              let mode = AriaOperatingMode(rawValue: raw) else { return false }
        return mode.isAvailable
    }

    /// Modes this build can actually run. A production build has no Dummy.
    static var selectableCases: [AriaOperatingMode] {
        allCases.filter { $0.isAvailable }
    }

    /// False only for `.dummy` in a build with the Dummy compiled out.
    var isAvailable: Bool {
        self != .dummy || AriaDummyOrchestra.isCompiledIn
    }

    /// Bundle / Info.plist only — safe during `ForgeAuthClient` init.
    static func resolveFromBundle() -> AriaOperatingMode {
        let config = ForgeAuthConfig.fromInfoDictionary(Bundle.main.infoDictionary ?? [:])
        #if DEBUG && FORGE_DUMMY_ORCHESTRA
        if config.environment.lowercased() == "dummy" || config.apiIsLoopback {
            return .dummy
        }
        #endif
        return .localTesting
    }

    @MainActor
    static func resolve(using client: ForgeAuthClient? = nil) -> AriaOperatingMode {
        if let client = client ?? ForgeAuthClient.sharedIfReady {
            return resolve(
                session: client.session,
                config: client.config,
                canUseDevOverride: client.canUseDevOverride
            )
        }
        return persistedOverride() ?? resolveFromBundle()
    }

    /// Session-aware resolution that never reads `ForgeAuthClient.shared`.
    @MainActor
    static func resolve(
        session: ForgeAuthSession?,
        config: ForgeAuthConfig,
        canUseDevOverride: Bool
    ) -> AriaOperatingMode {
        if let override = persistedOverride() { return override }
        if AriaDummyOrchestra.isCompiledIn,
           canUseDevOverride,
           (session?.mode == .devOverride
            || config.environment.lowercased() == "dummy"
            || config.apiIsLoopback
            || ForgeAuthPolicy.isXcodeDeviceHubLaunch) {
            return .dummy
        }
        return resolveFromBundle()
    }

    /// A `.dummy` override persisted by an older TestFlight build is
    /// ignored once the Dummy is compiled out.
    @MainActor
    private static func persistedOverride() -> AriaOperatingMode? {
        guard let raw = UserDefaults.standard.string(forKey: overrideKey),
              let mode = AriaOperatingMode(rawValue: raw),
              mode.isAvailable else { return nil }
        return mode
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
