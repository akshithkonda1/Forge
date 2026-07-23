import Foundation

/// Turns a supported person's cycle snapshot into practical "how you show up" coaching.
/// Works for romantic partners **and** parents (especially fathers of daughters), family, friends.
/// Empathy-first, role-aware, non-clinical, consent-aware.
enum PartnerSupportCoach {

    static func brief(
        snapshot: MenstrualCycleSnapshot,
        settings: PartnerCycleSettings
    ) -> PartnerSupportBrief {
        let role = settings.resolvedRole
        switch role {
        case .child:
            return childBrief(snapshot: snapshot, settings: settings)
        case .family, .friend, .other:
            return familyFriendBrief(snapshot: snapshot, settings: settings, role: role)
        case .romantic:
            return romanticBrief(snapshot: snapshot, settings: settings)
        }
    }

    /// Full ARIA chat monologue.
    @MainActor
    static func ariaMessage(
        snapshot: MenstrualCycleSnapshot,
        settings: PartnerCycleSettings,
        userName: String,
        input: String
    ) -> String {
        // Instant label adaptation (wife vs girlfriend vs daughter…)
        let adaptation = AriaPersonRegistry.shared.adapt(to: input)
            ?? AriaPersonRegistry.shared.adaptationForCurrentPartnerSettings(settings)
        var settings = settings
        settings.supportRole = adaptation.role
        if settings.relationshipLabel != adaptation.label.rawValue {
            let parsed = AriaRelationshipLabel.parse(from: settings.relationshipLabel)
            if parsed == .other || settings.relationshipLabel == "partner" {
                settings.relationshipLabel = adaptation.label.displayLabel
            }
        }

        let brief = brief(snapshot: snapshot, settings: settings)
        let lower = input.lowercased()
        var lines: [String] = []

        let you = userName.isEmpty ? "You" : userName
        lines.append(adaptation.voicePreamble)
        let roleTag = adaptation.caregiverMode ? "parent / caregiver sync" : "relationship sync"
        lines.append("\(you) — \(roleTag) for **\(adaptation.who)** (\(adaptation.label.displayLabel)).")
        lines.append(brief.headline)
        lines.append(adaptation.supportStance)
        lines.append(adaptation.communicationAdvice)
        if adaptation.archetype != .unknown {
            lines.append("**\(adaptation.who.capitalized)'s vibe:** \(adaptation.archetype.label) — \(adaptation.archetype.tagline)")
            lines.append("Talk to them like this: \(adaptation.archetype.speechGuidance)")
        }
        lines.append("**How they speak:** \(adaptation.speech.coachingSummary)")
        if !adaptation.dynamics.userTags.isEmpty {
            lines.append("What I know about how you two work: " + adaptation.dynamics.userTags.prefix(5).joined(separator: " · "))
        }
        if snapshot.trackingEnabled, snapshot.confidence > 0 {
            lines.append("Model confidence \(Int(snapshot.confidence * 100))% · \(snapshot.dataQuality) · \(snapshot.cyclesObserved) cycles logged.")
        }

        let plansKey = brief.role == .romantic ? "date" : "plan"
        if lower.contains(plansKey) || lower.contains("tonight") || lower.contains("weekend")
            || lower.contains("activity") || lower.contains("what should we do") {
            lines.append(brief.role == .romantic ? "**Date / plan ideas**" : "**Plan / activity ideas**")
            lines.append(contentsOf: brief.dateIdeas.map { "• \($0)" })
        } else if brief.role == .romantic,
                  lower.contains("sex") || lower.contains("intimacy") || lower.contains("libido") {
            lines.append("**Intimacy**")
            lines.append(brief.intimacyNote)
        } else if brief.role == .child,
                  lower.contains("school") || lower.contains("sport") || lower.contains("practice")
                    || lower.contains("supplies") || lower.contains("pad") || lower.contains("tampon") {
            lines.append("**Practical support**")
            lines.append(contentsOf: brief.supportMoves.prefix(5).map { "• \($0)" })
            lines.append(brief.intimacyNote)
        } else if lower.contains("train") || lower.contains("workout") || lower.contains("gym") {
            lines.append(brief.role == .child ? "**Movement / sports**" : "**Training together**")
            lines.append(brief.trainingTogetherNote)
        } else if lower.contains("fight") || lower.contains("argument") || lower.contains("mad")
                    || lower.contains("upset") || lower.contains("attitude") {
            lines.append("**Conflict / repair**")
            lines.append(brief.communicationTip)
            lines.append(contentsOf: brief.avoidMoves.prefix(3).map { "• Avoid: \($0)" })
        } else {
            lines.append("**How you can show up**")
            lines.append(contentsOf: brief.supportMoves.prefix(5).map { "• \($0)" })
            lines.append("**Ease off**")
            lines.append(contentsOf: brief.avoidMoves.prefix(3).map { "• \($0)" })
            lines.append("**Say this**")
            lines.append(brief.communicationTip)
            if brief.role == .romantic {
                lines.append("**Together training**")
            } else if brief.role == .child {
                lines.append("**Sports / activity**")
            } else {
                lines.append("**Shared movement**")
            }
            lines.append(brief.trainingTogetherNote)
            if brief.role == .child {
                lines.append("**Dignity & privacy**")
                lines.append(brief.intimacyNote)
            }
        }

        if let next = snapshot.nextPeriod {
            lines.append("Next period window (est.): \(next.earliestDayKey) → \(next.latestDayKey) (median \(next.medianDayKey)).")
        }

        lines.append("\n" + brief.disclaimer)
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Romantic partner

    private static func romanticBrief(
        snapshot: MenstrualCycleSnapshot,
        settings: PartnerCycleSettings
    ) -> PartnerSupportBrief {
        let name = settings.displayName
        let phase = snapshot.phase
        let day = snapshot.dayInCycle

        let headline: String
        var support: [String] = []
        var avoid: [String] = []
        var dates: [String] = []
        let intimacy: String
        let training: String
        let talk: String

        switch phase {
        case .menstruation:
            headline = "\(name) is in menstruation" + (day.map { " (day \($0))" } ?? "") + " — lead with comfort and low pressure."
            support = [
                "Ask what would feel good today: quiet night, heat pack, snack run, or space.",
                "Offer to handle logistics (dinner, dishes, errands) without making it a big speech.",
                "Believe pain reports; don't minimize cramps or fatigue.",
                "Keep plans flexible — early exit from social events is a win, not a fail.",
                "If she trains, support technique/recovery sessions over ego lifts.",
            ]
            avoid = [
                "Don't police mood or say \"it's just hormones\" as a dismissive line.",
                "Don't schedule high-stakes conflict talks if they can wait.",
                "Don't assume she wants to be left alone — ask once, clearly.",
            ]
            dates = [
                "Cozy night in: film, blankets, favorite takeout.",
                "Short easy walk if she wants movement without intensity.",
                "You cook / order; she chooses the vibe.",
            ]
            intimacy = "Desire and comfort vary widely on period days. Follow her lead, ask, and treat \"not tonight\" as complete information — not a rejection of you."
            training = "If you train together, bias mobility, walk, or light full-body. Your hard session can be solo so she isn't dragged into it."
            talk = "Try: \"How's your body today — want company, help, or quiet?\" Simple > clever."

        case .follicular:
            headline = "\(name) is in the follicular phase" + (day.map { " · day \($0)" } ?? "") + " — energy often rebuilds; good window for active plans."
            support = [
                "Suggest adventures she already likes — new restaurant, hike, class, project.",
                "Match optimism without over-scheduling the whole week.",
                "Celebrate wins; this phase often feels more \"on\" for many people.",
            ]
            avoid = ["Don't pile on obligations just because she has more energy one day."]
            dates = [
                "Active date: gym session, climb, long walk, market browse.",
                "Social plans with an easy out still available.",
            ]
            intimacy = "Many people feel more open and energetic here — still consent every time; energy ≠ obligation."
            training = "Strong window for shared progressive sessions if she wants them."
            talk = "Try: \"Want to do something active this week, or keep it light?\""

        case .fertileWindow, .ovulation:
            headline = "\(name) is near ovulation / fertile window" + (day.map { " · day \($0)" } ?? "") + " — often peak vitality; stay attentive and respectful."
            support = [
                "Be present — this can be a high-connection window when both want it.",
                "Hydration, sleep, and food still matter; help the basics stay easy.",
                "If pregnancy is a topic for you two, stay aligned on your shared plan (never assume).",
            ]
            avoid = [
                "Don't treat fertility windows as entitlement to sex.",
                "Don't announce \"you're ovulating\" in a pressuring way unless she wants that language.",
            ]
            dates = [
                "Date night with intention — dress up or favorite ritual.",
                "Playful active plans if energy is high.",
            ]
            intimacy = "Only with clear mutual interest. Use the language she prefers. ARIA won't manage contraception."
            training = "Power and intensity can feel available. Shared PRs are fine if warm-ups are honest."
            talk = "Try: \"I'd love time with you this week — what kind of night sounds good?\""

        case .luteal:
            let late = (day ?? 0) >= 22 || snapshot.recommendRecoveryBias
            headline = late
                ? "\(name) may be in late luteal / pre-period territory — patience and lower friction help most."
                : "\(name) is in the luteal phase" + (day.map { " · day \($0)" } ?? "") + " — capacity can dip; protect the relationship from unnecessary stress."
            support = [
                "Default to kindness when irritability shows up — often physiology + load, not \"about you.\"",
                "Reduce decision fatigue: you pick dinner options, she vetoes.",
                "Protect sleep; offer wind-down without lecturing.",
                "If cravings show up, join without judgment.",
            ]
            avoid = [
                "Don't start scorekeeping fights about chores mid-spiral.",
                "Don't mock PMS — even as a joke — unless that's your established humor and she starts it.",
            ]
            dates = [
                "Low-stimulus comfort: home, nature, early night.",
                "Small thoughtful gesture > elaborate production.",
            ]
            intimacy = "Libido and touch preferences can shift. Ask what kind of closeness feels good."
            training = "If training together, leave reps in the tank. Your hard day can be alone."
            talk = "Try: \"I want this week to feel easy for you — anything I should take off your plate?\""

        case .unknown:
            headline = "Not enough of \(name)'s cycle data yet — log period starts (with consent) so ARIA can sync support."
            support = [
                "Ask \(name) if she's comfortable with you logging period start dates only.",
                "Even 2–3 cycles makes timing advice much sharper.",
            ]
            avoid = ["Don't guess or announce a phase without data."]
            dates = ["Ask what kind of plan would feel good this week — then do that."]
            intimacy = "Stay curious and consent-first regardless of calendar."
            training = "Train your own readiness; invite her with zero pressure."
            talk = "Try: \"Would it help if I tracked period starts so I can plan better around you?\""
        }

        if snapshot.irregularityFlag {
            support.append("Cycle length looks variable — use wider windows and check in more.")
        }

        return PartnerSupportBrief(
            partnerLabel: name,
            role: .romantic,
            phase: phase,
            dayInCycle: day,
            confidence: snapshot.confidence,
            headline: headline,
            supportMoves: support,
            avoidMoves: avoid,
            dateIdeas: dates,
            intimacyNote: intimacy,
            trainingTogetherNote: training,
            communicationTip: talk,
            disclaimer: PartnerSupportBrief.disclaimer
        )
    }

    // MARK: - Child / daughter (fathers & parents)

    private static func childBrief(
        snapshot: MenstrualCycleSnapshot,
        settings: PartnerCycleSettings
    ) -> PartnerSupportBrief {
        let name = settings.displayName
        let phase = snapshot.phase
        let day = snapshot.dayInCycle
        let she = pronounShe(settings)

        let headline: String
        var support: [String] = []
        var avoid: [String] = []
        var plans: [String] = []
        let dignity: String
        let sports: String
        let talk: String

        switch phase {
        case .menstruation:
            headline = "\(name) is on \(her(settings)) period" + (day.map { " (day \($0))" } ?? "") + " — dads and parents: comfort, supplies, and zero embarrassment."
            support = [
                "Keep a quiet stock of pads/tampons/period underwear in the bathroom and car — no speech required.",
                "Offer a heat pack, water, and a favorite snack without making it a production.",
                "Believe pain. Cramps can be real; \"walk it off\" is not medicine.",
                "Give permission to skip or modify sports/practice if \(she) feels rough — back \(her(settings)) up with coaches if needed.",
                "Protect privacy: no joking about \(her(settings)) period in front of siblings, relatives, or teammates.",
                "If pain is severe, sudden, or with fever/fainting, pause coaching and involve a clinician — you're the safety net.",
            ]
            avoid = [
                "Don't tease, nicknames about \"mood,\" or period jokes at \(her(settings)) expense.",
                "Don't interrogate details \(she) doesn't volunteer.",
                "Don't shame body, products, or accidents — handle laundry/supplies matter-of-factly.",
                "Don't force \"push through\" for every practice; teach listening to the body.",
            ]
            plans = [
                "Low-key night: movie, blankets, easy food \(she) picks.",
                "Short walk only if \(she) wants — no mandatory bonding adventure.",
                "Offer a ride so \(she) isn't stuck on a long day with limited bathroom access.",
            ]
            dignity = "This is about safety and dignity, not romance. Keep conversations age-appropriate, private, and led by what \(she) wants to share. Never discuss \(her(settings)) cycle with others without \(her(settings)) clear okay."
            sports = "Many girls still play through periods — support that choice and the choice to rest. Hydration, iron-rich meals, and sleep help more than pep talks."
            talk = "Try: \"I've got supplies if you need them. Want quiet, a snack, or a ride?\" Short. Normal. No lecture."

        case .follicular:
            headline = "\(name) is in the follicular phase" + (day.map { " · day \($0)" } ?? "") + " — energy often rises; good window for skills, sports, and confidence."
            support = [
                "Encourage activities \(she) already loves — practice, clubs, outdoors — without overloading the calendar.",
                "Celebrate effort and competence; this phase can feel stronger for many teens.",
                "Keep routines steady: sleep and meals still matter when energy is high.",
            ]
            avoid = ["Don't stack every commitment into one \"high energy\" week."]
            plans = [
                "Active family time if \(she) wants: hike, gym intro, bike.",
                "Help with a goal \(she) chose (skill, project, sport).",
            ]
            dignity = "Stay in the parent lane: pride and logistics, not body commentary."
            sports = "Often a solid window for progressive training if \(she) enjoys it — keep it fun and coached, not boot-camp."
            talk = "Try: \"Want to do something active this week, or keep it chill?\""

        case .fertileWindow, .ovulation:
            headline = "\(name) may be mid-cycle" + (day.map { " · day \($0)" } ?? "") + " — energy can peak; keep support practical and private."
            support = [
                "Normal life support: food, sleep, school logistics.",
                "If \(she) has questions about \(her(settings)) body, answer honestly or find a trusted resource together — don't dodge forever.",
            ]
            avoid = [
                "Don't lecture about fertility or \"becoming a woman\" unless \(she) opens that door.",
                "Don't announce cycle phase to others.",
            ]
            plans = [
                "Whatever \(she) enjoys when energy is up — still optional.",
            ]
            dignity = "Parents: this is not a romance frame. Skip fertility/intimacy language entirely for kids. Focus on health literacy only if invited."
            sports = "Performance can feel good mid-cycle for some — still watch for overuse and sleep debt."
            talk = "Try: \"Anything feel off with practice or school this week? I'm here.\""

        case .luteal:
            let late = (day ?? 0) >= 22 || snapshot.recommendRecoveryBias
            headline = late
                ? "\(name) may be pre-period — patience, snacks, and softer expectations help a lot."
                : "\(name) is in the luteal phase" + (day.map { " · day \($0)" } ?? "") + " — mood and energy can wobble; stay steady."
            support = [
                "Give extra grace on irritability — stay calm; don't match heat with heat.",
                "Help with decision load (meals, rides, homework logistics).",
                "Protect sleep; ease off late-night screens fights if you can trade for rest.",
                "Stock comfort foods without moralizing.",
            ]
            avoid = [
                "Don't diagnose \"PMS attitude\" out loud as a put-down.",
                "Don't pick big discipline battles that can wait 48 hours.",
                "Don't compare \(her(settings)) to siblings or peers.",
            ]
            plans = [
                "Cozy low-stimulus time at home.",
                "One-on-one hang without an audience if \(she) wants company.",
            ]
            dignity = "Your job is emotional safety. Private check-ins beat public commentary."
            sports = "Allow modified practice. Consistency over heroics."
            talk = "Try: \"You seem stretched — want help with anything, or just space?\""

        case .unknown:
            headline = "Log \(name)'s period starts (with \(her(settings)) knowledge) so you can plan school, sports, and support better."
            support = [
                "Many dads track starts on a shared calendar \(she) can see — transparency builds trust.",
                "Offer a simple code word for \"I need supplies/a break\" at school or practice.",
                "Two or three logged cycles makes predictions much more useful.",
            ]
            avoid = ["Don't track secretly. If \(she)'s old enough to care, \(she) should know."]
            plans = ["Ask what would make hard days easier — then do that one thing."]
            dignity = "Caregiver tracking is for support logistics, not surveillance. Privacy is the product."
            sports = "Until you have data, follow \(her(settings)) daily report on energy and pain."
            talk = "Try: \"Would it help if we noted period starts so I can back you up with practice and supplies?\""
        }

        if snapshot.irregularityFlag {
            support.append("Cycles can be irregular in teens — wider windows, less calendar certainty, more daily check-ins.")
        }

        return PartnerSupportBrief(
            partnerLabel: name,
            role: .child,
            phase: phase,
            dayInCycle: day,
            confidence: snapshot.confidence,
            headline: headline,
            supportMoves: support,
            avoidMoves: avoid,
            dateIdeas: plans,
            intimacyNote: dignity,
            trainingTogetherNote: sports,
            communicationTip: talk,
            disclaimer: PartnerSupportBrief.disclaimer
        )
    }

    // MARK: - Family / friend / other

    private static func familyFriendBrief(
        snapshot: MenstrualCycleSnapshot,
        settings: PartnerCycleSettings,
        role: CycleSupportRole
    ) -> PartnerSupportBrief {
        let name = settings.displayName
        let phase = snapshot.phase
        let day = snapshot.dayInCycle

        let headline: String
        var support: [String]
        var avoid: [String]
        var plans: [String]
        let boundary: String
        let movement: String
        let talk: String

        switch phase {
        case .menstruation:
            headline = "\(name) is on their period" + (day.map { " (day \($0))" } ?? "") + " — practical kindness beats over-involvement."
            support = [
                "Offer concrete help: errand, meal, quiet hang, heat pack.",
                "Believe discomfort; don't minimize.",
                "Keep plans flexible.",
            ]
            avoid = [
                "Don't make their body the group topic.",
                "Don't force advice they didn't ask for.",
            ]
            plans = ["Low-key hang or rain check without guilt."]
            boundary = "You're a support person, not their doctor or their partner — stay in your lane."
            movement = "Invite light movement only if they want it."
            talk = "Try: \"Need anything practical today, or prefer space?\""
        case .follicular, .fertileWindow, .ovulation:
            headline = "\(name) is mid-cycle" + (day.map { " · day \($0)" } ?? "") + " — energy may be higher; still ask before planning big."
            support = ["Match their pace on social plans.", "Be a solid friend without cycle commentary."]
            avoid = ["Don't announce their phase."]
            plans = ["Active plans they already enjoy."]
            boundary = "Minimal commentary on their body; maximum reliability."
            movement = "Shared activity is fine if they initiate or agree."
            talk = "Try: \"Want to do X this week?\""
        case .luteal:
            headline = "\(name) may be in luteal / pre-period" + (day.map { " · day \($0)" } ?? "") + " — softer plans, more patience."
            support = ["Give grace on short fuse.", "Offer low-stimulus company."]
            avoid = ["Don't pathologize mood as a joke."]
            plans = ["Quiet hang, early night."]
            boundary = "Support without diagnosing."
            movement = "Optional easy walk beats intensity."
            talk = "Try: \"Happy to keep it easy this week.\""
        case .unknown:
            headline = "Not enough data on \(name)'s cycle yet."
            support = ["Only log what they explicitly share.", "Daily kindness doesn't need a calendar."]
            avoid = ["Don't track without permission."]
            plans = ["Ask what would help this week."]
            boundary = "Consent first."
            movement = "Follow their energy day to day."
            talk = "Try: \"If you ever want me to remember period starts to help with plans, say the word.\""
        }

        return PartnerSupportBrief(
            partnerLabel: name,
            role: role,
            phase: phase,
            dayInCycle: day,
            confidence: snapshot.confidence,
            headline: headline,
            supportMoves: support,
            avoidMoves: avoid,
            dateIdeas: plans,
            intimacyNote: boundary,
            trainingTogetherNote: movement,
            communicationTip: talk,
            disclaimer: PartnerSupportBrief.disclaimer
        )
    }

    // MARK: Pronoun helpers (simple she/her default; labels can be neutral)

    private static func pronounShe(_ settings: PartnerCycleSettings) -> String {
        let l = settings.relationshipLabel.lowercased()
        if l.contains("they") || l.contains("them") || l.contains("child") && !l.contains("daughter") {
            // keep simple for coaching; still often she/her for daughter
        }
        if l.contains("daughter") || l.contains("girlfriend") || l.contains("wife") || l.contains("sister") || l.contains("mom") {
            return "she"
        }
        return "they"
    }

    private static func her(_ settings: PartnerCycleSettings) -> String {
        pronounShe(settings) == "she" ? "her" : "their"
    }
}
