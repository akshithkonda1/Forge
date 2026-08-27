import Foundation

/// Which ARIA the app is actually talking to.
///
/// This is the single seam between the local testing experience and the real
/// backend. It is checked in exactly one place — `AriaService.sendMessage`,
/// alongside the existing Test-Ready check — and deliberately nowhere else. A
/// mode flag that gets consulted in fifteen files stops being a mode and starts
/// being a tangle.
enum AriaOperatingMode {

    /// Everything runs on this device. No `URLSession`, no model, no cloud —
    /// `LocalTestingOrchestrator` answers from `RuleBasedResponseGenerator` and
    /// `AriaVoiceEngine`, the same two pieces that already back offline mode.
    case localTesting

    /// The real thing: `AriaService.postChat` against the deployed backend,
    /// with local generation kept as the offline fallback it was always meant
    /// to be.
    case liveBackend

    /// Swap to `.liveBackend` once auth is trusted end to end — sign-in now
    /// lives in `ForgeAuthClient.signIn(email:password:)`, hand-rolled against
    /// Cognito, not the placeholder `AppStore.authenticate()` this was
    /// originally written against. That method no longer exists.
    ///
    /// Until that swap, this is the only ARIA experience that actually runs.
    ///
    /// `@MainActor` because every reader is already main-actor isolated
    /// (`AriaService`, `AppStore`), which keeps this a plain settable flag
    /// instead of needing `nonisolated(unsafe)`.
    @MainActor
    static var current: AriaOperatingMode = .localTesting

    /// Local testing is a deliberate, visible choice. It is not the silent
    /// `try?` fallback that used to swallow a 500 and dress it up as coaching —
    /// that distinction is the whole reason this enum exists rather than a
    /// bool named `useFakeData`.
    var isLocalTesting: Bool { self == .localTesting }

    /// Shown in the UI wherever offline/test state is surfaced, so nobody
    /// mistakes a local answer for a backend one.
    var badge: String {
        switch self {
        case .localTesting: return "Local testing — on-device ARIA, no cloud."
        case .liveBackend:  return "Live backend."
        }
    }
}
