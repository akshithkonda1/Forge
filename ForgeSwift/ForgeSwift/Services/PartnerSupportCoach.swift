import Foundation

/// Turns a partner cycle snapshot into practical "how you show up" coaching
/// for the user (often a male partner). Empathy-first, non-clinical, consent-aware.
enum PartnerSupportCoach {

    static func brief(
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
            training = "If you train together, bias mobility, walk, or light full-body. Skip \"prove something\" energy. Your hard session can be solo so she isn't dragged into it."
            talk = "Try: \"How's your body today — want company, help, or quiet?\" Simple > clever."

        case .follicular:
            headline = "\(name) is in the follicular phase" + (day.map { " · day \($0)" } ?? "") + " — energy often rebuilds; good window for active plans."
            support = [
                "Suggest adventures she already likes — new restaurant, hike, class, project.",
                "Match optimism without over-scheduling the whole week.",
                "Celebrate wins; this phase often feels more \"on\" for many people.",
            ]
            avoid = [
                "Don't pile on obligations just because she has more energy one day.",
            ]
            dates = [
                "Active date: gym session, climb, long walk, market browse.",
                "Social plans with an easy out still available.",
                "Plan something you've both postponed.",
            ]
            intimacy = "Many people feel more open and energetic here — still consent every time; energy ≠ obligation."
            training = "Strong window for shared progressive sessions if she wants them. You can program a quality couple workout and keep intensity optional."
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
                "Don't announce \"you're ovulating\" in a clinical or pressuring way unless she wants that language.",
            ]
            dates = [
                "Date night with intention — dress up or favorite ritual.",
                "Playful active plans if energy is high.",
            ]
            intimacy = "Only with clear mutual interest. Use the language she prefers. If you're trying to conceive or avoid pregnancy, that plan is yours together — ARIA won't manage contraception."
            training = "Power and intensity can feel available. Shared PRs are fine if recovery and warm-ups are honest."
            talk = "Try: \"I'd love time with you this week — what kind of night sounds good?\""

        case .luteal:
            let late = (day ?? 0) >= 22 || snapshot.recommendRecoveryBias
            headline = late
                ? "\(name) may be in late luteal / pre-period territory — patience and lower friction help most."
                : "\(name) is in the luteal phase" + (day.map { " · day \($0)" } ?? "") + " — capacity can dip; protect the relationship from unnecessary stress."
            support = [
                "Default to kindness when irritability shows up — it's often physiology + load, not \"about you.\"",
                "Reduce decision fatigue: you pick dinner options, she vetoes.",
                "Protect sleep; offer wind-down without lecturing.",
                "If cravings or comfort food show up, join without judgment.",
                "Keep conflict repair short and soft; revisit big topics when both are resourced.",
            ]
            avoid = [
                "Don't start scorekeeping fights about chores mid-spiral.",
                "Don't mock PMS — even as a joke — unless that's your established humor and she starts it.",
                "Don't stack surprise high-pressure events.",
            ]
            dates = [
                "Low-stimulus comfort: home, nature, early night.",
                "Small thoughtful gesture > elaborate production.",
            ]
            intimacy = "Libido and touch preferences can shift. Ask what kind of closeness feels good — cuddle, space, or more."
            training = "If training together, leave reps in the tank. Your hard day can be alone so shared time stays supportive."
            talk = "Try: \"I want this week to feel easy for you — anything I should take off your plate?\""

        case .unknown:
            headline = "Not enough of \(name)'s cycle data yet — log period starts (with consent) so ARIA can sync support."
            support = [
                "Ask \(name) if she's comfortable with you logging period start dates only.",
                "Even 2–3 cycles makes timing advice much sharper.",
                "Until then, use daily check-ins: energy, pain, social battery.",
            ]
            avoid = [
                "Don't guess or announce a phase without data.",
            ]
            dates = [
                "Ask what kind of plan would feel good this week — then do that.",
            ]
            intimacy = "Stay curious and consent-first regardless of calendar."
            training = "Train your own readiness; invite her with zero pressure."
            talk = "Try: \"Would it help if I tracked period starts so I can plan better around you?\""
        }

        if snapshot.irregularityFlag {
            support.append("Her cycle length looks variable — use wider windows and check in more, trust less on calendar alone.")
        }

        return PartnerSupportBrief(
            partnerLabel: name,
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

    /// Full ARIA chat monologue for partner-support asks.
    static func ariaMessage(
        snapshot: MenstrualCycleSnapshot,
        settings: PartnerCycleSettings,
        userName: String,
        input: String
    ) -> String {
        let brief = brief(snapshot: snapshot, settings: settings)
        let lower = input.lowercased()
        var lines: [String] = []

        let you = userName.isEmpty ? "You" : userName
        lines.append("\(you) — partner sync for **\(brief.partnerLabel)**.")
        lines.append(brief.headline)
        if snapshot.trackingEnabled, snapshot.confidence > 0 {
            lines.append("Model confidence \(Int(snapshot.confidence * 100))% · \(snapshot.dataQuality) · \(snapshot.cyclesObserved) cycles logged.")
        }

        if lower.contains("date") || lower.contains("plan") || lower.contains("tonight") || lower.contains("weekend") {
            lines.append("**Date / plan ideas**")
            lines.append(contentsOf: brief.dateIdeas.map { "• \($0)" })
        } else if lower.contains("sex") || lower.contains("intimacy") || lower.contains("libido") {
            lines.append("**Intimacy**")
            lines.append(brief.intimacyNote)
        } else if lower.contains("train") || lower.contains("workout") || lower.contains("gym") {
            lines.append("**Training together**")
            lines.append(brief.trainingTogetherNote)
        } else if lower.contains("fight") || lower.contains("argument") || lower.contains("mad") || lower.contains("upset") {
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
            lines.append("**Together training**")
            lines.append(brief.trainingTogetherNote)
        }

        if let next = snapshot.nextPeriod {
            lines.append("Next period window (est.): \(next.earliestDayKey) → \(next.latestDayKey) (median \(next.medianDayKey)).")
        }

        lines.append("\n" + brief.disclaimer)
        return lines.joined(separator: "\n\n")
    }
}
