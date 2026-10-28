import XCTest
@testable import ForgeCore

/// The reliability log stores outcome metadata and nothing else. These tests
/// push user-shaped text through every door an error can come in by (an
/// NSError's description and userInfo, a decoding error's debug text, a
/// custom domain, an HTTP body) and check that none of it reaches the
/// ledger on disk or the exported report.
final class ReliabilityPrivacyTests: XCTestCase {

    /// Stand-ins for a chat message and a health value.
    private let message = "I feel dizzy after my run, resting HR 112, my name is Jane Doe"
    private let sentinels = ["dizzy", "112", "Jane", "Doe", "resting HR"]

    private struct Payload: Decodable { let value: Int }

    private func errorsCarryingText() -> [Error] {
        var errors: [Error] = []
        errors.append(NSError(domain: "com.apple.healthkit", code: 5, userInfo: [
            NSLocalizedDescriptionKey: message,
            "query": message,
        ]))
        errors.append(NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [
            NSLocalizedFailureReasonErrorKey: message,
        ]))
        // A custom domain built from user text must not survive as a domain.
        errors.append(NSError(domain: message, code: 1))
        do {
            _ = try JSONDecoder().decode(Payload.self, from: Data("{\"value\": \"\(message)\"}".utf8))
        } catch {
            errors.append(error)
        }
        return errors
    }

    func testClassifiedErrorsKeepNoText() throws {
        for error in errorsCarryingText() {
            let classified = ReliabilityError.classify(error)
            let encoded = try String(decoding: JSONEncoder().encode(classified), as: UTF8.self)
            for sentinel in sentinels {
                XCTAssertFalse(encoded.contains(sentinel), "\(sentinel) leaked through \(type(of: error))")
            }
        }
        XCTAssertEqual(ReliabilityError.classify(NSError(domain: message, code: 1)).domain, "other")
    }

    func testRecordsHaveNoFreeTextFields() {
        // Every stored record is built only from enums, numbers, dates and
        // classified errors. A new String property on a record should be a
        // deliberate decision, so the String-typed properties are listed here.
        let turn = AriaTurnRecord(route: .cloud, outcome: .failure, latencyMs: 10, error: .http(status: 500))
        XCTAssertEqual(stringProperties(of: turn), [])
        let failure = ReliabilityFailureRecord(area: .healthKit, operation: .quantityQuery, error: ReliabilityError(kind: .healthKit, code: 6))
        XCTAssertEqual(stringProperties(of: failure), [])
        XCTAssertEqual(stringProperties(of: ReliabilityError(kind: .healthKit, code: 6, domain: "com.apple.healthkit")), ["domain"])
    }

    func testDiskFileAndExportedReportContainNoMessageText() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reliability-privacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = ReliabilityLog(directory: directory)

        for error in errorsCarryingText() {
            await log.record(AriaTurnRecord(
                route: .onDeviceModel, outcome: .failure, latencyMs: 900,
                error: ReliabilityError.classify(error)
            ))
            await log.record(ReliabilityFailureRecord(
                area: .healthKit, operation: .quantityQuery, error: ReliabilityError.classify(error)
            ))
        }
        // The backend's error body is never a parameter: only the status is.
        await log.record(AriaTurnRecord(route: .cloud, outcome: .fallback, latencyMs: 1_200, error: .http(status: 500)))
        await log.flush()

        let onDisk = try String(contentsOf: directory.appendingPathComponent("reliability.json"), encoding: .utf8)
        let report = await log.report(build: .init(
            appVersion: "1.0", appBuild: "1", osVersion: "27.0", deviceModel: "iPhone", configuration: "Release"
        ))
        let exported = try String(decoding: report.jsonData(), as: UTF8.self)

        for sentinel in sentinels {
            XCTAssertFalse(onDisk.contains(sentinel), "\(sentinel) reached the ledger file")
            XCTAssertFalse(exported.contains(sentinel), "\(sentinel) reached the exported report")
        }
        XCTAssertTrue(exported.contains("\"format\" : \"forge-reliability-report\""))
        XCTAssertEqual(report.summary.aria.failures, 4)
        XCTAssertEqual(report.summary.aria.fallbacks, 1)
    }

    private func stringProperties(of value: Any) -> [String] {
        Mirror(reflecting: value).children.compactMap { child in
            let unwrapped: Any
            let mirror = Mirror(reflecting: child.value)
            if mirror.displayStyle == .optional, let some = mirror.children.first {
                unwrapped = some.value
            } else {
                unwrapped = child.value
            }
            return unwrapped is String ? child.label : nil
        }
    }
}
