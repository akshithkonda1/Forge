import Foundation

/// Stable ids for registered mouths. Kokoro is the only shipping engine.
public enum AriaVoiceEngineID: Sendable {
    public static let kokoro = "kokoro"
}

/// One mouth. Call sites never name a concrete engine.
///
/// A later engine registers under its own id. There is no speak-time
/// fallback: if the selected engine is missing or returns false, ARIA
/// stays silent and the text stays on screen.
public protocol AriaVoiceEngine: AnyObject {
    var id: String { get }
    func speak(_ text: String, voiceID: String, speed: Double) async -> Bool
    func stop()
}

/// In-memory selection. Empty / unknown values resolve to Kokoro.
public enum AriaVoiceEngineSelection: Sendable {
    public static let defaultsKey = "aria.voice.engine"
    public static let defaultID = AriaVoiceEngineID.kokoro

    public static func sanitize(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultID : trimmed
    }
}

/// Single registry. Swapping or removing an engine does not change speak
/// call sites. Removing the selected engine restores Kokoro when it is
/// still registered. Speak never walks the remaining engines.
public final class AriaVoiceEngineRegistry: @unchecked Sendable {
    public static let shared = AriaVoiceEngineRegistry()
    public static let defaultEngineID = AriaVoiceEngineSelection.defaultID

    private let lock = NSLock()
    private var engines: [String: any AriaVoiceEngine] = [:]
    private var selectedID: String = defaultEngineID

    public init() {}

    public var selectedEngineID: String {
        lock.lock()
        defer { lock.unlock() }
        return selectedID
    }

    public var registeredIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return engines.keys.sorted()
    }

    public func register(_ engine: any AriaVoiceEngine) {
        let id = AriaVoiceEngineSelection.sanitize(engine.id)
        lock.lock()
        engines[id] = engine
        lock.unlock()
    }

    public func unregister(_ id: String) {
        let key = AriaVoiceEngineSelection.sanitize(id)
        lock.lock()
        engines[key] = nil
        if selectedID == key {
            selectedID = engines[Self.defaultEngineID] != nil
                ? Self.defaultEngineID
                : key
        }
        lock.unlock()
    }

    /// Point at an id. The id may be unregistered — speak then fails closed.
    public func select(_ id: String) {
        lock.lock()
        selectedID = AriaVoiceEngineSelection.sanitize(id)
        lock.unlock()
    }

    public func engine(for id: String) -> (any AriaVoiceEngine)? {
        let key = AriaVoiceEngineSelection.sanitize(id)
        lock.lock()
        defer { lock.unlock() }
        return engines[key]
    }

    /// Selected engine only. Missing or a `false` return is silence.
    public func speak(
        _ text: String,
        voiceID: String,
        speed: Double
    ) async -> Bool {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return false }
        let engine = lockedSelectedEngine()
        guard let engine else { return false }
        return await engine.speak(line, voiceID: voiceID, speed: speed)
    }

    public func stop() {
        lockedSelectedEngine()?.stop()
    }

    public func resetForTests() {
        lock.lock()
        engines = [:]
        selectedID = Self.defaultEngineID
        lock.unlock()
    }

    private func lockedSelectedEngine() -> (any AriaVoiceEngine)? {
        lock.lock()
        defer { lock.unlock() }
        return engines[selectedID]
    }
}
