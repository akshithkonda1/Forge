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
            lines.append("Connect Apple Health anytime and I’ll fold sleep, HRV, and activity into every call.")
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
        • Recovery — HRV, sleep debt, when to keep it easy
        • Sleep — last night, tonight’s setup, the trend behind it
        • Lifestyle — work, travel, food and water, the day you already have
        • Progress — the trend behind the numbers, not just today’s reading
        • Cycle — how to train or show up around a cycle, only if you share that with me

        I read Apple Health. I don’t invent fertility charts. I don’t diagnose.
        """
    }

    static func learnedLine(_ snapshot: Snapshot) -> String? {
        var bits: [String] = []
        if let hours = snapshot.sleepHours {
            var sleep = String(format: "last night %.1fh", hours)
            if let score = snapshot.sleepScore { sleep += ", score \(score)" }
            bits.append(sleep)
        }
        if let hrv = snapshot.hrvMs { bits.append("HRV \(hrv)ms") }
        if let rhr = snapshot.restingHR { bits.append("resting HR \(rhr)") }
        if let ready = snapshot.readiness { bits.append("readiness \(ready)") }
        if let steps = snapshot.steps { bits.append("\(steps) steps so far") }
        if let workout = snapshot.lastWorkoutName { bits.append("last session \(workout)") }
        guard !bits.isEmpty else { return nil }
        let joined = bits.joined(separator: ". ")
        return joined.hasSuffix(".") ? joined : joined + "."
    }

    static func learnInsights(snapshot: Snapshot) -> [String] {
        var insights: [String] = []
        if snapshot.fromHealthKit {
            insights.append("Apple Health first connect — Forge is reading this phone.")
        }
        if let learned = learnedLine(snapshot) {
            insights.append("HealthKit: \(learned)")
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
