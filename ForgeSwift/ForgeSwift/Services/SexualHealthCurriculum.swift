import Foundation

/// Biologically-grounded sexual health and contraception content.
/// Content is based on reproductive physiology, not anecdote.
/// ARIA uses this as the factual substrate for personalised coaching.
enum SexualHealthCurriculum {

    static let medicalDisclaimer = "I'm an AI health coach, not a medical professional. This information is educational and based on reproductive physiology — consult a doctor or qualified clinician for personal medical advice."

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
            cycleImpact: "Requires consistent daily tracking — this is the method Forge's cycle engine supports. Reliability improves with more confirmed cycles."
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

        return "\(accuracyNote) \(ovulationNote) The fertile window is typically the 5 days before ovulation plus the day of ovulation itself. \(medicalDisclaimer)"
    }

    // MARK: - FAM Reliability for User's Cycle

    /// `dataQuality` is the raw string from `MenstrualCycleSnapshot.dataQuality`
    static func famReliability(dataQuality: String, cycleLengthMAD: Double) -> String {
        let regularity: String
        if cycleLengthMAD <= 1.5 {
            regularity = "Your cycles are very regular (variability ≤1.5 days) — this is ideal for FAM."
        } else if cycleLengthMAD <= 3.0 {
            regularity = "Your cycles have moderate variability (±\(String(format: "%.1f", cycleLengthMAD)) days), which requires wider abstinence/barrier windows for FAM."
        } else {
            regularity = "Your cycle variability is high (±\(String(format: "%.1f", cycleLengthMAD)) days) — FAM carries higher pregnancy risk with irregular cycles."
        }

        let dataNote: String
        switch dataQuality {
        case "highSignal", "solid":
            dataNote = "Your tracking data quality is strong, which supports more accurate fertile window identification."
        case "mixed", "noisy":
            dataNote = "Improving log consistency (daily flow, BBT, or LH tests) would strengthen FAM reliability."
        default:
            dataNote = "More logged cycles are needed before FAM can be considered reliable for you specifically."
        }

        return "\(regularity) \(dataNote) Even with perfect use, FAM has ~0.4–4% failure rate in clinical studies. \(medicalDisclaimer)"
    }
}
