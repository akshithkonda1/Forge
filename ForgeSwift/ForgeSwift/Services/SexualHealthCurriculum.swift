import Foundation

/// Biologically-grounded sexual health and contraception content.
/// Content is based on reproductive physiology, not anecdote.
/// ARIA uses this as the factual substrate for personalised coaching.
enum SexualHealthCurriculum {

    static let medicalDisclaimer = "I'm an AI health coach, not a medical professional. This is educational — not a birth-control method, not an FDA-regulated contraceptive, not a diagnosis. Talk to a clinician you trust for personal medical advice."

    static let intimacyDisclaimer =
        "Consent, comfort, and stop-means-stop come first. Tips are optional ideas, not a script and not a medical protocol."

    // MARK: - Contraception Methods

    struct ContraceptionMethod {
        let name: String
        let mechanism: String
        let typicalUseEffectiveness: String
        let perfectUseEffectiveness: String
        let suitableFor: String
        let notSuitableFor: String
        let cycleImpact: String
    }

    static let contraceptionMethods: [ContraceptionMethod] = [
        ContraceptionMethod(
            name: "Combined Oral Contraceptive Pill",
            mechanism: "Synthetic oestrogen and progestogen suppress the LH surge that triggers ovulation. Also thickens cervical mucus to impede sperm and thins the endometrium.",
            typicalUseEffectiveness: "91% (9 in 100 users become pregnant per year)",
            perfectUseEffectiveness: "99.7%",
            suitableFor: "Those wanting a reversible hormonal method with cycle regulation benefits",
            notSuitableFor: "Smokers over 35, those with migraine with aura, history of clotting disorders",
            cycleImpact: "Suppresses natural ovulation — cycle predictions based on LH/BBT will not reflect natural fertility"
        ),
        ContraceptionMethod(
            name: "Progestogen-Only Pill (Mini-Pill)",
            mechanism: "Progestogen thickens cervical mucus and may suppress ovulation (varies by formulation — desogestrel-based pills suppress in ~97% of cycles).",
            typicalUseEffectiveness: "91%",
            perfectUseEffectiveness: "99.7%",
            suitableFor: "Those who cannot use oestrogen; breastfeeding individuals",
            notSuitableFor: "Those who struggle with consistent daily timing (must be taken within a 3-hour window for most formulations)",
            cycleImpact: "Variable — some users retain ovulatory cycles; natural cycle tracking unreliable"
        ),
        ContraceptionMethod(
            name: "Hormonal IUD (e.g. Mirena)",
            mechanism: "Releases low-dose levonorgestrel locally, thickening cervical mucus and thinning the endometrium. May suppress ovulation in some cycles but primarily works locally.",
            typicalUseEffectiveness: "99.8%",
            perfectUseEffectiveness: "99.8%",
            suitableFor: "Those wanting long-term (3–7 year), low-maintenance contraception",
            notSuitableFor: "Unexplained vaginal bleeding, certain uterine abnormalities",
            cycleImpact: "Often reduces or eliminates periods; natural cycle signals unreliable"
        ),
        ContraceptionMethod(
            name: "Copper IUD (non-hormonal)",
            mechanism: "Copper ions are toxic to sperm (impair motility and acrosomal reaction). Also prevents implantation if fertilisation occurs.",
            typicalUseEffectiveness: "99.2%",
            perfectUseEffectiveness: "99.4%",
            suitableFor: "Those wanting hormone-free long-term contraception or emergency contraception",
            notSuitableFor: "Those with heavy periods (can worsen bleeding), copper allergy",
            cycleImpact: "Does not suppress ovulation — natural cycle tracking remains valid; may cause heavier, longer periods"
        ),
        ContraceptionMethod(
            name: "Fertility Awareness Methods (FAM)",
            mechanism: "Identifying fertile days by tracking basal body temperature (BBT rises ~0.2–0.5°C after ovulation due to progesterone), cervical mucus changes (becomes egg-white/watery at peak fertility), and cycle length history.",
            typicalUseEffectiveness: "76–88% (varies significantly by method and consistency)",
            perfectUseEffectiveness: "95–99.6% (symptothermal method with perfect use)",
            suitableFor: "Those with regular cycles (≤2 days variability), consistent daily logging habits, and a thorough understanding of the method",
            notSuitableFor: "Highly irregular cycles, perimenopause, recent hormonal contraception use, postpartum",
            cycleImpact: "Requires consistent daily tracking with a clinician-guided method. Forge does not sell or clear fertility awareness as contraception."
        ),
        ContraceptionMethod(
            name: "Male Condom",
            mechanism: "Physical barrier preventing sperm from reaching the cervix. Also the only method providing STI protection.",
            typicalUseEffectiveness: "87%",
            perfectUseEffectiveness: "98%",
            suitableFor: "Everyone; essential for STI protection",
            notSuitableFor: "Latex allergy (use polyurethane/polyisoprene alternatives)",
            cycleImpact: "No impact on cycle or hormones"
        ),
        ContraceptionMethod(
            name: "Emergency Contraception (Levonorgestrel, e.g. Plan B)",
            mechanism: "High-dose progestogen delays or inhibits ovulation. Most effective when taken before the LH surge. Does not end an established pregnancy.",
            typicalUseEffectiveness: "Up to 89% if taken within 72 hours; effectiveness decreases with time",
            perfectUseEffectiveness: "95% if taken within 24 hours",
            suitableFor: "Use after unprotected sex or contraception failure",
            notSuitableFor: "Not a regular contraception method; reduced effectiveness in users over ~70–75kg (ulipristal acetate preferred)",
            cycleImpact: "Disrupts the natural cycle — next period may be early or late by up to a week"
        ),
    ]

    // MARK: - Phase-Aware Wellness

    static func phaseWellness(for phase: MenstrualPhase) -> String {
        switch phase {
        case .menstruation:
            return "Oestrogen and progesterone are at their lowest, which can lower mood and energy. Prostaglandins (hormone-like compounds) cause uterine contractions — the source of cramps. Iron-rich foods can help offset blood loss. Rest and lighter movement are physiologically appropriate."
        case .follicular:
            return "Rising oestrogen (driven by FSH stimulating follicle development) increases energy, sociability, and focus. Oestrogen enhances serotonin and dopamine sensitivity — many people feel sharper and more motivated in this phase."
        case .fertileWindow:
            return "Oestrogen peaks just before ovulation, often producing peak energy and libido. Cervical mucus becomes clear and stretchy (egg-white consistency) to facilitate sperm transport. This is physiologically the most fertile period of the cycle."
        case .ovulation:
            return "A sharp LH surge (~24–36 hours before ovulation) triggers the dominant follicle to release an egg. Core body temperature remains low until ovulation occurs, then rises ~0.2–0.5°C and stays elevated. Libido often peaks around ovulation."
        case .luteal:
            return "The ruptured follicle becomes the corpus luteum, producing progesterone. Progesterone raises basal body temperature, supports potential implantation, and can cause bloating, breast tenderness, and PMS symptoms. If fertilisation does not occur, progesterone drops, triggering menstruation."
        case .unknown:
            return "Log more cycle data to unlock phase-specific insights."
        }
    }

    // MARK: - TTC Guidance

    static func ttcGuidance(snapshot: MenstrualCycleSnapshot) -> String {
        let accuracyNote: String
        switch snapshot.accuracyGrade {
        case "market_leading", "excellent":
            accuracyNote = "Your prediction accuracy is excellent — fertile window timing is reliable."
        case "solid":
            accuracyNote = "Your predictions are solid. Keep confirming period starts to sharpen the window."
        default:
            accuracyNote = "More cycle data will improve fertile window accuracy. Log consistently."
        }

        let ovulationNote: String
        switch snapshot.ovulationMethod {
        case "lh_surge":
            ovulationNote = "LH tests are your most reliable ovulation signal — the egg releases ~24–36 hours after the surge."
        case "bbt_shift":
            ovulationNote = "BBT shift confirms ovulation occurred but is retrospective — pair with LH tests to predict in advance."
        case "peak_mucus":
            ovulationNote = "Peak egg-white mucus is a good pre-ovulation signal. Adding LH tests would further sharpen timing."
        default:
            ovulationNote = "Adding LH tests or BBT tracking would significantly improve your ovulation detection."
        }

        return "\(accuracyNote) \(ovulationNote) If you are trying to conceive, many people time sex across the days leading up to a confirmed LH surge. Forge is a tracker and a coach, not a fertility clinic. \(medicalDisclaimer)"
    }

    // MARK: - FAM Reliability for User's Cycle

    /// `dataQuality` is the raw string from `MenstrualCycleSnapshot.dataQuality`
    static func famReliability(dataQuality: String, cycleLengthMAD: Double) -> String {
        let regularity: String
        if cycleLengthMAD <= 1.5 {
            regularity = "Your cycles are very regular (variability ≤1.5 days)."
        } else if cycleLengthMAD <= 3.0 {
            regularity = "Your cycles have moderate variability (±\(String(format: "%.1f", cycleLengthMAD)) days)."
        } else {
            regularity = "Your cycle variability is high (±\(String(format: "%.1f", cycleLengthMAD)) days)."
        }

        let dataNote: String
        switch dataQuality {
        case "highSignal", "solid":
            dataNote = "Your tracking data quality is strong, which supports more accurate fertile window identification."
        case "mixed", "noisy":
            dataNote = "Improving log consistency (daily flow, BBT, or LH tests) would strengthen timing estimates."
        default:
            dataNote = "More logged cycles are needed before timing estimates get personal."
        }

        return "\(regularity) \(dataNote) Forge does not offer fertility awareness as contraception. If pregnancy timing matters, use a clinician-guided method. \(medicalDisclaimer)"
    }

    // MARK: - Intimacy, safe sex, positions, partner help

    static func safeSexBasics() -> String {
        """
        Healthy sex is consent plus comfort plus protection you actually chose.
        • Ask, then listen. Enthusiastic yes. Stop is always allowed, including mid-way.
        • Condoms (and non-latex options) are the only common method that also cuts STI risk. Lube — water-based with latex — prevents micro-tears.
        • Dental dams or a condom cut open help for oral sex if STI risk is on the table.
        • Protection used is a conversation, not a test. Forge can log sexual activity to Apple Health if you want; it never has to.
        • Aftercare counts: water, a towel, a check-in. Sharp or new pain is a reason to pause and, if it stays, see a clinician.
        \(intimacyDisclaimer)
        """
    }

    static func periodSex(phase: MenstrualPhase) -> String {
        let core = """
        Sex during a period is allowed if everyone wants it. Blood is not an emergency. Mess is a towel and dark sheets, not a character flaw.
        • Extra lube — menstrual blood is not the same as arousal fluid.
        • Positions that don't fold the abdomen hard (side-lying, spooning, you on top so you control depth) often hurt less if cramps are running.
        • A menstrual disc can work for some people who want less mess; tampons and cups usually come out first.
        • Orgasm can ease cramps for some and worsen them for others. Believe today's body.
        • Condoms still matter for STI risk. A period is not birth control.
        """
        if phase == .menstruation {
            return core + " You are bleeding now — optional, never owed. \(intimacyDisclaimer)"
        }
        return core + " \(intimacyDisclaimer)"
    }

    static func positionsAndIdeas(for phase: MenstrualPhase) -> String {
        let menu = """
        A short menu — pick what sounds kind, skip the rest:
        • Side-lying / spooning — least athletic, easy to pause, good if the abdomen is tender.
        • You on top — you set depth and tempo. Stop is one shift away.
        • Modified missionary — pillow under hips or a knee, not a fold in half.
        • Seated / lap sit — face-to-face, hands free for check-ins.
        • From behind with a shallower angle — only if it does not punch the cervix; say so early.
        • Hands, mouth, a toy, or just kissing — sex is not a penetration requirement.
        Start slower than you think. Lube is a tool, not a mood killer. Switch if something pinches.
        """
        switch phase {
        case .menstruation:
            return """
            While bleeding: side-lying, spooning, and you-on-top usually hurt less than anything that needs a long plank. A towel, dark sheets, extra lube. Skip deep flexion if cramps are loud. \(menu)
            \(intimacyDisclaimer)
            """
        case .follicular, .fertileWindow, .ovulation:
            return """
            Energy and desire often run higher here. If you both want novelty: trade who leads, change the angle, slow the build. Warm up joints — laxity can sneak up on deep flexion. \(menu)
            \(intimacyDisclaimer)
            """
        case .luteal:
            return """
            Later-cycle: more lube, less athletic, more time. Spooning, a pillow, or a lap sit can feel kinder than core-endurance positions. Mood can swing — check in twice. \(menu)
            \(intimacyDisclaimer)
            """
        case .unknown:
            return """
            Not enough cycle signal yet. Default to a position you can leave easily, a pause word, and the menu below. \(menu)
            \(intimacyDisclaimer)
            """
        }
    }

    /// Optional experiments — never a chore list.
    static func thingsYouCanTry(for phase: MenstrualPhase) -> String {
        let shared = """
        Things you can try (optional, reversible, no score):
        • Agree a pause word in daylight. Use it once so it is not theoretical.
        • Make lube the default, not the apology.
        • Trade who starts. One night they lead; one night you do.
        • Ten minutes of only kissing / only hands before anyone escalates.
        • Change the room: lights lower, a towel ready, phone in another room.
        • Aftercare as part of it: water, a shower, “was that good for you?”
        If it feels like homework, it is too much. Drop it.
        """
        if phase == .menstruation {
            return """
            Period-week extras: a menstrual disc if you want less mess; heat on the back while you stay close without penetration; permission for a quiet night to still be intimacy. \(shared)
            \(intimacyDisclaimer)
            """
        }
        return "\(shared)\n\(intimacyDisclaimer)"
    }

    /// Crossing the friend/help border without turning into a clinician or a creep.
    static func partnerAndYouTips(roleHint: String?) -> String {
        let who = (roleHint ?? "").lowercased()
        if who.contains("parent") || who.contains("mom") || who.contains("dad") {
            return """
            Parent lane: supplies, heat, flexibility on plans, and dignity. No body commentary, no sex tips, no “are you on your period?” quizzes. Help is logistics. \(intimacyDisclaimer)
            """
        }
        if who.contains("relative") || who.contains("sister") || who.contains("brother") || who.contains("friend") {
            return """
            Friend / relative lane — this is the friend→help border:
            Help looks like: show up, heat, food, covering a shift, “I’ve got the dishes.”
            Help does not look like: asking for a chart, diagnosing PMS, or sliding into sex talk they did not start.
            If they want to talk intimacy, they will open it. You do not. \(intimacyDisclaimer)
            """
        }
        return """
        The friend→help border (and the help→intimacy border):

        For you:
        • You do not owe anyone sex, a mood, or an explanation of your cycle.
        • You can want closeness and still want a quiet night.
        • “Not tonight” is a complete sentence. So is “yes, and slower.”
        • Tell them what help looks like *today* — heat, space, errands, or invited closeness.

        For a partner:
        • Friend-level help is practical, not investigative. Heating pad out. Do not interrogate. Ask “comfort, space, or distraction?” once.
        • Help is not a quiz about their body. You are not their clinician.
        • Intimate help (massage, sex, closeness) is invited, never assumed from a phase label.
        • If you want to try something new — positions, period sex, a slower night — ask in daylight, not as a surprise in bed.
        • After they say what they need, do that thing. Do not upgrade it into a performance.

        Crossing into intimacy: they ask, or they reach first, or you ask and wait for a real yes. A cycle phase is not a yes. \(intimacyDisclaimer)
        """
    }

    static func difficultyConceiving() -> String {
        """
        Not conceiving yet is common and not a moral failure. Many clinicians suggest seeking care after about 12 months of trying if you are under 35, or about 6 months if you are 35 or older — sooner if periods are missing, very painful, or you already know a relevant condition.
        Forge can show what you have been tracking. It cannot diagnose infertility, run labs, or replace a reproductive endocrinologist.
        While you wait: sex you actually want (not a calendar hostage), sleep, alcohol in check, and a clinician if pain or bleeding is alarming.
        \(medicalDisclaimer)
        """
    }
}
