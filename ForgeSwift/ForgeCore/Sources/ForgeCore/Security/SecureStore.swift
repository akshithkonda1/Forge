import Foundation

#if canImport(Security)
import Security
#endif

// ============================================================
// MARK: - Protocol
// ============================================================

/// Storage for values that must not sit in a plist.
///
/// The distinction this type exists to enforce: `UserDefaults` writes an
/// unencrypted plist inside the app container, and that container is included in
/// iCloud and iTunes backups. For a session token that means a stolen backup is a
/// stolen session. For cycle data it means reproductive health information leaves
/// the device in the clear, which in several US states is a legal exposure rather
/// than merely an Apple one.
///
/// A protocol rather than a concrete type because the Keychain cannot be
/// exercised in CI — the data-protection keychain needs an entitlement no test
/// process has — so every consumer takes this and tests against
/// `InMemorySecureStore`.
public protocol SecureStore: AnyObject {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data?, forKey key: String) throws
    func removeAll() throws
}

public enum SecureStoreError: Error, Equatable {
    /// A non-success OSStatus from the Security framework, carried verbatim so a
    /// caller can distinguish "no entitlement" from "user locked the device".
    case keychain(status: Int32)
    case encodingFailed
}

// ------------------------------------------------------------
// MARK: Convenience
// ------------------------------------------------------------

extension SecureStore {

    public func string(forKey key: String) throws -> String? {
        guard let data = try data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?, forKey key: String) throws {
        guard let value else { return try set(nil as Data?, forKey: key) }
        guard let data = value.data(using: .utf8) else { throw SecureStoreError.encodingFailed }
        try set(data, forKey: key)
    }

    public func value<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = try data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func setValue<T: Encodable>(_ value: T?, forKey key: String) throws {
        guard let value else { return try set(nil as Data?, forKey: key) }
        try set(try JSONEncoder().encode(value), forKey: key)
    }

    public func remove(_ key: String) throws {
        try set(nil as Data?, forKey: key)
    }
}

// ============================================================
// MARK: - Keychain
// ============================================================

#if canImport(Security)

/// The real store. One generic-password item per key, scoped to a service.
public final class KeychainStore: SecureStore {

    private let service: String
    private let accessGroup: String?

    /// `AfterFirstUnlock` rather than `WhenUnlocked` because widgets and
    /// background refresh need to read after a reboot the user has not yet
    /// unlocked twice. `ThisDeviceOnly` is the part that matters most: it is what
    /// keeps these items out of iCloud and encrypted backups, which is the whole
    /// reason for moving them off `UserDefaults`.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    public init(service: String = "com.forge.ForgeSwift", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func query(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public func data(forKey key: String) throws -> Data? {
        var query = self.query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:  return item as? Data
        case errSecItemNotFound: return nil
        default: throw SecureStoreError.keychain(status: status)
        }
    }

    public func set(_ data: Data?, forKey key: String) throws {
        let query = self.query(for: key)

        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            // Deleting something that was never there is the desired end state,
            // not a failure.
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecureStoreError.keychain(status: status)
            }
            return
        }

        // Update first: SecItemAdd on an existing account returns errSecDuplicateItem
        // rather than overwriting, so add-then-fallback would leave stale values.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.accessibility,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecureStoreError.keychain(status: updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = Self.accessibility
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureStoreError.keychain(status: addStatus)
        }
    }

    public func removeAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.keychain(status: status)
        }
    }
}

#endif

// ============================================================
// MARK: - Test double
// ============================================================

/// In-memory store for tests, and the fallback on a platform with no Security
/// framework. Deliberately not thread-safe beyond a lock — it is a test double.
public final class InMemorySecureStore: SecureStore {

    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    /// Set by a test to make the next write fail, so callers can be checked for
    /// doing the right thing when the Keychain is unavailable — which happens
    /// for real on a device that has never been unlocked since boot.
    public var failNextWrite: SecureStoreError?

    public init() {}

    public func data(forKey key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ data: Data?, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        if let failure = failNextWrite {
            failNextWrite = nil
            throw failure
        }
        if let data { storage[key] = data } else { storage.removeValue(forKey: key) }
    }

    public func removeAll() throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }

    /// Test-only view of what is held, so assertions do not need to guess keys.
    public var keys: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage.keys.sorted()
    }
}
