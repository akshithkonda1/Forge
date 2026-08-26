import Foundation

/// First-run guide for the ARIA tab — how to talk to her, not another
/// profile interview. Completes once, replayable from Settings.
enum AriaUseOnboardingStep: Int, CaseIterable, Equatable {
    case meet
    case ask
    case specialists
    case health
    case tryIt
}

struct AriaUseOnboardingPage: Equatable {
    var step: AriaUseOnboardingStep
    var title: String
    var body: String
    var symbol: String
}

enum AriaUseOnboarding {
    static let storageKey = "forge.aria.useOnboarding.v1"

    static let tryPrompts = AriaFirstHealthBriefing.suggestedActions

    static func pages(
        name: String,
        snapshot: AriaFirstHealthBriefing.Snapshot
    ) -> [AriaUseOnboardingPage] {
        let you = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hello = you.isEmpty ? "I’m ARIA." : "\(you) — I’m ARIA."
        let healthBody: String = {
            if snapshot.fromHealthKit, let learned = AriaFirstHealthBriefing.learnedLine(snapshot) {
                return "You connected Apple Health. \(learned)\n\nAsk about sleep or training and I’ll use that — not a generic plan."
            }
            if snapshot.fromHealthKit {
                return "Apple Health is connected. I’ll keep learning from sleep, HRV, and activity. The more that’s in Health, the less I guess."
            }
            return "Connect Apple Health when you can. Sleep, HRV, and activity are how I learn you. Without them I can still talk — I just can’t personalize."
        }()

        return [
            AriaUseOnboardingPage(
                step: .meet,
                title: hello,
                body: "I live in this tab. I’m your lifestyle coach — sleep, training, food, the day you already have.\n\nI read Apple Health. I don’t diagnose. I’m not a game.",
                symbol: "sparkles"
            ),
            AriaUseOnboardingPage(
                step: .ask,
                title: "Talk like a coach",
                body: "Plain sentences. One question. Name the constraint.\n\n• How did I sleep?\n• I have 40 minutes and my knee is sore.\n• How do I show up for her this week?\n\nSkip quest language. Don’t ask me for medical care.",
                symbol: "text.bubble.fill"
            ),
            AriaUseOnboardingPage(
                step: .specialists,
                title: "I bring people in",
                body: "You talk to me. I spawn whoever the question needs:\n\nTrain · today’s session from sleep and readiness\nRecover · HRV, rest, when to keep it easy\nFuel · protein and water, not a diet\nLife · work, travel, the day you have\nCycle · only if you shared that with me\n\nPin one in Settings, or leave Auto.",
                symbol: "person.3.fill"
            ),
            AriaUseOnboardingPage(
                step: .health,
                title: "Health is how I learn you",
                body: healthBody,
                symbol: "heart.text.square.fill"
            ),
            AriaUseOnboardingPage(
                step: .tryIt,
                title: "Try one",
                body: "Pick a question. That’s the fastest way to see me work — I’ll answer from Health and bring in the right specialist.",
                symbol: "arrow.up.message.fill"
            ),
        ]
    }
}
