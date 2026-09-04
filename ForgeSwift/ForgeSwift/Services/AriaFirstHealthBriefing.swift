import Foundation

/// What ARIA says the first time Forge reads Apple Health — and whenever
/// someone asks who she is. Built from HealthKit numbers, not a canned demo.
enum AriaFirstHealthBriefing {

    struct Snapshot: Equatable {
        var sleepHours: Double?
        var sleepScore: Int?
        var hrvMs: Int?
        var restingHR: Int?
        var readiness: Int?
        var steps: Int?
        var lastWorkoutName: String?
        var fromHealthKit: Bool
    }

    struct Result: Equatable {
        var message: String
        var actions: [String]
    }

    static let suggestedActions = [
        "Who are you?",
        "How did I sleep?",
        "What should I train?",
        "How do I show up?",
    ]

    @MainActor
    static func snapshot(from store: AppStore) -> Snapshot {
        let night = store.sleepData.first
        let sleepHours = night?.totalHours
            ?? (store.dailyMetrics.totalSleep > 0 ? Double(store.dailyMetrics.totalSleep) / 60 : nil)
        return Snapshot(
            sleepHours: sleepHours,
            sleepScore: night?.score,
            hrvMs: store.dailyMetrics.hrv > 0 ? store.dailyMetrics.hrv : nil,
            restingHR: store.dailyMetrics.restingHR > 0 ? store.dailyMetrics.restingHR : nil,
            readiness: store.readiness.overall > 0 ? store.readiness.overall : nil,
            steps: store.dailyMetrics.steps > 0 ? store.dailyMetrics.steps : nil,
            lastWorkoutName: store.workoutHistory.first?.name,
            fromHealthKit: store.healthKitLive || store.usingTestReadyHealthPack
        )
    }

    static func isIdentityQuestion(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "who are you", "who're you", "what are you", "what can you do",
            "what do you do", "what is aria", "what's aria", "whats aria",
            "introduce yourself", "tell me about yourself", "help",
            "what is this", "what can aria",
        ]
        return needles.contains { lower.contains($0) }
    }

    /// Spoken right after the user taps Connect Apple Health.
    static func onboardingConnectedLine(snapshot: Snapshot) -> String {
        let learned = learnedLine(snapshot)
        if snapshot.fromHealthKit, let learned {
            return "Apple Health is connected — first time Forge is reading this phone. \(learned) That’s enough for me to coach from, not guess."
        }
        if snapshot.fromHealthKit {
            return "Apple Health is connected — first time Forge is reading this phone. I’ll keep pulling sleep, heart, and activity while we finish."
        }
        return "Apple Health connected. Pulling sleep, heart rate, and activity in the background while we finish."
    }

    static func identityShort() -> String {
        "I’m ARIA, your lifestyle coach. I bring in Workout, Recovery, Sleep, Lifestyle, and Progress when a question needs them. Cycle only if you share that with me. I’m not a doctor."
    }

    static func welcome(name: String, healthConnected: Bool, snapshot: Snapshot) -> Result {
        let you = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hi = you.isEmpty ? "Hey." : "Hey \(you)."
        var lines: [String] = [hi]

        if healthConnected {
            lines.append("I just connected to Apple Health for the first time on this phone.")
            if let learned = learnedLine(snapshot) {
                lines.append(learned)
            }
            lines.append("That’s me learning you from Health — not a made-up profile.")
        } else {
            lines.append("Connect Apple Health anytime and I’ll fold sleep, heart, and activity into every call.")
        }

        lines.append("")
        lines.append(identityBody())
        lines.append("")
        lines.append("Ask me how you slept, what to train, or how to show up. I’ll bring in whoever the question needs.")

        return Result(message: lines.joined(separator: "\n"), actions: suggestedActions)
    }

    static func identityAnswer(name: String, snapshot: Snapshot) -> Result {
        let you = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        if !you.isEmpty {
            lines.append("\(you) — I’m ARIA.")
        } else {
            lines.append("I’m ARIA.")
        }
        lines.append(identityBody())
        if let learned = learnedLine(snapshot) {
            lines.append("")
            lines.append("From Apple Health right now: \(learned)")
        }
        lines.append("Ask a real question and I’ll bring in the specialist it needs.")
        return Result(message: lines.joined(separator: "\n"), actions: suggestedActions)
    }

    static func identityBody() -> String {
        """
        I’m a lifestyle coach inside Forge, not a game and not a clinic. One of me, several specialists:

        • Workout — today’s session from how you slept and how ready you are
        • Recovery — when to keep it easy, and whether last night paid you back
        • Sleep — last night, tonight’s setup, the trend behind it
        • Lifestyle — work, travel, food and water, the day you already have
        • Progress — the trend behind the numbers, not just today’s reading
        • Cycle — how to train or show up around a cycle, only if you share that with me

        I read Apple Health. I don’t invent fertility charts. I don’t diagnose.
        """
    }

    /// A companion sentence from the first Health read — never a field dump.
    /// Numbers stay in Sleep / Stats. This is what a friend would say after
    /// looking at last night, not what a HUD would print.
    static func learnedLine(_ snapshot: Snapshot) -> String? {
        var bits: [String] = []

        if let hours = snapshot.sleepHours, hours > 0 {
            let score = snapshot.sleepScore ?? 0
            if hours >= 7.0 && score >= 80 {
                bits.append("Last night actually rebuilt you")
            } else if hours >= 6.5 && (score == 0 || score >= 60) {
                bits.append("Last night was decent — not extra, not empty")
            } else {
                bits.append("Last night ran thinner than I'd like")
            }
        }

        if let ready = snapshot.readiness, ready > 0 {
            switch ready {
            case 80...: bits.append("you're in a place you can spend")
            case 55..<80: bits.append("you're in a workable place")
            default: bits.append("your system's still catching up")
            }
        } else if let hrv = snapshot.hrvMs, hrv > 0 {
            if hrv < 40 { bits.append("your system's still catching up") }
            else if hrv >= 55 { bits.append("recovery is holding") }
        }

        if let workout = snapshot.lastWorkoutName, !workout.isEmpty {
            bits.append("last session was \(workout)")
        }

        guard !bits.isEmpty else { return nil }
        if bits.count == 1 { return bits[0] + "." }
        return bits[0] + " — " + bits.dropFirst().joined(separator: ", ") + "."
    }

    static func learnInsights(snapshot: Snapshot) -> [String] {
        var insights: [String] = []
        if snapshot.fromHealthKit {
            insights.append("Apple Health first connect — Forge is reading this phone.")
        }
        if let learned = learnedLine(snapshot) {
            insights.append(learned)
        }
        return insights
    }

    static func fingerprint(_ snapshot: Snapshot) -> String {
        [
            snapshot.sleepHours.map { String(format: "%.1f", $0) } ?? "-",
            snapshot.hrvMs.map(String.init) ?? "-",
            snapshot.readiness.map(String.init) ?? "-",
        ].joined(separator: "|")
    }
}
