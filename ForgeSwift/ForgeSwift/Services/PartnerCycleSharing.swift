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

    /// One instance, because two would disagree. The sharing sheet mints an
    /// invite and the Support pane reads a received digest; separate instances
    /// would each hold half the truth and neither would see the other revoke.
    static let shared = PartnerCycleSharing()

    /// One shared digest per supporter, keyed by the CloudKit share.
    @Published private(set) var activeShares: [ShareHandle] = []
    @Published private(set) var lastPublishError: String?

    /// The invite this device most recently created, kept so the UI can say
    /// "you're sharing" without a CloudKit round trip on every appearance — and
    /// so a user who force-quits mid-flow still sees the truth on relaunch.
    @Published private(set) var currentInvite: PartnerCycleInvite?

    /// A digest someone shared *with* this user, once fetched.
    @Published private(set) var receivedDigest: PartnerCycleDigest?

    /// When the digest last actually reached CloudKit, for the "updated …" line.
    var lastPublishedAt: Date? { publishGate.lastPublishedAt }

    private static let inviteKey = "forge.cycle.sharing.invite.v1"

    /// Long enough to swallow a burst — logging several days in one sitting moves
    /// the digest repeatedly and only the last state matters — short enough that
    /// a correction the user makes deliberately lands promptly. Doubles as the
    /// delay before a deferred or failed write is retried.
    private static let retryInterval: TimeInterval = 90

    /// Content-keyed, so a recompute that leaves the redacted digest unchanged
    /// writes nothing. See `PublishGate` for why this is not simply "publish on
    /// every recompute".
    private let publishGate = PublishGate<PartnerCycleDigest>(
        key: "forge.cycle.sharing.digest",
        minimumInterval: PartnerCycleSharing.retryInterval
    )

    /// The trailing write scheduled by a throttled change. At most one is ever
    /// outstanding; a newer deferral replaces it.
    private var pendingPublish: Task<Void, Never>?

    /// Where a deferred publish gets the *current* digest from when it fires.
    ///
    /// A closure rather than a direct reference so the dependency runs one way
    /// at the type level — the store calls sharing, not the reverse — and so a
    /// test can drive the trailing path without a live store.
    var digestSource: @MainActor () -> PartnerCycleDigest? = {
        MenstrualHealthStore.shared.supporterDigest
    }

    struct ShareHandle: Identifiable, Equatable {
        /// Stable per person, which is what the UI needs to offer "stop sharing
        /// with *them*". Empty when CloudKit gave nothing to identify them by —
        /// see `identifier(for:)`, and note the UI hides removal for those rows.
        let id: String
        let name: String
        let status: PartnerCycleInvite.Status
        /// True for the owner's own row, which CloudKit always includes and the
        /// UI must not offer to remove.
        let isOwner: Bool
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
        if let data = UserDefaults.standard.data(forKey: Self.inviteKey),
           let invite = try? JSONDecoder().decode(PartnerCycleInvite.self, from: data) {
            currentInvite = invite
        }
    }

    private func persistInvite() {
        guard let currentInvite,
              let data = try? JSONEncoder().encode(currentInvite) else {
            UserDefaults.standard.removeObject(forKey: Self.inviteKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.inviteKey)
    }

    // ------------------------------------------------------------
    // MARK: Publish
    // ------------------------------------------------------------

    /// The entry point the app should use. Publishes only when the redacted
    /// digest has actually moved.
    ///
    /// Called from `MenstrualHealthStore.recompute()`, which runs on every
    /// foreground, every logged day and every HealthKit sync. Without the gate
    /// this would be a CloudKit write dozens of times a day for a four-field
    /// value that changes about once — see `PublishGate`.
    ///
    /// Returns whether anything was written.
    @discardableResult
    func publishIfChanged(_ digest: PartnerCycleDigest) async -> Bool {
        // Nobody has been invited, so there is no zone and nothing to keep
        // current. Creating one here would put reproductive state in CloudKit
        // for a user who never asked to share.
        guard currentInvite != nil else { return false }

        switch publishGate.decide(digest) {
        case .skipUnchanged:
            return false

        case .skipTooSoon(let retryAfter):
            // Deferred, never dropped. A throttle with no trailing edge is not a
            // throttle, it is data loss: `recompute()` only runs on foreground,
            // on a log, or on a HealthKit sync, so a change discarded here can
            // sit unpublished until the next one of those — possibly tomorrow.
            // That is the staleness this whole path exists to prevent.
            scheduleTrailingPublish(after: retryAfter)
            return false

        case .publish:
            // Any pending trailing write is now redundant: this call is about to
            // publish something at least as fresh.
            pendingPublish?.cancel()
            pendingPublish = nil

            let ok = await publish(digest)
            // Recorded only on success. A failed write that moved the watermark
            // would drop the change until the digest happened to move again,
            // which for a cycle digest can be a whole day.
            if ok {
                publishGate.recordPublished(digest)
            } else {
                // Retry once the throttle allows it rather than waiting for the
                // next recompute — a transient CloudKit failure should not cost
                // the user a day of freshness.
                scheduleTrailingPublish(after: Self.retryInterval)
            }
            return ok
        }
    }

    /// Publish once the throttle window closes, collapsing repeated deferrals
    /// into a single write.
    ///
    /// Re-reads the digest when it fires rather than capturing the one that was
    /// deferred. Logging four days in one sitting defers three times; the value
    /// worth writing is the state at the end, not the state at the first defer.
    /// A backgrounded app may never get to run this, which is fine: the next
    /// foreground triggers a recompute, and the gate will still see a changed
    /// digest and publish then. The trailing write is what closes the gap for a
    /// user who stays in the app, not a durability guarantee.
    private func scheduleTrailingPublish(after delay: TimeInterval) {
        pendingPublish?.cancel()
        pendingPublish = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard let current = self.digestSource() else { return }
            self.pendingPublish = nil
            await self.publishIfChanged(current)
        }
    }

    /// Write the current digest.
    ///
    /// Every supporter reads the *same* record, so there is one digest to keep
    /// correct rather than one per participant — and revoking a participant cannot
    /// leave a stale personalised copy behind.
    @discardableResult
    func publish(_ digest: PartnerCycleDigest) async -> Bool {
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
            return true
        } catch {
            lastPublishError = error.localizedDescription
            return false
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
        // Recorded before the network call, so the Messages extension can stop
        // showing a live-looking offer even if the zone delete is still in
        // flight or fails outright.
        if let url = currentInvite?.shareURL {
            PartnerInviteRevocation.record(shareURL: url)
        }
        currentInvite = nil
        persistInvite()
        // A deferred write must not outlive the share it was for. Without this
        // cancel, a publish scheduled seconds before the user tapped stop would
        // fire afterwards and recreate the zone they just deleted.
        pendingPublish?.cancel()
        pendingPublish = nil
        // The zone is about to go, taking the record the watermark describes
        // with it. Without this, re-sharing later would compare against a
        // digest that no longer exists anywhere and skip the first publish.
        publishGate.reset()
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [Self.zoneID])
            activeShares = []
        } catch {
            lastPublishError = error.localizedDescription
        }
    }

    /// Stop sharing with one person while leaving anyone else in place.
    ///
    /// `revokeAll` deletes the zone, which is right for "stop entirely" and
    /// wrong the moment there is more than one supporter — removing your partner
    /// should not also cut off your sister. CloudKit removes the participant
    /// from the share; their device loses read access on the next fetch.
    func revoke(participantID: String) async {
        // An unidentifiable participant cannot be matched, and matching the
        // wrong one would remove someone the user did not choose.
        guard !participantID.isEmpty else { return }
        do {
            let rootID = CKRecord.ID(recordName: Self.digestRecordName, zoneID: Self.zoneID)
            let root = try await database.record(for: rootID)
            guard let shareRef = root.share else { return }
            guard let share = try await database.record(for: shareRef.recordID) as? CKShare else { return }

            guard let participant = share.participants.first(where: {
                Self.identifier(for: $0) == participantID
            }), participant.role != .owner else { return }

            share.removeParticipant(participant)
            _ = try await database.modifyRecords(saving: [share], deleting: [])
            await refreshParticipants()
        } catch {
            lastPublishError = error.localizedDescription
        }
    }

    // ------------------------------------------------------------
    // MARK: Who is actually reading this
    // ------------------------------------------------------------

    /// Populate `activeShares` from the real `CKShare` participant list.
    ///
    /// Until this existed the sharing screen said "Sharing is on" because a
    /// locally-stored invite existed — which is true the instant you tap create
    /// and stays true forever, whether or not a single person ever accepted.
    /// The owner could not tell an accepted share from an ignored one.
    func refreshParticipants() async {
        guard currentInvite != nil else {
            activeShares = []
            return
        }
        do {
            let rootID = CKRecord.ID(recordName: Self.digestRecordName, zoneID: Self.zoneID)
            let root = try await database.record(for: rootID)
            guard let shareRef = root.share,
                  let share = try await database.record(for: shareRef.recordID) as? CKShare else {
                activeShares = []
                return
            }
            activeShares = share.participants.map { participant in
                ShareHandle(
                    id: Self.identifier(for: participant),
                    name: Self.displayName(for: participant),
                    status: Self.status(for: participant),
                    isOwner: participant.role == .owner
                )
            }
            lastPublishError = nil
        } catch let error as CKError where error.code == .unknownItem {
            // No zone or no record: the share was revoked, or never completed.
            // Not an error worth showing — it is just the empty state.
            activeShares = []
        } catch {
            lastPublishError = error.localizedDescription
        }
    }

    /// Stable identity for a participant, or `""` when CloudKit gave us nothing
    /// to identify them by.
    ///
    /// The empty sentinel matters: this value is generated during a participant
    /// refresh and matched again during a revoke, so a random fallback would
    /// produce a row whose remove button could never find its own participant.
    /// An empty id is instead treated as "not removable" by the UI, which is at
    /// least honest about what it can do.
    ///
    /// In practice one of the three is always present — `userRecordID` once they
    /// accept, and the email or phone they were invited by before that.
    private static func identifier(for participant: CKShare.Participant) -> String {
        participant.userIdentity.userRecordID?.recordName
            ?? participant.userIdentity.lookupInfo?.emailAddress
            ?? participant.userIdentity.lookupInfo?.phoneNumber
            ?? ""
    }

    private static func displayName(for participant: CKShare.Participant) -> String {
        let components = participant.userIdentity.nameComponents
        if let components {
            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .short)
            if !name.isEmpty { return name }
        }
        // Falls back to whatever they were invited by. Deliberately not "Unknown
        // participant" — a row the owner cannot identify is a row they cannot
        // make a revoke decision about.
        return participant.userIdentity.lookupInfo?.emailAddress
            ?? participant.userIdentity.lookupInfo?.phoneNumber
            ?? "Invited person"
    }

    private static func status(for participant: CKShare.Participant) -> PartnerCycleInvite.Status {
        switch participant.acceptanceStatus {
        case .accepted: return .accepted
        case .pending:  return .pending
        case .removed:  return .revoked
        case .unknown:  return .pending
        @unknown default: return .pending
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
        // Published directly rather than through the gate: this is the very
        // first write, and it must land even if an identical digest happens to
        // match a watermark left by a share the user has since revoked.
        if await publish(digest) {
            publishGate.recordPublished(digest)
        }

        let rootID = CKRecord.ID(recordName: Self.digestRecordName, zoneID: Self.zoneID)
        let root = try await database.record(for: rootID)

        // Reuse the existing share when there is one. Constructing a second
        // CKShare for the same root fails, and inviting a second supporter is
        // the normal case, not an error.
        let share: CKShare
        if let existing = root.share,
           let found = try? await database.record(for: existing.recordID) as? CKShare {
            share = found
        } else {
            share = CKShare(rootRecord: root)
        }
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
        currentInvite = invite
        persistInvite()
        await refreshParticipants()
        return invite
    }

    // ------------------------------------------------------------
    // MARK: Supporter side
    // ------------------------------------------------------------

    /// Fetch the digest a supporter has been granted. Reads the *shared* database —
    /// a supporter never has the owner's private database, so there is no path from
    /// here back to the owner's raw logs even if this code were wrong.
    @discardableResult
    func fetchSharedDigest() async -> PartnerCycleDigest? {
        do {
            let zones = try await container.sharedCloudDatabase.allRecordZones()
            for zone in zones where zone.zoneID.zoneName == Self.zoneID.zoneName {
                let id = CKRecord.ID(recordName: Self.digestRecordName, zoneID: zone.zoneID)
                let record = try await container.sharedCloudDatabase.record(for: id)
                guard let data = record["payload"] as? Data else { continue }
                let digest = try JSONDecoder().decode(PartnerCycleDigest.self, from: data)
                receivedDigest = digest
                return digest
            }
            // No zone means the owner revoked. Drop the cached copy rather than
            // keep showing a digest they have withdrawn — a supporter must not
            // go on seeing yesterday's state after sharing stopped.
            receivedDigest = nil
        } catch {
            lastPublishError = error.localizedDescription
        }
        return nil
    }

    /// Wake supporters when a new digest lands. The notification carries no payload —
    /// only a nudge to refetch — so nothing sensitive passes through APNs or shows up
    /// on a lock screen.
    ///
    /// Registered once per install and remembered locally. CloudKit keeps
    /// subscriptions server-side forever, so re-saving on every launch is a
    /// wasted round trip; the local flag is cleared if the save fails, so a
    /// first launch with no network still gets a subscription eventually.
    func subscribeToUpdates() async {
        let flag = "forge.cycle.sharing.subscribed.v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }

        let subscription = CKDatabaseSubscription(subscriptionID: "partner-digest-updates")
        let info = CKSubscription.NotificationInfo()
        // Silent. No alert, no badge, no sound — the push exists only to say
        // "refetch", and a visible notification about a cycle update is exactly
        // the thing that should never appear on someone's lock screen.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        do {
            _ = try await container.sharedCloudDatabase.modifySubscriptions(
                saving: [subscription], deleting: []
            )
            UserDefaults.standard.set(true, forKey: flag)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Already exists from a previous install of the same iCloud account.
            // That is success as far as we are concerned.
            UserDefaults.standard.set(true, forKey: flag)
        } catch {
            // Left unrecorded so the next launch retries. Not surfaced: a
            // supporter who never gets the push still sees fresh data when they
            // open the Support pane, which refetches on appear.
            #if DEBUG
            print("[PartnerCycleSharing] subscribe failed: \(error.localizedDescription)")
            #endif
        }
    }

    // ------------------------------------------------------------

    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: Self.zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
    }
}
