import Foundation
import ForgeCore

// ============================================================
// MARK: - Partner cycle digest
// ============================================================

/// What a support person is allowed to see.
///
/// This is a **separate type**, not a filtered `MenstrualCycleSnapshot`. That is the
/// whole point. The snapshot carries 45 fields including `fertileScore`,
/// `ovulationDayInCycle`, `cycleGoal` (`.ttc` — trying to conceive), `twwDaysElapsed`
/// (the two-week wait, i.e. possibly pregnant), `condition`, and day-level bleeding
/// state. Handing partner UI a snapshot and trusting every future view to remember
/// which fields are off-limits is a guarantee that lasts until the next feature.
/// Handing it a digest means the compiler enforces the boundary instead.
///
/// There is exactly one place the boundary is crossed — `init(redacting:)` below — so
/// there is exactly one place to audit, and one place to test.
///
/// **Deliberately absent, and it must stay that way:** fertile window, fertile score,
/// ovulation timing, cycle goal, two-week-wait state, health conditions, flow volume,
/// individual symptoms, sexual-activity logs, test results, exact cycle day, and any
/// raw day-level entry.
struct PartnerCycleDigest: Codable, Equatable, Hashable {

    /// A deliberately coarser phase than `MenstrualPhase`.
    ///
    /// `MenstrualPhase` has `.fertileWindow` and `.ovulation` cases, so passing the
    /// real phase through *is* a fertility disclosure — it tells a partner when
    /// conception is likely, which is not theirs to know by default. Those collapse
    /// into `.rebuilding` here, alongside ordinary follicular days, and the two are
    /// indistinguishable from the outside.
    enum SupportPhase: String, Codable, Hashable {
        /// Menstruation.
        case bleeding
        /// Follicular *and* fertile/ovulatory days, deliberately merged.
        case rebuilding
        /// Luteal.
        case winding
        case unknown

        var label: String {
            switch self {
            case .bleeding:   return "On their period"
            case .rebuilding: return "Energy building"
            case .winding:    return "Winding down"
            case .unknown:    return "No recent data"
            }
        }
    }

    /// Coarse energy read. Three buckets, because a partner needs to know how to show
    /// up, not a number they can chart.
    enum EnergyBand: String, Codable, Hashable {
        case low, steady, high

        var label: String {
            switch self {
            case .low:    return "Lower energy"
            case .steady: return "Steady"
            case .high:   return "Higher energy"
            }
        }
    }

    let phase: SupportPhase
    let energy: EnergyBand

    /// Rough distance to the next period, in days, bucketed — never an exact date.
    /// `nil` when unknown or when the prediction is not confident enough to share.
    let daysUntilNextPeriodApprox: Int?

    /// True when a little extra thoughtfulness lands well. Derived from phase and
    /// energy only — never from symptoms or mood logs.
    let extraThoughtfulnessHelps: Bool

    /// One short, actionable line. Generated on the owner's device from data that
    /// never leaves it, so the sentence travels instead of the inputs.
    let supportHeadline: String

    /// When the owner's device produced this. Lets the partner UI say "as of
    /// yesterday" rather than implying live access.
    let asOfDayKey: String

    /// Either person marked the bleed over. Visible on both sides, no dates
    /// of ovulation, no notes. `false` on older digests that omit the field.
    let periodFinished: Bool
    /// Coarse day the finish was recorded. Never a predicted next-period date.
    let periodFinishedDayKey: String?

    // ------------------------------------------------------------
    // MARK: Freshness
    // ------------------------------------------------------------

    /// How many days old this digest is, from the supporter's point of view.
    ///
    /// The whole value of a shared digest is that it is current. When the owner's
    /// device stops publishing — they deleted the app, lost iCloud, turned
    /// sharing off in a way that left the zone intact — the supporter's copy just
    /// sits there looking authoritative. This is what lets the UI say so.
    var ageInDays: Int? {
        CycleDayKey.daysBetween(asOfDayKey, CycleDayKey.key())
    }

    /// Past this, the digest is old enough that acting on it is worse than
    /// asking. Three days is roughly the point where a phase could have changed
    /// underneath it without the supporter seeing anything move.
    static let stalenessThresholdDays = 3

    var isStale: Bool { (ageInDays ?? .max) >= Self.stalenessThresholdDays }

    /// A digest that says nothing, for when the owner has paused sharing.
    ///
    /// Pausing publishes one of these rather than simply stopping. The
    /// difference matters: a supporter who stops receiving updates sees a stale
    /// digest that still *looks* current for days, whereas `.unknown` renders as
    /// "No recent data" — which is true, and which carries no accusation. It does
    /// not announce that a choice was made, only that there is nothing to show.
    static func paused(asOf dayKey: String = CycleDayKey.key()) -> PartnerCycleDigest {
        PartnerCycleDigest(
            phase: .unknown,
            energy: .steady,
            daysUntilNextPeriodApprox: nil,
            extraThoughtfulnessHelps: false,
            supportHeadline: SupporterGuidance.headline(phase: .unknown,
                                                        energy: .steady,
                                                        thoughtfulnessHelps: false),
            asOfDayKey: dayKey,
            periodFinished: false,
            periodFinishedDayKey: nil
        )
    }

    /// Memberwise, kept private so `init(redacting:)` stays the only way a
    /// *snapshot* becomes a digest. `paused(asOf:)` builds a digest from nothing
    /// at all, which is a different thing and cannot leak.
    private init(phase: SupportPhase,
                 energy: EnergyBand,
                 daysUntilNextPeriodApprox: Int?,
                 extraThoughtfulnessHelps: Bool,
                 supportHeadline: String,
                 asOfDayKey: String,
                 periodFinished: Bool = false,
                 periodFinishedDayKey: String? = nil) {
        self.phase = phase
        self.energy = energy
        self.daysUntilNextPeriodApprox = daysUntilNextPeriodApprox
        self.extraThoughtfulnessHelps = extraThoughtfulnessHelps
        self.supportHeadline = supportHeadline
        self.asOfDayKey = asOfDayKey
        self.periodFinished = periodFinished
        self.periodFinishedDayKey = periodFinishedDayKey
    }

    /// Support-side write: mark the bleed over without inventing fertility data.
    func markingPeriodFinished(on dayKey: String) -> PartnerCycleDigest {
        let nextPhase: SupportPhase = phase == .bleeding ? .rebuilding : phase
        return PartnerCycleDigest(
            phase: nextPhase,
            energy: nextPhase == .rebuilding ? .high : energy,
            daysUntilNextPeriodApprox: daysUntilNextPeriodApprox,
            extraThoughtfulnessHelps: false,
            supportHeadline: "Period finished. Everyday support is enough.",
            asOfDayKey: dayKey,
            periodFinished: true,
            periodFinishedDayKey: dayKey
        )
    }

    // ------------------------------------------------------------
    // MARK: The one crossing point
    // ------------------------------------------------------------

    /// Build a digest from a full snapshot. **The only place snapshot data becomes
    /// partner-visible.** Every field is either coarsened or dropped; nothing is
    /// copied across verbatim except the date stamp.
    ///
    /// The headline is *not* a parameter. It used to be, and that was a hole: a
    /// caller holding the full snapshot could write "great week to try" and hand
    /// it in, moving the disclosure out of the fields and into the prose where
    /// nothing checks it. It is now derived from the coarse values this
    /// initialiser has already computed, so the digest cannot say more than the
    /// digest contains.
    init(redacting snapshot: MenstrualCycleSnapshot) {
        // Everything is resolved into locals first and assigned in one block at
        // the end. The headline is a function of the other fields, and reading a
        // half-initialised `self` to compute it is the kind of thing that works
        // until someone reorders the assignments.

        // Fertile and ovulatory days are folded into `.rebuilding` so the digest
        // cannot be used to infer conception timing.
        let resolvedPhase: SupportPhase
        switch snapshot.phase {
        case .menstruation:
            resolvedPhase = .bleeding
        case .follicular, .fertileWindow, .ovulation:
            resolvedPhase = .rebuilding
        case .luteal:
            resolvedPhase = .winding
        case .unknown:
            resolvedPhase = .unknown
        }

        let resolvedEnergy: EnergyBand
        switch resolvedPhase {
        case .bleeding:   resolvedEnergy = snapshot.recommendRecoveryBias ? .low : .steady
        case .rebuilding: resolvedEnergy = .high
        case .winding:    resolvedEnergy = snapshot.recommendRecoveryBias ? .low : .steady
        case .unknown:    resolvedEnergy = .steady
        }

        // Bucketed to a coarse number of days. The exact predicted date is withheld
        // even though it is known, because a date invites counting and a rough
        // distance is all a supporter needs.
        let approxDays: Int? = {
            guard let next = snapshot.nextPeriod,
                  let days = CycleDayKey.daysBetween(snapshot.asOfDayKey, next.medianDayKey),
                  days >= 0,
                  // Withhold entirely when the underlying prediction is weak, rather
                  // than sharing a guess someone might plan around.
                  snapshot.periodTimingConfidence >= 0.4
            else { return nil }
            switch days {
            case 0...1:   return 1
            case 2...3:   return 3
            case 4...7:   return 7
            case 8...14:  return 14
            default:      return 21
            }
        }()

        let thoughtful = (resolvedPhase == .bleeding)
            || (resolvedPhase == .winding && snapshot.recommendRecoveryBias)

        phase = resolvedPhase
        energy = resolvedEnergy
        daysUntilNextPeriodApprox = approxDays
        extraThoughtfulnessHelps = thoughtful
        let finished = snapshot.periodEndConfirmed && !snapshot.isCurrentlyBleeding
        supportHeadline = finished
            ? "Period finished. Everyday support is enough."
            : SupporterGuidance.headline(
                phase: resolvedPhase,
                energy: resolvedEnergy,
                thoughtfulnessHelps: thoughtful
            )
        asOfDayKey = snapshot.asOfDayKey
        periodFinished = finished
        periodFinishedDayKey = finished ? snapshot.asOfDayKey : nil
    }

    enum CodingKeys: String, CodingKey {
        case phase, energy, daysUntilNextPeriodApprox, extraThoughtfulnessHelps
        case supportHeadline, asOfDayKey, periodFinished, periodFinishedDayKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decode(SupportPhase.self, forKey: .phase)
        energy = try c.decode(EnergyBand.self, forKey: .energy)
        daysUntilNextPeriodApprox = try c.decodeIfPresent(Int.self, forKey: .daysUntilNextPeriodApprox)
        extraThoughtfulnessHelps = try c.decode(Bool.self, forKey: .extraThoughtfulnessHelps)
        supportHeadline = try c.decode(String.self, forKey: .supportHeadline)
        asOfDayKey = try c.decode(String.self, forKey: .asOfDayKey)
        periodFinished = try c.decodeIfPresent(Bool.self, forKey: .periodFinished) ?? false
        periodFinishedDayKey = try c.decodeIfPresent(String.self, forKey: .periodFinishedDayKey)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(phase, forKey: .phase)
        try c.encode(energy, forKey: .energy)
        try c.encodeIfPresent(daysUntilNextPeriodApprox, forKey: .daysUntilNextPeriodApprox)
        try c.encode(extraThoughtfulnessHelps, forKey: .extraThoughtfulnessHelps)
        try c.encode(supportHeadline, forKey: .supportHeadline)
        try c.encode(asOfDayKey, forKey: .asOfDayKey)
        try c.encode(periodFinished, forKey: .periodFinished)
        try c.encodeIfPresent(periodFinishedDayKey, forKey: .periodFinishedDayKey)
    }
}

// ============================================================
// MARK: - Adaptive support lens
// ============================================================

/// Shapes what a supporter is shown, by who they are to the person they support.
///
/// A romantic partner, a father supporting a daughter, and a friend need different
/// language for the same underlying state — and the sexual-health material that is
/// appropriate for one is inappropriate or irrelevant for another. Rather than one
/// screen with conditionals scattered through it, the lens resolves once and the UI
/// reads it.
struct PartnerSupportLens: Equatable {

    /// How much intimate-health material to surface, if any.
    enum Intimacy: Equatable {
        /// Romantic partners: contraception, comfort, desire changes across the cycle.
        case full
        /// Everyone else. Never shown for a parent/child or family relationship —
        /// this is the case that must not regress.
        case none
    }

    let role: CycleSupportRole
    /// The *supporter's* biological sex, which changes framing rather than content:
    /// a man supporting a partner is often learning this for the first time, where a
    /// woman supporting a partner usually has lived experience to build on.
    let supporterSex: BiologicalSex?
    let intimacy: Intimacy

    init(role: CycleSupportRole, supporterSex: BiologicalSex?) {
        self.role = role
        self.supporterSex = supporterSex
        // Intimate content is gated on the *relationship*, never on sex or on the
        // digest. A parent supporting a child must never reach this material.
        self.intimacy = (role == .romantic) ? .full : .none
    }

    /// Section headings the supporter surface should render, in order.
    var sections: [Section] {
        var out: [Section] = [.todayAtAGlance, .howToShowUp]
        if intimacy == .full { out.append(.intimacyAndComfort) }
        if role == .child { out.append(.parentPlaybook) }
        out.append(.whatYouCannotSee)
        return out
    }

    enum Section: String, Equatable {
        case todayAtAGlance
        case howToShowUp
        case intimacyAndComfort
        case parentPlaybook
        /// Always last, always present. Shows the supporter exactly what is withheld,
        /// so the privacy promise is legible to *both* sides rather than being an
        /// invisible policy the owner has to take on trust.
        case whatYouCannotSee

        var title: String {
            switch self {
            case .todayAtAGlance:     return "Today"
            case .howToShowUp:        return "How to show up"
            case .intimacyAndComfort: return "Intimacy & comfort"
            case .parentPlaybook:     return "The soft playbook"
            case .whatYouCannotSee:   return "What you can't see"
            }
        }
    }

    /// Rendered under `.whatYouCannotSee`. Stated plainly and in the negative,
    /// because a supporter who knows the limits is less likely to ask the person
    /// they support to fill them in.
    var withheldExplanation: String {
        """
        You see a general picture, not a diary. Fertility and ovulation timing, \
        whether they're trying to conceive, symptoms, flow, and anything they log \
        day to day stay with them. They can stop sharing at any time, and you'll \
        simply stop seeing updates.
        """
    }
}

// ============================================================
// MARK: - Invite
// ============================================================

/// An invitation to receive someone's digest, carried by a CloudKit share.
///
/// There is no bearer token and no Forge-side pairing service. The invite *is* a
/// `CKShare` URL: CloudKit owns acceptance, participant identity and revocation, so
/// reproductive data never reaches Forge infrastructure and there is nothing on our
/// side to breach, subpoena or retain.
///
/// What travels in the message is the share URL and a display name. The digest does
/// not: an iMessage thread is backed up, screenshotted and read on lock screens, so
/// nothing in the bubble should be sensitive if it leaks.
struct PartnerCycleInvite: Codable, Equatable {
    /// The `CKShare.url`. Meaningless without an Apple ID CloudKit accepts.
    let shareURL: URL
    let role: CycleSupportRole
    /// Display name the sender chose for themselves, so the recipient sees who is
    /// asking. Not derived from the account, so it can be a first name only.
    let fromDisplayName: String
    let createdAt: Date

    init(shareURL: URL,
         role: CycleSupportRole,
         fromDisplayName: String,
         createdAt: Date = Date()) {
        self.shareURL = shareURL
        self.role = role
        self.fromDisplayName = fromDisplayName
        self.createdAt = createdAt
    }

    /// Fallback text for the plain-SMS path, when the recipient has no iMessage or
    /// no Forge app. Deliberately vague about *what* is being shared — the sender
    /// should decide who knows they track a cycle, not a lock-screen preview.
    var fallbackMessageBody: String {
        "\(fromDisplayName) wants to share their Forge support updates with you. \(shareURL.absoluteString)"
    }

    /// Bubble caption for the Messages extension. Same discretion rule.
    var bubbleCaption: String { "Support updates from \(fromDisplayName)" }

    /// Live state of an invite already sitting in a thread. The Messages extension
    /// updates the bubble in place through `MSSession`, so a revoked invite stops
    /// reading as a live offer in the transcript.
    enum Status: String, Codable {
        case pending, accepted, revoked, expired

        var caption: String {
            switch self {
            case .pending:  return "Waiting to be accepted"
            case .accepted: return "Sharing support updates"
            case .revoked:  return "Sharing stopped"
            case .expired:  return "Invitation expired"
            }
        }
    }

    /// How long an unaccepted invite stays live.
    ///
    /// It lapses on purpose. An invite that never expires is a standing offer
    /// sitting in a thread indefinitely, redeemable months later by whoever has
    /// the device — including someone the sender is no longer close to. Two
    /// weeks is long enough to survive a slow reply and short enough that a
    /// forgotten invite closes itself.
    static let validity: TimeInterval = 60 * 60 * 24 * 14

    var expiresAt: Date { createdAt.addingTimeInterval(Self.validity) }

    /// Flatten to the wire type the Messages extension understands.
    ///
    /// The extension has no access to `CycleSupportRole`, so the label is
    /// rendered here — this is the boundary where app types stop.
    var messagePayload: PartnerInvitePayload {
        PartnerInvitePayload(shareURL: shareURL,
                             fromDisplayName: fromDisplayName,
                             roleRaw: role.rawValue,
                             roleLabel: role.shortLabel,
                             status: .pending,
                             createdAt: createdAt,
                             expiresAt: expiresAt)
    }
}
