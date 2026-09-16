import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

/// HealthKit HRV quantity identifiers. SDNN and RMSSD are different
/// calculations on RR intervals; this layer never aliases one to the other.
///
/// Not Apple Readiness. Not Apple Health Age. A vendor Recovery score is not
/// RMSSD. Client metric names are `hrv_sdnn` and `hrv_rmssd`.
public enum HealthKitHRVQuantity: Sendable {
    public static let sdnnIdentifierRaw = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
    public static let rmssdIdentifierRaw = "HKQuantityTypeIdentifierHeartRateVariabilityRMSSD"
}

/// One HRV statistic. Names match BodyModel metric ids so a payload cannot
/// silently become the other calculation.
public enum HRVStatistic: String, Codable, Equatable, Sendable, CaseIterable {
    case sdnn = "hrv_sdnn"
    case rmssd = "hrv_rmssd"

    public var healthKitIdentifierRaw: String {
        switch self {
        case .sdnn: return HealthKitHRVQuantity.sdnnIdentifierRaw
        case .rmssd: return HealthKitHRVQuantity.rmssdIdentifierRaw
        }
    }

    public var cloudMetricType: String {
        switch self {
        case .sdnn: return "hrv-sdnn"
        case .rmssd: return "hrv-rmssd"
        }
    }

    public static func fromHealthKitIdentifierRaw(_ raw: String) -> HRVStatistic? {
        switch raw {
        case HealthKitHRVQuantity.sdnnIdentifierRaw: return .sdnn
        case HealthKitHRVQuantity.rmssdIdentifierRaw: return .rmssd
        default: return nil
        }
    }

    /// Classify a metric name. `"rmssd"` is RMSSD, never SDNN. Legacy unlabeled
    /// `"hrv"` is SDNN-shaped in this tree (HealthKit's historical type).
    public static func fromMetricName(_ raw: String) -> HRVStatistic? {
        let key = raw.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "hkquantitytypeidentifier", with: "")
        switch key {
        case "hrv-sdnn", "sdnn", "heartratevariabilitysdnn", "hrv":
            return .sdnn
        case "hrv-rmssd", "rmssd", "heartratevariabilityrmssd":
            return .rmssd
        default:
            return nil
        }
    }
}

/// Cadence / window semantics for a baseline. Series 12-class watches sample
/// HRV far more often than overnight-sparse SDNN; mixing those windows poisons
/// a personal center. Bump `version` when the meaning of a sample changes.
public struct HRVSamplingDensity: Codable, Equatable, Sendable {
    public var version: Int
    public var expectedSamplesPerDay: Int

    public init(version: Int, expectedSamplesPerDay: Int) {
        self.version = version
        self.expectedSamplesPerDay = expectedSamplesPerDay
    }

    /// Classic Apple Watch overnight SDNN — a handful of samples per night.
    public static let overnightSparse = HRVSamplingDensity(version: 1, expectedSamplesPerDay: 6)

    /// HealthKit RMSSD samples, when the type exists and readings are present.
    /// Distinct version so sparse SDNN history is never mixed into an RMSSD baseline.
    public static let denseRMSSD = HRVSamplingDensity(version: 2, expectedSamplesPerDay: 144)

    public static func `default`(for statistic: HRVStatistic) -> HRVSamplingDensity {
        switch statistic {
        case .sdnn: return .overnightSparse
        case .rmssd: return .denseRMSSD
        }
    }
}

/// One typed HRV sample. The statistic is required; there is no unlabeled "hrv".
public struct HRVObservation: Equatable, Sendable {
    public var statistic: HRVStatistic
    public var milliseconds: Double
    public var timestamp: Date
    public var samplingDensity: HRVSamplingDensity
    public var source: String

    public init(
        statistic: HRVStatistic,
        milliseconds: Double,
        timestamp: Date,
        samplingDensity: HRVSamplingDensity? = nil,
        source: String = "apple-health"
    ) {
        self.statistic = statistic
        self.milliseconds = milliseconds
        self.timestamp = timestamp
        self.samplingDensity = samplingDensity ?? .default(for: statistic)
        self.source = source
    }
}

/// On-device BodyModel HRV baselines. SDNN and RMSSD each keep their own
/// `OnlineStat`. A sampling-density version mismatch resets that statistic
/// only — the other side is left alone.
public struct BodyModelHRVBaselines: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var sdnn: OnlineStat
    public var rmssd: OnlineStat
    public var sdnnSamplingDensityVersion: Int
    public var rmssdSamplingDensityVersion: Int

    enum CodingKeys: String, CodingKey {
        case schemaVersion, sdnn, rmssd
        case sdnnSamplingDensityVersion, rmssdSamplingDensityVersion
    }

    public init(
        schemaVersion: Int = BodyModelHRVBaselines.currentSchemaVersion,
        sdnn: OnlineStat = OnlineStat(),
        rmssd: OnlineStat = OnlineStat(),
        sdnnSamplingDensityVersion: Int = 0,
        rmssdSamplingDensityVersion: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.sdnn = sdnn
        self.rmssd = rmssd
        self.sdnnSamplingDensityVersion = sdnnSamplingDensityVersion
        self.rmssdSamplingDensityVersion = rmssdSamplingDensityVersion
        migrateDecodedIfNeeded()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        sdnn = try c.decodeIfPresent(OnlineStat.self, forKey: .sdnn) ?? OnlineStat()
        rmssd = try c.decodeIfPresent(OnlineStat.self, forKey: .rmssd) ?? OnlineStat()
        sdnnSamplingDensityVersion = try c.decodeIfPresent(Int.self, forKey: .sdnnSamplingDensityVersion) ?? 0
        rmssdSamplingDensityVersion = try c.decodeIfPresent(Int.self, forKey: .rmssdSamplingDensityVersion) ?? 0
        migrateDecodedIfNeeded()
    }

    /// Unversioned history has unknown sampling density. Drop it rather than
    /// mix overnight-sparse SDNN with denser RMSSD (or a later cadence).
    public mutating func migrateDecodedIfNeeded() {
        if schemaVersion != Self.currentSchemaVersion {
            schemaVersion = Self.currentSchemaVersion
        }
        if sdnnSamplingDensityVersion == 0, sdnn.n > 0 {
            sdnn = OnlineStat(alpha: sdnn.alpha)
        }
        if rmssdSamplingDensityVersion == 0, rmssd.n > 0 {
            rmssd = OnlineStat(alpha: rmssd.alpha)
        }
    }

    public mutating func ingest(_ observation: HRVObservation) {
        migrateIfNeeded(to: observation.samplingDensity, for: observation.statistic)
        switch observation.statistic {
        case .sdnn:
            sdnn.update(observation.milliseconds)
        case .rmssd:
            rmssd.update(observation.milliseconds)
        }
    }

    /// Density-version change resets that statistic's running center so old
    /// samples are not mixed with the new window/cadence.
    public mutating func migrateIfNeeded(to density: HRVSamplingDensity, for statistic: HRVStatistic) {
        schemaVersion = Self.currentSchemaVersion
        switch statistic {
        case .sdnn:
            if sdnnSamplingDensityVersion != density.version {
                sdnn = OnlineStat(alpha: sdnn.alpha)
                sdnnSamplingDensityVersion = density.version
            }
        case .rmssd:
            if rmssdSamplingDensityVersion != density.version {
                rmssd = OnlineStat(alpha: rmssd.alpha)
                rmssdSamplingDensityVersion = density.version
            }
        }
    }

    public func stat(_ statistic: HRVStatistic) -> OnlineStat {
        switch statistic {
        case .sdnn: return sdnn
        case .rmssd: return rmssd
        }
    }

    public func samplingDensityVersion(_ statistic: HRVStatistic) -> Int {
        switch statistic {
        case .sdnn: return sdnnSamplingDensityVersion
        case .rmssd: return rmssdSamplingDensityVersion
        }
    }

    /// Same thin-history rule as `ForgeHealthQueries.hrvBaseline` (< 5 samples).
    public func baselineMs(_ statistic: HRVStatistic, minimumSamples: Int = 5) -> Double? {
        let series = stat(statistic)
        guard series.n >= minimumSamples else { return nil }
        return series.mean
    }
}

public enum BodyModelHRVBaselineStore: Sendable {
    public static let defaultsKey = "forge.bodyModel.hrvBaselines.v1"

    public static func load(defaults: UserDefaults = .standard) -> BodyModelHRVBaselines {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(BodyModelHRVBaselines.self, from: data) else {
            return BodyModelHRVBaselines()
        }
        return decoded
    }

    public static func save(_ baselines: BodyModelHRVBaselines, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(baselines) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    public static func ingest(_ observation: HRVObservation, defaults: UserDefaults = .standard) {
        var baselines = load(defaults: defaults)
        baselines.ingest(observation)
        save(baselines, defaults: defaults)
    }
}

#if canImport(HealthKit)
extension HealthKitHRVQuantity {
    public static var sdnnIdentifier: HKQuantityTypeIdentifier { .heartRateVariabilitySDNN }

    /// `HKQuantityTypeIdentifierHeartRateVariabilityRMSSD` (`heartRateVariabilityRMSSD`
    /// in HealthKit). Raw value so ForgeCore still compiles on the SPM floor
    /// (iOS 18 / macOS 14) if the SDK has not shipped the static symbol.
    public static var rmssdIdentifier: HKQuantityTypeIdentifier {
        HKQuantityTypeIdentifier(rawValue: rmssdIdentifierRaw)
    }

    public static var sdnnType: HKQuantityType { HKQuantityType(sdnnIdentifier) }
    public static var rmssdType: HKQuantityType { HKQuantityType(rmssdIdentifier) }

    /// Nil when the current SDK/OS does not know the RMSSD quantity type.
    /// Callers must not invent samples; ingest only when this is non-nil and
    /// HealthKit actually returns a reading.
    public static var rmssdTypeIfAvailable: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: rmssdIdentifier)
    }
}
#endif
