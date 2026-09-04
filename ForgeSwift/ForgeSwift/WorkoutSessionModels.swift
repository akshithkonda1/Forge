import SwiftUI

struct WorkoutHRZone: Equatable {
    let label: String
    let color: Color
    let range: ClosedRange<Int>
    let index: Int
    static func == (l: WorkoutHRZone, r: WorkoutHRZone) -> Bool { l.label == r.label }

    static let all: [WorkoutHRZone] = [
        WorkoutHRZone(label: "Rest",   color: .steel,               range: 0...99,    index: 0),
        WorkoutHRZone(label: "Zone 1", color: Color(hex: "38BDF8"),  range: 100...114, index: 1),
        WorkoutHRZone(label: "Zone 2", color: .success,              range: 115...133, index: 2),
        WorkoutHRZone(label: "Zone 3", color: Color(hex: "F59E0B"),  range: 134...152, index: 3),
        WorkoutHRZone(label: "Zone 4", color: .ember,                range: 153...171, index: 4),
        WorkoutHRZone(label: "Zone 5", color: .danger,               range: 172...220, index: 5),
    ]

    /// Zone 0 is the fallback rather than a crash: a heart rate above 220 is a
    /// sensor artefact, and an artefact should not take the workout down.
    static func zone(for bpm: Int) -> WorkoutHRZone {
        all.first { $0.range.contains(bpm) } ?? all[0]
    }
}

struct SetLogEntry: Identifiable {
    let id = UUID()
    let exerciseName: String
    let setNumber:    Int
    var repsPerformed: Int
    var weightUsed:   Int
    var rpe:          Int        // 1–10
    var isPersonalRecord: Bool = false
    var timestamp: Date = Date()
    var volume: Int { repsPerformed * max(1, weightUsed) }
}

struct PainEntry: Identifiable {
    let id = UUID()
    let location:     String
    let severity:     Int
    let exerciseName: String
}

struct WorkoutSummaryData {
    let duration:           Int
    let totalVolume:        Int
    let totalSets:          Int
    let totalReps:          Int
    let peakHR:             Int
    let avgHR:              Int
    let peakO2:             Int
    let minO2:              Int
    let caloriesBurned:     Int
    let personalRecords:    [String]
    let exercisesCompleted: Int
    let avgRPE:             Double
    let hrHistory:          [Int]
    // Adaptive / ARIA additions
    var muscleVolume:       [String: Double] = [:]   // TargetMuscle.rawValue → relative load
    var autoRegLog:         [String] = []
    var painFlags:          [String] = []
    var readiness:          Int = 0
    var workoutName:        String = ""

    var ariaSnapshot: ARIASessionSnapshot {
        var mv: [TargetMuscle: Double] = [:]
        for (k, v) in muscleVolume { if let g = TargetMuscle(rawValue: k) { mv[g] = v } }
        var zones = Array(repeating: 0, count: 6)
        for hr in hrHistory { zones[WorkoutHRZone.zone(for: hr).index] += 2 }
        return ARIASessionSnapshot(
            title: workoutName.isEmpty ? "Workout" : workoutName,
            durationSec: duration, totalVolume: totalVolume, totalSets: totalSets,
            totalReps: totalReps, exercisesCompleted: exercisesCompleted, avgHR: avgHR,
            peakHR: peakHR, minO2: minO2, avgRPE: avgRPE, calories: caloriesBurned,
            readiness: readiness, muscleVolume: mv, zoneSeconds: Array(zones.dropFirst()),
            autoRegLog: autoRegLog, painFlags: painFlags, personalRecords: personalRecords)
    }
}
