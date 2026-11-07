import XCTest
@testable import ForgeCore

final class CycleReportEnvelopeTests: XCTestCase {

    func testEncryptRoundTripAndKeyStaysOutOfCiphertext() throws {
        #if canImport(CryptoKit)
        let pdf = Data("FORGE cycle report".utf8)
        let envelope = try CycleReportCrypto.encrypt(pdf)
        XCTAssertEqual(envelope.contentType, "application/octet-stream")
        XCTAssertNotEqual(envelope.ciphertext, pdf)
        XCTAssertFalse(String(data: envelope.ciphertext, encoding: .utf8)?.contains("cycle") == true)
        XCTAssertFalse(envelope.ciphertext.map { String(format: "%02x", $0) }.joined().contains(envelope.keyHex))
        let opened = try CycleReportCrypto.decrypt(envelope)
        XCTAssertEqual(opened, pdf)
        let url = envelope.shareURL(base: URL(string: "https://uploads.test/obj")!)
        XCTAssertTrue(url.absoluteString.contains("#k="))
        XCTAssertFalse(url.absoluteString.contains("FORGE"))
        #else
        throw XCTSkip("CryptoKit is required for AES-GCM cycle envelopes")
        #endif
    }
}
