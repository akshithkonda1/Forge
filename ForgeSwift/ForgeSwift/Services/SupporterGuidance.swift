import Foundation

// ============================================================
// MARK: - Guidance for someone who was shared with
// ============================================================

/// Turns a received `PartnerCycleDigest` into what to actually do today.
///
/// **A pure function of the digest and the lens, and that is the point.**
/// `PartnerSupportCoach` writes far better guidance, but it reads a whole
/// `MenstrualCycleSnapshot` — fertile score, ovulation day, symptoms, cycle goal.
/// Running it on the owner's device and shipping its sentences would move the
/// disclosure from the data into the prose: "great week to try" is a fertility
/// disclosure however it is worded.
///
/// So guidance is generated *here*, on the supporter's device, from the three
/// coarse fields they were given. Nothing it can say exceeds what they already
/// hold, because there is no other input. The digest is provably the whole
/// channel rather than merely the intended one.
///
/// That costs precision. A supporter gets "lower energy — take something off
/// their plate" instead of a symptom-aware line, and that is the correct trade:
/// the person being supported did not agree to share symptoms.
enum SupporterGuidance {

    struct Guidance: Equatable {
        let headline: String
        let doThis: [String]
        let notThis: [String]
        /// Romantic lens only. Empty for every other relationship.
        let intimacy: [String]
        /// Parent lens only.
        let parentNotes: [String]
    }

    static func make(digest: PartnerCycleDigest, lens: PartnerSupportLens) -> Guidance {
        Guidance(
            headline: digest.supportHeadline,
            doThis: doThis(digest, lens),
            notThis: notThis(digest, lens),
            intimacy: lens.intimacy == .full ? intimacy(digest) : [],
            parentNotes: lens.role == .child ? parentNotes(digest) : []
        )
    }

    // ------------------------------------------------------------

    private static func doThis(_ digest: PartnerCycleDigest,
                               _ lens: PartnerSupportLens) -> [String] {
        var moves: [String] = []

        switch digest.phase {
        case .bleeding:
            moves.append("Take one thing off their plate without being asked.")
            moves.append("Warmth helps — a hot water bottle, a blanket, a bath.")
            moves.append(lens.role == .child
                         ? "Keep supplies stocked and visible so nobody has to ask."
                         : "Keep the easy food and the painkillers where they can find them.")
        case .rebuilding:
            moves.append("Good stretch for plans that take a bit of energy.")
            moves.append("Say yes to the thing they've been wanting to do.")
        case .winding:
            moves.append("Lower the stakes on the week — fewer commitments, earlier nights.")
            moves.append("Ask what would help rather than guessing.")
        case .unknown:
            moves.append("No recent updates. Just ask how they're doing.")
        }

        switch digest.energy {
        case .low:
            moves.append("Match their pace instead of pulling them along.")
        case .high:
            moves.append("They may want more going on than usual — follow their lead.")
        case .steady:
            break
        }

        if digest.extraThoughtfulnessHelps {
            moves.append("Small and specific beats big and vague. A cup of tea lands.")
        }
        return moves
    }

    private static func notThis(_ digest: PartnerCycleDigest,
                                _ lens: PartnerSupportLens) -> [String] {
        var avoid: [String] = [
            // First and always. The single most common way this goes wrong is a
            // supporter using the app as ammunition in an argument.
            "Don't explain their mood to them using this app."
        ]

        switch digest.phase {
        case .bleeding:
            avoid.append("Don't schedule anything that can't be cancelled.")
            if lens.role == .child {
                avoid.append("No commentary on their body, ever — not even kind commentary.")
            }
        case .winding:
            avoid.append("Don't save up a hard conversation for this week.")
        case .rebuilding, .unknown:
            break
        }

        if digest.energy == .low {
            avoid.append("Don't read low energy as disinterest in you.")
        }
        return avoid
    }

    /// Romantic lens only — gated on the relationship in `PartnerSupportLens`,
    /// never on the digest. Deliberately about comfort and consent rather than
    /// timing: the digest folds fertile and ovulatory days into `.rebuilding`
    /// precisely so this section cannot become a conception calendar.
    private static func intimacy(_ digest: PartnerCycleDigest) -> [String] {
        switch digest.phase {
        case .bleeding:
            return ["Desire varies a lot here, in both directions. Ask, don't assume.",
                    "Closeness without sex is still closeness. Offer it plainly.",
                    "If they're in pain, pressure is the opposite of helpful."]
        case .rebuilding:
            return ["Often an easier stretch for feeling connected. Still ask.",
                    "Nothing here tells you whether they want to — only they do."]
        case .winding:
            return ["Comfort and familiarity tend to land better than novelty.",
                    "Tenderness without an agenda is worth more than you'd think."]
        case .unknown:
            return ["No recent updates. The only reliable signal is asking."]
        }
    }

    /// Parent lens. Written for the case the app is most likely to get wrong: a
    /// father supporting a daughter, wanting to help and unsure how without
    /// making it worse.
    private static func parentNotes(_ digest: PartnerCycleDigest) -> [String] {
        var notes = [
            "Practical beats emotional. Stocked cupboard, no questions, no fuss.",
            "Privacy is the gift. Don't mention it to relatives, siblings, anyone."
        ]
        if digest.phase == .bleeding {
            notes.append("A ride home, a lighter evening, a favourite meal. That's it.")
        }
        if digest.extraThoughtfulnessHelps {
            notes.append("If they want to talk they'll start. Leave the door open, don't walk through it.")
        }
        return notes
    }

    // ------------------------------------------------------------

    /// The headline the *owner's* device writes into the digest.
    ///
    /// Also derived only from digest-visible state, for the same reason: it is
    /// generated before the digest exists, so it is the one line that could
    /// smuggle something past the redaction if it were written from the full
    /// snapshot.
    static func headline(phase: PartnerCycleDigest.SupportPhase,
                         energy: PartnerCycleDigest.EnergyBand,
                         thoughtfulnessHelps: Bool) -> String {
        switch (phase, energy) {
        case (.bleeding, _):
            return "On their period — comfort and a lighter load help most."
        case (.winding, .low):
            return "Winding down with less in the tank. Keep the week gentle."
        case (.winding, _):
            return "Winding down. Fewer commitments land better than more."
        case (.rebuilding, .high):
            return "Energy's building — a good stretch for plans."
        case (.rebuilding, _):
            return "Steadier stretch. Follow their lead on how much to take on."
        case (.unknown, _):
            return thoughtfulnessHelps
                ? "No recent updates — checking in never hurts."
                : "No recent updates to share right now."
        }
    }
}
