import Foundation

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

    // ------------------------------------------------------------
    // MARK: The one crossing point
    // ------------------------------------------------------------

    /// Build a digest from a full snapshot. **The only place snapshot data becomes
    /// partner-visible.** Every field is either coarsened or dropped; nothing is
    /// copied across verbatim except the date stamp.
    init(redacting snapshot: MenstrualCycleSnapshot, headline: String) {
        // Fertile and ovulatory days are folded into `.rebuilding` so the digest
        // cannot be used to infer conception timing.
        switch snapshot.phase {
        case .menstruation:
            phase = .bleeding
        case .follicular, .fertileWindow, .ovulation:
            phase = .rebuilding
        case .luteal:
            phase = .winding
        case .unknown:
            phase = .unknown
        }

        switch phase {
        case .bleeding:   energy = snapshot.recommendRecoveryBias ? .low : .steady
        case .rebuilding: energy = .high
        case .winding:    energy = snapshot.recommendRecoveryBias ? .low : .steady
        case .unknown:    energy = .steady
        }

        // Bucketed to a coarse number of days. The exact predicted date is withheld
        // even though it is known, because a date invites counting and a rough
        // distance is all a supporter needs.
        daysUntilNextPeriodApprox = {
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

        extraThoughtfulnessHelps = (phase == .bleeding)
            || (phase == .winding && snapshot.recommendRecoveryBias)

        supportHeadline = headline
        asOfDayKey = snapshot.asOfDayKey
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

/// A time-boxed invitation to receive someone's digest.
///
/// Sent over iMessage as a link. The token is meaningless on its own — it is
/// exchanged for a share, and the digest itself never travels inside the message.
/// That matters: an iMessage thread is backed up, screenshotted, and read on lock
/// screens, so nothing in the link should be sensitive if it leaks.
struct PartnerCycleInvite: Codable, Equatable {
    let token: String
    let role: CycleSupportRole
    /// Display name the sender chose for themselves, so the recipient sees who is
    /// asking. Not derived from the account, so it can be a first name only.
    let fromDisplayName: String
    let createdAt: Date
    let expiresAt: Date

    /// Short by design. A sharing invitation for reproductive data should not sit
    /// live in a message thread for weeks.
    static let defaultLifetime: TimeInterval = 60 * 60 * 24 * 3

    var isExpired: Bool { Date() >= expiresAt }

    init(token: String,
         role: CycleSupportRole,
         fromDisplayName: String,
         createdAt: Date = Date(),
         lifetime: TimeInterval = PartnerCycleInvite.defaultLifetime) {
        self.token = token
        self.role = role
        self.fromDisplayName = fromDisplayName
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(lifetime)
    }

    /// The text that goes in the iMessage. Deliberately vague about *what* is being
    /// shared — the recipient may read this on a lock screen in company, and the
    /// sender should be the one to decide who knows they track a cycle.
    func messageBody(link: URL) -> String {
        "\(fromDisplayName) wants to share their Forge support updates with you. \(link.absoluteString)"
    }
}
