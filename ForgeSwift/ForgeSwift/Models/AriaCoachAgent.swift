import Foundation
import SwiftUI
import ForgeCore

/// Specialized personal coaches ARIA can bring in. One product, several agents —
/// not extra apps and not a game class.
///
/// The user can pin one. Otherwise a router picks from the message and from
/// what they actually live (readiness, cycle share). Cycle only appears when
/// they opted that data in.
enum AriaCoachAgent: String, Codable, CaseIterable, Identifiable {
    case aria
    case train
    case recover
    case fuel
    case life
    case cycle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .aria:    return "ARIA"
        case .train:   return "Train"
        case .recover: return "Recover"
        case .fuel:    return "Fuel"
        case .life:    return "Life"
        case .cycle:   return "Cycle"
        }
    }

    var roleLine: String {
        switch self {
        case .aria:    return "Your coach. Brings in a specialist when it helps."
        case .train:   return "Today’s session from how you slept and how ready you are."
        case .recover: return "Sleep, HRV, and when to keep it easy."
        case .fuel:    return "Meals, protein, water — enough to train, not a diet plan."
        case .life:    return "Work, travel, places, the rest of the day."
        case .cycle:   return "How to train and show up around a cycle. Never a chart."
        }
    }

    var icon: String {
        switch self {
        case .aria:    return "sparkles"
        case .train:   return "figure.strengthtraining.traditional"
        case .recover: return "moon.zzz.fill"
        case .fuel:    return "fork.knife"
        case .life:    return "leaf.fill"
        case .cycle:   return "heart.text.square.fill"
        }
    }

    var accent: Color {
        switch self {
        case .aria:    return .ember
        case .train:   return Color(hex: "FF5A00")
        case .recover: return Color(hex: "A855F7")
        case .fuel:    return Color(hex: "22C55E")
        case .life:    return Color(hex: "38BDF8")
        case .cycle:   return Color(hex: "F43F5E")
        }
    }

    /// Sent to `/ai/chat` so Bedrock wears this specialist, not a generic bot.
    var backendId: String { rawValue }

    /// On-device system law for local fallback. Cycle agent repeats the privacy line.
    var localDirective: String {
        switch self {
        case .aria:
            return "You are ARIA. Speak in second person. One next move."
        case .train:
            return "You are ARIA’s Train agent. Write today’s session from readiness. No XP, no quests."
        case .recover:
            return "You are ARIA’s Recover agent. Sleep and HRV first. Protect recovery when the numbers are soft."
        case .fuel:
            return "You are ARIA’s Fuel agent. Protein, water, the next meal. Not a calorie cop."
        case .life:
            return "You are ARIA’s Life agent. Training fits the day they already have."
        case .cycle:
            return """
            You are ARIA’s Cycle agent. Lifestyle coaching only — not medical care, not contraception. \
            Use cycle context only if they shared it with ARIA. Never invent fertility timing, flow, or symptoms. \
            If they asked how to support someone, coach the supporter, not the diary.
            """
        }
    }
}

/// One running specialist. Kinds are templates; workers are instances — a
/// question that names two people to support gets two Cycle workers, not one.
struct AriaCoachWorker: Equatable, Identifiable {
    let id: String
    let kind: AriaCoachAgent
    /// Who this instance is for, when it is not the user (a partner, a child).
    let subject: String?
    let isPrimary: Bool

    var label: String {
        if let subject, !subject.isEmpty { return "\(kind.label) · \(subject)" }
        return kind.label
    }
}

/// What to run for this turn. Unbounded: spawn every specialist the question
/// actually needs. Efficiency comes from *how* they run — one live model call
/// for the primary, cheap on-device briefs in parallel for the rest — not from
/// capping the roster.
struct AriaCoachPlan: Equatable {
    var workers: [AriaCoachWorker]

    var primary: AriaCoachWorker { workers.first(where: { $0.isPrimary }) ?? workers[0] }

    var kinds: [AriaCoachAgent] {
        var seen: [AriaCoachAgent] = []
        for worker in workers where !seen.contains(worker.kind) {
            seen.append(worker.kind)
        }
        return seen
    }

    var backendIds: [String] { kinds.map(\.backendId) }
}

enum AriaCoachAgentRouter {

    struct Context: Equatable {
        var pinned: AriaCoachAgent?
        var cycleAvailable: Bool
        /// Distinct people Cycle may coach around (self is omitted — empty
        /// subject). One worker per name so supporting two people does not
        /// flatten them through one lens.
        var cycleSubjects: [String] = []
    }

    /// Single-agent convenience. Prefer `plan` when a turn can use several.
    static func resolve(message: String, context: Context) -> AriaCoachAgent {
        plan(message: message, context: context).primary.kind
    }

    /// Spawn every specialist the message needs. No artificial cap.
    static func plan(message: String, context: Context) -> AriaCoachPlan {
        let lower = message.lowercased()
        var kinds: [AriaCoachAgent] = []

        func add(_ kind: AriaCoachAgent) {
            guard isAvailable(kind, context: context) else { return }
            if !kinds.contains(kind) { kinds.append(kind) }
        }

        if matches(lower, Self.cycleNeedles) { add(.cycle) }
        if matches(lower, Self.recoverNeedles) { add(.recover) }
        if matches(lower, Self.fuelNeedles) { add(.fuel) }
        if matches(lower, Self.lifeNeedles) { add(.life) }
        if matches(lower, Self.trainNeedles) { add(.train) }

        if let pinned = context.pinned, isAvailable(pinned, context: context) {
            add(pinned)
        }

        if kinds.isEmpty { kinds = [.aria] }

        let primaryKind: AriaCoachAgent = {
            if let pinned = context.pinned, kinds.contains(pinned) { return pinned }
            for preferred in [AriaCoachAgent.train, .recover, .cycle, .fuel, .life, .aria] {
                if kinds.contains(preferred) { return preferred }
            }
            return kinds[0]
        }()

        var workers: [AriaCoachWorker] = []
        for kind in kinds {
            if kind == .cycle, context.cycleAvailable, !context.cycleSubjects.isEmpty {
                for subject in context.cycleSubjects {
                    workers.append(
                        AriaCoachWorker(
                            id: "cycle-\(subject)",
                            kind: .cycle,
                            subject: subject,
                            isPrimary: primaryKind == .cycle && workers.allSatisfy { $0.kind != .cycle }
                        )
                    )
                }
            } else {
                workers.append(
                    AriaCoachWorker(
                        id: kind.rawValue,
                        kind: kind,
                        subject: nil,
                        isPrimary: kind == primaryKind && workers.allSatisfy { !$0.isPrimary }
                    )
                )
            }
        }
        if workers.allSatisfy({ !$0.isPrimary }), let idx = workers.firstIndex(where: { $0.kind == primaryKind }) {
            let current = workers[idx]
            workers[idx] = AriaCoachWorker(
                id: current.id, kind: current.kind, subject: current.subject, isPrimary: true
            )
        }
        return AriaCoachPlan(workers: workers)
    }

    /// The same plan, plus whatever the body and the session history argue for.
    ///
    /// `plan(message:context:)` is unchanged and still keyword-driven: it is
    /// tuned, it is covered by nineteen tests, and a clear sentence should
    /// route the same way forever. This wraps it rather than replacing it.
    ///
    /// What it adds is the case keywords cannot reach. Someone who says "hey"
    /// on three hours of sleep and 38 readiness is asking about recovery; the
    /// words contain nothing to match on, so the old path answered as a
    /// generalist and the data sat unread two feet away. `AriaIntentResolver`
    /// scores language *and* data *and* what this person keeps returning to,
    /// and anything it surfaces strongly enough joins the plan.
    ///
    /// Additive on purpose: this can add a specialist, never remove one. A
    /// router that silently drops the agent the user explicitly asked for is a
    /// worse failure than one that occasionally brings a spare.
    static func plan(
        message: String,
        context: Context,
        signals: AriaIntentInput
    ) -> AriaCoachPlan {
        let keywordPlan = plan(message: message, context: context)
        let ranked = AriaIntentResolver.rank(signals)
        let surfaced = AriaIntentResolver.actionable(ranked)

        var extras: [AriaCoachAgent] = []
        for domain in surfaced {
            guard let kind = Self.agent(for: domain) else { continue }
            guard isAvailable(kind, context: context) else { continue }
            guard !keywordPlan.kinds.contains(kind) else { continue }
            extras.append(kind)
        }
        guard !extras.isEmpty else { return keywordPlan }

        // A generalist-only plan means the keywords found nothing. In that case
        // the data's answer leads instead of tagging along behind `.aria`.
        var workers = keywordPlan.workers
        let keywordFoundNothing = keywordPlan.kinds == [.aria]
        if keywordFoundNothing {
            workers = []
        }
        for (index, kind) in extras.enumerated() {
            workers.append(
                AriaCoachWorker(
                    id: kind.rawValue,
                    kind: kind,
                    subject: nil,
                    isPrimary: keywordFoundNothing && index == 0
                )
            )
        }
        return AriaCoachPlan(workers: workers)
    }

    /// Intent domains are the resolver's vocabulary; coach agents are the
    /// product's. Several domains map onto one specialist — `.sleep` and
    /// `.readiness` are both Recover — and `.progress` has no specialist of its
    /// own, which is why this returns an optional rather than inventing one.
    static func agent(for domain: AriaIntentDomain) -> AriaCoachAgent? {
        switch domain {
        case .training:            return .train
        case .sleep, .readiness:   return .recover
        case .nutrition:           return .fuel
        case .lifestyle:           return .life
        case .cycle:               return .cycle
        case .body:                return .recover
        case .progress:            return nil
        }
    }

    static func isAvailable(_ agent: AriaCoachAgent, context: Context) -> Bool {
        if agent == .cycle { return context.cycleAvailable }
        return true
    }

    @MainActor
    static func cycleAvailable() -> Bool {
        let cycle = MenstrualHealthStore.shared
        if cycle.settings.enabled, cycle.settings.shareWithAria { return true }
        if cycle.consentedPeople.contains(where: { $0.settings.shareWithAria }) { return true }
        if !PartnerCycleSharing.shared.receivedDigests.isEmpty { return true }
        return false
    }

    @MainActor
    static func cycleSubjects() -> [String] {
        let cycle = MenstrualHealthStore.shared
        var names: [String] = []
        for person in cycle.consentedPeople where person.settings.shareWithAria {
            let name = person.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !names.contains(name) { names.append(name) }
        }
        for received in PartnerCycleSharing.shared.receivedDigests {
            let name = received.ownerName.split(separator: " ").first.map(String.init) ?? received.ownerName
            if !name.isEmpty, !names.contains(name) { names.append(name) }
        }
        return names
    }

    @MainActor
    static func context(pinned: AriaCoachAgent?) -> Context {
        Context(
            pinned: pinned,
            cycleAvailable: cycleAvailable(),
            cycleSubjects: cycleSubjects()
        )
    }

    /// Cheap on-device notes from supporting workers. Run in parallel so a
    /// five-agent turn does not wait five model calls.
    @MainActor
    static func supportingBriefs(plan: AriaCoachPlan, store: AppStore, primaryText: String) async -> [String] {
        let others = plan.workers.filter { !$0.isPrimary }
        guard !others.isEmpty else { return [] }
        return await withTaskGroup(of: String?.self, returning: [String].self) { group in
            for worker in others {
                group.addTask { @MainActor in
                    brief(for: worker, store: store, alreadySaid: primaryText)
                }
            }
            var lines: [String] = []
            for await line in group {
                if let line { lines.append(line) }
            }
            return lines
        }
    }

    @MainActor
    private static func brief(for worker: AriaCoachWorker, store: AppStore, alreadySaid: String) -> String? {
        let said = alreadySaid.lowercased()
        switch worker.kind {
        case .train:
            guard let session = store.todayWorkout else { return nil }
            let line = "\(session.name) · \(session.duration) min"
            if said.contains(session.name.lowercased()) { return nil }
            return "Train · \(line)"
        case .recover:
            let hours = store.dailyMetrics.totalSleep > 0
                ? String(format: "%.1fh sleep", Double(store.dailyMetrics.totalSleep) / 60.0)
                : nil
            let hrv = store.dailyMetrics.hrv > 0 ? "HRV \(store.dailyMetrics.hrv)ms" : nil
            let bits = [hours, hrv].compactMap { $0 }
            guard !bits.isEmpty else { return nil }
            return "Recover · \(bits.joined(separator: ", ")). You’re at \(store.readiness.overall)."
        case .fuel:
            return nil
        case .life:
            return nil
        case .cycle:
            let cycle = MenstrualHealthStore.shared
            if let subject = worker.subject, !subject.isEmpty {
                if let glance = PartnerSupportGlanceStore.load(),
                   glance.firstName.caseInsensitiveCompare(subject) == .orderedSame {
                    return "Cycle · \(subject): \(glance.lockScreenLine)"
                }
                return "Cycle · \(subject): show up, don’t diagnose."
            }
            guard cycle.settings.enabled, cycle.settings.shareWithAria,
                  let day = cycle.snapshot.dayInCycle else { return nil }
            let line = "Day \(day)"
            if said.contains("day \(day)") { return nil }
            return "Cycle · \(line)."
        case .aria:
            return nil
        }
    }

    private static let trainNeedles = [
        "workout", "session", "lift", "squat", "train today", "today's plan",
        "todays plan", "exercise", "gym", "run today", "what should i train",
    ]
    private static let recoverNeedles = [
        "sleep", "slept", "tired", "hrv", "recover", "sore", "rest day", "wind down",
        "can't sleep", "cant sleep", "insomnia",
    ]
    private static let fuelNeedles = [
        "eat", "food", "protein", "hungry", "meal", "water", "hydrat",
        "calories", "lunch", "dinner", "breakfast",
    ]
    private static let lifeNeedles = [
        "calendar", "busy", "travel", "workday", "restaurant", "free time",
        "places", "tonight's plan", "tonights plan",
    ]
    private static let cycleNeedles = [
        "period", "luteal", "follicular", "pms", "cramp", "cycle",
        "support her", "her period", "daughter", "how to show up", "show up",
    ]

    private static func matches(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
