import Foundation

// MARK: - Emotional need taxonomy

/// What the user (or someone they support) seems to need emotionally right now.
/// Lifestyle coaching only — not therapy, diagnosis, or crisis intervention.
enum AriaEmotionalNeed: String, CaseIterable, Identifiable {
    case conflict
    case anxiety
    case overwhelm
    case sadness
    case loneliness
    case anger
    case guilt
    case parentingStress
    case relationshipTension
    case periodMoodSupport
    case burnout
    case validation
    case grief
    case crisis

    var id: String { rawValue }

    var label: String {
        switch self {
        case .conflict: return "Conflict / repair"
        case .anxiety: return "Anxiety / worry"
        case .overwhelm: return "Overwhelm"
        case .sadness: return "Sadness / low mood"
        case .loneliness: return "Loneliness"
        case .anger: return "Anger / frustration"
        case .guilt: return "Guilt / shame"
        case .parentingStress: return "Parenting stress"
        case .relationshipTension: return "Relationship tension"
        case .periodMoodSupport: return "Period / cycle mood support"
        case .burnout: return "Burnout"
        case .validation: return "Need to be heard"
        case .grief: return "Grief / loss"
        case .crisis: return "Crisis signals"
        }
    }
}

struct AriaEmotionalReading: Equatable {
    var primary: AriaEmotionalNeed
    var secondary: AriaEmotionalNeed?
    var score: Double
    var matchedKeywords: [String]
    /// true when message is about supporting someone else emotionally
    var isAboutOther: Bool
    var aboutRole: CycleSupportRole?
    var aboutName: String?
}

// MARK: - Coach

/// Keyword + context emotional support for the user and for family/partner support roles.
enum AriaEmotionalSupportCoach {

    static let disclaimer = """
    This is human lifestyle support — listening, language, and practical steadiness. \
    It is not therapy, not a diagnosis, and not a crisis service. \
    If you or someone else is in immediate danger, contact local emergency services.
    """

    static let crisisResources = """
    If you might hurt yourself or someone else, stop here and get real-time help:
    • Emergency services (local)
    • US: 988 Suicide & Crisis Lifeline (call/text 988)
    • International: https://www.iasp.info/suicidalthoughts/

    I'm glad you said something. You deserve support from people who can stay with you in person.
    """

    // MARK: Detection

    static func detect(in text: String, context: TrainerContext? = nil) -> AriaEmotionalReading? {
        let lower = text.lowercased()
        if isCrisis(lower) {
            return AriaEmotionalReading(
                primary: .crisis,
                secondary: nil,
                score: 1,
                matchedKeywords: crisisKeywords.filter { lower.contains($0) },
                isAboutOther: AriaRelationalCoach.mentionsSupportContext(lower),
                aboutRole: AriaRelationalCoach.detectSupportMention(in: text)?.role,
                aboutName: AriaRelationalCoach.detectSupportMention(in: text)?.name
            )
        }

        var scores: [AriaEmotionalNeed: Double] = [:]
        var matched: [AriaEmotionalNeed: [String]] = [:]

        func hit(_ need: AriaEmotionalNeed, _ words: [String], weight: Double = 1) {
            for w in words where lower.contains(w) {
                scores[need, default: 0] += weight
                matched[need, default: []].append(w)
            }
        }

        hit(.conflict, [
            "fight", "fought", "argument", "arguing", "yelling", "yelled", "screaming",
            "we broke up", "break up", "breaking up", "silent treatment", "not talking",
            "mad at me", "she's mad", "he's mad", "they hate me", "blew up",
        ], weight: 1.2)

        hit(.anxiety, [
            "anxious", "anxiety", "worried", "worrying", "panic", "panicking", "spiraling",
            "can't stop thinking", "overthinking", "on edge", "nervous", "scared",
            "what if", "catastroph", "heart racing",
        ], weight: 1.15)

        hit(.overwhelm, [
            "overwhelmed", "too much", "can't handle", "drowning", "maxed out",
            "everything at once", "falling behind", "no bandwidth", "stretched thin",
            "can't keep up", "swamped",
        ], weight: 1.1)

        hit(.sadness, [
            "sad", "crying", "cried", "tears", "down bad", "depressed", "hopeless",
            "empty", "numb", "don't care anymore", "feeling low", "blue today",
            "heartbroken", "heart broken",
        ], weight: 1.15)

        hit(.loneliness, [
            "lonely", "alone", "no one gets", "isolated", "nobody to talk",
            "left out", "abandoned", "missing her", "missing him",
        ])

        hit(.anger, [
            "furious", "rage", "pissed", "angry", "hate this", "so frustrated",
            "irritated", "losing it", "snap at", "snapped",
        ], weight: 1.05)

        hit(.guilt, [
            "guilty", "guilt", "ashamed", "shame", "i messed up", "i failed",
            "bad parent", "bad dad", "bad husband", "bad boyfriend", "i should have",
            "it's my fault", "i'm the problem",
        ], weight: 1.1)

        hit(.parentingStress, [
            "my daughter", "my kid", "my child", "my teen", "as a dad", "as a father",
            "as a parent", "parenting", "she won't listen", "attitude", "teen drama",
            "school meltdown", "bedtime battle", "i don't know how to parent",
        ], weight: 1.2)

        hit(.relationshipTension, [
            "distant", "growing apart", "don't feel close", "no spark", "walking on eggshells",
            "relationship is", "marriage is", "we never", "she doesn't", "he doesn't",
            "not connecting", "disconnected", "resent",
        ], weight: 1.1)

        hit(.periodMoodSupport, [
            "pms", "pmdd", "hormonal", "period mood", "on her period", "period rage",
            "cramps and mood", "cycle mood", "she's emotional", "period day",
        ], weight: 1.25)

        hit(.burnout, [
            "burned out", "burnt out", "burnout", "running on empty", "checked out",
            "nothing left", "can't recover", "wired and tired",
        ], weight: 1.1)

        hit(.validation, [
            "nobody understands", "feel crazy", "am i crazy", "validate", "just need to vent",
            "listen", "hear me out", "need to talk", "can i vent", "tell me i'm not",
        ], weight: 1.05)

        hit(.grief, [
            "grief", "grieving", "passed away", "died", "funeral", "loss of",
            "miss them", "in mourning",
        ], weight: 1.3)

        // Soft emotional support asks without a strong need word
        if lower.contains("emotional support") || lower.contains("need support")
            || lower.contains("feeling off") || lower.contains("rough day")
            || lower.contains("hard day") || lower.contains("struggling") {
            scores[.validation, default: 0] += 0.8
            matched[.validation, default: []].append("support ask")
        }

        // Context boosts from living cycle / readiness
        if let context {
            if let partner = context.partnerCycleSnapshot, partner.trackingEnabled {
                if partner.phase == .menstruation || partner.phase == .luteal {
                    scores[.periodMoodSupport, default: 0] += 0.45
                    if partner.recommendRecoveryBias {
                        scores[.periodMoodSupport, default: 0] += 0.2
                    }
                }
                if context.partnerCycleSettings?.resolvedRole == .child {
                    scores[.parentingStress, default: 0] += 0.25
                } else if context.partnerCycleSettings?.resolvedRole == .romantic {
                    scores[.relationshipTension, default: 0] += 0.15
                }
            }
            if context.readiness.overall < 50 {
                scores[.overwhelm, default: 0] += 0.25
                scores[.burnout, default: 0] += 0.15
            }
            if context.isLateNight {
                scores[.anxiety, default: 0] += 0.1
                scores[.sadness, default: 0] += 0.1
            }
        }

        guard let best = scores.max(by: { $0.value < $1.value }), best.value >= 0.9 else {
            return nil
        }

        let secondary = scores
            .filter { $0.key != best.key && $0.value >= 0.9 }
            .max(by: { $0.value < $1.value })?.key

        let mention = AriaRelationalCoach.detectSupportMention(in: text)
        let aboutOther = mention != nil
            || lower.contains("she feels") || lower.contains("she's upset")
            || lower.contains("help her") || lower.contains("calm her")
            || lower.contains("my wife is") || lower.contains("my daughter is")
            || lower.contains("girlfriend is") || lower.contains("partner is")

        return AriaEmotionalReading(
            primary: best.key,
            secondary: secondary,
            score: best.value,
            matchedKeywords: Array(Set(matched[best.key] ?? [])).prefix(6).map { $0 },
            isAboutOther: aboutOther,
            aboutRole: mention?.role ?? context?.partnerCycleSettings?.resolvedRole,
            aboutName: mention?.name ?? context?.partnerCycleSettings?.displayName
        )
    }

    static func isEmotionalSupportQuery(_ text: String, context: TrainerContext? = nil) -> Bool {
        detect(in: text, context: context) != nil
            || text.lowercased().contains("emotional support")
            || text.lowercased().contains("i need to vent")
            || text.lowercased().contains("feeling off")
    }

    private static let crisisKeywords = [
        "kill myself", "suicide", "suicidal", "end my life", "want to die",
        "self harm", "self-harm", "cut myself", "hurt myself",
        "hurt her", "hurt him", "kill her", "kill him", "homicide",
    ]

    private static func isCrisis(_ lower: String) -> Bool {
        crisisKeywords.contains { lower.contains($0) }
    }

    // MARK: Response

    static func respond(
        reading: AriaEmotionalReading,
        context: TrainerContext,
        input: String
    ) -> TrainerResponse {
        if reading.primary == .crisis {
            return TrainerResponse(
                content: """
                I hear how heavy this is. I'm not the right (or safe) place for crisis care.

                \(crisisResources)

                If you can, reach a person who can stay with you right now.
                """,
                suggestedActions: ["I want lighter support instead", "What should I train today?"],
                confidence: 0.99
            )
        }

        let you = context.userProfile.name.split(separator: " ").first.map(String.init) ?? ""
        // Instant label adaptation (wife ≠ girlfriend ≠ daughter)
        let adaptation = AriaPersonRegistry.shared.adapt(to: input)
            ?? context.partnerCycleSettings.map {
                AriaPersonRegistry.shared.adaptationForCurrentPartnerSettings($0)
            }
        let who = reading.aboutName
            ?? adaptation?.name
            ?? context.partnerCycleSettings?.displayName
            ?? (reading.isAboutOther ? adaptation?.who : nil)

        var body = composeBody(
            reading: reading,
            context: context,
            userName: you,
            otherName: who,
            input: input,
            adaptation: adaptation
        )
        if let adaptation, reading.isAboutOther || adaptation.caregiverMode || adaptation.intimacyCoachingAllowed {
            body = adaptation.voicePreamble + "\n\n" + body
                + "\n\n" + adaptation.communicationAdvice
                + "\n" + adaptation.conflictAdvice
            if !adaptation.dynamics.userTags.isEmpty {
                body += "\n\nWhat you've taught me about them: "
                    + adaptation.dynamics.userTags.prefix(4).joined(separator: " · ")
                    + "."
            }
        }
        let actions = suggestedActions(for: reading, adaptation: adaptation)

        // Persist light context tags for continuity
        Task { @MainActor in
            AriaContextStore.shared.tagEmotionalNeed(reading.primary, aboutOther: reading.isAboutOther)
        }

        return TrainerResponse(
            content: body,
            suggestedActions: actions,
            confidence: min(0.95, 0.75 + reading.score * 0.05)
        )
    }

    private static func composeBody(
        reading: AriaEmotionalReading,
        context: TrainerContext,
        userName: String,
        otherName: String?,
        input: String,
        adaptation: AriaPersonAdaptation? = nil
    ) -> String {
        var rng = AriaSeededRNG(seed: UInt64(abs(input.hashValue) &+ reading.primary.hashValue))
        let nameBit = userName.isEmpty ? "" : "\(userName) — "
        let aboutOther = reading.isAboutOther
        let role = adaptation?.role ?? reading.aboutRole ?? context.partnerCycleSettings?.resolvedRole
        let person = otherName ?? adaptation?.who ?? "them"

        let opener = rng.pick(openers(for: reading.primary, aboutOther: aboutOther, role: role, person: person))
        let validate = rng.pick(validationLines(for: reading.primary, aboutOther: aboutOther, person: person))
        let moves = practicalMoves(
            for: reading,
            context: context,
            person: person,
            role: role,
            adaptation: adaptation,
            rng: &rng
        )
        let say = scriptLine(for: reading, person: person, role: role, aboutOther: aboutOther, rng: &rng)
        let closer = rng.pick(closers(for: reading.primary, aboutOther: aboutOther))

        var cycleNote: String?
        if let snap = context.partnerCycleSnapshot,
           context.partnerCycleSettings?.enabled == true,
           aboutOther || reading.primary == .periodMoodSupport {
            if snap.phase == .menstruation || snap.phase == .luteal {
                cycleNote = role == .child
                    ? "Context: \(person) may also be in a \(snap.phase.shortLabel.lowercased()) window — physiology can turn the volume up. That doesn't erase feelings; it means extra gentleness helps."
                    : "Context: \(person)'s cycle looks \(snap.phase.shortLabel.lowercased()) right now. Hormones can amplify stress — still respect the feeling, just don't take every spike as permanent."
            }
        }

        var parts: [String] = [
            "\(nameBit)\(opener)",
            validate,
            "**What helps right now**",
        ]
        parts.append(contentsOf: moves.map { "• \($0)" })
        parts.append("**Words you can use**\n\(say)")
        if let cycleNote {
            parts.append(cycleNote)
        }
        if let secondary = reading.secondary {
            parts.append("I'm also hearing some \(secondary.label.lowercased()) in what you said — we can sit with that too.")
        }
        parts.append(closer)
        parts.append("\n_\(disclaimer)_")

        return parts.joined(separator: "\n\n")
    }

    // MARK: Phrase banks

    private static func openers(
        for need: AriaEmotionalNeed,
        aboutOther: Bool,
        role: CycleSupportRole?,
        person: String
    ) -> [String] {
        if aboutOther {
            switch role {
            case .child:
                return [
                    "Parenting gets heavy. Let's slow this down.",
                    "Okay — dad/parent mode, no judgment.",
                    "Yeah. Showing up for \(person) emotionally is real work.",
                ]
            case .romantic:
                return [
                    "Relationship stuff hits different. I'm here with you.",
                    "Alright — human first, fix-it second.",
                    "Got it. Let's care for \(person) and for you.",
                ]
            default:
                return [
                    "Supporting someone emotionally is hard. We'll keep it simple.",
                    "Okay. Steady > perfect.",
                ]
            }
        }
        switch need {
        case .anxiety: return ["That sounds loud in your head. We'll turn the volume down a notch.", "Anxiety lies with confidence — let's reality-check gently."]
        case .overwhelm: return ["Too much at once is a nervous system problem, not a character flaw.", "Okay. We don't solve everything tonight."]
        case .sadness: return ["Sadness gets space here. You don't have to perform okay.", "I'm glad you said it out loud."]
        case .conflict: return ["Fights leave residue. We'll clean what we can without rewriting history tonight.", "Alright — repair over winning."]
        case .anger: return ["Anger is information. We'll aim it, not spray it.", "I hear the heat. Let's use it cleanly."]
        case .guilt: return ["Guilt's loud after you care. We'll separate fault from growth.", "You're allowed to be a person who messes up and repairs."]
        case .burnout: return ["Empty is a signal, not laziness.", "Recovery counts as work today."]
        case .grief: return ["Grief doesn't do schedules. We can keep this soft.", "I'm sorry. Loss rearranges everything."]
        default: return ["Thanks for trusting me with this.", "I'm listening — really."]
        }
    }

    private static func validationLines(
        for need: AriaEmotionalNeed,
        aboutOther: Bool,
        person: String
    ) -> [String] {
        if aboutOther {
            return [
                "Wanting to help \(person) well already means you're not checked out.",
                "It's normal to feel unsure when someone you love is hurting.",
                "You don't have to fix their whole inner world. Presence is a lot.",
            ]
        }
        switch need {
        case .anxiety:
            return [
                "Your body is trying to protect you — even if the alarm is too sensitive today.",
                "Worry doesn't make you weak; it means something matters.",
            ]
        case .overwhelm:
            return [
                "Capacity isn't infinite. Hitting a wall is data.",
                "You're carrying a lot — of course it feels heavy.",
            ]
        case .sadness:
            return [
                "Low days don't erase your progress.",
                "Feeling this doesn't mean you're broken.",
            ]
        case .conflict:
            return [
                "Conflict with people you care about hurts more because the bond is real.",
                "Both things can be true: you care, and you're frustrated.",
            ]
        case .guilt:
            return [
                "Guilt often shows up in people who actually give a damn.",
                "Shame says you're bad. Growth says you can repair. We pick growth.",
            ]
        case .parentingStress:
            return [
                "Parenting without a script is hard — especially with a teen or a cycle day stacked on top.",
                "Good parents still feel lost sometimes.",
            ]
        case .periodMoodSupport:
            return [
                "Cycle-related mood swings are real for many people — supporting that isn't enabling, it's informed care.",
            ]
        default:
            return [
                "What you're feeling makes sense in context.",
                "You don't have to justify needing support.",
            ]
        }
    }

    private static func practicalMoves(
        for reading: AriaEmotionalReading,
        context: TrainerContext,
        person: String,
        role: CycleSupportRole?,
        adaptation: AriaPersonAdaptation? = nil,
        rng: inout AriaSeededRNG
    ) -> [String] {
        if reading.isAboutOther {
            switch reading.primary {
            case .conflict, .relationshipTension, .anger:
                return [
                    "Pause the debate for 20 minutes if voices are rising — physiology first.",
                    "Lead with one feeling + one need: \"I felt X, I need Y.\" Skip the court case.",
                    role == .child
                        ? "With \(person): shorter sentences, lower volume, no audience (siblings/relatives)."
                        : "Ask \(person) if they want solutions or just a witness for 5 minutes.",
                    "Repair later with a clean apology for your part only — no \"but you.\"",
                    adaptation?.conflictAdvice ?? "Keep the repair about impact, not character.",
                ]
            case .anxiety, .overwhelm:
                return [
                    "Help \(person) shrink the problem: one next action, not the whole mountain.",
                    "Offer a body basic: water, food, walk, or quiet room — ask which.",
                    "Don't stack questions. One at a time.",
                    role == .child
                        ? "Protect sleep and overstimulation (screens, chaos) if you can."
                        : "Sit nearby without hovering if they want company.",
                ]
            case .sadness, .loneliness, .grief:
                return [
                    "Sit with \(person) without forcing a silver lining.",
                    "Offer concrete comfort: blanket, snack, ride, cancel a plan.",
                    "Ask: \"Want company or space?\" Then honor the answer.",
                ]
            case .parentingStress, .periodMoodSupport:
                return [
                    "Assume physiology may be loud; still take feelings seriously.",
                    "Stock the easy wins: heat pack, supplies, favorite food, flexible schedule.",
                    "Skip jokes about mood. Matter-of-fact kindness ages better.",
                    "If pain or mood is extreme or scary, escalate to a clinician — you're not alone as the adult.",
                ]
            case .guilt:
                return [
                    "Name the specific behavior you regret — not your whole identity.",
                    "One repair action beats a monologue about how bad you feel.",
                ]
            default:
                return [
                    "Ask \(person) what would help in one sentence.",
                    "Do one helpful thing without a speech.",
                    "Check your own regulation: water, breath, 2-minute pause before re-entering.",
                ]
            }
        }

        // Self support
        switch reading.primary {
        case .anxiety:
            return [
                "Name 3 facts you know vs 3 fears you're predicting.",
                "Box breathe 4-4-4-4 for two minutes — physiology first.",
                "Put the worry on paper; pick one thing you can influence in 24 hours.",
                context.readiness.overall < 55
                    ? "Your readiness is low — go lighter on training and decisions today."
                    : "A short walk can discharge alarm energy without a full workout.",
            ]
        case .overwhelm:
            return [
                "List everything, then circle only the next 2 moves.",
                "Say no (or \"not today\") to one optional ask.",
                "Eat something with protein; under-fueling amplifies chaos.",
                "Phone on Do Not Disturb for 30 minutes if you can.",
            ]
        case .sadness:
            return [
                "Let the wave exist for 10 minutes without fixing it.",
                "Text one safe person a single honest line.",
                "Gentle movement or shower — not a punishment session.",
                "If this is multi-week and stuck, consider a human professional — that's strength.",
            ]
        case .conflict:
            return [
                "Don't send the paragraph while hot. Draft, wait 20 minutes.",
                "Own your 10% before you request theirs.",
                "Re-open with: impact + need, not character attacks.",
            ]
        case .anger:
            return [
                "Discharge body heat safely: walk, push-ups, cold water — not the group chat.",
                "Write the uncensored version privately, then rewrite the adult version.",
                "Ask: what boundary was crossed?",
            ]
        case .guilt:
            return [
                "Separate: what I did / what I value / what I repair.",
                "Apologize once cleanly; then change one behavior.",
                "Self-punishment isn't accountability.",
            ]
        case .burnout:
            return [
                "Cut volume: training, obligations, or both — today is maintenance.",
                "Protect a sleep block like a meeting.",
                "One joyful thing that isn't productive.",
            ]
        case .loneliness:
            return [
                "Reach out with a low-stakes invite, not a life update essay.",
                "Co-working café or call while doing chores beats waiting to feel better first.",
            ]
        case .grief:
            return [
                "No timeline. Rituals help: photo, walk, letter you don't send.",
                "Borrow structure (meals, sleep) when meaning feels gone.",
            ]
        case .validation:
            return [
                "You already did the hard part by saying it.",
                "Pick one need: vent, advice, or distraction — tell people which.",
            ]
        default:
            return [
                "Pause. Drink water. One honest sentence about what you need.",
                "Choose support: train light, talk, or rest — not all three at max.",
            ]
        }
    }

    private static func scriptLine(
        for reading: AriaEmotionalReading,
        person: String,
        role: CycleSupportRole?,
        aboutOther: Bool,
        rng: inout AriaSeededRNG
    ) -> String {
        if aboutOther {
            switch role {
            case .child:
                return rng.pick([
                    "\"I can tell today's hard. I'm not mad at you. Want quiet, a snack, or a ride?\"",
                    "\"You don't have to explain everything. I'm here. We'll figure the next hour.\"",
                    "\"I'm on your team. Tell me one thing that would help.\"",
                ])
            case .romantic:
                return rng.pick([
                    "\"I care more about us than about being right. Can we reset?\"",
                    "\"I want to understand. Do you want solutions or just me listening?\"",
                    "\"I love you. Let's take 20 and come back softer.\"",
                ])
            default:
                return "\"I'm here. What would feel supportive — company or space?\""
            }
        }
        switch reading.primary {
        case .anxiety:
            return "To yourself: \"I can handle the next small step. I don't need the whole future solved.\""
        case .overwhelm:
            return "To someone safe: \"I'm maxed. Can you help with X, or just remind me I'm not failing?\""
        case .conflict:
            return "\"When Y happened, I felt Z. I need A. Can we try that?\""
        case .guilt:
            return "\"I regret X. Here's how I'll make it right. I won't dump my shame on you.\""
        default:
            return "\"I'm having a rough one. I don't need fixing — just a little steadiness.\""
        }
    }

    private static func closers(for need: AriaEmotionalNeed, aboutOther: Bool) -> [String] {
        if aboutOther {
            return [
                "You won't do this perfectly. Consistency beats performance.",
                "Check back with me after you talk to them if you want a debrief.",
                "Protect your own calm — dysregulated helpers rarely help.",
            ]
        }
        return [
            "I'm here for the next round when you're ready.",
            "One honest step is enough for this hour.",
            "You don't have to earn rest or support.",
        ]
    }

    private static func suggestedActions(
        for reading: AriaEmotionalReading,
        adaptation: AriaPersonAdaptation? = nil
    ) -> [String] {
        if reading.primary == .crisis {
            return ["I need emergency resources again", "Talk about something lighter"]
        }
        if reading.isAboutOther {
            let role = adaptation?.role ?? reading.aboutRole
            switch role {
            case .child:
                return ["Parent script for tonight", "How do I support her period day?", "I need to calm down first", "What should I train?"]
            case .romantic:
                let wife = adaptation?.label == .wife || adaptation?.label == .spouse
                return wife
                    ? ["Repair as a spouse", "Share the load tonight", "Help me listen better", "What should I train?"]
                    : ["Repair script", "Date idea that won't stress her", "Help me listen better", "What should I train?"]
            default:
                return ["What do I say?", "How do I help without fixing?", "I need support too"]
            }
        }
        switch reading.primary {
        case .anxiety: return ["2-minute calm down", "Light recovery session", "Help me name the fear"]
        case .overwhelm: return ["Triage my day", "Say no for me", "Recovery workout"]
        case .sadness: return ["Gentle movement", "I just need to vent more", "Sleep tips"]
        case .conflict: return ["Draft a repair text", "Cool-down routine", "Train to blow off steam"]
        case .burnout: return ["Deload day plan", "Sleep priority", "Minimum viable day"]
        default: return ["Keep talking", "What should I train?", "Family support tips"]
        }
    }
}

// MARK: - Context tags

extension AriaContextStore {
    func tagEmotionalNeed(_ need: AriaEmotionalNeed, aboutOther: Bool) {
        var tags = context.lifestyleTags.filter { !$0.hasPrefix("emotion:") }
        tags.append("emotion:\(need.rawValue)")
        if aboutOther { tags.append("emotion:about_other") }
        context.lifestyleTags = Array(Set(tags)).sorted()
        context.recentPatterns = context.recentPatterns.filter { !$0.hasPrefix("emotion:") }
        context.recentPatterns.append("emotion:\(need.rawValue)")
        if context.recentPatterns.count > 12 {
            context.recentPatterns = Array(context.recentPatterns.suffix(12))
        }
        context.lastInsights.insert(
            aboutOther
                ? "Emotional support focus: helping someone else with \(need.label.lowercased())."
                : "Emotional support focus: \(need.label.lowercased()).",
            at: 0
        )
        if context.lastInsights.count > 15 {
            context.lastInsights = Array(context.lastInsights.prefix(15))
        }
        context.lastUpdated = Date()
        persist()
    }
}
