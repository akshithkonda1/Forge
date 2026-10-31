import XCTest
@testable import ForgeCore

/// Reed's hold on reliability telemetry: the classifier, the ledger and
/// MetricKit summaries stay on this device. Health values and reply text
/// never reach a record, a log line we persist, or the network. The AWS
/// upload is a TODO(aws) stub that fails closed when the endpoint is unset.
final class AriaReliabilityClassifierPrivacyTests: XCTestCase {

    /// Stand-ins for a chat reply and a health sample.
    private let reply = "Rest today — your HRV dropped after that interval set."
    private let health = "resting HR 112, HRV 18, readiness 41, Jane Doe"
    private let sentinels = [
        "Rest today", "interval set", "HRV dropped",
        "112", "HRV 18", "readiness 41", "Jane", "Doe",
    ]

    private var canaryErrors: [Error] {
        [
            NSError(domain: "com.apple.healthkit", code: 5, userInfo: [
                NSLocalizedDescriptionKey: health,
                "sample": health,
                NSLocalizedFailureReasonErrorKey: reply,
            ]),
            NSError(domain: reply, code: 1, userInfo: [NSLocalizedDescriptionKey: reply]),
            URLError(.notConnectedToInternet),
        ]
    }

    // MARK: Classifier

    func testClassifierKeepsNoHealthValuesOrReplyText() throws {
        for error in canaryErrors {
            let classified = AriaReliabilityClassifier.classify(error)
            let encoded = try String(decoding: JSONEncoder().encode(classified), as: UTF8.self)
            assertNoSentinels(encoded, context: "classifier \(type(of: error))")
        }

        let http = AriaReliabilityClassifier.classifyHTTP(status: 500)
        XCTAssertEqual(http.kind, .serverError)
        XCTAssertEqual(http.code, 500)
        XCTAssertEqual(http.domain, "http")
        assertNoSentinels(try String(decoding: JSONEncoder().encode(http), as: UTF8.self), context: "http")

        let paused = AriaReliabilityClassifier.classifyHTTP(status: 503, isAriaPaused: true)
        XCTAssertEqual(paused.kind, .ariaPaused)
        XCTAssertEqual(paused.code, 503)

        let transport = AriaReliabilityClassifier.classifyTransport(
            NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [
                NSLocalizedDescriptionKey: health,
            ])
        )
        XCTAssertEqual(transport.kind, .offline)
        assertNoSentinels(try String(decoding: JSONEncoder().encode(transport), as: UTF8.self), context: "transport")

        XCTAssertEqual(AriaReliabilityClassifier.classifyAuth().kind, .unauthorized)
        XCTAssertEqual(AriaReliabilityClassifier.classifyNotConfigured().kind, .notConfigured)
        XCTAssertEqual(
            AriaReliabilityClassifier.classify(NSError(domain: reply, code: 1)).domain,
            "other"
        )
    }

    func testHTTPClassifierHasNoBodyParameter() throws {
        // A body argument would be the leak: the backend can echo the user's
        // message. The signature is status + a boolean, nothing else.
        let source = try String(contentsOf: reliabilitySource("AriaReliabilityClassifier.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("func classifyHTTP(status: Int, isAriaPaused: Bool"))
        XCTAssertFalse(source.contains("body:"))
        XCTAssertFalse(source.contains("localizedDescription"))
        XCTAssertFalse(source.contains("userInfo"))
        XCTAssertFalse(source.contains("URLSession"))
        XCTAssertFalse(source.contains("URLRequest"))
    }

    // MARK: Ledger + MetricKit

    func testLedgerAndMetricKitStayOnDeviceAndHoldNoUserText() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-reliability-privacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = ReliabilityLog(directory: directory)

        for error in canaryErrors {
            await log.record(AriaTurnRecord(
                route: .cloud, outcome: .fallback, latencyMs: 800,
                error: AriaReliabilityClassifier.classify(error)
            ))
            await log.record(ReliabilityFailureRecord(
                area: .healthKit, operation: .quantityQuery,
                error: AriaReliabilityClassifier.classify(error)
            ))
        }

        var metric = ReliabilityMetricSummary(
            periodStart: Date(timeIntervalSince1970: 1_800_000_000),
            periodEnd: Date(timeIntervalSince1970: 1_800_086_400)
        )
        metric.appVersion = "1.0"
        metric.appBuild = "1"
        metric.peakMemoryMB = 120
        metric.foregroundSeconds = 3_600
        var diagnostic = ReliabilityDiagnosticSummary(kind: .crash, at: Date(timeIntervalSince1970: 1_800_000_100))
        diagnostic.signal = 11
        diagnostic.exceptionType = 1
        diagnostic.exceptionName = "EXC_BAD_ACCESS"
        diagnostic.terminationReason = "Namespace SIGNAL, Code 11"
        await log.ingest(metrics: [metric])
        await log.ingest(diagnostics: [diagnostic])
        await log.flush()

        let fileURL = directory.appendingPathComponent("reliability.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "ledger must be a local file")
        XCTAssertTrue(fileURL.path.contains(directory.path), "ledger left the temp directory")

        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        let report = await log.report(build: .init(
            appVersion: "1.0", appBuild: "1", osVersion: "27.0",
            deviceModel: "iPhone", configuration: "Release"
        ))
        let exported = try String(decoding: report.jsonData(), as: UTF8.self)

        assertNoSentinels(onDisk, context: "ledger file")
        assertNoSentinels(exported, context: "exported report")
        XCTAssertTrue(exported.contains("\"format\" : \"forge-reliability-report\""))
        XCTAssertEqual(report.metrics.count, 1)
        XCTAssertEqual(report.diagnostics.count, 1)
        XCTAssertEqual(report.diagnostics.first?.exceptionName, "EXC_BAD_ACCESS")
        XCTAssertNil(report.metrics.first?.appVersion?.range(of: "Jane"))
    }

    func testMetricKitSummariesHaveNoHealthOrReplyFields() {
        let strings = stringProperties(of: ReliabilityMetricSummary(
            periodStart: Date(), periodEnd: Date()
        ))
        let allowed = Set(["appVersion", "appBuild", "osVersion"])
        XCTAssertTrue(Set(strings).isSubset(of: allowed), "unexpected MetricKit strings: \(strings)")

        var diagnostic = ReliabilityDiagnosticSummary(kind: .hang, at: Date())
        diagnostic.exceptionName = "NSRangeException"
        diagnostic.terminationReason = "Namespace SIGNAL, Code 11"
        let diagStrings = Set(stringProperties(of: diagnostic))
        let allowedDiag: Set<String> = [
            "appBuild", "osVersion", "terminationReason", "exceptionName", "callStackJSON",
        ]
        XCTAssertTrue(diagStrings.isSubset(of: allowedDiag), "unexpected diagnostic strings: \(diagStrings)")
        XCTAssertFalse(diagStrings.contains("message"))
        XCTAssertFalse(diagStrings.contains("reply"))
        XCTAssertFalse(diagStrings.contains("sample"))
    }

    // MARK: Network + AWS

    func testNothingGoesOverTheNetwork() throws {
        let banned = ["URLSession", "URLRequest", "NWConnection", "URLSessionConfiguration"]
        let files = [
            "AriaReliabilityClassifier.swift",
            "ReliabilityCloudExport.swift",
            "ReliabilityLog.swift",
            "ReliabilityLedger.swift",
            "ReliabilityMetricKit.swift",
            "ReliabilityModels.swift",
            "ReliabilityAppleMetrics.swift",
            "ReliabilitySummary.swift",
        ]
        for name in files {
            let source = try String(contentsOf: reliabilitySource(name), encoding: .utf8)
            for term in banned {
                XCTAssertFalse(source.contains(term), "\(name) talks to the network via \(term)")
            }
        }

        let appClassifier = try appSideClassifierSource()
        for term in banned {
            XCTAssertFalse(appClassifier.contains(term), "app classifier talks to the network via \(term)")
        }
        XCTAssertTrue(appClassifier.contains("case .http(let status, _)"), "HTTP body must be discarded")
        XCTAssertFalse(appClassifier.contains("localizedDescription"))
    }

    func testAWSExportFailsClosedWhenTODOAwsIsUnset() throws {
        XCTAssertNil(
            ReliabilityCloudExport.configuredEndpoint,
            "TODO(aws) endpoint must stay unset so export fails closed"
        )
        XCTAssertFalse(ReliabilityCloudExport.isEnabled)

        let report = ReliabilityReport(
            ledger: ReliabilityLedger(),
            build: .init(
                appVersion: "1.0", appBuild: "1", osVersion: "27.0",
                deviceModel: "iPhone", configuration: "Release"
            )
        )
        let result = ReliabilityCloudExport.send(report)
        XCTAssertEqual(result, .failure(.notConfigured))

        let source = try String(contentsOf: reliabilitySource("ReliabilityCloudExport.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("TODO(aws)"))
        XCTAssertFalse(source.contains("URLSession"))
        XCTAssertTrue(source.contains("fails closed") || source.contains("Fail closed") || source.contains("fail closed"))
        assertNoSentinels(try String(decoding: report.jsonData(), as: UTF8.self), context: "empty report")
    }

    // MARK: Helpers

    private func assertNoSentinels(_ text: String, context: String) {
        for sentinel in sentinels {
            XCTAssertFalse(text.contains(sentinel), "\(sentinel) leaked through \(context)")
        }
    }

    private func reliabilitySource(_ file: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ForgeCore/Reliability/\(file)")
    }

    private func appSideClassifierSource() throws -> String {
        let aria = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ForgeSwift/Services/AriaService.swift")
        let source = try String(contentsOf: aria, encoding: .utf8)
        guard let range = source.range(of: "extension AriaReliabilityClassifier") else {
            XCTFail("AriaService.swift lost the ForgeAPI.Failure adapter")
            return source
        }
        return String(source[range.lowerBound...])
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
