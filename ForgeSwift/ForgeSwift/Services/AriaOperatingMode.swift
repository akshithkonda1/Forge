import Foundation

/// Which ARIA the app is actually talking to.
///
/// This is the seam between the local testing experience and the real backend.
/// Chat consults it in `AriaService.sendMessage`, after the Test-Ready dummy
/// gate. The voice session uses those same two gates, in that same order, in
/// `AriaVoiceTransport.resolve` — dummy first, so Device Hub cannot fall
/// through to local testing or live ConvAI. Do not consult this flag from
/// random call sites; a mode that is checked in fifteen files stops being a
/// mode and starts being a tangle.
enum AriaOperatingMode {

    /// Everything runs on this device. HealthKit / wearables are read here.
    /// Claude and Grok are the only off-device intelligence, and they never
    /// receive the HealthKit warehouse — `LocalTestingOrchestrator` answers
    /// from on-device generators and tools.
    case localTesting

    /// Claude / Grok via `AriaService.postChat`. Health samples still stay on
    /// this iPhone (`AriaOnDeviceHealthPolicy`). Local generation remains the
    /// offline fallback.
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
