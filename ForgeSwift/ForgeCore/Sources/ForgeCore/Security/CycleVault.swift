import CryptoKit
import Foundation

/// Keychain-wrapped encrypted archive for reproductive data.
///
/// The wrapping key lives in a `SecureStore` (`ThisDeviceOnly` on device).
/// Ciphertext lives in its own directory — never in `UserDefaults`, never on
/// Forge servers. Monthly boxes are a rolling 12-month clinician archive.
public enum CycleVaultError: Error, Equatable {
    case missingWrappingKey
    case cryptoFailed
    case ioFailed
    case invalidBox
}

public final class CycleVault {

    public static let wrappingKeyAccount = "forge.cycle.vault.wrappingKey.v1"
    public static let liveFileName = "live.box"
    public static let monthsDirectoryName = "months"
    public static let retainedMonths = 12
    public static let boxVersion: UInt8 = 1

    public let rootDirectory: URL
    private let secureStore: SecureStore
    private let fileManager: FileManager

    public init(
        secureStore: SecureStore,
        rootDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.secureStore = secureStore
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public static func defaultRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("ForgeCycleVault", isDirectory: true)
    }

    public var liveURL: URL {
        rootDirectory.appendingPathComponent(Self.liveFileName)
    }

    public var monthsDirectory: URL {
        rootDirectory.appendingPathComponent(Self.monthsDirectoryName, isDirectory: true)
    }

    public var hasLiveBox: Bool {
        fileManager.fileExists(atPath: liveURL.path)
    }

    // MARK: Live state

    public func writeLive(_ plaintext: Data) throws {
        try ensureDirectories()
        try writeProtected(try seal(plaintext), to: liveURL)
    }

    public func readLive() throws -> Data? {
        guard fileManager.fileExists(atPath: liveURL.path) else { return nil }
        let boxed = try Data(contentsOf: liveURL)
        return try open(boxed)
    }

    // MARK: Monthly archive

    public static func monthKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    public func writeMonth(_ monthKey: String, plaintext: Data) throws {
        try ensureDirectories()
        let url = monthURL(monthKey)
        try writeProtected(try seal(plaintext), to: url)
        try purgeExpiredMonths()
    }

    public func readMonth(_ monthKey: String) throws -> Data? {
        let url = monthURL(monthKey)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try open(try Data(contentsOf: url))
    }

    public func monthKeys() throws -> [String] {
        try ensureDirectories()
        let urls = (try? fileManager.contentsOfDirectory(
            at: monthsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension == "box" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    public func readRecentMonths(limit: Int = CycleVault.retainedMonths) throws -> [(key: String, data: Data)] {
        let keys = try monthKeys().suffix(limit)
        var out: [(String, Data)] = []
        for key in keys {
            if let data = try readMonth(key) {
                out.append((key, data))
            }
        }
        return out
    }

    public func purgeExpiredMonths(keeping: Int = CycleVault.retainedMonths) throws {
        let keys = try monthKeys()
        guard keys.count > keeping else { return }
        for key in keys.dropLast(keeping) {
            try? fileManager.removeItem(at: monthURL(key))
        }
    }

    /// Owner wipe of the 12-month clinician pack. Live state is left intact.
    public func purgeMonths() throws {
        if fileManager.fileExists(atPath: monthsDirectory.path) {
            try fileManager.removeItem(at: monthsDirectory)
        }
        try ensureDirectories()
    }

    // MARK: Wipe

    public func wipe() throws {
        if fileManager.fileExists(atPath: rootDirectory.path) {
            try fileManager.removeItem(at: rootDirectory)
        }
        try secureStore.remove(Self.wrappingKeyAccount)
    }

    // MARK: Key

    public func wrappingKey() throws -> Data {
        if let existing = try secureStore.data(forKey: Self.wrappingKeyAccount),
           existing.count == 32 {
            return existing
        }
        let fresh = SymmetricKey(size: .bits256)
        let data = fresh.withUnsafeBytes { Data($0) }
        try secureStore.set(data, forKey: Self.wrappingKeyAccount)
        return data
    }

    // MARK: Crypto

    func seal(_ plaintext: Data) throws -> Data {
        let key = SymmetricKey(data: try wrappingKey())
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(plaintext, using: key)
        } catch {
            throw CycleVaultError.cryptoFailed
        }
        guard let combined = sealed.combined else { throw CycleVaultError.cryptoFailed }
        var out = Data([Self.boxVersion])
        out.append(combined)
        return out
    }

    func open(_ boxed: Data) throws -> Data {
        guard boxed.count > 1, boxed[0] == Self.boxVersion else {
            throw CycleVaultError.invalidBox
        }
        let combined = boxed.dropFirst()
        let key = SymmetricKey(data: try wrappingKey())
        do {
            let box = try AES.GCM.SealedBox(combined: Data(combined))
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CycleVaultError.cryptoFailed
        }
    }

    // MARK: Files

    private func monthURL(_ key: String) -> URL {
        monthsDirectory.appendingPathComponent("\(key).box")
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: monthsDirectory, withIntermediateDirectories: true)
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        #if os(iOS) || os(watchOS) || os(tvOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
