import Foundation

/// On-device Test-Ready ARIA. Same idea as SimRunner's dummy orchestra:
/// synthetic/local numbers, as many specialist workers as the turn needs,
/// no AWS, no Mac localhost. This is what Xcode Device Hub runs.
@MainActor
enum AriaDummyOrchestrator {

    static func reply(
        text: String,
        store: AppStore,
        agent: AriaCoachAgent
    ) -> AriaResponse {
        let first = store.userProfile.name.split(separator: " ").first.map(String.init) ?? ""
        let you = first.isEmpty ? "You’re" : "\(first), you’re"
        let r = store.readiness.overall
        let sleepMin = store.dailyMetrics.totalSleep
        let hrv = store.dailyMetrics.hrv
        let sleepLine: String = {
            guard sleepMin > 0 else { return "I don’t have last night’s sleep on this phone yet" }
            return "last night was \(sleepMin / 60)h \(sleepMin % 60)m"
        }()
        let hrvLine = hrv > 0 ? "HRV \(hrv)ms" : "no HRV yet"

        let prose: String
        switch agent {
        case .recover:
            prose = "\(you) at \(r). \(sleepLine.prefix(1).uppercased() + sleepLine.dropFirst()). \(hrvLine). Keep today easy."
        case .train:
            if let session = store.todayWorkout {
                prose = "\(you) at \(r). Train · \(displaySessionName(session.name)), \(session.duration) min · \(session.intensity.label)."
            } else {
                prose = "\(you) at \(r). I’ll write a session from how you live — no production model on this Device Hub run."
            }
        case .fuel:
            prose = "\(you) at \(r). Fuel · protein and water next. Not a diet plan."
        case .life:
            prose = "\(you) at \(r). Fit training into the day you already have."
        case .cycle:
            prose = "\(you) at \(r). Cycle coaching on this phone only — no log leaves the device, no fertility calendar."
        case .aria:
            prose = "\(you) at \(r). \(sleepLine). Test-ready ARIA on this device — not a production instance."
        }

        return AriaResponse(
            confidenceReason: "Test-ready dummy on this device. SimRunner-shaped. No cloud.",
            proseSummary: prose,
            message: prose,
            suggestedActions: ["What should I train?", "How did I sleep?", "How do I show up?"],
            confidence: 0.74
        )
    }
}
