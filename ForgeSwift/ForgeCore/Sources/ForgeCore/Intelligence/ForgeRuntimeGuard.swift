import Foundation

/// Shed nonessential work under thermal or memory pressure. No always-on timers.
public enum ForgeRuntimeGuard: Sendable {
    public static let maxFileBytes = 512_000
    public static let compactOffMainThread = true

    public static func shouldShed(thermal: String, memoryWarning: Bool = false) -> Bool {
        if memoryWarning { return true }
        let value = thermal.lowercased()
        return value == "serious" || value == "critical"
    }
}
