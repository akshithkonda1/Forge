import Foundation

/// Device-to-device continuity for on-phone health state.
///
/// This envelope is for CloudKit's private database (end-to-end encrypted
/// where Apple provides it). It never goes to Forge's API, Dynamo, or S3.
/// A new phone logs into iCloud and reads this; Forge servers stay
/// compute, non-health database, and AI inference only.
public struct HealthContinuityEnvelope: Equatable, Sendable, Codable {
    public static let schemaVersion = 1
    public static let cloudKitRecordType = "ForgeHealthContinuity"
    public static let cloudKitZone = "ForgePrivate"

    public var schemaVersion: Int
    public var learnerJSON: Data
    public var scoutTags: [String]
    public var updatedAt: Date

    public init(
        schemaVersion: Int = schemaVersion,
        learnerJSON: Data,
        scoutTags: [String],
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.learnerJSON = learnerJSON
        self.scoutTags = scoutTags
        self.updatedAt = updatedAt
    }

    public static func make(learner: HealthIngestLearner, scout: HealthScoutReport) -> HealthContinuityEnvelope {
        let data = (try? JSONEncoder().encode(learner)) ?? Data()
        return HealthContinuityEnvelope(learnerJSON: data, scoutTags: scout.ariaTags)
    }
}
