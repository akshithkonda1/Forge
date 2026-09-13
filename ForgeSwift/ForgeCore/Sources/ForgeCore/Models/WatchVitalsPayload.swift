import Foundation

/// Compact Watch → iPhone vitals. HealthKit is still the ledger; this is
/// the extra path for Simulator pairs (App Groups often do not share) and
/// for ARIA to see a wrist reading before Apple Health has synced.
public struct WatchVitalsPayload: Codable, Sendable, Equatable {
    public var sampledAt: Date
    public var bodyTemperatureF: Double?
    public var wristTemperatureDeviationC: Double?
    public var restingHeartRate: Double?
    public var restingHeartRateBaseline: Double?
    public var hrvMs: Double?
    public var hrvBaselineMs: Double?
    public var hoursSinceLastWorkout: Double?
    /// `watch` or `iphone`. Never a user identifier.
    public var source: String

    public init(
        sampledAt: Date = Date(),
        bodyTemperatureF: Double? = nil,
        wristTemperatureDeviationC: Double? = nil,
        restingHeartRate: Double? = nil,
        restingHeartRateBaseline: Double? = nil,
        hrvMs: Double? = nil,
        hrvBaselineMs: Double? = nil,
        hoursSinceLastWorkout: Double? = nil,
        source: String
    ) {
        self.sampledAt = sampledAt
        self.bodyTemperatureF = bodyTemperatureF
        self.wristTemperatureDeviationC = wristTemperatureDeviationC
        self.restingHeartRate = restingHeartRate
        self.restingHeartRateBaseline = restingHeartRateBaseline
        self.hrvMs = hrvMs
        self.hrvBaselineMs = hrvBaselineMs
        self.hoursSinceLastWorkout = hoursSinceLastWorkout
        self.source = source
    }

    public func asReading() -> AriaVitalReading {
        AriaVitalReading(
            sampledAt: sampledAt,
            bodyTemperatureF: bodyTemperatureF,
            wristTemperatureDeviationC: wristTemperatureDeviationC,
            restingHeartRate: restingHeartRate,
            restingHeartRateBaseline: restingHeartRateBaseline,
            hrvMs: hrvMs,
            hrvBaselineMs: hrvBaselineMs,
            hoursSinceLastWorkout: hoursSinceLastWorkout
        )
    }

    public var hasAnySignal: Bool {
        bodyTemperatureF != nil
            || wristTemperatureDeviationC != nil
            || restingHeartRate != nil
            || hrvMs != nil
    }
}

public enum WatchVitalsLinkKeys {
    public static let snapshot = "forge.watch.vitals"
}

/// Watch → iPhone latest sleep stage Apple just delivered. Not a live stream.
public struct WatchSleepSamplePayload: Codable, Sendable, Equatable {
    public var sampledAt: Date
    public var stage: String
    public var start: Date
    public var end: Date
    public var source: String

    public init(
        sampledAt: Date = Date(),
        stage: String,
        start: Date,
        end: Date,
        source: String
    ) {
        self.sampledAt = sampledAt
        self.stage = stage
        self.start = start
        self.end = end
        self.source = source
    }

    public init(segment: SleepStageSegment, sampledAt: Date = Date(), source: String) {
        self.init(
            sampledAt: sampledAt,
            stage: segment.stage.rawValue,
            start: segment.start,
            end: segment.end,
            source: source
        )
    }

    public var sleepStage: SleepStage? { SleepStage(rawValue: stage) }
}

public enum WatchSleepLinkKeys {
    public static let snapshot = "forge.watch.sleepSample"
}

/// On-device inbox. Not uploaded. App Group when it works; WCSession fills
/// the same key on the phone when the Watch pair cannot share defaults.
public enum WatchVitalsInbox {
    private static let key = "forge.watch.vitals.inbox.v1"

    public static func load(defaults: UserDefaults? = UserDefaults(suiteName: WatchSnapshotStore.appGroupID)) -> WatchVitalsPayload? {
        let store = defaults ?? .standard
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchVitalsPayload.self, from: data)
    }

    public static func save(
        _ payload: WatchVitalsPayload,
        defaults: UserDefaults? = UserDefaults(suiteName: WatchSnapshotStore.appGroupID)
    ) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        (defaults ?? .standard).set(data, forKey: key)
    }
}
