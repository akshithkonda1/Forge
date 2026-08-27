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
        let snapshot = AriaFirstHealthBriefing.snapshot(from: store)
        if AriaFirstHealthBriefing.isIdentityQuestion(text) {
            let identity = AriaFirstHealthBriefing.identityAnswer(name: first, snapshot: snapshot)
            return AriaResponse(
                confidenceReason: store.usingTestReadyHealthPack
                    ? "Test-ready dummy. HealthKit on this simulator (ForgeCore pack). No cloud."
                    : "Test-ready dummy on this device. SimRunner-shaped. No cloud.",
                proseSummary: identity.message,
                message: identity.message,
                suggestedActions: identity.actions,
                confidence: 0.9
            )
        }

        let you = first.isEmpty ? "You’re" : "\(first), you’re"
        let r = store.readiness.overall
        let sleepMin = store.dailyMetrics.totalSleep
        let hrv = store.dailyMetrics.hrv
        let night = store.sleepData.first
        let sleepLine: String = {
            if let night {
                return String(format: "last night was %.1fh, score %d", night.totalHours, night.score)
            }
            guard sleepMin > 0 else { return "I don’t have last night’s sleep on this phone yet" }
            return "last night was \(sleepMin / 60)h \(sleepMin % 60)m"
        }()
        let hrvLine = hrv > 0 ? "HRV \(hrv)ms" : "no HRV yet"
        let packNote = store.usingTestReadyHealthPack
            ? " Numbers came from HealthKit on this simulator (Test-Ready pack)."
            : ""

        let prose: String
        switch agent {
        case .recover:
            prose = "\(you) at \(r). \(sleepLine.prefix(1).uppercased() + sleepLine.dropFirst()). \(hrvLine). Keep today easy.\(packNote)"
        case .train:
            if let session = store.todayWorkout {
                prose = "\(you) at \(r). Train · \(displaySessionName(session.name)), \(session.duration) min · \(session.intensity.label).\(packNote)"
            } else {
                prose = "\(you) at \(r). I’ll write a session from how you live — no production model on this Device Hub run."
            }
        case .sleep:
            prose = "\(you) at \(r). \(sleepLine.prefix(1).uppercased() + sleepLine.dropFirst()).\(packNote)"
        case .life:
            prose = "\(you) at \(r). Fit training into the day you already have — protein and water next, not a diet plan.\(packNote)"
        case .progress:
            prose = "\(you) at \(r). Zooming out on trend, not just today — no production model on this Device Hub run.\(packNote)"
        case .cycle:
            prose = "\(you) at \(r). Cycle coaching on this phone only — no log leaves the device, no fertility calendar."
        case .aria:
            prose = "\(you) at \(r). \(sleepLine). \(hrvLine). Test-ready ARIA on this device — not a production instance.\(packNote)"
        }

        return AriaResponse(
            confidenceReason: store.usingTestReadyHealthPack
                ? "Test-ready dummy. HealthKit on this simulator (ForgeCore pack). No cloud."
                : "Test-ready dummy on this device. SimRunner-shaped. No cloud.",
            proseSummary: prose,
            message: prose,
            suggestedActions: AriaFirstHealthBriefing.suggestedActions,
            confidence: 0.74
        )
    }
}
