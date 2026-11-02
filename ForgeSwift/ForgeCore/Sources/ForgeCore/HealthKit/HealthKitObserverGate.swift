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
