import Foundation

/// Human-readable ingest failures. Call sites should surface this string
/// rather than crash or swallow the error.
public enum LifeIngestError: Sendable {

    /// `"Couldn't write the Forge test calendar: no writable EventKit source."`
    public static func explain(_ error: Error, doing: String) -> String {
        let action = doing.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = Self.reason(from: error)
        if action.isEmpty { return reason }
        if reason.isEmpty { return action }
        if reason.hasPrefix(action) { return reason }
        return "\(action): \(reason)"
    }

    public static func skipped(doing: String, because: String) -> String {
        let action = doing.trimmingCharacters(in: .whitespacesAndNewlines)
        let because = because.trimmingCharacters(in: .whitespacesAndNewlines)
        if action.isEmpty { return because }
        if because.isEmpty { return "\(action) skipped" }
        return "\(action) skipped: \(because)"
    }

    /// Keep the first failure and append a later distinct one so Home can
    /// show both a HealthKit and a calendar reason from the same launch.
    public static func combine(existing: String?, incoming: String?) -> String? {
        guard let incoming else { return existing }
        let trimmed = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return existing }
        guard let existing, !existing.isEmpty else { return trimmed }
        if existing.contains(trimmed) { return existing }
        return existing + " " + trimmed
    }

    /// Prefer `LocalizedError` copy. Generic Swift/`NSError` bridging
    /// (`"The operation couldn’t be completed"`) is replaced with the type
    /// name and domain so the UI can say *what* failed.
    public static func reason(from error: Error) -> String {
        if let localized = error as? LocalizedError {
            let pieces = [localized.errorDescription, localized.failureReason]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let first = pieces.first {
                return first
            }
        }
        let ns = error as NSError
        let desc = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let typeName = String(describing: type(of: error))
        let isGeneric = desc.isEmpty || desc.hasPrefix("The operation could")
        if isGeneric {
            if ns.domain.isEmpty {
                return typeName
            }
            return "\(typeName) (\(ns.domain) \(ns.code))"
        }
        return desc
    }
}
