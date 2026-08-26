import Foundation

/// First conversation with ARIA. Dynamic: name, Health, goals, and yes/no
/// answers change what she says next. Runs once — the first time you open
/// this tab without having talked to her.
enum AriaFirstBond {

    static let storageKey = "forge.aria.firstBond.v2"
    static let openingID = "aria-bond-open"
    static let replyIDPrefix = "aria-bond-"

    enum Beat: String, Equatable {
        case opening
        case notDoctor
        case health
        case notGame
        case specialists
        case howToAsk
        case invite
        case done
    }

    enum Answer: Equatable {
        case yes
        case no
        case unsure
        case stay
        case seeHealth
        case leave
        case other

        static func parse(_ raw: String) -> Answer {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = t.lowercased()
            if lower.contains("come back") || lower.contains("not now")
                || lower.contains("look around") || lower == "later" {
                return .leave
            }
            if lower.contains("did you see") || lower.contains("what did you")
                || (lower.contains("health") && (lower.contains("see") || lower.contains("what"))) {
                return .seeHealth
            }
            if ["i’m here", "i'm here", "i am here", "hi", "hey", "hello", "stay"].contains(lower) {
                return .stay
            }
            if ["yes", "yes.", "yeah", "yep", "yup", "ok", "okay", "okay.", "fair",
                "true", "right", "sounds right", "sound right", "i get it",
                "got it", "work for me", "works", "agreed"].contains(lower) {
                return .yes
            }
            if ["no", "no.", "nope", "nah", "not really", "wrong", "no thanks"].contains(lower) {
                return .no
            }
            if lower.contains("not sure") || lower == "maybe" || lower == "kind of"
                || lower == "kinda" || lower.contains("don't know") || lower.contains("dont know") {
                return .unsure
            }
            if lower.hasPrefix("yes") { return .yes }
            if lower.hasPrefix("no") { return .no }
            return .other
        }
    }

    struct Context: Equatable {
        var name: String
        var snapshot: AriaFirstHealthBriefing.Snapshot
        var goal: String?
        var cycleAvailable: Bool
    }

    struct Turn: Equatable {
        var message: String
        var replies: [String]
        var next: Beat
        var finishes: Bool { next == .done }
    }

    static let yesNo = ["Yes.", "No.", "Not sure."]
    static let stayReplies = ["I’m here.", "What did you actually see?", "Not now."]
    static let inviteReplies = [
        "How did I sleep?",
        "What should I train?",
        "How do I show up?",
        "I’ll come back.",
    ]

    static func start(_ context: Context) -> Turn {
        turn(for: .opening, answer: .stay, context: context, isOpening: true)
    }

    static func advance(beat: Beat, userText: String, context: Context) -> Turn {
        let answer = Answer.parse(userText)
        if answer == .leave {
            return farewell(context)
        }
        if shouldHandoffToCoach(userText) {
            return Turn(message: "", replies: [], next: .done)
        }
        return turn(for: beat, answer: answer, context: context, isOpening: false)
    }

    /// Real coaching — leave the hello and let her work.
    static func shouldHandoffToCoach(_ text: String) -> Bool {
        let answer = Answer.parse(text)
        if answer != .other { return false }
        let lower = text.lowercased()
        let needles = [
            "sleep", "slept", "train", "workout", "show up", "period",
            "eat", "hungry", "protein", "tired", "hrv", "sore",
        ]
        return needles.contains { lower.contains($0) } || text.count > 48
    }

    static func isBondMessageID(_ id: String) -> Bool {
        id == openingID || id.hasPrefix(replyIDPrefix)
    }

    // MARK: - Beats

    private static func turn(
        for beat: Beat,
        answer: Answer,
        context: Context,
        isOpening: Bool
    ) -> Turn {
        let you = firstName(context.name)
        switch beat {
        case .opening:
            if isOpening {
                return opening(context)
            }
            if answer == .seeHealth {
                return healthCiteThenCheck(context)
            }
            return checkNotDoctor(you: you, preface: stayPreface(you: you, answer: answer))

        case .notDoctor:
            let preface: String
            switch answer {
            case .yes:
                preface = you.isEmpty
                    ? "Good. That line stays clean."
                    : "Good, \(you). That line stays clean."
            case .no:
                preface = "I can still help you live the day — sleep, training, showing up. I just won’t diagnose, treat, or play doctor. That’s the deal."
            default:
                preface = "Simple version: lifestyle coaching, not medical care. If something needs a clinician, I say so."
            }
            return checkHealth(context, preface: preface)

        case .health:
            let preface: String
            switch answer {
            case .yes:
                if let learned = AriaFirstHealthBriefing.learnedLine(context.snapshot) {
                    preface = "Then we’re aligned. Right now: \(learned)"
                } else {
                    preface = "Then we’re aligned. When Health is thin, I’ll say I don’t have it."
                }
            case .no:
                preface = "Then I’ll be extra plain when the data is missing. I would rather say “I don’t know that night” than invent one."
            default:
                preface = "If I have last night, I use it. If I don’t, I tell you. No fake precision."
            }
            return checkNotGame(you: you, preface: preface)

        case .notGame:
            let preface: String
            switch answer {
            case .yes:
                preface = "That’s why this tab can feel quiet. That’s on purpose."
            case .no:
                preface = "There’s no quest log and no XP for talking to me. You’re not grinding a character. You’re living a day."
            default:
                preface = "Think coach, not campaign. No levels. No loot."
            }
            return checkSpecialists(context, preface: preface)

        case .specialists:
            let preface: String
            switch answer {
            case .yes:
                preface = "You’ll see their names when they join a turn. You still talk to me."
            case .no:
                preface = "You never pick a class. You ask. I bring Train, Recover, Fuel, or Life if the question needs them."
                    + (context.cycleAvailable ? " Cycle only because you shared that." : " Cycle stays off until you share it.")
            default:
                preface = "One conversation. Extra hands only when useful."
            }
            return checkHowToAsk(you: you, preface: preface)

        case .howToAsk:
            let preface: String
            switch answer {
            case .yes:
                preface = you.isEmpty ? "Let’s use it." : "Let’s use it, \(you)."
            case .no:
                preface = "You can still ramble. I’ll pull the one true thing out. Shorter is kinder to both of us."
            default:
                preface = "Try it anyway. One sentence is enough."
            }
            return invite(context, preface: preface)

        case .invite, .done:
            return farewell(context)
        }
    }

    private static func opening(_ context: Context) -> Turn {
        let you = firstName(context.name)
        var lines: [String] = []
        lines.append(you.isEmpty ? "Hey. I’m ARIA." : "\(you). I’m ARIA.")
        lines.append("I’m going to be in this tab with you — not a help article, not a quest log.")
        if context.snapshot.fromHealthKit, let learned = AriaFirstHealthBriefing.learnedLine(context.snapshot) {
            lines.append("I just read Apple Health on this phone. \(learned)")
            lines.append("That’s the first true thing between us. I don’t know the rest of you yet.")
        } else {
            lines.append("I don’t have your Health yet, so I won’t pretend I do.")
        }
        if let goal = context.goal, !goal.isEmpty {
            lines.append("You mentioned \(goal.lowercased()). We’ll get there — not as a dump on day one.")
        }
        lines.append("Before we go: a few yes-or-no so we’re the same person. Stay?")
        return Turn(message: lines.joined(separator: "\n\n"), replies: stayReplies, next: .opening)
    }

    private static func stayPreface(you: String, answer: Answer) -> String {
        switch answer {
        case .stay, .yes:
            return you.isEmpty ? "Good. I like that we started honest." : "Good, \(you). I like that we started honest."
        default:
            return "We’ll keep this short."
        }
    }

    private static func healthCiteThenCheck(_ context: Context) -> Turn {
        let seen = AriaFirstHealthBriefing.learnedLine(context.snapshot)
            ?? "I connected, but the night is still thin — I’ll learn as Health fills in."
        let preface = "\(seen)\n\nThat’s our starting ground. I won’t invent the rest."
        return checkNotDoctor(you: firstName(context.name), preface: preface)
    }

    private static func checkNotDoctor(you: String, preface: String) -> Turn {
        Turn(
            message: """
            \(preface)

            I’m a lifestyle coach, not a doctor. If something needs a clinician, that’s not me. Fair?
            """,
            replies: yesNo,
            next: .notDoctor
        )
    }

    private static func checkHealth(_ context: Context, preface: String) -> Turn {
        let extra = context.snapshot.fromHealthKit
            ? " I already pulled what this phone has."
            : " Connect Health when you can — until then I’ll say when I’m guessing."
        return Turn(
            message: """
            \(preface)

            I read Apple Health. I don’t invent your night.\(extra) Work for you?
            """,
            replies: yesNo,
            next: .health
        )
    }

    private static func checkNotGame(you: String, preface: String) -> Turn {
        Turn(
            message: """
            \(preface)

            This isn’t a game. No XP for chatting. You’re not grinding a character. Okay?
            """,
            replies: yesNo,
            next: .notGame
        )
    }

    private static func checkSpecialists(_ context: Context, preface: String) -> Turn {
        let cycle = context.cycleAvailable
            ? " Cycle too, because you shared that."
            : " Cycle stays out until you share it."
        return Turn(
            message: """
            \(preface)

            You talk to me. I bring in Train, Recover, Fuel, Life when a question needs them.\(cycle) You don’t pick a class. Sound right?
            """,
            replies: yesNo,
            next: .specialists
        )
    }

    private static func checkHowToAsk(you: String, preface: String) -> Turn {
        Turn(
            message: """
            \(preface)

            Best way to use me: one true sentence. “I slept badly and I have forty minutes.” Not a search box. Want to try that?
            """,
            replies: yesNo,
            next: .howToAsk
        )
    }

    private static func invite(_ context: Context, preface: String) -> Turn {
        let you = firstName(context.name)
        let close = you.isEmpty ? "Ask me something true." : "Ask me something true, \(you)."
        return Turn(
            message: """
            \(preface)

            \(close) Sleep, training, how you show up — I’ll stay with it. Or come back later. This tab is ours.
            """,
            replies: inviteReplies,
            next: .invite
        )
    }

    private static func farewell(_ context: Context) -> Turn {
        let you = firstName(context.name)
        return Turn(
            message: you.isEmpty ? "I’ll be here. This tab is ours." : "I’ll be here, \(you). This tab is ours.",
            replies: [],
            next: .done
        )
    }

    private static func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? ""
    }
}

enum AriaUseOnboarding {
    static let storageKey = AriaFirstBond.storageKey
    static let tryPrompts = AriaFirstBond.inviteReplies
}
