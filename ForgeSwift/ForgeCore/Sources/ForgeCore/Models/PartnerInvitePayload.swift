import Foundation

// ============================================================
// MARK: - Wire format for a support invite
// ============================================================

/// The invite as it travels inside an iMessage bubble.
///
/// **In ForgeCore, not the app**, for two reasons. It is the one piece of this
/// feature the Messages extension has to share with the app, and ForgeCore is
/// where shared code already lives — but more usefully, ForgeCore is the only
/// part of this project `swift test` can reach, so the URL codec, the expiry
/// rule and the staging window are covered by CI rather than by a simulator
/// session someone remembers to run.
///
/// It imports nothing but Foundation, and must keep doing so. The extension must
/// never pull in `MenstrualCycleModels.swift` — that file carries the flow
/// levels, symptom logs and fertility state this whole feature exists to keep
/// away from a partner, and an extension that can decode them is one refactor
/// away from displaying them. Keeping the shared surface to plain strings makes
/// that impossible rather than merely discouraged.
///
/// Nothing here is cycle data. The payload is a share URL, a name the sender
/// chose, and a status. An iMessage transcript is backed up to iCloud,
/// screenshotted, read on a lock screen and synced to every device on the
/// account — so the rule is that the whole payload can leak without revealing
/// that the sender menstruates, let alone anything about it.
public struct PartnerInvitePayload: Codable, Equatable, Sendable {

    /// Bumped when a field changes meaning. An extension that receives a payload
    /// from a newer app shows "update Forge" instead of guessing — a bubble that
    /// silently mis-renders a sharing state is worse than one that admits it is
    /// out of date.
    public static let currentVersion = 1

    /// Custom scheme, consumed by the extension rather than by Safari. The
    /// *human* accept path is `shareURL`, which CloudKit resolves through
    /// `userDidAcceptCloudKitShareWith` — see `acceptURL`.
    public static let scheme = "forge"
    public static let host = "support-invite"

    /// Live state of an invite sitting in a transcript. Mirrors
    /// `PartnerCycleInvite.Status`; deliberately re-declared rather than shared,
    /// so the extension needs no app types.
    public enum Status: String, Codable, Sendable {
        case pending, accepted, revoked, expired

        public var caption: String {
            switch self {
            case .pending:  return "Waiting to be accepted"
            case .accepted: return "Sharing support updates"
            case .revoked:  return "Sharing stopped"
            case .expired:  return "Invitation expired"
            }
        }

        /// Whether the bubble should still read as an offer. A revoked invite
        /// that still says "Accept" is the failure this exists to prevent.
        public var isActionable: Bool { self == .pending }
    }

    public let version: Int
    /// `CKShare.url`. Worthless without an Apple ID CloudKit has accepted, since
    /// the share is created with `publicPermission = .none`.
    public let shareURL: URL
    public let fromDisplayName: String
    /// `CycleSupportRole.rawValue`, carried as a plain string. The extension
    /// never interprets it — it only echoes it back on a status update, so the
    /// app remains the only place the role taxonomy is known.
    public let roleRaw: String
    /// Pre-rendered by the app, so the extension needs no copy of the role
    /// labels and cannot drift out of sync with them.
    public let roleLabel: String
    public let status: Status
    public let createdAt: Date
    public let expiresAt: Date

    public init(version: Int = PartnerInvitePayload.currentVersion,
         shareURL: URL,
         fromDisplayName: String,
         roleRaw: String,
         roleLabel: String,
         status: Status = .pending,
         createdAt: Date = Date(),
         expiresAt: Date) {
        self.version = version
        self.shareURL = shareURL
        self.fromDisplayName = fromDisplayName
        self.roleRaw = roleRaw
        self.roleLabel = roleLabel
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    // ------------------------------------------------------------
    // MARK: URL coding
    // ------------------------------------------------------------

    /// Characters that must not survive into a query value.
    ///
    /// `CharacterSet.urlQueryAllowed` permits `&`, `=`, `+` and `?`, because they
    /// are legal *somewhere* in a query string — but a display name containing
    /// one would end the value early and silently truncate everything after it.
    /// "Sam & Alex" would arrive as "Sam " with the share URL missing.
    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?")
        return set
    }()

    /// Encoded as query items rather than a JSON blob because `MSMessage.url` is
    /// the only state a message carries, and query items survive the round trip
    /// through Messages without a second layer of escaping.
    ///
    /// Written through `percentEncodedQueryItems` rather than `queryItems` so the
    /// escaping above is the one that applies — the `queryItems` setter uses
    /// `urlQueryAllowed` and would leave the separators intact.
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.percentEncodedQueryItems = [
            ("v", String(version)),
            ("share", shareURL.absoluteString),
            ("from", fromDisplayName),
            ("role", roleRaw),
            ("roleLabel", roleLabel),
            ("status", status.rawValue),
            ("created", String(Int(createdAt.timeIntervalSince1970))),
            ("expires", String(Int(expiresAt.timeIntervalSince1970)))
        ].map { name, value in
            URLQueryItem(name: name,
                         value: value.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed))
        }
        // Only reachable if URLComponents rejects a value it just accepted;
        // falling back keeps the extension from trapping inside Messages.
        return components.url ?? URL(string: "\(Self.scheme)://\(Self.host)")!
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == Self.host,
              let items = components.queryItems else { return nil }

        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        guard let versionText = value("v"), let version = Int(versionText),
              let shareText = value("share"), let shareURL = URL(string: shareText),
              let from = value("from"),
              let role = value("role"),
              let statusText = value("status"),
              let status = Status(rawValue: statusText)
        else { return nil }

        self.version = version
        self.shareURL = shareURL
        self.fromDisplayName = from
        self.roleRaw = role
        self.roleLabel = value("roleLabel") ?? ""
        self.status = status
        self.createdAt = Self.date(value("created")) ?? Date()
        // A payload with no expiry is treated as already expired rather than as
        // permanent. An invite that never lapses is a standing grant nobody
        // revisits, which is the wrong default for this data.
        self.expiresAt = Self.date(value("expires")) ?? .distantPast
    }

    private static func date(_ text: String?) -> Date? {
        guard let text, let seconds = TimeInterval(text) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    // ------------------------------------------------------------
    // MARK: Presentation
    // ------------------------------------------------------------

    /// What the recipient's device opens to accept. This is the CloudKit share
    /// URL untouched: iOS hands it to `userDidAcceptCloudKitShareWith`, so
    /// acceptance, participant identity and revocation stay CloudKit's job and
    /// no pairing service of ours ever sees it.
    public var acceptURL: URL { shareURL }

    /// Rendered into the bubble, and therefore onto lock screens. Says who is
    /// asking and nothing about what for.
    public var bubbleCaption: String { "Support updates from \(fromDisplayName)" }

    public var bubbleSubcaption: String {
        effectiveStatus.isActionable ? "Tap to see what you'd see" : effectiveStatus.caption
    }

    /// `status` with expiry applied. The sender's device sets `.pending` and then
    /// may never run again, so a bubble that trusted the stored value alone would
    /// keep offering a dead invite indefinitely.
    public var effectiveStatus: Status {
        if status == .pending && expiresAt <= Date() { return .expired }
        return status
    }

    public var isReadable: Bool { version <= Self.currentVersion }

    /// A copy with a new status, for the in-place `MSSession` update that keeps
    /// the transcript honest after an accept or a revoke.
    public func updating(status newStatus: Status) -> PartnerInvitePayload {
        PartnerInvitePayload(version: version,
                             shareURL: shareURL,
                             fromDisplayName: fromDisplayName,
                             roleRaw: roleRaw,
                             roleLabel: roleLabel,
                             status: newStatus,
                             createdAt: createdAt,
                             expiresAt: expiresAt)
    }
}

// ============================================================
// MARK: - App → extension handoff
// ============================================================

/// Shared backing store for the two handoff boxes below.
///
/// Split out so tests can point them at a scratch suite. Without a seam, the
/// tests either write into the real app-group domain — leaking state between
/// runs and into a developer's simulator — or skip on any machine where
/// `UserDefaults(suiteName:)` declines the group, which would quietly turn the
/// only coverage this feature has into a no-op.
enum PartnerInviteBox {
    // Mutable global, deliberately: the seam exists so tests can redirect it,
    // and in the app it is written once at launch or never.
    nonisolated(unsafe) static var store: UserDefaults? =
        UserDefaults(suiteName: WatchSnapshotStore.appGroupID)
}

/// The box the app leaves an invite in for the Messages extension to pick up.
///
/// The extension deliberately cannot mint a share itself. Two reasons, and the
/// second is the one that matters:
///
/// 1. Messages extensions run under a hard memory ceiling and get killed
///    mid-CloudKit-round-trip often enough that it is not a sane place to do it.
/// 2. **Minting a share is a consent decision.** Choosing who to share with, and
///    what role they hold, belongs to the deliberate flow in the app next to
///    `CyclePrivacy` — not to a keyboard-height sheet inside a chat. An extension
///    that could create a share on its own would be a path to sharing reproductive
///    data without ever seeing the screen that explains what is being shared.
///
/// So the app mints, writes here, and the extension carries. With no invite
/// staged, the extension's only option is to send the user to the app.
public enum PartnerInviteHandoff {

    public static let appGroupID = WatchSnapshotStore.appGroupID
    private static let key = "partner.invite.outbound.v1"

    /// Invites go stale on purpose. Staging one is the app saying "the user is
    /// about to send this", not "the user has standing permission to send it" —
    /// so if they wander off and come back tomorrow, the extension asks again.
    public static let stagingWindow: TimeInterval = 60 * 30

    private static var defaults: UserDefaults? { PartnerInviteBox.store }

    /// Stage an invite for the extension. Pass `nil` to clear — which the app
    /// must do on revoke, so a stale invite cannot be re-sent after sharing has
    /// been turned off.
    public static func stage(_ payload: PartnerInvitePayload?) {
        guard let defaults else { return }
        guard let payload else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }

    /// The staged invite, or `nil` if there is none, it has gone stale, or it is
    /// past its own expiry. All three collapse to the same answer on purpose:
    /// the extension has exactly one fallback and does not need to distinguish.
    public static func staged(now: Date = Date()) -> PartnerInvitePayload? {
        guard let defaults,
              let data = defaults.data(forKey: key),
              let payload = try? JSONDecoder().decode(PartnerInvitePayload.self, from: data),
              payload.isReadable,
              now.timeIntervalSince(payload.createdAt) <= stagingWindow,
              payload.expiresAt > now
        else { return nil }
        return payload
    }

    public static func clear() { stage(nil) }
}

// ============================================================
// MARK: - Supporter → extension handoff
// ============================================================

/// The mirror of `PartnerInviteHandoff`, on the receiving side: which shares
/// this device has actually accepted.
///
/// It exists so the extension never has to *claim* an acceptance it cannot see.
/// Tapping "Accept" hands off to Safari and then to CloudKit, and the extension
/// is long dead by the time that resolves — so an extension that flipped the
/// bubble to "accepted" on tap would be reporting an intention as a fact, and
/// would keep saying so even if the accept failed.
///
/// Instead the app records the acceptance when CloudKit confirms it
/// (`userDidAcceptCloudKitShareWith`), and the next time the supporter opens
/// this bubble the extension offers to send the update. The transcript only ever
/// states things that happened.
public enum PartnerInviteAcceptance {

    private static let key = "partner.invite.accepted.v1"

    private static var defaults: UserDefaults? { PartnerInviteBox.store }

    /// Keyed by share URL rather than by sender, because one supporter can hold
    /// shares from more than one person and the URL is the only identifier both
    /// sides agree on.
    public static func record(shareURL: URL) {
        guard let defaults else { return }
        var accepted = Set(defaults.stringArray(forKey: key) ?? [])
        accepted.insert(shareURL.absoluteString)
        defaults.set(Array(accepted), forKey: key)
    }

    public static func forget(shareURL: URL) {
        guard let defaults else { return }
        var accepted = Set(defaults.stringArray(forKey: key) ?? [])
        accepted.remove(shareURL.absoluteString)
        defaults.set(Array(accepted), forKey: key)
    }

    public static func hasAccepted(shareURL: URL) -> Bool {
        guard let defaults else { return false }
        return (defaults.stringArray(forKey: key) ?? []).contains(shareURL.absoluteString)
    }
}

// ============================================================
// MARK: - Owner → extension revocation
// ============================================================

/// Shares this device has stopped, so the Messages extension can offer to say so
/// in the thread it was offered in.
///
/// Without it the sender's own bubble goes on reading "Waiting on them" forever
/// after they revoke — the extension has no CloudKit access and no other way to
/// learn that sharing ended. Same discipline as `PartnerInviteAcceptance`: the
/// app records a thing that *happened*, and the extension reports it. The
/// extension never infers it.
///
/// Only whole-share revocation is recorded. Removing one participant cannot be
/// mapped back to a specific conversation, so claiming a particular thread's
/// invite was stopped would sometimes be wrong.
public enum PartnerInviteRevocation {

    private static let key = "partner.invite.revoked.v1"

    private static var defaults: UserDefaults? { PartnerInviteBox.store }

    public static func record(shareURL: URL) {
        guard let defaults else { return }
        var revoked = Set(defaults.stringArray(forKey: key) ?? [])
        revoked.insert(shareURL.absoluteString)
        defaults.set(Array(revoked), forKey: key)
        // A revoked share is no longer accepted by anyone, and leaving it in the
        // accepted set would let a supporter's bubble claim it is live.
        PartnerInviteAcceptance.forget(shareURL: shareURL)
    }

    /// Called when the same URL is shared again, which cannot happen today —
    /// revoking deletes the zone and a new share gets a new URL — but keeps the
    /// two sets from disagreeing if that ever changes.
    public static func clear(shareURL: URL) {
        guard let defaults else { return }
        var revoked = Set(defaults.stringArray(forKey: key) ?? [])
        revoked.remove(shareURL.absoluteString)
        defaults.set(Array(revoked), forKey: key)
    }

    public static func wasRevoked(shareURL: URL) -> Bool {
        guard let defaults else { return false }
        return (defaults.stringArray(forKey: key) ?? []).contains(shareURL.absoluteString)
    }
}
