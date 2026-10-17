import Foundation

/// Shed nonessential work under thermal or memory pressure. No always-on timers.
public enum ForgeRuntimeGuard: Sendable {
    public static let maxFileBytes = 512_000
    public static let compactOffMainThread = true
    public static let clockHzCap = 12
    public static let clockPausedWhenIdle = true
    public static let noAlwaysOnTimers = true
    public static let noPolling = true

    /// Source baselines for store + discovery (seconds / item caps).
    public static let storeCompactBaselineSeconds = 2.0
    public static let discoveryRankBaselineSeconds = 1.0
    public static let largeStoreFacts = 400

    public static func shouldShed(thermal: String, memoryWarning: Bool = false) -> Bool {
        if memoryWarning { return true }
        let value = thermal.lowercased()
        return value == "serious" || value == "critical"
    }

    public static func thermalLabel(_ state: String) -> String {
        let value = state.lowercased()
        if value.contains("critical") { return "critical" }
        if value.contains("serious") { return "serious" }
        return "nominal"
    }
}
