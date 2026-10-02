import CryptoKit
import Foundation

// ============================================================
// MARK: - Life Context vault
// ============================================================
//
// Privacy contract
// ----------------
// What ARIA / the backend sees: nothing from this file. It is storage.
// What stays on-device: `LifeContextFact`s the user told Forge to remember
// ("Remember life context" on, and Remember tapped) — never message text,
// never a reminder title. They are sealed with AES-256-GCM under a key held in
// a `SecureStore` (the Keychain, `ThisDeviceOnly`: not in iCloud, not in
// backups), written with complete file protection, and the directory is
// excluded from backups. A restored backup on another phone has ciphertext
// and no key.
//
// The Share extension cannot read this vault. It can only *deposit* into the
// inbox: facts sealed to the app's Curve25519 public key (ECIES: X25519 +
// HKDF-SHA256 + AES-GCM). The private key never leaves the app's Keychain, so
// the extension — and anything else with the app group — can write a box but
// not open one, including its own.
//
// "Forget all" (`wipe`) deletes the facts file, the directory, the vault key,
// the hash key and the inbox private key, then `isWiped` checks every one of
// them is gone. Deleting the key alone would already make the ciphertext
// unreadable; the file goes too.

public enum LifeContextVaultError: Error, Equatable {
    case cryptoFailed
    case invalidBox
    case invalidPublicKey
}

public final class LifeContextVault {

    public static let wrappingKeyAccount = "forge.lifeContext.vault.wrappingKey.v1"
    public static let hashKeyAccount = "forge.lifeContext.hashKey.v1"
    public static let inboxPrivateKeyAccount = "forge.lifeContext.inbox.privateKey.v1"
    public static let factsFileName = "facts.box"
    static let boxVersion: UInt8 = 1
    static let factsAssociatedData = Data("forge.lifeContext.facts.v1".utf8)

    public let rootDirectory: URL
    private let secureStore: SecureStore
    private let fileManager: FileManager

    public init(secureStore: SecureStore, rootDirectory: URL, fileManager: FileManager = .default) {
        self.secureStore = secureStore
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public static func defaultRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("ForgeLifeContext", isDirectory: true)
    }

    public var factsURL: URL {
        rootDirectory.appendingPathComponent(Self.factsFileName)
    }

    public var hasStoredFacts: Bool {
        fileManager.fileExists(atPath: factsURL.path)
    }

    // MARK: Facts

    public func loadFacts() throws -> [LifeContextFact] {
        guard hasStoredFacts else { return [] }
        let plaintext = try open(try Data(contentsOf: factsURL))
        return try JSONDecoder().decode([LifeContextFact].self, from: plaintext)
    }

    /// Seal and write. An empty list removes the file instead of sealing "[]".
    public func saveFacts(_ facts: [LifeContextFact]) throws {
        guard !facts.isEmpty else {
            try removeFacts()
            return
        }
        try ensureDirectory()
        let plaintext = try JSONEncoder().encode(facts)
        try writeProtected(try seal(plaintext), to: factsURL)
    }

    public func removeFacts() throws {
        if hasStoredFacts {
            try fileManager.removeItem(at: factsURL)
        }
    }

    // MARK: Forget all

    public func wipe() throws {
        if fileManager.fileExists(atPath: rootDirectory.path) {
            try fileManager.removeItem(at: rootDirectory)
        }
        try secureStore.remove(Self.wrappingKeyAccount)
        try secureStore.remove(Self.hashKeyAccount)
        try secureStore.remove(Self.inboxPrivateKeyAccount)
    }

    /// True only when the directory and every key are gone. A Keychain read
    /// that fails counts as *not* wiped — "could not check" is not "deleted".
    public func isWiped() -> Bool {
        guard !fileManager.fileExists(atPath: rootDirectory.path) else { return false }
        for account in [Self.wrappingKeyAccount, Self.hashKeyAccount, Self.inboxPrivateKeyAccount] {
            do {
                if try secureStore.data(forKey: account) != nil { return false }
            } catch {
                return false
            }
        }
        return true
    }

    // MARK: Keys

    /// The HMAC key for `ContactID` and `sourceHash`. Created on first use.
    public func hashKey() throws -> LifeContextHashKey {
        try LifeContextHashKey.loadOrCreate(in: secureStore, account: Self.hashKeyAccount)
    }

    /// The raw Curve25519 public key the Share extension seals to.
    public func inboxPublicKey() throws -> Data {
        try inboxPrivateKey().publicKey.rawRepresentation
    }

    /// Open one box the Share extension deposited.
    public func openInbox(_ boxed: Data) throws -> [LifeContextFact] {
        let plaintext = try LifeContextInbox.open(boxed, with: try inboxPrivateKey())
        return try JSONDecoder().decode([LifeContextFact].self, from: plaintext)
    }

    private func inboxPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let raw = try secureStore.data(forKey: Self.inboxPrivateKeyAccount),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) {
            return key
        }
        let fresh = Curve25519.KeyAgreement.PrivateKey()
        try secureStore.set(fresh.rawRepresentation, forKey: Self.inboxPrivateKeyAccount)
        return fresh
    }

    private func wrappingKey() throws -> SymmetricKey {
        if let existing = try secureStore.data(forKey: Self.wrappingKeyAccount), existing.count == 32 {
            return SymmetricKey(data: existing)
        }
        let fresh = SymmetricKey(size: .bits256)
        try secureStore.set(fresh.withUnsafeBytes { Data($0) }, forKey: Self.wrappingKeyAccount)
        return fresh
    }

    // MARK: Crypto

    func seal(_ plaintext: Data) throws -> Data {
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(plaintext, using: try wrappingKey(), authenticating: Self.factsAssociatedData)
        } catch let error as SecureStoreError {
            throw error
        } catch {
            throw LifeContextVaultError.cryptoFailed
        }
        guard let combined = sealed.combined else { throw LifeContextVaultError.cryptoFailed }
        var out = Data([Self.boxVersion])
        out.append(combined)
        return out
    }

    func open(_ boxed: Data) throws -> Data {
        guard boxed.count > 1, boxed.first == Self.boxVersion else { throw LifeContextVaultError.invalidBox }
        let key = try wrappingKey()
        do {
            let box = try AES.GCM.SealedBox(combined: Data(boxed.dropFirst()))
            return try AES.GCM.open(box, using: key, authenticating: Self.factsAssociatedData)
        } catch {
            throw LifeContextVaultError.cryptoFailed
        }
    }

    // MARK: Files

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = rootDirectory
        try? url.setResourceValues(values)
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        #if os(iOS) || os(watchOS) || os(tvOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

// ============================================================
// MARK: - Share inbox (write-only for the extension)
// ============================================================

public enum LifeContextInbox {

    public static let directoryName = "LifeContextInbox"
    static let boxVersion: UInt8 = 1
    static let info = Data("forge.lifeContext.inbox.v1".utf8)
    static let publicKeyLength = 32

    public static func directory(in container: URL) -> URL {
        container.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Seal facts so only the holder of `publicKey`'s private half can open them.
    public static func seal(_ facts: [LifeContextFact], toPublicKey publicKey: Data) throws -> Data {
        try seal(plaintext: try JSONEncoder().encode(facts), toPublicKey: publicKey)
    }

    static func seal(plaintext: Data, toPublicKey publicKey: Data) throws -> Data {
        let recipient: Curve25519.KeyAgreement.PublicKey
        do {
            recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        } catch {
            throw LifeContextVaultError.invalidPublicKey
        }
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        do {
            let secret = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
            let context = ephemeral.publicKey.rawRepresentation + recipient.rawRepresentation
            let key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: context, sharedInfo: info, outputByteCount: 32)
            let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: context)
            guard let combined = sealed.combined else { throw LifeContextVaultError.cryptoFailed }
            var out = Data([boxVersion])
            out.append(ephemeral.publicKey.rawRepresentation)
            out.append(combined)
            return out
        } catch {
            throw LifeContextVaultError.cryptoFailed
        }
    }

    static func open(_ boxed: Data, with privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        let bytes = [UInt8](boxed)
        guard bytes.count > 1 + publicKeyLength, bytes[0] == boxVersion else { throw LifeContextVaultError.invalidBox }
        let ephemeralRaw = Data(bytes[1..<(1 + publicKeyLength)])
        let combined = Data(bytes[(1 + publicKeyLength)...])
        do {
            let ephemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralRaw)
            let secret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeral)
            let context = ephemeralRaw + privateKey.publicKey.rawRepresentation
            let key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: context, sharedInfo: info, outputByteCount: 32)
            return try AES.GCM.open(try AES.GCM.SealedBox(combined: combined), using: key, authenticating: context)
        } catch {
            throw LifeContextVaultError.cryptoFailed
        }
    }

    /// Write one sealed box into the app group's inbox. Returns its URL.
    @discardableResult
    public static func deposit(
        _ facts: [LifeContextFact],
        toPublicKey publicKey: Data,
        container: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let boxed = try seal(facts, toPublicKey: publicKey)
        let folder = directory(in: container)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = String(format: "%012ld", Int(now.timeIntervalSince1970)) + "-" + UUID().uuidString + ".box"
        let url = folder.appendingPathComponent(name)
        #if os(iOS) || os(watchOS) || os(tvOS)
        try boxed.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try boxed.write(to: url, options: .atomic)
        #endif
        return url
    }

    /// Boxes waiting for the app, oldest first.
    public static func pendingBoxes(in container: URL, fileManager: FileManager = .default) -> [URL] {
        let folder = directory(in: container)
        let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "box" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Delete every pending box. Used by "Forget all".
    public static func purge(in container: URL, fileManager: FileManager = .default) throws {
        let folder = directory(in: container)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
    }
}
