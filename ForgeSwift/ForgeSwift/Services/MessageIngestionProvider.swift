import Foundation
import ForgeCore

/// Where conversations come from — and the only way they come in.
///
/// Privacy contract
/// ----------------
/// What ARIA sees: nothing from a provider. Providers hand `MessageTurn`s to
/// `MessageContextEngine`, which hands back `LifeContextFact`s; only facts (and
/// the brief built from them) reach on-device ARIA, and never a remote model.
/// What stays on-device: the turns, in memory, for one fetch. A provider must
/// not cache, log, or write message text, and must give each contact a keyed
/// `ContactID` — never a name, handle, or phone number.
///
/// iOS has no public API for reading Messages, and Forge uses no private one:
/// no `ChatStorage`/`sms.db`, no private frameworks. Every provider is a door
/// the user opens on purpose, one conversation at a time:
/// - `ShareExtensionProvider` (ForgeShareExtension): text handed over from the
///   Share Sheet.
/// - `SyntheticMessageProvider`: a scripted conversation for Debug/TestFlight,
///   compiled only with `FORGE_DUMMY_ORCHESTRA`.
///
/// Compiled into both the app and ForgeShareExtension.
protocol MessageIngestionProvider {
    /// Human-readable source name for the privacy UI ("Shared via Share Sheet").
    var displayName: String { get }
    /// Returns new turns since the given date. Never caches raw text.
    func fetchTurns(since: Date) async throws -> [MessageTurn]
}
