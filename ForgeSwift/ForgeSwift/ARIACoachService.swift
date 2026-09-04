import SwiftUI
import Combine
import UIKit

/// Structured form read returned by ARIA's vision pass.
struct FormFeedback: Identifiable {
    let id = UUID()
    var score: Int                 // 0–100
    var status: Status             // safety read
    var summary: String
    var cues: [String]
    var isLive: Bool               // true = real Claude call, false = on-device heuristic
    let timestamp = Date()

    enum Status: String { case good, adjust, stop
        var color: Color { self == .good ? .success : self == .adjust ? .warning : .danger }
        var label: String { self == .good ? "Looking strong" : self == .adjust ? "Adjust" : "Stop & reset" }
        var icon: String { self == .good ? "checkmark.seal.fill" : self == .adjust ? "slider.horizontal.3" : "exclamationmark.octagon.fill" }
    }
}

/// Live-data packet ARIA reasons over. (Named to avoid clashing with VoiceCoachManager's WorkoutContext.)
struct ARIALiveContext {
    var exerciseName: String
    var setLabel: String
    var weight: Int
    var reps: String
    var heartRate: Int
    var hrZone: Int
    var spO2: Int
    var elapsed: String
    var cues: [String]
}

@MainActor
final class ARIACoachService: ObservableObject {
    @Published var isAnalyzing = false
    @Published var lastFeedback: FormFeedback?
    @Published var lastError: String?

    /// Whether the server last told us live coaching was available.
    ///
    /// Optimistic until proven otherwise: the first call decides. This replaces
    /// `hasAPIKey`, which asked the wrong question — whether *this device* held a
    /// credential — and answered it by reading one out of the app bundle.
    @Published private(set) var isLiveCoachingAvailable = true

    // ── Vision: analyze a camera frame against the movement ───────────────────
    func analyzeForm(image: UIImage, context: ARIALiveContext) async -> FormFeedback {
        isAnalyzing = true
        defer { isAnalyzing = false }

        guard let jpeg = image.downscaledJPEG(maxDimension: 1024, quality: 0.55) else {
            return fallback(for: context)
        }

        let body: [String: Any] = [
            "mode": "vision",
            "context": Self.payload(for: context),
            "image_base64": jpeg.base64EncodedString(),
        ]

        do {
            let json = try await post(body)
            guard (json["available"] as? Bool) == true,
                  let raw = json["feedback"] as? String else {
                // The server declines rather than guessing when vision routing is
                // not wired up. That is the same situation the old code was in
                // whenever no API key was present, and it is handled the same way.
                isLiveCoachingAvailable = false
                return fallback(for: context)
            }
            isLiveCoachingAvailable = true
            let fb = Self.parseFeedback(raw, context: context)
            lastFeedback = fb
            lastError = nil
            return fb
        } catch {
            lastError = (error as? ForgeAPI.Failure)?.userMessage ?? error.localizedDescription
            return fallback(for: context)
        }
    }

    private func fallback(for context: ARIALiveContext) -> FormFeedback {
        let fb = Self.heuristicFeedback(for: context)
        lastFeedback = fb
        return fb
    }

    // ── Text: turn a session snapshot into a coaching briefing ────────────────
    func briefing(for snapshot: ARIASessionSnapshot) async -> String? {
        if AriaService.shouldUseTestReadyDummy || AriaOperatingMode.current.isLocalTesting {
            return snapshot.localBriefing
        }
        do {
            let json = try await post(["mode": "briefing", "snapshot": snapshot.promptPayload])
            guard (json["available"] as? Bool) == true,
                  let text = json["briefing"] as? String else { return snapshot.localBriefing }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? snapshot.localBriefing
        } catch {
            lastError = (error as? ForgeAPI.Failure)?.userMessage ?? error.localizedDescription
            return snapshot.localBriefing
        }
    }

    // ── Transport ─────────────────────────────────────────────────────────────
    //
    // One authenticated request to Forge's own backend. This used to be a raw
    // POST to api.anthropic.com carrying a key read out of Info.plist — an
    // extractable secret in any build that set it, and a request that skipped
    // auth, sanitization, the model router and every cost control at once.
    private func post(_ body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "workouts/form-check", relativeTo: AriaService.shared.baseURL) else {
            throw ForgeAPI.Failure.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await ForgeAPI.send(request)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func payload(for context: ARIALiveContext) -> [String: Any] {
        [
            "exerciseName": context.exerciseName,
            "setLabel": context.setLabel,
            "weight": context.weight,
            "reps": context.reps,
            "heartRate": context.heartRate,
            "hrZone": context.hrZone,
            "spO2": context.spO2,
            "elapsed": context.elapsed,
            "cues": Array(context.cues.prefix(3)),
        ]
    }

    // ── Parsing + offline fallback ────────────────────────────────────────────
    private static func parseFeedback(_ raw: String, context: ARIALiveContext) -> FormFeedback {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"),
              let data = String(raw[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FormFeedback(score: 80, status: .adjust,
                                summary: raw.isEmpty ? "Reframe so your whole body is in shot." : String(raw.prefix(120)),
                                cues: context.cues.isEmpty ? ["Brace and control the tempo"] : Array(context.cues.prefix(2)),
                                isLive: true)
        }
        let score = (obj["score"] as? Int) ?? Int((obj["score"] as? Double) ?? 80)
        let status = FormFeedback.Status(rawValue: (obj["status"] as? String ?? "adjust").lowercased()) ?? .adjust
        let summary = (obj["summary"] as? String) ?? "Keep that position."
        let cues = (obj["cues"] as? [String]) ?? Array(context.cues.prefix(2))
        return FormFeedback(score: max(0, min(100, score)), status: status, summary: summary,
                            cues: cues.isEmpty ? ["Own every rep"] : cues, isLive: true)
    }

    static func heuristicFeedback(for context: ARIALiveContext) -> FormFeedback {
        // No key / no frame → deterministic on-device read so the feature still works.
        let stressed = context.hrZone >= 4 || context.spO2 < 95
        return FormFeedback(
            score: stressed ? 78 : 88,
            status: stressed ? .adjust : .good,
            summary: stressed
                ? "Fatigue is creeping in — keep technique tight as the HR climbs."
                : "Position looks controlled. Keep the tempo honest.",
            cues: context.cues.isEmpty ? ["Brace the core", "Control the eccentric"] : Array(context.cues.prefix(2)),
            isLive: false)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension UIImage {
    func downscaledJPEG(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// Everything ARIA needs to brief the athlete. Built from either a plan (pre-workout) or
/// the live log (post-workout).
struct ARIASessionSnapshot {
    var title: String
    var durationSec: Int
    var totalVolume: Int
    var totalSets: Int
    var totalReps: Int
    var exercisesCompleted: Int
    var avgHR: Int
    var peakHR: Int
    var minO2: Int
    var avgRPE: Double
    var calories: Int
    var readiness: Int
    var muscleVolume: [TargetMuscle: Double]   // relative working-set load per group
    var zoneSeconds: [Int]                    // index 1...5
    var autoRegLog: [String]
    var painFlags: [String]
    var personalRecords: [String]

    /// Balance read: which regions got the most / least work.
    var regionShare: [(TargetMuscle.Region, Double)] {
        var totals: [TargetMuscle.Region: Double] = [:]
        for (m, v) in muscleVolume { totals[m.region, default: 0] += v }
        let sum = max(1, totals.values.reduce(0, +))
        return TargetMuscle.Region.allRegions.map { ($0, (totals[$0] ?? 0) / sum) }
    }

    var topMuscles: [(TargetMuscle, Double)] {
        let sum = max(1, muscleVolume.values.reduce(0, +))
        return muscleVolume.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value / sum) }
    }

    /// Locally-authored briefing — used when no API key is configured.
    var localBriefing: String {
        var lines: [String] = []
        let topRegion = regionShare.max { $0.1 < $1.1 }?.0.rawValue ?? "full-body"
        lines.append("Logged \(totalSets) sets for \(totalVolume.formattedVolume) lb of volume across \(exercisesCompleted) movements — mostly \(topRegion) work.")
        if !personalRecords.isEmpty { lines.append("New ground on \(personalRecords.joined(separator: ", ")) 🏆.") }
        if avgRPE > 0 { lines.append("Average effort landed at RPE \(String(format: "%.1f", avgRPE)) with a \(peakHR) bpm peak.") }
        if let weak = regionShare.filter({ $0.1 > 0 }).min(by: { $0.1 < $1.1 })?.0, regionShare.count > 1 {
            lines.append("Your \(weak.rawValue) volume trailed today — worth balancing next session.")
        }
        if !painFlags.isEmpty { lines.append("Flagged discomfort: \(painFlags.joined(separator: ", ")) — ARIA will program around it.") }
        return lines.joined(separator: " ")
    }

    /// Compact payload handed to Claude for a richer debrief.
    var promptPayload: String {
        let muscles = topMuscles.map { "\($0.0.label) \(Int($0.1 * 100))%" }.joined(separator: ", ")
        return """
        Workout: \(title)
        Duration: \(durationSec / 60) min · Volume: \(totalVolume) lb · Sets: \(totalSets) · Reps: \(totalReps)
        Avg RPE: \(String(format: "%.1f", avgRPE)) · Avg HR: \(avgHR) · Peak HR: \(peakHR) · Min O₂: \(minO2)% · Calories: \(calories)
        Readiness going in: \(readiness)/100
        Muscle emphasis: \(muscles)
        Auto-regulation: \(autoRegLog.isEmpty ? "none" : autoRegLog.joined(separator: "; "))
        Pain flags: \(painFlags.isEmpty ? "none" : painFlags.joined(separator: ", "))
        PRs: \(personalRecords.isEmpty ? "none" : personalRecords.joined(separator: ", "))
        """
    }
}

extension Int {
    var formattedVolume: String {
        self >= 1000 ? String(format: "%.1fk", Double(self) / 1000) : "\(self)"
    }
}
