import Foundation

/// Background Swarm: Grok-agentic read / evaluate / write over wearables.
///
/// When a chat turn starts, Swarm looks at WHOOP, Apple Watch, and Oura (RRA)
/// and writes one actionable picture. Claude still speaks. This file is the
/// on-device stand-in — no URLSession, no Bedrock, no off-device LLM — so
/// dummy and local testing can tune the agentic shape without a model.
public enum AriaSwarm {
    public static let name = "swarm"
    public static let slotName = "Grok"
    public static let stages = ["read", "evaluate", "write"]

    public static func canonicalSource(_ raw: String?) -> String? {
        let key = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        if key.isEmpty { return nil }
        if Self.canon[key] != nil { return Self.canon[key] }
        if key.contains("whoop") { return "whoop" }
        if key.contains("oura") || key == "rra" { return "oura" }
        if key.contains("garmin") { return "garmin" }
        if key.contains("watch") || key.contains("apple") || key.contains("healthkit") {
            return "apple-watch"
        }
        return nil
    }

    public static func sourceLabel(_ id: String) -> String {
        switch id {
        case "apple-watch": return "Apple Watch"
        case "whoop": return "WHOOP"
        case "oura": return "Oura"
        case "garmin": return "Garmin"
        default: return id
        }
    }

    public static func run(snapshot: AriaSwarmSnapshot) -> AriaSwarmPicture {
        let grouped = group(snapshot.samples)
        let reads = read(snapshot: snapshot, grouped: grouped)
        let agents = evaluate(reads)
        return write(agents: agents, reads: reads)
    }

    /// File Swarm writes into the knowledge ledger as inferences.
    @discardableResult
    public static func file(
        _ picture: AriaSwarmPicture,
        defaults: UserDefaults = .standard
    ) -> AriaKnowledgeLedger {
        var ledger = AriaKnowledgeLedgerStore.load(defaults: defaults)
        for item in picture.writes {
            ledger.file(AriaKnowledgeFact(
                category: .inferences,
                kind: item.kind,
                summary: item.summary,
                source: item.source.isEmpty ? name : item.source
            ))
        }
        AriaKnowledgeLedgerStore.save(ledger, defaults: defaults)
        return ledger
    }

    private static let canon: [String: String] = [
        "apple-watch": "apple-watch",
        "applewatch": "apple-watch",
        "watch": "apple-watch",
        "apple-health": "apple-watch",
        "applehealth": "apple-watch",
        "healthkit": "apple-watch",
        "whoop": "whoop",
        "oura": "oura",
        "rra": "oura",
        "garmin": "garmin",
    ]
}

public struct AriaSwarmSample: Equatable, Sendable {
    public var type: String
    public var source: String?

    public init(type: String, source: String? = nil) {
        self.type = type
        self.source = source
    }
}

public struct AriaSwarmSnapshot: Equatable, Sendable {
    public var sleepHours: Double?
    public var hrvMs: Double?
    public var readiness: Int?
    public var sleepDebtHours: Double?
    public var isOvertrained: Bool
    public var workoutLogged: Bool
    public var daysSinceWorkout: Int?
    public var trainingStreak: Int
    public var samples: [AriaSwarmSample]
    public var connected: [String]

    public init(
        sleepHours: Double? = nil,
        hrvMs: Double? = nil,
        readiness: Int? = nil,
        sleepDebtHours: Double? = nil,
        isOvertrained: Bool = false,
        workoutLogged: Bool = false,
        daysSinceWorkout: Int? = nil,
        trainingStreak: Int = 0,
        samples: [AriaSwarmSample] = [],
        connected: [String] = []
    ) {
        self.sleepHours = sleepHours
        self.hrvMs = hrvMs
        self.readiness = readiness
        self.sleepDebtHours = sleepDebtHours
        self.isOvertrained = isOvertrained
        self.workoutLogged = workoutLogged
        self.daysSinceWorkout = daysSinceWorkout
        self.trainingStreak = trainingStreak
        self.samples = samples
        self.connected = connected
    }

    public var sleepBand: String {
        guard let hours = sleepHours else { return "unknown" }
        if hours < 6.4 { return "thin" }
        if hours >= 7.4 { return "rebuilt" }
        return "decent"
    }

    public var recoveryBand: String {
        if isOvertrained { return "asking" }
        if let debt = sleepDebtHours, debt > 5 { return "asking" }
        guard let score = readiness else {
            return hrvMs == nil ? "unknown" : "steady"
        }
        if score < 50 { return "asking" }
        if score >= 75 { return "ready" }
        return "steady"
    }

    public var activityBand: String {
        if trainingStreak >= 3 { return "on_a_streak" }
        if workoutLogged || daysSinceWorkout == 0 { return "in_the_legs" }
        if let days = daysSinceWorkout, days >= 3 { return "fresh" }
        return "quiet"
    }
}

public struct AriaSwarmAgent: Equatable, Sendable {
    public var id: String
    public var kind: String
    public var source: String
    public var stance: String
    public var read: String
    public var evaluate: String
    public var write: String
    public var ops: [String]
}

public struct AriaSwarmWrite: Equatable, Sendable {
    public var kind: String
    public var summary: String
    public var source: String
    public var stance: String
}

public struct AriaSwarmSourceRead: Equatable, Sendable {
    public var id: String
    public var label: String
    public var present: Bool
    public var domains: [String]
}

public struct AriaSwarmPicture: Equatable, Sendable {
    public var name: String
    public var slotName: String
    public var agentic: Bool
    public var stages: [String]
    public var sources: [AriaSwarmSourceRead]
    public var agents: [AriaSwarmAgent]
    public var headline: String
    public var stance: String
    public var actions: [String]
    public var writes: [AriaSwarmWrite]
}

private let swarmSleepTypes: Set<String> = [
    "sleep", "sleep-stage", "sleep_duration", "sleep_deep", "sleep_rem",
    "sleep_light", "sleep_efficiency",
]
private let swarmRecoveryTypes: Set<String> = [
    "hrv", "hrv_sdnn", "recovery", "readiness", "resting-heart-rate", "resting_heart_rate",
]
private let swarmActivityTypes: Set<String> = [
    "steps", "active-calories", "active_energy", "distance", "exercise_minutes",
    "heart-rate", "heart_rate",
]
private let swarmMetricSource: [String: String] = [
    "sleep": "oura", "sleep-stage": "oura", "sleep_duration": "oura",
    "hrv": "whoop", "hrv_sdnn": "whoop", "recovery": "whoop",
    "resting-heart-rate": "apple-watch", "steps": "apple-watch",
    "active-calories": "apple-watch", "active_energy": "apple-watch",
]
private let swarmSourceDomains: [String: [String]] = [
    "oura": ["sleep"],
    "whoop": ["recovery"],
    "apple-watch": ["activity"],
    "garmin": ["activity", "recovery"],
]

private func swarmDomain(for metric: String) -> String? {
    let key = metric.lowercased().replacingOccurrences(of: "_", with: "-")
    let alt = metric.lowercased().replacingOccurrences(of: "-", with: "_")
    if swarmSleepTypes.contains(key) || swarmSleepTypes.contains(alt) { return "sleep" }
    if swarmRecoveryTypes.contains(key) || swarmRecoveryTypes.contains(alt) { return "recovery" }
    if swarmActivityTypes.contains(key) || swarmActivityTypes.contains(alt) { return "activity" }
    return nil
}

private func group(_ samples: [AriaSwarmSample]) -> [String: [String: Int]] {
    var grouped: [String: [String: Int]] = [:]
    for sample in samples {
        let metric = sample.type.lowercased().replacingOccurrences(of: "_", with: "-")
        let tagged = AriaSwarm.canonicalSource(sample.source)
        let source = tagged
            ?? swarmMetricSource[metric]
            ?? swarmMetricSource[sample.type.lowercased()]
        guard let source, let domain = swarmDomain(for: metric) else { continue }
        var bucket = grouped[source] ?? [:]
        bucket[domain, default: 0] += 1
        grouped[source] = bucket
    }
    return grouped
}

private func contextHas(domain: String, snapshot: AriaSwarmSnapshot) -> Bool {
    switch domain {
    case "sleep": return snapshot.sleepBand != "unknown"
    case "recovery": return snapshot.recoveryBand != "unknown"
    case "activity": return snapshot.activityBand != "quiet"
    default: return false
    }
}

private func band(for domain: String, snapshot: AriaSwarmSnapshot) -> String {
    switch domain {
    case "sleep": return snapshot.sleepBand
    case "recovery": return snapshot.recoveryBand
    default: return snapshot.activityBand
    }
}

private struct SwarmRead {
    var present: Bool
    var domains: [String]
    var notes: [String: String]
}

private func read(snapshot: AriaSwarmSnapshot, grouped: [String: [String: Int]]) -> [String: SwarmRead] {
    let hasSamples = !grouped.isEmpty
    var reads: [String: SwarmRead] = [:]
    for (source, domains) in swarmSourceDomains {
        var presentDomains: [String] = []
        var notes: [String: String] = [:]
        for domain in domains {
            let fromSamples = (grouped[source]?[domain] ?? 0) > 0
            let fromContext = contextHas(domain: domain, snapshot: snapshot)
            let inferred = fromContext && (fromSamples || !hasSamples)
            if fromSamples || inferred {
                presentDomains.append(domain)
                notes[domain] = band(for: domain, snapshot: snapshot)
            } else {
                notes[domain] = "missing"
            }
        }
        reads[source] = SwarmRead(present: !presentDomains.isEmpty, domains: presentDomains, notes: notes)
    }
    return reads
}

private func agentCopy(source: String, domain: String, note: String, present: Bool) -> AriaSwarmAgent {
    let label = AriaSwarm.sourceLabel(source)
    let stance: String
    let readLine: String
    let evaluate: String
    let write: String
    if !present || note == "missing" || note == "unknown" {
        stance = "missing"
        readLine = "\(label) has no \(domain) read in yet."
        evaluate = "Won't invent a \(domain) picture from \(label)."
        write = "Leave \(domain) open until \(label) lands."
    } else if domain == "sleep" {
        switch note {
        case "thin":
            stance = "caution"
            readLine = "\(label) has the night."
            evaluate = "The night ran thin, so today should protect tomorrow."
            write = "Protect sleep before adding load."
        case "rebuilt":
            stance = "go"
            readLine = "\(label) has the night."
            evaluate = "Sleep has been catching up — there is something to spend."
            write = "One honest session is on the table if recovery agrees."
        default:
            stance = "info"
            readLine = "\(label) has the night."
            evaluate = "Sleep is decent, not a story."
            write = "Keep the night in the picture; don't overclaim it."
        }
    } else if domain == "recovery" {
        switch note {
        case "asking":
            stance = "caution"
            readLine = "\(label) has recovery."
            evaluate = "The body is asking for care, not a lecture."
            write = "Keep today kind."
        case "ready":
            stance = "go"
            readLine = "\(label) has recovery."
            evaluate = "Recovery is steady enough for real work."
            write = "Train inside what the day already holds."
        default:
            stance = "info"
            readLine = "\(label) has recovery."
            evaluate = "Recovery is workable, not sharp."
            write = "Don't pick a fight with the day."
        }
    } else {
        switch note {
        case "in_the_legs", "on_a_streak":
            stance = "info"
            readLine = "\(label) logged movement."
            evaluate = "Last session is still in the legs."
            write = "Train if you want — don't pretend it didn't happen."
        case "fresh":
            stance = "go"
            readLine = "\(label) has activity."
            evaluate = "It's been a minute — the body can take real work if the night agrees."
            write = "A full session is allowed, not required."
        default:
            stance = "info"
            readLine = "\(label) has activity."
            evaluate = "Movement is quiet today."
            write = "Fit training into the day you already have."
        }
    }
    return AriaSwarmAgent(
        id: "\(source)-\(domain)",
        kind: domain,
        source: source,
        stance: stance,
        read: readLine,
        evaluate: evaluate,
        write: write,
        ops: AriaSwarm.stages
    )
}

private func evaluate(_ reads: [String: SwarmRead]) -> [AriaSwarmAgent] {
    var agents: [AriaSwarmAgent] = []
    for source in ["whoop", "apple-watch", "oura", "garmin"] {
        let info = reads[source] ?? SwarmRead(present: false, domains: [], notes: [:])
        if source == "garmin" && !info.present { continue }
        let domains = info.domains.isEmpty ? (swarmSourceDomains[source] ?? []) : info.domains
        for domain in domains {
            let note = info.notes[domain] ?? "missing"
            let present = info.present && info.domains.contains(domain)
            agents.append(agentCopy(source: source, domain: domain, note: note, present: present))
        }
    }
    return agents
}

private func write(agents: [AriaSwarmAgent], reads: [String: SwarmRead]) -> AriaSwarmPicture {
    let stances = agents.map(\.stance)
    let stance: String
    if stances.contains("caution") {
        stance = "protect"
    } else if !stances.isEmpty && stances.allSatisfy({ $0 == "missing" }) {
        stance = "clarify"
    } else {
        stance = "proceed"
    }
    let present = reads.compactMap { id, info -> AriaSwarmSourceRead? in
        AriaSwarmSourceRead(
            id: id,
            label: AriaSwarm.sourceLabel(id),
            present: info.present,
            domains: info.domains
        )
    }.sorted { $0.id < $1.id }
    let caution = agents.filter { $0.stance == "caution" }
    let go = agents.filter { $0.stance == "go" }
    let missing = agents.filter { $0.stance == "missing" }
    let headline: String
    if let first = caution.first {
        headline = first.evaluate
    } else if stance == "proceed", let first = go.first {
        headline = first.evaluate
    } else if !missing.isEmpty && present.allSatisfy({ !$0.present }) {
        headline = "No wearable picture is in yet, so I won't pretend I have a clean read."
    } else {
        headline = "I looked across the wearables you already have. One next move from there."
    }
    let actions: [String]
    switch stance {
    case "protect": actions = ["Keep it light today", "How did I sleep?"]
    case "clarify": actions = ["How did I sleep?", "What should I train?"]
    default: actions = ["What should I train?", "How did I sleep?"]
    }
    var writes: [AriaSwarmWrite] = [
        AriaSwarmWrite(kind: "swarm_picture", summary: headline, source: AriaSwarm.name, stance: stance)
    ]
    for agent in agents where agent.stance != "missing" {
        writes.append(AriaSwarmWrite(
            kind: "swarm_\(agent.kind)",
            summary: agent.write,
            source: agent.source,
            stance: agent.stance
        ))
    }
    return AriaSwarmPicture(
        name: AriaSwarm.name,
        slotName: AriaSwarm.slotName,
        agentic: true,
        stages: AriaSwarm.stages,
        sources: present.filter { $0.present || ["whoop", "apple-watch", "oura"].contains($0.id) },
        agents: agents,
        headline: headline,
        stance: stance,
        actions: actions,
        writes: writes
    )
}
