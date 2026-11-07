import Foundation

/// Completeness Scout for the on-device HealthKit ingest pipeline.
///
/// The repo already has a research Scout (`AriaScoutDummy` / `AriaScoutClient`
/// / `backend/scout`) whose job is cited web briefs. That Scout is a
/// different agent. This type reuses the Scout name for the ingest role
/// Akshith asked for: after dedup, inspect the canonical batch against
/// what this user/day should have, trigger on-device HealthKit re-gather,
/// and emit a structured gap report. It never invents a value and never
/// uses the network.
///
/// Flow: HealthKit batch → dedup → HealthScout → clean batch + gap report → ARIA.
public struct HealthScoutGap: Equatable, Sendable, Codable {
    public enum Status: String, Codable, Sendable {
        case missing
        case filledFromHealthKit
        case permanent
    }

    public var field: String
    public var day: Date
    public var expectedSource: String?
    public var status: Status
    public var note: String

    public init(
        field: String,
        day: Date,
        expectedSource: String? = nil,
        status: Status,
        note: String
    ) {
        self.field = field
        self.day = day
        self.expectedSource = expectedSource
        self.status = status
        self.note = note
    }
}

public struct HealthScoutReport: Equatable, Sendable {
    public var gaps: [HealthScoutGap]
    public var reGatherAttempted: [String]
    public var connectedSources: [String]

    public init(
        gaps: [HealthScoutGap] = [],
        reGatherAttempted: [String] = [],
        connectedSources: [String] = []
    ) {
        self.gaps = gaps
        self.reGatherAttempted = reGatherAttempted
        self.connectedSources = connectedSources
    }

    public var openGaps: [HealthScoutGap] {
        gaps.filter { $0.status != .filledFromHealthKit }
    }

    /// Coarse labels for on-device ARIA. Stripped before `/ai/chat`.
    public var ariaTags: [String] {
        openGaps.map { "scout_gap:\($0.field):\($0.status.rawValue)" }
    }

    /// Honest spoken line. Names the missing field and the source, never
    /// a fabricated number.
    public var ariaLine: String? {
        let open = openGaps
        guard !open.isEmpty else { return nil }
        let bits = open.map { gap -> String in
            if gap.status == .permanent {
                return gap.note
            }
            if let source = gap.expectedSource {
                return "\(gap.field) is missing from \(HealthSourcePriority.canonicalize(source))"
            }
            return "\(gap.field) is missing"
        }
        return bits.joined(separator: ". ") + "."
    }
}

public enum HealthScout: Sendable {

    /// Source + field pairs this product already knows will never arrive
    /// through Apple Health. WHOOP's cloud writes recovery, not HRV SDNN.
    public static let permanentGaps: [(source: String, field: String, note: String)] = [
        ("whoop", "hrv", "WHOOP doesn't share HRV"),
        ("strava", "sleep", "Strava doesn't share sleep"),
        ("strava", "hrv", "Strava doesn't share HRV"),
        ("runna", "sleep", "Runna doesn't share sleep"),
        ("runna", "hrv", "Runna doesn't share HRV"),
        ("runna", "restingHR", "Runna doesn't share resting HR"),
    ]

    /// What this user/day/workout should have, given connected sources
    /// and the workouts already in the batch. Apple Health is a ledger,
    /// not a sensor: HRV and workout HR are only expected when a source
    /// that writes them is connected, or a workout is already present.
    public static func expectedMetrics(
        connectedSources: [String],
        samples: [HealthIngestSample] = []
    ) -> Set<HealthIngestMetric> {
        let sources = connectedSources.map(HealthSourcePriority.canonicalize)
        var expected: Set<HealthIngestMetric> = []
        for metric in [HealthIngestMetric.sleep, .hrv, .restingHR, .steps] {
            if typicalSource(for: metric, connected: sources) != nil
                || permanentGap(field: metric.rawValue, connected: sources) != nil {
                expected.insert(metric)
            }
        }
        let hasWorkout = samples.contains { $0.metric == .workout }
        // Rest days are not a gap. Workout HR is only expected for a
        // workout already in this batch.
        if hasWorkout {
            expected.insert(.workout)
            expected.insert(.workoutHR)
        }
        return expected
    }

    public static func inspect(
        samples: [HealthIngestSample],
        connectedSources: [String],
        expected: Set<HealthIngestMetric>,
        day: Date
    ) -> HealthScoutReport {
        let present = Set(samples.map(\.metric))
        var gaps: [HealthScoutGap] = []
        let sources = connectedSources.map(HealthSourcePriority.canonicalize)

        for metric in expected.sorted(by: { $0.rawValue < $1.rawValue }) {
            if present.contains(metric) { continue }
            if let permanent = permanentGap(field: metric.rawValue, connected: sources) {
                gaps.append(HealthScoutGap(
                    field: metric.rawValue,
                    day: day,
                    expectedSource: permanent.source,
                    status: .permanent,
                    note: permanent.note
                ))
                continue
            }
            let expectedSource = typicalSource(for: metric, connected: sources)
            gaps.append(HealthScoutGap(
                field: metric.rawValue,
                day: day,
                expectedSource: expectedSource,
                status: .missing,
                note: expectedSource.map { "\(metric.rawValue) not in this batch; \( $0 ) usually writes it." }
                    ?? "\(metric.rawValue) not in this batch."
            ))
        }

        return HealthScoutReport(gaps: gaps, connectedSources: sources)
    }

    public static func permanentGap(
        field: String,
        connected: [String]
    ) -> (source: String, note: String)? {
        for item in permanentGaps {
            if item.field == field, connected.contains(item.source) {
                // Only treat as permanent when no other connected *sensor*
                // is expected to provide the field. Apple Health is the
                // ledger, not a writer of WHOOP HRV.
                let others = connected.filter { $0 != item.source }
                let someoneElseCould = others.contains { source in
                    if source == "apple-health" && (field == "hrv" || field == "workoutHR") {
                        return false
                    }
                    return typicalSource(forField: field, connected: [source]) != nil
                }
                if someoneElseCould { continue }
                return (item.source, item.note)
            }
        }
        return nil
    }

    public static func typicalSource(
        for metric: HealthIngestMetric,
        connected: [String]
    ) -> String? {
        typicalSource(forField: metric.rawValue, connected: connected)
    }

    public static func typicalSource(forField field: String, connected: [String]) -> String? {
        let prefer: [String]
        switch field {
        case "sleep", "hrv", "restingHR":
            prefer = ["apple-watch", "apple-health", "oura", "whoop", "garmin"]
        case "steps", "activeCalories":
            prefer = ["apple-watch", "apple-health", "garmin", "oura"]
        case "workout", "workoutHR":
            prefer = ["apple-watch", "apple-health", "strava", "runna", "garmin", "oura"]
        default:
            prefer = HealthSourcePriority.ranked
        }
        return prefer.first(where: { connected.contains($0) })
    }

    /// ARIA-facing copy. Mentions the gap; never a number we do not have.
    public static func ariaMentionsGap(_ text: String, field: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains(field.lowercased()) && (
            lower.contains("missing")
            || lower.contains("doesn't share")
            || lower.contains("does not share")
            || lower.contains("not in")
            || lower.contains("gap")
            || lower.contains("unavailable")
        )
    }
}
