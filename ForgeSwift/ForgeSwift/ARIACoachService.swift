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

    // Real-time form coaching is latency-sensitive and high-frequency, so it defaults to a
    // fast vision-capable model. Swap this one constant for `claude-opus-4-8` if you want the
    // deepest analysis at the cost of speed.
    private let visionModel = "claude-sonnet-4-6"
    private let textModel   = "claude-sonnet-4-6"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private var apiKey: String? {
        (Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
    var hasAPIKey: Bool { apiKey != nil }

    // ── Vision: analyze a camera frame against the movement ───────────────────
    func analyzeForm(image: UIImage, context: ARIALiveContext) async -> FormFeedback {
        isAnalyzing = true
        defer { isAnalyzing = false }

        guard let key = apiKey, let jpeg = image.downscaledJPEG(maxDimension: 1024, quality: 0.55) else {
            let fb = Self.heuristicFeedback(for: context)
            lastFeedback = fb
            return fb
        }

        let system = """
        You are ARIA, an elite strength & conditioning coach watching a single video frame of an \
        athlete training. Judge only what is visible. Be specific to the named exercise and the \
        live biometrics. Respond with STRICT JSON and nothing else:
        {"score": <0-100 form quality>, "status": "good"|"adjust"|"stop", \
        "summary": "<one short sentence>", "cues": ["<≤2 imperative cues, ≤8 words each>"]}
        If the body is not clearly visible, status "adjust" and ask them to reframe.
        """
        let prompt = """
        Exercise: \(context.exerciseName)
        Set: \(context.setLabel) · \(context.weight > 0 ? "\(context.weight) lb × " : "")\(context.reps) reps
        Live: HR \(context.heartRate) bpm (Zone \(context.hrZone)), SpO₂ \(context.spO2)%, elapsed \(context.elapsed)
        Key technique points: \(context.cues.prefix(3).joined(separator: "; "))
        Analyze this athlete's form from the frame.
        """
        let content: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
            ["type": "text", "text": prompt],
        ]

        do {
            let text = try await call(model: visionModel, maxTokens: 400, system: system, content: content, key: key)
            let fb = Self.parseFeedback(text, context: context)
            lastFeedback = fb
            lastError = nil
            return fb
        } catch {
            lastError = error.localizedDescription
            let fb = Self.heuristicFeedback(for: context)
            lastFeedback = fb
            return fb
        }
    }

    // ── Text: turn a session snapshot into a coaching briefing ────────────────
    func briefing(for snapshot: ARIASessionSnapshot) async -> String? {
        guard let key = apiKey else { return nil }
        let system = """
        You are ARIA, the athlete's onboard coach. Given a workout data summary, write a tight, \
        motivating debrief (3-4 sentences, no markdown, no lists). Reference the strongest numbers, \
        flag one balance or recovery insight, and end with one concrete focus for next session.
        """
        let content: [[String: Any]] = [["type": "text", "text": snapshot.promptPayload]]
        do {
            return try await call(model: textModel, maxTokens: 320, system: system, content: content, key: key)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // ── Transport (raw HTTP — Swift has no official Anthropic SDK) ─────────────
    private func call(model: String, maxTokens: Int, system: String, content: [[String: Any]], key: String) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model, "max_tokens": maxTokens, "system": system,
            "messages": [["role": "user", "content": content]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "ARIA", code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "ARIA service returned an error."])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else {
            throw NSError(domain: "ARIA", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unreadable response."])
        }
        return blocks.compactMap { $0["text"] as? String }.joined()
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

private extension UIImage {
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
