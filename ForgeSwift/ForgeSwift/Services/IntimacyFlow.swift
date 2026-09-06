import Foundation
import ForgeCore

/// One Sexual Health & Intimacy control → a real conversation or a dedicated page.
enum IntimacyFlow: String, CaseIterable, Identifiable, Equatable {
    case healthySafeSex
    case positions
    case periodSex
    case partnerTips
    case tryingToConceive
    case difficultyConceiving

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .healthySafeSex: return "heart.circle.fill"
        case .positions: return "figure.stand"
        case .periodSex: return "drop.fill"
        case .partnerTips: return "person.2.fill"
        case .tryingToConceive: return "staroflife.fill"
        case .difficultyConceiving: return "clock.badge.questionmark"
        }
    }

    var label: String {
        switch self {
        case .healthySafeSex: return "Healthy & safe sex"
        case .positions: return "Positions & things to try"
        case .periodSex: return "Sex during your period"
        case .partnerTips: return "Tips for you and a partner"
        case .tryingToConceive: return "Trying to conceive"
        case .difficultyConceiving: return "If conceiving is taking longer"
        }
    }

    var subtitle: String {
        switch self {
        case .healthySafeSex: return "ARIA explains consent, protection, aftercare"
        case .positions: return "ARIA walks through comfort-first ideas"
        case .periodSex: return "Uses your period logs — you still decide"
        case .partnerTips: return "ARIA asks about you and them, then advises"
        case .tryingToConceive: return "ARIA asks what you're trying to conceive"
        case .difficultyConceiving: return "Options, next steps, specialists — literacy"
        }
    }

    /// Short line the human actually sent. Curriculum is ARIA's, not the user's.
    var userOpener: String {
        switch self {
        case .healthySafeSex:
            return "Walk me through healthy and safe sex."
        case .positions:
            return "Positions and things to try — explain them like you would."
        case .periodSex:
            return "Given my period data, how does sex look for my body right now?"
        case .partnerTips:
            return "Tips for me and a partner. Ask me a bit about us first."
        case .tryingToConceive:
            return "Trying to conceive. Ask me what that means for me."
        case .difficultyConceiving:
            return "Conceiving is taking longer. What are my options?"
        }
    }

    var opensChat: Bool { self != .difficultyConceiving }
}

struct IntimacyChatSession: Equatable {
    var flow: IntimacyFlow
    var userOpener: String
    var ariaOpening: String
    var suggestedActions: [String]
}

enum IntimacyFlowComposer {

    static func session(
        _ flow: IntimacyFlow,
        phase: MenstrualPhase,
        snapshot: MenstrualCycleSnapshot?,
        todayLog: CycleDayLog?,
        relationshipLabel: String?
    ) -> IntimacyChatSession {
        let composed = compose(
            flow,
            phase: phase,
            snapshot: snapshot,
            todayLog: todayLog,
            relationshipLabel: relationshipLabel
        )
        return IntimacyChatSession(
            flow: flow,
            userOpener: flow.userOpener,
            ariaOpening: composed.text,
            suggestedActions: composed.actions
        )
    }

    static func compose(
        _ flow: IntimacyFlow,
        phase: MenstrualPhase,
        snapshot: MenstrualCycleSnapshot?,
        todayLog: CycleDayLog?,
        relationshipLabel: String?
    ) -> (text: String, actions: [String]) {
        let header = "I'm ARIA, on this iPhone. I read your cycle ledger locally — nothing below was uploaded to Forge."
        switch flow {
        case .healthySafeSex:
            let body = [
                header,
                "Let's start with the basics, then you can steer.",
                SexualHealthCurriculum.safeSexBasics(),
                SexualHealthCurriculum.phaseWellness(for: phase),
            ].joined(separator: "\n\n")
            return (body, [
                "Consent and protection",
                "How to talk about condoms",
                "Aftercare",
            ])
        case .positions:
            let body = [
                header,
                "A short menu — pick what sounds kind. Skip anything that feels like homework.",
                SexualHealthCurriculum.positionsAndIdeas(for: phase),
                SexualHealthCurriculum.thingsYouCanTry(for: phase),
            ].joined(separator: "\n\n")
            return (body, [
                "What's gentlest right now",
                "Things we can try this week",
                "Just the menu",
            ])
        case .periodSex:
            let eval = SexualHealthCurriculum.periodSexEvaluation(
                phase: phase,
                isBleeding: snapshot?.isCurrentlyBleeding ?? todayLog?.flow.isBleeding ?? false,
                flow: todayLog?.flow,
                painScale: todayLog?.painScale,
                symptoms: todayLog?.symptoms ?? [],
                dayInCycle: snapshot?.dayInCycle
            )
            let body = [
                header,
                eval.asAriaSpeech,
                SexualHealthCurriculum.periodSex(phase: phase),
                SexualHealthCurriculum.positionsAndIdeas(for: phase),
            ].joined(separator: "\n\n")
            return (body, [
                "Walk me through comfort tonight",
                "What should I tell a partner",
                "Positions that hurt less",
            ])
        case .partnerTips:
            let who = (relationshipLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ask: String
            if who.contains("parent") || who.contains("mom") || who.contains("dad") {
                ask = "You're in a parent / caregiver lane. I'll stay on logistics and dignity — no sex tips."
            } else {
                ask = """
                Before I advise: tell me a little about you, and a little about them.
                • Who is this person to you — romantic partner, friend, or something newer?
                • What do you want tonight — closeness, practical help, or both?
                • Anything they should know about your body today that isn't their business to guess?
                """
            }
            let body = [
                header,
                ask,
                SexualHealthCurriculum.partnerAndYouTips(roleHint: relationshipLabel),
            ].joined(separator: "\n\n")
            return (body, [
                "I have a romantic partner",
                "I'm asking for myself",
                "This is about a friend",
            ])
        case .tryingToConceive:
            let ttc = snapshot.map { SexualHealthCurriculum.ttcGuidance(snapshot: $0) }
                ?? "I don't have enough of your cycle yet to personalize timing. That's okay — we start with what you mean."
            let body = [
                header,
                """
                First: what are you trying to conceive?
                • A pregnancy this cycle
                • A clearer picture of timing, so sex isn't a calendar hostage
                • Something else you want to name
                """,
                ttc,
            ].joined(separator: "\n\n")
            return (body, [
                "A pregnancy this cycle",
                "Better timing literacy",
                "I'm not sure yet",
            ])
        case .difficultyConceiving:
            let body = [
                header,
                SexualHealthCurriculum.difficultyConceiving(),
                DifficultyConceivingGuide.copy.joined(separator: "\n\n"),
            ].joined(separator: "\n\n")
            return (body, [
                "When to see someone",
                "What I can do this month",
                "Specialists",
            ])
        }
    }
}

/// Literacy page for “it’s taking longer” — not a clinic, not a chat dump.
enum DifficultyConceivingGuide {
    struct Specialist: Equatable, Identifiable {
        var id: String { title }
        var title: String
        var when: String
    }

    static let specialists: [Specialist] = [
        Specialist(
            title: "OB-GYN / GP",
            when: "First stop for missing periods, very painful bleeding, or a check-in before the 6–12 month mark."
        ),
        Specialist(
            title: "Reproductive endocrinologist (REI)",
            when: "If you've been trying about 12 months under 35, or about 6 months at 35+, or you already know a relevant condition."
        ),
        Specialist(
            title: "Urology / andrology",
            when: "If sperm or a male partner's health is part of the picture — this is not only a 'female' workup."
        ),
        Specialist(
            title: "Fertility counselor",
            when: "For the emotional load. Wanting a child and waiting is not a character test."
        ),
    ]

    static let steps: [String] = [
        "Keep having sex you actually want. A calendar hostage is worse coaching than a slightly imperfect window.",
        "Sleep, alcohol, smoking, and very low body weight are the levers that show up in almost every clinical conversation — not because they are magic, because they are cheap to check.",
        "Keep logging bleeding, pain, and optional BBT / OPK. That pack is what you hand a clinician — Forge is not the clinician.",
        "Don't wait the full 12 / 6 months if periods are missing, bleeding is alarming, or pain is taking over the month. Go sooner.",
        "If conceiving involves two people's bodies, both people get evaluated. One-sided workups stall people.",
    ]

    static var copy: [String] {
        ["Options — literacy, not a diagnosis."]
            + steps
            + specialists.map { "\($0.title): \($0.when)" }
    }
}
