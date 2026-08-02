import Foundation
import CloudKit
import ForgeCore

// ============================================================
// MARK: - Partner cycle sharing (CloudKit only)
// ============================================================

/// Publishes the owner's `PartnerCycleDigest` to supporters through CloudKit sharing.
///
/// **There is no Forge-side channel.** No DynamoDB, no Lambda, no pairing service.
/// CloudKit owns the record, the share, participant identity, acceptance and
/// revocation, which means Forge never holds reproductive data — there is nothing on
/// our side to breach, subpoena, retain, or get a retention policy wrong about.
///
/// The digest is written to its own custom zone rather than the default one. Sharing
/// in CloudKit is per-record-hierarchy, and a dedicated zone keeps the shared surface
/// to exactly one record: a supporter can never be handed a share whose root reaches
/// something else the user stored later.
///
/// What crosses the wire is a `PartnerCycleDigest` — already redacted by
/// `init(redacting:)`. The full `MenstrualCycleSnapshot` is never encoded here, and
/// deliberately has no path into this file.
@MainActor
final class PartnerCycleSharing: ObservableObject {

    /// One shared digest per supporter, keyed by the CloudKit share.
    @Published private(set) var activeShares: [ShareHandle] = []
    @Published private(set) var lastPublishError: String?

    struct ShareHandle: Identifiable, Equatable {
        let id: String            // CKRecord.ID.recordName of the share
        let role: CycleSupportRole
        let participantName: String?
        let status: PartnerCycleInvite.Status
    }

    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }

    /// Custom zone — see the note above on why this is not the default zone.
    private static let zoneID = CKRecordZone.ID(zoneName: "PartnerCycleDigest",
                                                ownerName: CKCurrentUserDefaultName)
    private static let digestRecordType = "CycleDigest"
    private static let digestRecordName = "currentDigest"

    init(containerIdentifier: String = "iCloud.com.forge.ForgeSwift") {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    // ------------------------------------------------------------
    // MARK: Publish
    // ------------------------------------------------------------

    /// Write the current digest. Called whenever the owner's snapshot changes.
    ///
    /// Every supporter reads the *same* record, so there is one digest to keep
    /// correct rather than one per participant — and revoking a participant cannot
    /// leave a stale personalised copy behind.
    func publish(_ digest: PartnerCycleDigest) async {
        do {
            try await ensureZone()
            let record = CKRecord(
                recordType: Self.digestRecordType,
                recordID: CKRecord.ID(recordName: Self.digestRecordName, zoneID: Self.zoneID)
            )
            // Encoded whole rather than field-by-field, so adding a digest field can
            // never accidentally skip the redaction boundary on its way to CloudKit.
            record["payload"] = try JSONEncoder().encode(digest) as CKRecordValue
            record["asOfDayKey"] = digest.asOfDayKey as CKRecordValue

            _ = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .allKeys
            )
            lastPublishError = nil
        } catch {
            lastPublishError = error.localizedDescription
        }
    }

    /// Stop sharing with everyone, immediately.
    ///
    /// Deletes the whole zone rather than just the share. Removing participants
    /// leaves the record in place; deleting the zone removes the record the shares
    /// point at, so a cached copy on a supporter's device has nothing to refresh
    /// from. Revocation should be total and obvious, not partial and quiet.
    func revokeAll() async {
        // Cleared first, and unconditionally. If the zone delete fails we would
        // rather have an un-sendable staged invite than leave one sitting in the
        // app group for the Messages extension to hand out after the user has
        // said stop.
        PartnerInviteHandoff.clear()
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [Self.zoneID])
            activeShares = []
        } catch {
            lastPublishError = error.localizedDescription
        }
    }

    // ------------------------------------------------------------
    // MARK: Invite
    // ------------------------------------------------------------

    /// Create (or reuse) the share and hand back an invite ready for Messages.
    ///
    /// `publicPermission` stays `.none`: the share is participant-only, so a leaked
    /// URL alone grants nothing without an Apple ID CloudKit has accepted.
    func makeInvite(role: CycleSupportRole,
                    fromDisplayName: String,
                    digest: PartnerCycleDigest) async throws -> PartnerCycleInvite {
        try await ensureZone()
        await publish(digest)

        let rootID = CKRecord.ID(recordName: Self.digestRecordName, zoneID: Self.zoneID)
        let root = try await database.record(for: rootID)

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Forge support updates" as CKRecordValue
        share.publicPermission = .none

        _ = try await database.modifyRecords(saving: [root, share], deleting: [])

        guard let url = share.url else {
            throw NSError(domain: "PartnerCycleSharing", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "CloudKit did not return a share URL."
            ])
        }
        let invite = PartnerCycleInvite(shareURL: url, role: role, fromDisplayName: fromDisplayName)

        // Hand the invite to the Messages extension. Staging happens only here,
        // after the share exists and after the owner walked the consent flow that
        // led to this call — the extension has no way to reach this method, which
        // is what stops an invite being created from inside a chat.
        PartnerInviteHandoff.stage(invite.messagePayload)
        return invite
    }

    // ------------------------------------------------------------
    // MARK: Supporter side
    // ------------------------------------------------------------

    /// Fetch the digest a supporter has been granted. Reads the *shared* database —
    /// a supporter never has the owner's private database, so there is no path from
    /// here back to the owner's raw logs even if this code were wrong.
    func fetchSharedDigest() async -> PartnerCycleDigest? {
        do {
            let zones = try await container.sharedCloudDatabase.allRecordZones()
            for zone in zones where zone.zoneID.zoneName == Self.zoneID.zoneName {
                let id = CKRecord.ID(recordName: Self.digestRecordName, zoneID: zone.zoneID)
                let record = try await container.sharedCloudDatabase.record(for: id)
                guard let data = record["payload"] as? Data else { continue }
                return try JSONDecoder().decode(PartnerCycleDigest.self, from: data)
            }
        } catch {
            lastPublishError = error.localizedDescription
        }
        return nil
    }

    /// Wake supporters when a new digest lands. The notification carries no payload —
    /// only a nudge to refetch — so nothing sensitive passes through APNs or shows up
    /// on a lock screen.
    func subscribeToUpdates() async {
        let subscription = CKDatabaseSubscription(subscriptionID: "partner-digest-updates")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try? await container.sharedCloudDatabase.modifySubscriptions(
            saving: [subscription], deleting: []
        )
    }

    // ------------------------------------------------------------

    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: Self.zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
    }
}
