import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Client-side envelope for an Apple Cycle PDF.
///
/// The PDF is generated on this iPhone. Before any optional upload, it is
/// encrypted here. The key never goes in a request body, query, or header —
/// it stays in the Keychain or a URL fragment (`#k=`). The server only
/// ever sees ciphertext.
public struct CycleReportEnvelope: Equatable, Sendable {
    public var ciphertext: Data
    public var keyHex: String
    public var nonceHex: String
    public var contentType: String

    public init(ciphertext: Data, keyHex: String, nonceHex: String, contentType: String = "application/octet-stream") {
        self.ciphertext = ciphertext
        self.keyHex = keyHex
        self.nonceHex = nonceHex
        self.contentType = contentType
    }

    public var shareFragment: String { "k=\(keyHex)&n=\(nonceHex)" }

    public func shareURL(base: URL) -> URL {
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.fragment = shareFragment
        return parts.url ?? base
    }
}

public enum CycleReportCrypto: Sendable {
    public static let contentType = "application/octet-stream"

    public static func encrypt(_ plaintext: Data) throws -> CycleReportEnvelope {
        #if canImport(CryptoKit)
        let key = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw CycleReportCryptoError.sealFailed
        }
        return CycleReportEnvelope(
            ciphertext: combined,
            keyHex: hex(key.withUnsafeBytes { Data($0) }),
            nonceHex: hex(Data(sealed.nonce))
        )
        #else
        throw CycleReportCryptoError.cryptoUnavailable
        #endif
    }

    public static func decrypt(_ envelope: CycleReportEnvelope) throws -> Data {
        #if canImport(CryptoKit)
        guard let keyData = unhex(envelope.keyHex) else {
            throw CycleReportCryptoError.badKey
        }
        let key = SymmetricKey(data: keyData)
        let box = try AES.GCM.SealedBox(combined: envelope.ciphertext)
        return try AES.GCM.open(box, using: key)
        #else
        throw CycleReportCryptoError.cryptoUnavailable
        #endif
    }

    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public static func unhex(_ hex: String) -> Data? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count.isMultiple(of: 2), !clean.isEmpty else { return nil }
        var data = Data()
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

public enum CycleReportCryptoError: Error, Equatable, Sendable {
    case sealFailed
    case badKey
    case cryptoUnavailable
}
