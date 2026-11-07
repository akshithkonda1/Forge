import Foundation

/// One HealthKit-derived reading after it has been named, before ARIA
/// or BodyModel see it. Values stay on this device.
public struct HealthIngestSample: Equatable, Sendable, Codable {
    public var metric: HealthIngestMetric
    public var value: Double
    public var unit: String
    public var start: Date
    public var end: Date?
    public var source: String
    public var workoutType: String?

    public init(
        metric: HealthIngestMetric,
        value: Double,
        unit: String,
        start: Date,
        end: Date? = nil,
        source: String,
        workoutType: String? = nil
    ) {
        self.metric = metric
        self.value = value
        self.unit = unit
        self.start = start
        self.end = end
        self.source = source
        self.workoutType = workoutType
    }

    public var windowEnd: Date { end ?? start }
    public var duration: TimeInterval { windowEnd.timeIntervalSince(start) }
}

public enum HealthIngestMetric: String, Codable, Sendable, CaseIterable {
    case sleep
    case hrv
    case restingHR
    case steps
    case workout
    case workoutHR
    case activeCalories
}

/// Why a sample was kept or dropped. ARIA reads this so she can say
/// "Watch won over Oura for steps" instead of double-counting.
public struct HealthIngestDecision: Equatable, Sendable, Codable {
    public var kept: HealthIngestSample
    public var dropped: [HealthIngestSample]
    public var reason: String

    public init(kept: HealthIngestSample, dropped: [HealthIngestSample], reason: String) {
        self.kept = kept
        self.dropped = dropped
        self.reason = reason
    }
}

/// Apple Health source priority for steps / sleep / HR. Lower index wins.
/// Workouts use overlap-merge, then this list as the tie-break.
public enum HealthSourcePriority: Sendable {
    public static let ranked: [String] = [
        "apple-watch", "apple-health", "oura", "whoop", "garmin",
        "strava", "runna", "polar", "fitbit", "ultrahuman", "withings",
    ]

    public static func rank(_ source: String) -> Int {
        let key = canonicalize(source)
        return ranked.firstIndex(of: key) ?? ranked.count
    }

    public static func canonicalize(_ raw: String) -> String {
        let key = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        if key.contains("apple-watch") || key.contains("watch") { return "apple-watch" }
        if key.contains("apple") || key.contains("healthkit") { return "apple-health" }
        if key.contains("oura") { return "oura" }
        if key.contains("whoop") { return "whoop" }
        if key.contains("garmin") { return "garmin" }
        if key.contains("strava") { return "strava" }
        if key.contains("runna") { return "runna" }
        return key
    }

    public static func preferred(_ a: HealthIngestSample, _ b: HealthIngestSample) -> HealthIngestSample {
        let ra = rank(a.source)
        let rb = rank(b.source)
        if ra != rb { return ra < rb ? a : b }
        // Same rank: keep the longer window / richer workout.
        if a.duration != b.duration { return a.duration >= b.duration ? a : b }
        return a.start <= b.start ? a : b
    }
}

/// On-device learner: this user's duplication patterns. Online means and
/// counts only — no tokens, no cloud, no Core ML binary. Rules stay the
/// floor; the learner only tightens the near-duplicate window when a
/// source pair has been seen often enough.
public struct HealthIngestLearner: Equatable, Sendable, Codable {
    public static let defaultsKey = "forge.healthIngest.learner.v1"
    public static let currentSchemaVersion = 1

    public struct Pair: Equatable, Sendable, Codable {
        public var count: Int
        public var meanOffsetSeconds: Double
        public var gapCount: Int

        public init(count: Int = 0, meanOffsetSeconds: Double = 0, gapCount: Int = 0) {
            self.count = count
            self.meanOffsetSeconds = meanOffsetSeconds
            self.gapCount = gapCount
        }

        public mutating func observeOffset(_ seconds: Double) {
            count += 1
            meanOffsetSeconds += (seconds - meanOffsetSeconds) / Double(count)
        }

        public mutating func observeGap() {
            gapCount += 1
        }
    }

    public var schemaVersion: Int
    public var pairs: [String: Pair]

    public init(schemaVersion: Int = currentSchemaVersion, pairs: [String: Pair] = [:]) {
        self.schemaVersion = schemaVersion
        self.pairs = pairs
    }

    public static func pairKey(_ a: String, _ b: String) -> String {
        [HealthSourcePriority.canonicalize(a), HealthSourcePriority.canonicalize(b)].sorted().joined(separator: "|")
    }

    /// Default near-dup window is 90s. After 3+ overlaps for a pair, use
    /// the learned offset plus a 30s pad, never looser than 4 minutes.
    public func nearDuplicateWindow(sourceA: String, sourceB: String) -> TimeInterval {
        let key = Self.pairKey(sourceA, sourceB)
        guard let pair = pairs[key], pair.count >= 3 else { return 90 }
        return min(240, max(45, abs(pair.meanOffsetSeconds) + 30))
    }

    public mutating func recordOverlap(winner: String, loser: String, offsetSeconds: Double) {
        let key = Self.pairKey(winner, loser)
        var pair = pairs[key] ?? Pair()
        pair.observeOffset(offsetSeconds)
        pairs[key] = pair
    }

    public mutating func recordRecurringGap(source: String, field: String) {
        let key = "gap:\(HealthSourcePriority.canonicalize(source)):\(field)"
        var pair = pairs[key] ?? Pair()
        pair.observeGap()
        pairs[key] = pair
    }

    public func summary() -> String {
        let overlaps = pairs.filter { !$0.key.hasPrefix("gap:") && $0.value.count > 0 }
        let gaps = pairs.filter { $0.key.hasPrefix("gap:") && $0.value.gapCount > 0 }
        if overlaps.isEmpty && gaps.isEmpty {
            return "No learned duplication patterns yet."
        }
        var bits: [String] = []
        for (key, pair) in overlaps.sorted(by: { $0.key < $1.key }) {
            bits.append("\(key) overlaps \(pair.count)×, typical offset \(Int(pair.meanOffsetSeconds.rounded()))s")
        }
        for (key, pair) in gaps.sorted(by: { $0.key < $1.key }) {
            bits.append("\(key) missing \(pair.gapCount)×")
        }
        return bits.joined(separator: "; ")
    }

    public static func load(defaults: UserDefaults = .standard) -> HealthIngestLearner {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(HealthIngestLearner.self, from: data) else {
            return HealthIngestLearner()
        }
        return decoded
    }

    public static func save(_ state: HealthIngestLearner, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

public struct HealthCanonicalBatch: Equatable, Sendable {
    public var samples: [HealthIngestSample]
    public var decisions: [HealthIngestDecision]
    public var scout: HealthScoutReport
    public var learnerSummary: String

    public init(
        samples: [HealthIngestSample],
        decisions: [HealthIngestDecision],
        scout: HealthScoutReport,
        learnerSummary: String
    ) {
        self.samples = samples
        self.decisions = decisions
        self.scout = scout
        self.learnerSummary = learnerSummary
    }

    public var ariaTags: [String] {
        scout.ariaTags + ["ingest:dedup:\(decisions.count)"]
    }
}

/// HealthKit batch → dedup → Health Scout (gaps + re-gather) → clean
/// canonical batch for ARIA / BodyModel. Never fetches a network, never
/// invents a value.
public enum HealthIngestLayer: Sendable {

    public static let downsampleStride: TimeInterval = 60

    public static func process(
        incoming: [HealthIngestSample],
        connectedSources: [String],
        expected: Set<HealthIngestMetric>,
        day: Date,
        learner: HealthIngestLearner,
        reGather: (HealthScoutGap) -> [HealthIngestSample]
    ) -> (HealthCanonicalBatch, HealthIngestLearner) {
        var state = learner
        let (deduped, decisions) = dedup(incoming, learner: state)
        for decision in decisions where !decision.dropped.isEmpty {
            for lost in decision.dropped {
                let offset = decision.kept.start.timeIntervalSince(lost.start)
                state.recordOverlap(winner: decision.kept.source, loser: lost.source, offsetSeconds: offset)
            }
        }

        var working = deduped
        var workingDecisions = decisions
        let want = expected.union(
            HealthScout.expectedMetrics(connectedSources: connectedSources, samples: working)
        )
        let firstReport = HealthScout.inspect(
            samples: working,
            connectedSources: connectedSources,
            expected: want,
            day: day
        )

        var filled: [HealthScoutGap] = []
        for gap in firstReport.gaps where gap.status == .missing {
            let extra = reGather(gap).filter { $0.value > 0 && $0.value.isFinite }
            if extra.isEmpty {
                filled.append(gap)
                continue
            }
            let merged = working + extra
            let pass = dedup(merged, learner: state)
            working = pass.samples
            workingDecisions.append(contentsOf: pass.decisions)
            filled.append(HealthScoutGap(
                field: gap.field,
                day: gap.day,
                expectedSource: gap.expectedSource,
                status: .filledFromHealthKit,
                note: "Re-gathered \(gap.field) from HealthKit (\(extra[0].source))."
            ))
        }

        let permanent = firstReport.gaps.filter { $0.status == .permanent }
        for gap in permanent {
            if let source = gap.expectedSource {
                state.recordRecurringGap(source: source, field: gap.field)
            }
        }
        for gap in filled where gap.status == .missing {
            if let source = gap.expectedSource {
                state.recordRecurringGap(source: source, field: gap.field)
            }
        }

        let scout = HealthScoutReport(
            gaps: permanent + filled,
            reGatherAttempted: firstReport.gaps.filter { $0.status == .missing }.map(\.field),
            connectedSources: connectedSources
        )

        let batch = HealthCanonicalBatch(
            samples: working.sorted { $0.start < $1.start },
            decisions: workingDecisions,
            scout: scout,
            learnerSummary: state.summary()
        )
        return (batch, state)
    }

    public static func dedup(
        _ incoming: [HealthIngestSample],
        learner: HealthIngestLearner
    ) -> (samples: [HealthIngestSample], decisions: [HealthIngestDecision]) {
        let trimmed = downsample(incoming)
        var groups: [[HealthIngestSample]] = []

        for sample in trimmed.sorted(by: { $0.start < $1.start }) {
            if let index = groups.firstIndex(where: { clusterOverlaps($0, sample, learner: learner) }) {
                groups[index].append(sample)
            } else {
                groups.append([sample])
            }
        }

        var kept: [HealthIngestSample] = []
        var decisions: [HealthIngestDecision] = []
        for group in groups {
            if group.count == 1 {
                kept.append(group[0])
                continue
            }
            let winner = group.reduce(group[0], HealthSourcePriority.preferred)
            let lost = group.filter { $0 != winner }
            let reason = reasonFor(winner: winner, losers: lost)
            kept.append(winner)
            decisions.append(HealthIngestDecision(kept: winner, dropped: lost, reason: reason))
        }
        return (kept, decisions)
    }

    /// Drop exact copies and thin over-dense workout HR to one sample / minute.
    public static func downsample(_ incoming: [HealthIngestSample]) -> [HealthIngestSample] {
        var seen: Set<String> = []
        var out: [HealthIngestSample] = []
        let ordered = incoming.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return HealthSourcePriority.rank(lhs.source) < HealthSourcePriority.rank(rhs.source)
        }
        for sample in ordered {
            let exact = exactKey(sample)
            if seen.contains(exact) { continue }
            seen.insert(exact)
            if sample.metric == .workoutHR {
                let bucket = "\(sample.metric.rawValue)|\(Int(sample.start.timeIntervalSince1970 / downsampleStride))"
                if seen.contains(bucket) { continue }
                seen.insert(bucket)
            }
            out.append(sample)
        }
        return out
    }

    private static func exactKey(_ sample: HealthIngestSample) -> String {
        let end = sample.end.map { String($0.timeIntervalSince1970) } ?? ""
        return "\(sample.metric.rawValue)|\(sample.source)|\(sample.start.timeIntervalSince1970)|\(sample.value)|\(end)|\(sample.workoutType ?? "")"
    }

    private static func clusterOverlaps(
        _ cluster: [HealthIngestSample],
        _ sample: HealthIngestSample,
        learner: HealthIngestLearner
    ) -> Bool {
        cluster.contains { other in samplesOverlap(other, sample, learner: learner) }
    }

    public static func samplesOverlap(
        _ a: HealthIngestSample,
        _ b: HealthIngestSample,
        learner: HealthIngestLearner
    ) -> Bool {
        guard a.metric == b.metric else { return false }
        if a.metric == .workout {
            let typeA = (a.workoutType ?? "").lowercased()
            let typeB = (b.workoutType ?? "").lowercased()
            guard typeA == typeB, !typeA.isEmpty else { return false }
            return windowIoU(a, b) >= 0.5
        }
        let window = learner.nearDuplicateWindow(sourceA: a.source, sourceB: b.source)
        let startDelta = abs(a.start.timeIntervalSince(b.start))
        guard startDelta <= window else { return false }
        if a.value == 0 || b.value == 0 { return startDelta <= 1 }
        let rel = abs(a.value - b.value) / max(abs(a.value), abs(b.value))
        return rel <= 0.05 || abs(a.value - b.value) < 1
    }

    public static func windowIoU(_ a: HealthIngestSample, _ b: HealthIngestSample) -> Double {
        let start = max(a.start, b.start)
        let end = min(a.windowEnd, b.windowEnd)
        let inter = max(0, end.timeIntervalSince(start))
        let union = max(a.duration + b.duration - inter, 1)
        return inter / union
    }

    private static func reasonFor(winner: HealthIngestSample, losers: [HealthIngestSample]) -> String {
        if winner.metric == .workout {
            let names = losers.map { HealthSourcePriority.canonicalize($0.source) }.joined(separator: ", ")
            return "Merged overlapping \(winner.workoutType ?? "workout") windows; \(HealthSourcePriority.canonicalize(winner.source)) won over \(names)."
        }
        if [.steps, .sleep, .restingHR, .hrv, .workoutHR].contains(winner.metric) {
            return "Apple Health source priority kept \(HealthSourcePriority.canonicalize(winner.source)) for \(winner.metric.rawValue)."
        }
        return "Near-duplicate dropped; kept \(HealthSourcePriority.canonicalize(winner.source))."
    }
}
