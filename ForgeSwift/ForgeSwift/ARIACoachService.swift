import SwiftUI
import Combine
import UIKit
import Vision
import ForgeCore

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
    /// Measured vitals only. nil = no live sample yet — never a resting or default stand-in.
    var heartRate: Int?
    var hrZone: Int?
    var spO2: Int?
    var elapsed: String
    var cues: [String]
}

@MainActor
final class ARIACoachService: ObservableObject {
    @Published var isAnalyzing = false
    @Published var lastFeedback: FormFeedback?
    @Published var lastError: String?

    /// Form-check is on this phone. Forge servers never see a frame.
    @Published private(set) var isLiveCoachingAvailable = false

    // ── Vision: analyze a camera frame against the movement ───────────────────
    func analyzeForm(image: UIImage, context: ARIALiveContext) async -> FormFeedback {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let joints = Self.visionJointCount(image)
        let line = await Self.foundationLine(exercise: context.exerciseName)
        let read = OnDeviceFormCheck.evaluate(
            exerciseName: context.exerciseName,
            setLabel: context.setLabel,
            cues: context.cues,
            personInFrame: joints > 0,
            jointCount: joints,
            foundationLine: line
        )
        let fb = FormFeedback(
            score: read.score,
            status: FormFeedback.Status(rawValue: read.status) ?? .adjust,
            summary: read.summary,
            cues: read.cues,
            isLive: read.usedFoundationModels
        )
        lastFeedback = fb
        lastError = nil
        return fb
    }

    /// Vision body-pose on this phone. Never uploaded.
    static func visionJointCount(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        try? handler.perform([request])
        return request.results?.first?.availableJointNames.count ?? 0
    }

    /// Foundation Models / Apple Intelligence may run on-device or via PCC.
    /// Forge cannot call PCC itself. Dummy stays offline.
    static func foundationLine(exercise: String) async -> String? {
        _ = exercise
        return nil
    }

    // ── Text: turn a session snapshot into a coaching briefing ────────────────
    func briefing(for snapshot: ARIASessionSnapshot) async -> String? {
        // Snapshot includes HR / SpO2. It stays on this phone.
        snapshot.localBriefing
    }

    /// Contract for tests and any leftover caller: never include HealthKit fields.
    static func payload(for context: ARIALiveContext) -> [String: Any] {
        [
            "exerciseName": context.exerciseName,
            "setLabel": context.setLabel,
            "weight": context.weight,
            "reps": context.reps,
            "elapsed": context.elapsed,
            "cues": Array(context.cues.prefix(3)),
        ]
    }

    static func heuristicFeedback(for context: ARIALiveContext) -> FormFeedback {
        // No key / no frame → deterministic on-device read so the feature still works.
        // Unknown O₂ is "no reading", not a reason to flag.
        let stressed = (context.hrZone.map { $0 >= 4 } ?? false) || (context.spO2.map { $0 < 95 } ?? false)
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
