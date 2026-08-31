import Foundation
import ForgeCore

/// Domains a local turn can be about.
///
/// Names mirror `ALL_DOMAINS` in `backend/infra/lambda/services/aria_engine.py`
/// so a tally read here means the same thing it means there — even though this
/// state never leaves the device. `cycle` is the one addition: the local
/// dispatch has `isCycleQuery` and the backend tuple has no equivalent, so it
/// is marked rather than folded into `body` and quietly mixed with injuries.
enum AriaLocalDomain: String, CaseIterable {
    case sleep
    case readiness
    case activity
    case training
    case chronotype
    case body
    case nutrition
    case profile
    case progress
    case lifestyle
    case clinicalData = "clinical_data"
    case cycle

    var spokenName: String {
        switch self {
        case .clinicalData: return "your records"
        case .cycle:        return "your cycle"
        case .body:         return "how your body's holding up"
        case .readiness:    return "your energy"
        default:            return rawValue
        }
    }
}

/// Which model slot a turn would route to in production.
///
/// Mirrors `default_models()` in `backend/infra/lambda/ai_router.py`, which
/// defines three slots: a fast primary responder, a fallback/verifier, and a
/// third that pressure-tests edge cases. Local testing never calls any of them
/// — it reports the routing it *would* have taken, so a tester sees the same
/// decision production would make.
///
/// Note the tertiary name here is Grok by instruction, while the backend's
/// slot-3 default is still `moonshotai.kimi-k2.5`. The slot is env-overridable
/// (`AI_ROUTER_MODEL_3_ID` / `_NAME`), so nothing is wrong in the client — but
/// the two disagree until that env is set, and a label that quietly lies about
/// which model answered is worse than no label.
enum AriaModelTier: String {
    case primary
    case secondary
    case tertiary

    var slot: Int {
        switch self {
        case .primary:   return 1
        case .secondary: return 2
        case .tertiary:  return 3
        }
    }

    var displayName: String {
        switch self {
        case .primary:   return "Claude Sonnet 4.6"
        case .secondary: return "Claude Opus 4.7"
        case .tertiary:  return "Grok"
        }
    }

    /// Typical turns run on data plus the primary and secondary models. Agentic
    /// work — a mode spawning its own specialists and subagents to solve
    /// something the single-pass path cannot — calls in the tertiary.
    static func route(workerCount: Int, hasSubagents: Bool) -> AriaModelTier {
        if workerCount > 1 || hasSubagents { return .tertiary }
        return .primary
    }
}

/// On-device ARIA for testing: stateful across a session, no network to
/// Forge's own cloud.
///
/// This wraps `RuleBasedResponseGenerator`/`FoundationModelsResponseGenerator`
/// and `AriaVoiceEngine` rather than reimplementing any of them. The keyword
/// dispatch in `RuleBasedResponseGenerator.generateResponse` already is a
/// domain agent per area ARIA covers; what it has never been is *stateful* —
/// every turn starts from nothing, so ARIA cannot notice you have asked about
/// sleep four times, and cannot remember you told it about a bad knee. That
/// memorylessness, not the phrasing, is what makes a local session feel canned.
///
/// The other half of "canned": until now this hardcoded `RuleBasedResponseGenerator`
/// for the actual prose, even on a device where Apple Intelligence is available
/// and `AppStore` was already correctly preferring `FoundationModelsResponseGenerator`
/// for the exact same job. A template dispatcher was answering every real
/// message in production (`AriaOperatingMode.current` never leaves
/// `.localTesting` anywhere in this codebase) while a real on-device model sat
/// unused two files away. Fixed below: same preference `AppStore` already
/// applies, no network required either way — Foundation Models runs fully
/// on-device.
///
/// Deliberately holds no `URLSession`, no `baseURL`, and no reference to
/// `AriaService`'s transport — this orchestrator itself never calls Forge's
/// own backend. That is checkable by grep, and it should stay checkable.
///
/// The one intentional exception: `reply()` can call out to
/// `AriaWebResearch`, a separate, clearly-named collaborator whose entire
/// job is a curated, keyless fetch from a handful of general (non-Forge)
/// reference URLs — gated to local testing, isolated in its own file so
/// this file's own "no network" grep stays literally true.
@MainActor
final class LocalTestingOrchestrator {

    static let shared = LocalTestingOrchestrator()

    // MARK: - Session state

    /// Running per-domain tally. The point of keeping it is the *second* thing
    /// it enables: once a domain dominates, ARIA can raise it unprompted.
    private(set) var affinity: [AriaLocalDomain: Int] = [:]

    /// Turns exchanged this session.
    private(set) var exchanges: Int = 0

    /// Offline mirror of the backend's `relationship_level`
    /// (`CoachContextEngine.UserContext`), which the frontend otherwise never
    /// reads. 1–10, same range, so the two are comparable when the live path
    /// lands.
    var familiarity: Int { min(10, 1 + exchanges / 3) }

    /// What the user has told us about themselves this session. Recall, not
    /// comprehension — which is most of what "it remembers me" reads as from
    /// the outside.
    private(set) var facts: [FactKey: String] = [:]

    enum FactKey: String, CaseIterable {
        case limitation   // "bad knee", "shoulder's been off"
        case goal         // "training for a half marathon"
        case schedule     // "I work nights"
        case equipment    // "no gym this week"
    }

    /// Domain classification (`.domain(of:)`) is a `RuleBasedResponseGenerator`-
    /// specific method, not part of `TrainerResponseGenerator` — every turn
    /// needs it for affinity tracking/recall regardless of which generator
    /// below actually writes the reply, so it stays a fixed, separate instance.
    private let domainClassifier = RuleBasedResponseGenerator()

    /// The actual prose generator. Prefers on-device Apple Intelligence via
    /// `FoundationModelsResponseGenerator` — the same preference `AppStore`
    /// already applies for every other ARIA surface — falling back to
    /// `RuleBasedResponseGenerator` only where Foundation Models isn't
    /// available. Neither call touches Forge's own network.
    private let generator: TrainerResponseGenerator
    private let usingFoundationModels: Bool

    /// Re-derived per session so a tester does not see identical phrasing every
    /// launch. `AriaSeededRNG` is the same generator the voice layer uses.
    private var seed: UInt64

    private init() {
        seed = Self.freshSeed()
        #if canImport(FoundationModels)
        let foundationModelsGenerator = FoundationModelsResponseGenerator()
        if foundationModelsGenerator.isAvailable {
            generator = foundationModelsGenerator
            usingFoundationModels = true
        } else {
            generator = domainClassifier
            usingFoundationModels = false
        }
        #else
        generator = domainClassifier
        usingFoundationModels = false
        #endif
    }

    /// Call on login / session start.
    func resetForNewSession() {
        affinity = [:]
        exchanges = 0
        facts = [:]
        seed = Self.freshSeed()
    }

    static func freshSeed() -> UInt64 {
        var value = UInt64(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1_000))
        value ^= UInt64(truncatingIfNeeded: UUID().hashValue)
        return value == 0 ? 0x9E37_79B9_7F4A_7C15 : value
    }

    // MARK: - Reply

    func reply(
        to text: String,
        store: AppStore,
        agent: AriaCoachAgent = .aria,
        agents: [String]? = nil
    ) async throws -> AriaResponse {
        // The 5-mode structure is not rebuilt here. `AppStore+Chat` already
        // runs `AriaCoachAgentRouter.plan` for every turn, spawns a worker per
        // specialist the message needs (and one per subject for cycle, which is
        // what a subagent is), and appends their briefs after this returns.
        // All of that happens in local testing too. What was missing is that
        // this orchestrator threw the routing away and answered as a generalist,
        // so a tester saw none of it.
        let routed = agents ?? [agent.backendId]
        let tier = AriaModelTier.route(
            workerCount: routed.count,
            hasSubagents: routed.count > 1
        )

        await simulateThinking(tier: tier)

        let domain = domainClassifier.domain(of: text)
        affinity[domain, default: 0] += 1
        captureFacts(from: text)
        exchanges += 1

        // Checked before anything is generated. Familiarity, mode and tone all
        // sit below this: a coach who has known you for forty turns still does
        // not get to answer a question about chest pain with a training tweak.
        let guidance = AriaGuidancePolicy.decide(text: text)
        if guidance.band == .referOut, let line = guidance.line {
            return AriaResponse(
                confidenceReason: "Local testing — outside coaching scope, referred out.",
                proseSummary: line,
                message: line,
                richCard: nil,
                suggestedActions: nil,
                contextUpdates: nil,
                confidence: 1.0
            )
        }

        var context = store.makeTrainerContext()
        // Feed session depth into the voice layer. `AriaVoiceEngine` infers
        // relationship level from `totalMessageCount` and folds the same number
        // into its phrasing salt, so this both deepens and rotates the voice.
        //
        // Note it does *not* travel through `profile.relationshipLevel`: that
        // field is set on the profile and read by nothing in beat generation
        // today, so gating on it would have been silently inert. The gating
        // that actually changes output lives below.
        context.totalMessageCount = max(context.totalMessageCount, exchanges * 4)

        let base = try await generator.generateResponse(for: text, context: context)

        var rng = AriaSeededRNG(seed: seed &+ UInt64(exchanges))
        var parts: [String] = [base.content]

        if let recall = recallBeat(for: domain, rng: &rng) {
            parts.append(recall)
        }
        if let crossover = affinityBeat(excluding: domain, rng: &rng) {
            parts.append(crossover)
        }
        // Wired: when the human is asking for outside knowledge, reach the
        // Mac's internet and blend the note humanly — feels connected, not cited.
        var usedWeb = false
        if AriaWebResearch.isResearchWorthy(text: text, leadingDomain: domain),
           let webNote = await AriaWebResearch.lookUp(domain: domain) {
            // Human blend, not a footnote dump
            let bridge = rng.pick([
                "Pulled this live so it's not just me:",
                "Checked against the outside so you get more than my take:",
                "Quick live pull — here's the outside line:",
            ])
            let landing = rng.pick([
                "Now, for you specifically —",
                "Here's how that lands with your numbers —",
                "For your context —",
            ])
            parts.append("\(bridge)\n\(webNote)\n\(landing)")
            usedWeb = true
        }

        let specialists = routed.count > 1
            ? "\(agent.label) + \(routed.count - 1) specialist\(routed.count - 1 == 1 ? "" : "s")"
            : agent.label
        let engine = usingFoundationModels ? "on-device model" : "on-device rules"

        let wiredTag = usedWeb ? " · live web (Mac) ✓" : ""
        return AriaResponse(
            confidenceReason: "Local testing — \(specialists) · \(engine) · slot "
                + "\(tier.slot) (\(tier.displayName)) · no cloud\(wiredTag) · familiarity \(familiarity)/10.",
            proseSummary: base.content,
            message: parts.joined(separator: "\n\n"),
            richCard: nil,
            suggestedActions: base.suggestedActions,
            contextUpdates: ["relationship_level": familiarity],
            confidence: base.confidence
        )
    }

    // MARK: - Simulated thinking

    /// Instant replies are the single biggest tell that something is canned
    /// rather than considered, so the wait is real even though the work is not
    /// — *when* the work isn't real. `FoundationModelsResponseGenerator` runs
    /// genuine on-device inference with its own real latency; stacking this
    /// synthetic delay on top of that would just make an honest wait feel
    /// sluggish for no reason, so it's skipped in that case.
    private func simulateThinking(tier: AriaModelTier) async {
        guard !usingFoundationModels else { return }
        var rng = AriaSeededRNG(seed: seed &+ UInt64(exchanges &* 7 &+ 1))
        // Agentic turns fan out to several specialists before anything comes
        // back, so they take visibly longer. A local mode where the hard
        // question returns as fast as "hey" is the tell that nothing fanned out.
        let range = tier == .tertiary ? 1_600..<3_200 : 800..<2_000
        let milliseconds = rng.int(in: range)
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    // MARK: - Fact capture

    /// Keyword capture, not parsing. Overbuilding this into an NLP layer would
    /// buy accuracy nobody testing the app would notice, and cost the clarity
    /// that makes a wrong recall obvious when it happens.
    private func captureFacts(from text: String) {
        let lower = text.lowercased()

        for joint in ["knee", "shoulder", "back", "hip", "ankle", "wrist", "elbow", "neck"] {
            let hurts = ["bad \(joint)", "\(joint) pain", "\(joint) hurts", "my \(joint) is",
                         "hurt my \(joint)", "sore \(joint)", "\(joint) injury"]
            if hurts.contains(where: { lower.contains($0) }) {
                facts[.limitation] = joint
                break
            }
        }

        for marker in ["training for", "prepping for", "signed up for", "working toward"] {
            guard let range = lower.range(of: marker) else { continue }
            let tail = lower[range.upperBound...]
                .prefix(40)
                .trimmingCharacters(in: .whitespaces)
            let goal = tail.split(whereSeparator: { ".,!?;".contains($0) }).first.map(String.init) ?? tail
            if !goal.isEmpty { facts[.goal] = goal }
            break
        }

        if lower.contains("work nights") || lower.contains("night shift") || lower.contains("graveyard") {
            facts[.schedule] = "night shifts"
        } else if lower.contains("early shift") || lower.contains("up at 4") || lower.contains("up at 5") {
            facts[.schedule] = "early starts"
        }

        if lower.contains("no gym") || lower.contains("gym is closed") || lower.contains("traveling")
            || lower.contains("hotel room") {
            facts[.equipment] = "no gym"
        } else if lower.contains("only dumbbells") || lower.contains("just dumbbells")
            || lower.contains("home gym") {
            facts[.equipment] = "dumbbells at home"
        }
    }

    // MARK: - Stateful beats

    /// Recall is gated on familiarity because a coach who quotes you back on the
    /// first exchange sounds like it is reading a form, not listening.
    private func recallBeat(for domain: AriaLocalDomain, rng: inout AriaSeededRNG) -> String? {
        guard familiarity >= 2 else { return nil }

        if let joint = facts[.limitation], domain == .training || domain == .body {
            return rng.pick([
                "Keeping that \(joint) in mind — nothing here should load it badly.",
                "I've still got the \(joint) on file. Say the word if it flares and we reshape this.",
                "Working around the \(joint), same as before.",
            ])
        }
        if let goal = facts[.goal], domain == .training || domain == .progress {
            return rng.pick([
                "This still points at \(goal).",
                "All of it feeds \(goal) — that's the thread I'm pulling.",
            ])
        }
        if let schedule = facts[.schedule], domain == .sleep || domain == .readiness {
            return rng.pick([
                "Reading this against \(schedule), not a nine-to-five — the timing matters more than the total.",
                "With \(schedule) in the mix, I'd judge consistency over any single night.",
            ])
        }
        if let equipment = facts[.equipment], domain == .training {
            return rng.pick([
                "Built for \(equipment), since that's where you are.",
                "Kept it to \(equipment).",
            ])
        }
        return nil
    }

    /// Once a domain dominates a session, raise it unprompted. Threshold is
    /// three so a passing mention does not turn ARIA into a single-subject bore.
    private func affinityBeat(excluding current: AriaLocalDomain, rng: inout AriaSeededRNG) -> String? {
        guard familiarity >= 3 else { return nil }
        guard rng.chance(0.4) else { return nil }

        let dominant = affinity
            .filter { $0.key != current && $0.value >= 3 }
            .max(by: { $0.value < $1.value })?
            .key
        guard let dominant else { return nil }

        return rng.pick([
            "You keep circling back to \(dominant.spokenName). Want to just take that apart properly?",
            "Noticing \(dominant.spokenName) comes up a lot with you — worth a real look when you've got the patience.",
            "That's the third time \(dominant.spokenName) has come up. I don't think it's incidental.",
        ])
    }
}
