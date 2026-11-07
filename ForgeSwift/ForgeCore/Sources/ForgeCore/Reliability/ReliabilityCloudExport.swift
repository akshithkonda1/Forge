import Foundation

// MARK: - ReliabilityCloudExport
//
// A later opt-in upload would POST the content-free `ReliabilityReport` to
// Forge's own AWS backend. That path is not shipped. The endpoint is a
// TODO(aws) config value; when it is unset (the default) export fails
// closed and nothing is sent. This type never opens a network client.

public enum ReliabilityCloudExportError: Error, Equatable, Sendable {
    /// TODO(aws) endpoint is missing, empty, or not a URL. Fail closed.
    case notConfigured
    /// An endpoint was set but the AWS upload is still a stub. Fail closed.
    case notImplemented
}

public enum ReliabilityCloudExport {

    /// TODO(aws): API Gateway URL that would accept `forge-reliability-report`.
    /// Unset / empty fails closed — the report stays on this iPhone.
    public static var configuredEndpoint: String? {
        let env = ProcessInfo.processInfo.environment["FORGE_RELIABILITY_AWS_ENDPOINT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty { return env }
        return nil
    }

    public static var isEnabled: Bool {
        guard let value = configuredEndpoint, let url = URL(string: value) else { return false }
        return url.scheme == "https"
    }

    /// Never opens a connection. Unset TODO(aws) → `.notConfigured`.
    /// A set endpoint still returns `.notImplemented` until the AWS path
    /// is reviewed and shipped — fail closed either way.
    public static func send(_ report: ReliabilityReport) -> Result<Void, ReliabilityCloudExportError> {
        _ = report
        guard isEnabled else { return .failure(.notConfigured) }
        return .failure(.notImplemented)
    }
}
