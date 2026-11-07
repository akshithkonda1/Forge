import Foundation

/// Shared contract for HealthKit observer callbacks (iPhone + Watch).
///
/// Apple may suspend the process as soon as `completion` runs. Calling it
/// before the refresh work finishes (the BH-15 / BH-16 bug) drops the update.
/// This gate waits for work, then fires completion exactly once — including
/// when work throws or the observer reports an error.
public enum HealthKitObserverGate {
    public private(set) static var lastObserverErrorDescription: String?
    public private(set) static var lastBackgroundDeliveryErrorDescription: String?

    public static func resetTestState() {
        lastObserverErrorDescription = nil
        lastBackgroundDeliveryErrorDescription = nil
    }

    public static func recordBackgroundDeliveryFailure(typeIdentifier: String, error: Error?) {
        if let error {
            lastBackgroundDeliveryErrorDescription = "\(typeIdentifier): \(error.localizedDescription)"
        } else {
            lastBackgroundDeliveryErrorDescription = "\(typeIdentifier): unsuccessful"
        }
    }

    public static func run(
        observerError: Error?,
        work: () async throws -> Void,
        completion: @escaping () -> Void
    ) async {
        var completed = false
        let finish = {
            guard !completed else { return }
            completed = true
            completion()
        }
        defer { finish() }
        if let observerError {
            lastObserverErrorDescription = observerError.localizedDescription
        }
        do {
            try await work()
        } catch {
            // Completion still runs exactly once via defer.
        }
    }
}

/// Source contract for the iPhone observer call site (BH-15).
/// A revert of `HealthKitManager.startBidirectionalSync` to the 0d1426ca
/// `scheduleLiveRefresh()` + immediate `completion()` pattern must fail tests
/// that assert `completesBeforeRefresh` is false and `usesCompletionGate` is true.
public enum HealthKitObserverCallSite {
    public static func loadHealthKitManagerSource() throws -> String {
        let gateFile = URL(fileURLWithPath: #filePath)
        let forgeSwiftRoot = gateFile
            .deletingLastPathComponent() // HealthKit
            .deletingLastPathComponent() // ForgeCore
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // ForgeCore package
            .deletingLastPathComponent() // ForgeSwift/
        let url = forgeSwiftRoot.appendingPathComponent("ForgeSwift/HealthKitManager.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static func startBidirectionalSyncBody(_ source: String) -> String {
        guard let start = source.range(of: "func startBidirectionalSync()") else {
            return ""
        }
        let rest = source[start.lowerBound...]
        if let end = rest.range(of: "\n    func stopBidirectionalSync()") {
            return String(rest[..<end.lowerBound])
        }
        return String(rest.prefix(3_000))
    }

    /// True for the main/0d1426ca bug: `completion()` fires before refresh work.
    public static func completesBeforeRefresh(_ source: String) -> Bool {
        let body = startBidirectionalSyncBody(source)
        if body.range(
            of: #"scheduleLiveRefresh\(\)[\s\S]{0,160}completion\(\)"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return body.range(of: #"(?<![:\w])completion\(\)"#, options: .regularExpression) != nil
    }

    public static func usesCompletionGate(_ source: String) -> Bool {
        let body = startBidirectionalSyncBody(source)
        return body.contains("HealthKitObserverGate.run")
            || body.contains("handleObserverDelivery")
    }
}
