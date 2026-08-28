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
    case workout
    case recovery
    case sleep
    case lifestyle
    case progress
    case cycle

    var id: String { rawValue }

    /// The five acts ARIA tracks and, when pinned, focuses specifically on —
    /// exactly what the user named, matching `TabItem.workout`/`.lifestyle`'s
    /// real case names rather than the abbreviated UI shortLabels ("Train",
    /// "Life") this used before. `.aria` is the generalist/no-pin state
    /// (already covered by "Auto" in the pin UI). Recovery has no page of
    /// its own — its content surfaces inside the Lifestyle tab rather than a
    /// dedicated top-level destination — but it stays one of the five
    /// pinnable/tracked modes; that's a UI-placement decision, not a
    /// demotion from the five acts the user consistently names it among.
    /// `.cycle` is the one that's genuinely outside the five: consent-gated,
    /// reachable by name or by the settings picker, never a headline mode.
    static let trackedModes: [AriaCoachAgent] = [.workout, .lifestyle, .sleep, .progress, .recovery]

    var label: String {
        switch self {
        case .aria:      return "ARIA"
        case .workout:   return "Workout"
        case .recovery:  return "Recovery"
        case .sleep:     return "Sleep"
        case .lifestyle: return "Lifestyle"
        case .progress:  return "Progress"
        case .cycle:     return "Cycle"
        }
    }

    var roleLine: String {
        switch self {
        case .aria:      return "Your coach. Brings in a specialist when it helps."
        case .workout:   return "Today’s session from how you slept and how ready you are."
        case .recovery:  return "HRV, soreness, and whether today’s a push day or an easy one."
        case .sleep:     return "Sleep debt, consistency, and what last night actually cost you."
        case .lifestyle: return "Work, travel, meals, water — training fits the day you already have."
        case .progress:  return "Trends over weeks, not today’s snapshot — streaks, PRs, what’s actually moving."
        case .cycle:     return "How to train and show up around a cycle. Never a chart."
        }
    }

    var icon: String {
        switch self {
        case .aria:      return "sparkles"
        case .workout:   return "figure.strengthtraining.traditional"
        case .recovery:  return "moon.zzz.fill"
        case .sleep:     return "bed.double.fill"
        case .lifestyle: return "leaf.fill"
        case .progress:  return "chart.line.uptrend.xyaxis"
        case .cycle:     return "heart.text.square.fill"
        }
    }

    var accent: Color {
        switch self {
        case .aria:      return .ember
        case .workout:   return Color(hex: "FF5A00")
        case .recovery:  return Color(hex: "A855F7")
        case .sleep:     return Color(hex: "6366F1")
        case .lifestyle: return Color(hex: "38BDF8")
        case .progress:  return Color(hex: "F59E0B")
        case .cycle:     return Color(hex: "F43F5E")
        }
    }

    /// Sent to `/ai/chat` so Bedrock wears this specialist, not a generic bot.
    /// These raw values are also the keys in the backend's `COACH_AGENTS`
    /// dict (`services/aria_engine.py`) — the two must stay in lockstep, or
    /// the backend silently falls every renamed agent back to generic
    /// "aria" (`normalize_coach_agent`'s unknown-key behavior) rather than
    /// erroring, which is exactly the kind of drift this whole effort is
    /// about eliminating.
    var backendId: String { rawValue }

    /// On-device system law for local fallback. Cycle agent repeats the privacy line.
    var localDirective: String {
        switch self {
        case .aria:
            return "You are ARIA. Speak in second person. One next move."
        case .workout:
            return "You are ARIA’s Workout agent. Write today’s session from readiness. No XP, no quests."
        case .recovery:
            return "You are ARIA’s Recovery agent. HRV and soreness first. Protect recovery when the numbers are soft."
        case .sleep:
            return "You are ARIA’s Sleep agent. Debt, consistency, and bedtime — not just last night’s number."
        case .lifestyle:
            return "You are ARIA’s Lifestyle agent. Training and meals both fit the day they already have. Not a calorie cop."
        case .progress:
            return "You are ARIA’s Progress agent. Zoom out — weeks, not today. Streaks, trends, what’s actually changing."
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
        /// Soft fallback from the tab the user is actually on, used only when
        /// nothing else matched — never overrides an explicit pin or a
        /// keyword hit. Pinning stays sacrosanct: someone who pinned Recovery
        /// and taps into Progress to check a number should not have their
        /// pin silently reinterpreted by navigation alone.
        var tabHint: AriaCoachAgent? = nil
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
        if matches(lower, Self.recoveryNeedles) { add(.recovery) }
        if matches(lower, Self.sleepNeedles) { add(.sleep) }
        if matches(lower, Self.lifestyleNeedles) { add(.lifestyle) }
        if matches(lower, Self.progressNeedles) { add(.progress) }
        if matches(lower, Self.workoutNeedles) { add(.workout) }

        if let pinned = context.pinned, isAvailable(pinned, context: context) {
            add(pinned)
        }

        if kinds.isEmpty {
            // Nothing pinned, nothing matched by keyword: fall back to the
            // tab the user is actually on rather than the bare generalist,
            // so an ambiguous "hey" on the Sleep tab gets a Sleep-flavored
            // answer instead of a generic one.
            if let hint = context.tabHint, isAvailable(hint, context: context) {
                kinds = [hint]
            } else {
                kinds = [.aria]
            }
        }

        let primaryKind: AriaCoachAgent = {
            if let pinned = context.pinned, kinds.contains(pinned) { return pinned }
            for preferred in [AriaCoachAgent.workout, .recovery, .sleep, .cycle, .progress, .lifestyle, .aria] {
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
            let kind = Self.agent(for: domain)
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
    /// product's. `.sleep` and `.readiness` used to both collapse onto
    /// Recover — now that Sleep is its own specialist, every domain maps
    /// onto a real agent, so this is total rather than partial.
    static func agent(for domain: AriaIntentDomain) -> AriaCoachAgent {
        switch domain {
        case .training:  return .workout
        case .sleep:     return .sleep
        case .readiness: return .recovery
        case .nutrition: return .lifestyle
        case .lifestyle: return .lifestyle
        case .cycle:     return .cycle
        case .body:      return .recovery
        case .progress:  return .progress
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
    static func context(pinned: AriaCoachAgent?, activeTab: TabItem? = nil) -> Context {
        Context(
            pinned: pinned,
            cycleAvailable: cycleAvailable(),
            cycleSubjects: cycleSubjects(),
            tabHint: activeTab.flatMap(Self.tabHint(for:))
        )
    }

    /// The specialist a tab maps to for routing purposes, when it has one.
    /// Home/ARIA/Profile have no natural specialist and stay nil so an
    /// ambiguous message there still falls back to the generalist.
    static func tabHint(for tab: TabItem) -> AriaCoachAgent? {
        switch tab {
        case .workout:   return .workout
        case .lifestyle: return .lifestyle
        case .sleep:     return .sleep
        case .progress:  return .progress
        case .home, .chat, .profile: return nil
        }
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

    /// A read first, then the numbers — and only sometimes the numbers. Same
    /// discipline `AriaVoiceEngine.statusLine` was rewritten to this session:
    /// a raw field dump ("HRV 48, sleep 6.8h") states nothing, it just
    /// reports; a coach who has actually looked at the data says what it
    /// means. Each specialist correlates two or more of its own signals into
    /// one statement rather than listing them, and cites the underlying
    /// numbers only some of the time (`rng.chance`), so a five-specialist
    /// turn doesn't read as five parallel data dumps.
    @MainActor
    private static func brief(for worker: AriaCoachWorker, store: AppStore, alreadySaid: String) -> String? {
        let said = alreadySaid.lowercased()
        var rng = AriaSeededRNG(seed: briefSeed(for: worker))
        switch worker.kind {
        case .workout:
            guard let session = store.todayWorkout else { return nil }
            let line = "\(session.name) · \(session.duration) min"
            if said.contains(session.name.lowercased()) { return nil }
            return "Workout · \(line)"
        case .recovery:
            let hrv = store.dailyMetrics.hrv
            guard hrv > 0 else { return nil }
            let r = store.readiness.overall
            let read: String
            switch r {
            case ..<40:   read = "your nervous system needs the day off"
            case 40..<55: read = "you're still catching up"
            case 55..<70: read = "workable, not sharp"
            default:      read = "you're clear to push"
            }
            let line = "Recovery · \(read.prefix(1).uppercased() + read.dropFirst())."
            return rng.chance(0.4) ? "\(line) HRV \(hrv)ms, readiness \(r)." : line
        case .sleep:
            // EnergySchedule already turns rolling sleep history into a
            // plain-language debt headline ("Square on sleep" / "2.3 hours
            // of sleep debt") — reused rather than reimplemented, same as
            // the deleted AriaResearchBrief used to.
            guard let debt = EnergySchedule.make(from: store.sleepData)?.debtHeadline else { return nil }
            guard !said.contains(debt.lowercased()) else { return nil }
            return "Sleep · \(debt)"
        case .lifestyle:
            guard let tag = AriaContextStore.shared.context.lifestyleTags.first else { return nil }
            guard !said.contains(tag.lowercased()) else { return nil }
            return rng.pick([
                "Lifestyle · \(tag) today — a fast protein hit beats skipping the next meal.",
                "Lifestyle · \(tag) today. Water and the next meal still count, even on a day like this.",
            ])
        case .progress:
            var bits: [String] = []
            if store.currentStreak >= 3 {
                bits.append("a \(store.currentStreak)-day streak")
            }
            if let recentPR = store.personalRecords.sorted(by: { $0.date > $1.date }).first {
                bits.append("a PR on \(recentPR.exercise)")
            }
            guard !bits.isEmpty else { return nil }
            let joined = bits.count > 1 ? bits.joined(separator: " and ") : bits[0]
            return "Progress · You’ve got \(joined) going — that’s the trend that matters, not any one session."
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

    /// Seeded from the worker + today's date, not a session-scoped seed —
    /// brief() runs identically on both the local and live-backend paths,
    /// so it can't depend on LocalTestingOrchestrator's session state.
    private static func briefSeed(for worker: AriaCoachWorker) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(worker.id)
        hasher.combine(Calendar.current.startOfDay(for: Date()))
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private static let workoutNeedles = [
        "workout", "session", "lift", "squat", "train today", "today's plan",
        "todays plan", "exercise", "gym", "run today", "what should i train",
    ]
    // Mirrors AriaIntentResolver.keywords[.readiness] — sleep-specific terms
    // (below) moved out to their own needle list rather than staying here,
    // once Sleep became its own specialist instead of sharing Recovery.
    private static let recoveryNeedles = [
        "hrv", "recover", "sore", "rest day", "tired", "exhausted", "drained",
    ]
    // Mirrors AriaIntentResolver.keywords[.sleep].
    private static let sleepNeedles = [
        "sleep", "slept", "rest", "bed", "wind down", "can't sleep",
        "cant sleep", "insomnia", "nap",
    ]
    // Fuel folded into Lifestyle: nutrition terms join the lifestyle ones
    // rather than staying a separate specialist.
    private static let lifestyleNeedles = [
        "eat", "food", "protein", "hungry", "meal", "water", "hydrat",
        "calories", "lunch", "dinner", "breakfast",
        "calendar", "busy", "travel", "workday", "restaurant", "free time",
        "places", "tonight's plan", "tonights plan",
    ]
    // Mirrors AriaIntentResolver's .progress phrases/keywords.
    private static let progressNeedles = [
        "progress", "gains", "stronger", "streak", "improving", "plateau",
        "getting stronger", "how am i progressing", "is this working",
    ]
    private static let cycleNeedles = [
        "period", "luteal", "follicular", "pms", "cramp", "cycle",
        "support her", "her period", "daughter", "how to show up", "show up",
    ]

    private static func matches(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
