import Foundation

/// On-phone viability only. Replaces the old server vitals audit.
///
/// Checks OS version (minimum iOS 26.5), app/build compatibility, and
/// HealthKit availability / permission — never a heart rate, HRV, sleep
/// minute, or any other health value. Nothing here leaves the device.
public struct ForgeDeviceViability: Equatable, Sendable {
    public static let minimumIOSMajor = 26
    public static let minimumIOSMinor = 5

    public var osMeetsMinimum: Bool
    public var appBuildCompatible: Bool
    public var healthKitAvailable: Bool
    public var healthKitAuthorized: Bool
    public var ready: Bool
    public var reasons: [String]

    public init(
        osMeetsMinimum: Bool,
        appBuildCompatible: Bool,
        healthKitAvailable: Bool,
        healthKitAuthorized: Bool,
        reasons: [String] = []
    ) {
        self.osMeetsMinimum = osMeetsMinimum
        self.appBuildCompatible = appBuildCompatible
        self.healthKitAvailable = healthKitAvailable
        self.healthKitAuthorized = healthKitAuthorized
        self.ready = osMeetsMinimum && appBuildCompatible && healthKitAvailable && healthKitAuthorized
        self.reasons = reasons
    }
}

public enum ForgeDeviceViabilityCheck: Sendable {

    public static func evaluate(
        major: Int,
        minor: Int,
        patch: Int = 0,
        appBuild: String,
        minimumBuild: String = "1",
        healthKitAvailable: Bool,
        healthKitAuthorized: Bool
    ) -> ForgeDeviceViability {
        _ = patch
        var reasons: [String] = []
        let osOK = (major, minor) >= (ForgeDeviceViability.minimumIOSMajor, ForgeDeviceViability.minimumIOSMinor)
        if !osOK {
            reasons.append("OS below iOS \(ForgeDeviceViability.minimumIOSMajor).\(ForgeDeviceViability.minimumIOSMinor)")
        }
        let buildOK = appBuild.compare(minimumBuild, options: .numeric) != .orderedAscending
        if !buildOK {
            reasons.append("App build \(appBuild) is older than \(minimumBuild)")
        }
        if !healthKitAvailable {
            reasons.append("HealthKit is not available on this device")
        }
        if !healthKitAuthorized {
            reasons.append("HealthKit permission is not granted")
        }
        return ForgeDeviceViability(
            osMeetsMinimum: osOK,
            appBuildCompatible: buildOK,
            healthKitAvailable: healthKitAvailable,
            healthKitAuthorized: healthKitAuthorized,
            reasons: reasons
        )
    }

    /// Current process. Callers inject HealthKit flags — this type never
    /// reads a sample.
    public static func evaluateCurrent(
        healthKitAvailable: Bool,
        healthKitAuthorized: Bool,
        appBuild: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    ) -> ForgeDeviceViability {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return evaluate(
            major: v.majorVersion,
            minor: v.minorVersion,
            patch: v.patchVersion,
            appBuild: appBuild,
            healthKitAvailable: healthKitAvailable,
            healthKitAuthorized: healthKitAuthorized
        )
    }
}
