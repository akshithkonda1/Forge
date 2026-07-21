import Foundation

// MARK: - Detected support mention from free text

struct AriaSupportMention: Equatable {
    var role: CycleSupportRole
    var relationshipLabel: String
    var name: String?
    var isSetupIntent: Bool
    var isCheckInIntent: Bool
}

/// Humanizes ARIA’s relational cycle coaching: asks natural questions, remembers
/// who you support (partner, daughter, family), and talks like a trusted friend —
/// not a medical pamphlet.
enum AriaRelationalCoach {

    // MARK: Understanding

    static func detectSupportMention(in text: String) -> AriaSupportMention? {
        let lower = text.lowercased()
        guard mentionsSupportContext(lower) else { return nil }

        let role: CycleSupportRole
        let label: String
        if lower.contains("daughter") {
            role = .child; label = "daughter"
        } else if lower.contains("my kid") || lower.contains("my child") || lower.contains("my teen") {
            role = .child; label = lower.contains("teen") ? "teen" : "child"
        } else if lower.contains("wife") {
            role = .romantic; label = "wife"
        } else if lower.contains("girlfriend") || lower.contains("gf") {
            role = .romantic; label = "girlfriend"
        } else if lower.contains("fiancé") || lower.contains("fiance") {
            role = .romantic; label = "fiancé"
        } else if lower.contains("spouse") || lower.contains("husband") {
            role = .romantic; label = lower.contains("husband") ? "husband" : "spouse"
        } else if lower.contains("sister") {
            role = .family; label = "sister"
        } else if lower.contains("mom") || lower.contains("mother") {
            role = .family; label = "mom"
        } else if lower.contains("partner") {
            role = .romantic; label = "partner"
        } else if lower.contains("as a dad") || lower.contains("as a father") || lower.contains("as a parent") {
            role = .child; label = "daughter"
        } else {
            role = .other; label = "someone I support"
        }

        let name = extractName(from: text, near: label)
        let setup = lower.contains("set up") || lower.contains("start tracking")
            || lower.contains("help me support") || lower.contains("i want to track")
            || lower.contains("can you track") || lower.contains("log her")
            || lower.contains("log my") || lower.contains("remember that")
            || (lower.contains("my ") && (lower.contains("wife") || lower.contains("girlfriend")
                || lower.contains("daughter") || lower.contains("partner")))
        let checkIn = lower.contains("how is she") || lower.contains("how's she")
            || lower.contains("what phase") || lower.contains("how do i support")
            || lower.contains("what should i do") || lower.contains("check in")

        return AriaSupportMention(
            role: role,
            relationshipLabel: label,
            name: name,
            isSetupIntent: setup,
            isCheckInIntent: checkIn
        )
    }

    static func mentionsSupportContext(_ lower: String) -> Bool {
        lower.contains("wife") || lower.contains("girlfriend") || lower.contains("partner")
            || lower.contains("daughter") || lower.contains("my kid") || lower.contains("my child")
            || lower.contains("my teen") || lower.contains("as a dad") || lower.contains("as a father")
            || lower.contains("as a parent") || lower.contains("her period") || lower.contains("her cycle")
            || lower.contains("her pms") || lower.contains("support her") || lower.contains("spouse")
            || lower.contains("fiancé") || lower.contains("fiance") || lower.contains("my sister")
            || lower.contains("for my daughter") || lower.contains("for my wife")
            || lower.contains("for my girlfriend")
    }

    /// Pull a likely first name after "my wife/daughter X" or "named X".
    private static func extractName(from text: String, near label: String) -> String? {
        let patterns = [
            "my \(label) ([A-Za-z]{2,20})",
            "\(label) ([A-Za-z]{2,20})",
            "named ([A-Za-z]{2,20})",
            "name is ([A-Za-z]{2,20})",
            "called ([A-Za-z]{2,20})",
        ]
        let ns = text as NSString
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges > 1 {
                let r = match.range(at: 1)
                if r.location != NSNotFound {
                    let name = ns.substring(with: r)
                    let banned: Set<String> = [
                        "is", "has", "was", "the", "and", "her", "his", "period", "cycle",
                        "today", "this", "week", "help", "with", "support", "started",
                    ]
                    if !banned.contains(name.lowercased()) {
                        return name.prefix(1).uppercased() + name.dropFirst().lowercased()
                    }
                }
            }
        }
        return nil
    }

    // MARK: Soft setup from chat

    /// If user names a wife/daughter/etc., seed support tracking (consent still required for full engine).
    @MainActor
    static func applyMentionIfNeeded(_ mention: AriaSupportMention, store: MenstrualHealthStore) {
        var changed = false
        if !store.partnerSettings.enabled {
            store.updatePartnerSettings {
                $0.enabled = true
                $0.supportRole = mention.role
                $0.relationshipLabel = mention.relationshipLabel
                if let n = mention.name { $0.partnerName = n }
                $0.shareWithAria = true
            }
            changed = true
        } else {
            store.updatePartnerSettings {
                if $0.supportRole == .other || $0.supportRole == .romantic && mention.role == .child {
                    $0.supportRole = mention.role
                }
                if $0.relationshipLabel == "partner" || $0.relationshipLabel.isEmpty {
                    $0.relationshipLabel = mention.relationshipLabel
                }
                if $0.partnerName.isEmpty, let n = mention.name {
                    $0.partnerName = n
                }
            }
            changed = true
        }
        if changed {
            AriaContextStore.shared.addInsight(
                humanMemoryLine(mention: mention, consented: store.partnerSettings.consentAcknowledged)
            )
        }
    }

    static func humanMemoryLine(mention: AriaSupportMention, consented: Bool) -> String {
        let who = mention.name ?? mention.relationshipLabel
        if mention.role == .child {
            return consented
                ? "You care for \(who) as a parent — I'll help you show up on hard period days without making it weird."
                : "You mentioned \(who) (daughter/child). When you're ready, confirm support tracking and log period starts she shares."
        }
        return consented
            ? "You're looking out for \(who) — I'll keep their cycle context human and practical."
            : "You mentioned \(who). With their okay, we can track period starts so I can help you plan around them."
    }

    // MARK: Humanized proactive questions

    /// Soft question ARIA can ask when support context is missing or stale.
    static func proactiveQuestion(
        userGender: Gender,
        partnerSettings: PartnerCycleSettings,
        partnerSnapshot: MenstrualCycleSnapshot?,
        readiness: Int,
        salt: UInt64
    ) -> String? {
        var rng = AriaSeededRNG(seed: salt == 0 ? 42 : salt)

        // Already tracking — human check-in by phase
        if partnerSettings.enabled, partnerSettings.consentAcknowledged,
           let snap = partnerSnapshot, snap.trackingEnabled || snap.dayInCycle != nil {
            let name = partnerSettings.displayName
            switch partnerSettings.resolvedRole {
            case .child:
                switch snap.phase {
                case .menstruation:
                    return rng.pick([
                        "Hey — is \(name) having a rough period day? I can help with the dad/parent playbook if useful.",
                        "Thinking of \(name). Need ideas for comfort, supplies, or practice today?",
                        "Quick check: anything \(name) needs from you today, or are you good?",
                    ])
                case .luteal:
                    return rng.pick([
                        "\(name) may be in a tender part of the cycle. Want a soft script for how to check in?",
                        "Parenting note: pre-period days can feel spiky. I can help you stay steady if you want.",
                    ])
                default:
                    if rng.chance(0.35) {
                        return "How's \(name) doing this week? I can sync support around her cycle if anything's up."
                    }
                    return nil
                }
            case .romantic:
                switch snap.phase {
                case .menstruation:
                    return rng.pick([
                        "Is \(name) on her period right now? I can help you make today easier for both of you.",
                        "Thinking about \(name) — want low-pressure ways to show up if she's not feeling great?",
                        "Quick human check: anything I can help with for \(name) today?",
                    ])
                case .luteal:
                    return rng.pick([
                        "\(name) might be in a lower-energy stretch. Want date/plan ideas that don't add stress?",
                        "Relationship note: patience goes far this part of the cycle. Need a gentle script?",
                    ])
                default:
                    if rng.chance(0.3) {
                        return "How are things with \(name)? I can keep your plans in sync with her cycle if that helps."
                    }
                    return nil
                }
            default:
                if snap.phase == .menstruation || snap.recommendRecoveryBias {
                    return "Thinking of \(name) — want practical ways to be helpful today?"
                }
                return nil
            }
        }

        // Not set up — invite without pressure (especially dads / partners)
        if partnerSettings.enabled, !partnerSettings.consentAcknowledged {
            return rng.pick([
                "You started support tracking but didn't finish consent — want me to walk you through it gently?",
                "Still there on supporting someone else's cycle? One quick confirmation and I can help you show up better.",
            ])
        }

        if !partnerSettings.enabled {
            // Don't spam; only sometimes, more for male profiles historically related to partner/dad use
            let bias = userGender == .male ? 0.55 : 0.28
            guard rng.chance(bias) else { return nil }
            return rng.pick([
                "Real question — is there someone whose cycle you try to support? Partner, wife, daughter? A lot of people do. I can help you show up human if you want.",
                "I coach more than workouts. If you're a partner or a dad who wants to handle period days better, I can learn that context — only what they're okay sharing.",
                "Anyone at home you plan around when they're on their period? I can keep that in mind so I'm not just talking about your lifts.",
                "If you've got a partner or a daughter, I can help with the human side — supplies, plans, what not to say. Want that?",
            ])
        }

        return nil
    }

    // MARK: Humanize structured briefs into conversation

    static func humanizeSupportReply(
        snapshot: MenstrualCycleSnapshot,
        settings: PartnerCycleSettings,
        userName: String,
        input: String
    ) -> String {
        let core = PartnerSupportCoach.ariaMessage(
            snapshot: snapshot,
            settings: settings,
            userName: userName,
            input: input
        )
        let name = settings.displayName
        let lower = input.lowercased()
        var openers: [String] = []

        switch settings.resolvedRole {
        case .child:
            openers = [
                "Alright — parent mode, no awkwardness.",
                "Got it. Supporting \(name) is the job today.",
                "Yeah. Dads who pay attention here make a real difference.",
                "I'm with you. Let's keep this practical and kind.",
            ]
        case .romantic:
            openers = [
                "Okay — let's treat \(name) like a person, not a calendar.",
                "Good that you're thinking about her. Here's how to make it real.",
                "Love that you're asking. Small moves beat grand speeches.",
                "Alright. Human first, advice second.",
            ]
        default:
            openers = [
                "Okay — supportive without overstepping.",
                "Got it. Keep it kind and useful.",
            ]
        }

        var rng = AriaSeededRNG(seed: UInt64(abs(input.hashValue) &+ name.hashValue))
        let opener = rng.pick(openers)

        var closer: String
        if lower.contains("thank") {
            closer = "Anytime. Showing up is the whole point."
        } else if settings.resolvedRole == .child {
            closer = "You've got this. Steady > perfect."
        } else {
            closer = "Check in with her in plain language — I'll be here if you want to adjust."
        }

        // Soft disclaimer once, less legal-brief tone
        let softLegal = settings.resolvedRole == .child
            ? "\n\n(I'm coaching *you* as a parent — not diagnosing \(name). Severe pain → clinician.)"
            : "\n\n(I'm coaching *you* on support — not medical advice for them.)"

        return "\(opener)\n\n\(core)\n\n\(closer)\(softLegal)"
    }

    static func humanSetupReply(mention: AriaSupportMention?) -> String {
        if let m = mention {
            let who = m.name ?? m.relationshipLabel
            switch m.role {
            case .child:
                return """
                Yeah — supporting a daughter or kid through cycles is more common than people admit, and it matters.

                I'll treat this as **parent support**, not romance talk: supplies, sports, school days, privacy, what not to joke about.

                Two gentle asks:
                1. Does \(who) know you're noting period starts to help (not to police)?
                2. Want me to open that in Cycle Health → Support, or tell me when her last period started?

                Only what she's okay sharing. I'll keep it human.
                """
            case .romantic:
                return """
                Love that you're thinking about \(who). Partners who plan around real life — not just gym PRs — last longer.

                If she's okay with it, I can remember period starts and coach *you* on comfort days, date energy, and training together.

                Quick human check: has she said it's alright for you to track starts? If yes, tell me her name (if you want) and roughly when the last period began — or set it in Cycle Health → Support.
                """
            default:
                return """
                Got it — you want to support \(who). I'll keep advice practical and in-bounds.

                With their okay, log period starts in Cycle Health → Support. Then ask me anytime: “How do I show up today?”
                """
            }
        }

        return """
        Totally. ARIA isn't only about *your* numbers.

        A lot of people use me to support a **partner** — and a surprising number of **dads** use me for a **daughter**: when periods hit, how to help with sports, what to stock, what never to say out loud.

        Is there someone whose cycle you try to plan around? Partner, wife, daughter, family? Tell me in plain words and we'll go from there — only with consent.
        """
    }

    /// Greeting add-on when we already know someone they support.
    static func greetingAddon(
        settings: PartnerCycleSettings?,
        snapshot: MenstrualCycleSnapshot?,
        salt: UInt64
    ) -> String? {
        guard let settings, settings.enabled, settings.consentAcknowledged else { return nil }
        let name = settings.displayName
        var rng = AriaSeededRNG(seed: salt)
        guard let snap = snapshot else {
            return rng.chance(0.4) ? "Also — how's \(name) doing?" : nil
        }
        switch snap.phase {
        case .menstruation:
            return settings.resolvedRole == .child
                ? rng.pick([
                    "Also checking in: is \(name) okay on her period day?",
                    "Side note — \(name) may need the softer parent playbook today.",
                ])
                : rng.pick([
                    "Also: \(name) may be on her period — want help making today easier?",
                    "Quick: anything \(name) needs from you today?",
                ])
        case .luteal where snap.recommendRecoveryBias:
            return "Also — \(name) might be in a tender stretch. I can help you stay easy with them."
        default:
            return rng.chance(0.25) ? "How's \(name) this week?" : nil
        }
    }
}
