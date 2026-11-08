import Foundation

/// One saved pharmacy item. `id` is the federal catalog id when known;
/// `name` is the display string the user saw.
public struct SavedMedication: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct PharmacyVaultState: Codable, Equatable, Sendable {
    public var items: [SavedMedication]
    public var shareWithAria: Bool
    public var lastRefreshFailed: Bool
    public var lastRefreshAt: Date?

    public static let empty = PharmacyVaultState(
        items: [],
        shareWithAria: false,
        lastRefreshFailed: false,
        lastRefreshAt: nil
    )

    public init(
        items: [SavedMedication],
        shareWithAria: Bool = false,
        lastRefreshFailed: Bool = false,
        lastRefreshAt: Date? = nil
    ) {
        self.items = items
        self.shareWithAria = shareWithAria
        self.lastRefreshFailed = lastRefreshFailed
        self.lastRefreshAt = lastRefreshAt
    }
}

public enum PharmacySaveResult: Equatable, Sendable {
    case added
    case removed
    case atCap
    /// The secure copy could not be read (for example before first unlock).
    /// Nothing was changed, so a saved list is never overwritten by a guess.
    case unavailable
}

/// Keychain-backed pharmacy list. Medication names never sit in a plist.
///
/// Matches the cycle-vault rule: write the secure copy first, delete the
/// plaintext `UserDefaults` key only after that write succeeds.
public final class PharmacyVault {

    public static let cap = 40
    public static let storageKey = "forge.pharmacy.vault.v1"
    public static let legacySavedKey = "forge.pharmacy.saved.v1"

    private let store: SecureStore
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cached: PharmacyVaultState?
    /// True when the last read of the secure copy threw, as opposed to finding
    /// nothing. While true, writes are refused so an empty guess cannot replace
    /// a real list.
    private var readFailed = false

    public init(store: SecureStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    public static func makeDefault() -> PharmacyVault {
        let tests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let store: SecureStore
        if tests {
            store = InMemorySecureStore()
        } else {
            #if canImport(Security)
            store = KeychainStore(service: "com.forge.ForgeSwift.pharmacy")
            #else
            store = InMemorySecureStore()
            #endif
        }
        return PharmacyVault(store: store)
    }

    public func load() -> PharmacyVaultState {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let state = readUnlocked()
        if !readFailed { cached = state }
        return state
    }

    public func savedNames() -> [String] {
        load().items.map(\.name)
    }

    public func contains(id: String, name: String) -> Bool {
        let state = load()
        return state.items.contains {
            $0.id.caseInsensitiveCompare(id) == .orderedSame
                || $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    @discardableResult
    public func toggle(id: String, name: String) -> PharmacySaveResult {
        lock.lock(); defer { lock.unlock() }
        guard var state = mutableStateUnlocked() else { return .unavailable }
        if let index = indexOf(id: id, name: name, in: state.items) {
            state.items.remove(at: index)
            persistUnlocked(state)
            return .removed
        }
        guard state.items.count < Self.cap else {
            persistUnlocked(state)
            return .atCap
        }
        state.items.insert(SavedMedication(id: id, name: name), at: 0)
        persistUnlocked(state)
        return .added
    }

    @discardableResult
    public func ensure(id: String, name: String) -> PharmacySaveResult {
        lock.lock(); defer { lock.unlock() }
        guard var state = mutableStateUnlocked() else { return .unavailable }
        if indexOf(id: id, name: name, in: state.items) != nil {
            return .added
        }
        guard state.items.count < Self.cap else {
            persistUnlocked(state)
            return .atCap
        }
        state.items.insert(SavedMedication(id: id, name: name), at: 0)
        persistUnlocked(state)
        return .added
    }

    public func setShareWithAria(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard var state = mutableStateUnlocked() else { return }
        state.shareWithAria = value
        persistUnlocked(state)
    }

    public func setRefreshOutcome(failed: Bool, at: Date? = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard var state = mutableStateUnlocked() else { return }
        state.lastRefreshFailed = failed
        if !failed { state.lastRefreshAt = at }
        persistUnlocked(state)
    }

    public func wipe() {
        lock.lock(); defer { lock.unlock() }
        cached = .empty
        readFailed = false
        try? store.remove(Self.storageKey)
        defaults.removeObject(forKey: Self.legacySavedKey)
    }

    // MARK: - IO

    /// The state a mutation should start from, or nil when the secure copy
    /// exists but cannot be read right now.
    private func mutableStateUnlocked() -> PharmacyVaultState? {
        if let cached { return cached }
        let state = readUnlocked()
        if readFailed { return nil }
        cached = state
        return state
    }

    private func readUnlocked() -> PharmacyVaultState {
        let stored: Data?
        do {
            stored = try store.data(forKey: Self.storageKey)
            readFailed = false
        } catch {
            // Locked or unavailable Keychain: say so, and do not migrate or
            // write anything on top of what we could not see.
            readFailed = true
            return .empty
        }
        if let data = stored,
           let state = try? JSONDecoder().decode(PharmacyVaultState.self, from: data) {
            defaults.removeObject(forKey: Self.legacySavedKey)
            return state
        }
        let migrated = migrateLegacyUnlocked()
        if migrated != .empty {
            persistUnlocked(migrated)
        }
        return migrated
    }

    private func migrateLegacyUnlocked() -> PharmacyVaultState {
        guard let names = defaults.stringArray(forKey: Self.legacySavedKey), !names.isEmpty else {
            return .empty
        }
        var seen = Set<String>()
        let items = names.compactMap { raw -> SavedMedication? in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let id = name.lowercased()
            guard seen.insert(id).inserted else { return nil }
            return SavedMedication(id: id, name: name)
        }
        return PharmacyVaultState(
            items: Array(items.prefix(Self.cap)),
            shareWithAria: false,
            lastRefreshFailed: false,
            lastRefreshAt: nil
        )
    }

    private func persistUnlocked(_ state: PharmacyVaultState) {
        cached = state
        do {
            try store.setValue(state, forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.legacySavedKey)
        } catch {
            // Leave the last good secure copy in place. Do not write names
            // back to UserDefaults — that would undo the migration.
        }
    }

    private func indexOf(id: String, name: String, in items: [SavedMedication]) -> Int? {
        items.firstIndex {
            $0.id.caseInsensitiveCompare(id) == .orderedSame
                || $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
