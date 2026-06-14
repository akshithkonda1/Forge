import SwiftUI
import Combine
import AVFoundation
import UIKit
import MediaPlayer

// =====================================================================================
// MARK: - FORGE · Workout Engine (single-file)
//
// This view is the entire training surface for Forge. It is intentionally self-contained:
//   • A kinesiology-grade exercise library (90+ movements with muscles, patterns, cues)
//   • An adaptive auto-regulation engine grounded in sports-medicine practice (RIR/RPE,
//     readiness scaling, pain-driven substitution, HR/SpO₂ rest extension)
//   • An ARIA performance dashboard that compiles live data and briefs the onboard coach
//   • A live camera form-coach that streams frames to Claude for real-time guidance
// All original idle / active / summary / music features are preserved and elevated.
// =====================================================================================

// MARK: - Kinesiology Domain

/// Major muscle groups used for volume balance + targeting.
enum MuscleGroup: String, CaseIterable, Identifiable, Hashable {
    case chest, upperBack, lats, traps, lowerBack
    case frontDelts, sideDelts, rearDelts
    case biceps, triceps, forearms
    case quads, hamstrings, glutes, adductors, abductors, calves, hipFlexors
    case abs, obliques
    case fullBody, cardio
    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: return "Chest"
        case .upperBack: return "Upper Back"
        case .lats: return "Lats"
        case .traps: return "Traps"
        case .lowerBack: return "Lower Back"
        case .frontDelts: return "Front Delts"
        case .sideDelts: return "Side Delts"
        case .rearDelts: return "Rear Delts"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .adductors: return "Adductors"
        case .abductors: return "Abductors"
        case .calves: return "Calves"
        case .hipFlexors: return "Hip Flexors"
        case .abs: return "Abs"
        case .obliques: return "Obliques"
        case .fullBody: return "Full Body"
        case .cardio: return "Cardio"
        }
    }

    /// Coarse training region — drives the balance read-out + accent colors.
    enum Region: String { case push, pull, legs, core, conditioning }
    var region: Region {
        switch self {
        case .chest, .frontDelts, .sideDelts, .triceps: return .push
        case .upperBack, .lats, .traps, .rearDelts, .biceps, .forearms: return .pull
        case .quads, .hamstrings, .glutes, .adductors, .abductors, .calves, .hipFlexors, .lowerBack: return .legs
        case .abs, .obliques: return .core
        case .fullBody, .cardio: return .conditioning
        }
    }

    var accent: Color {
        switch region {
        case .push: return .ember
        case .pull: return Color(hex: "38BDF8")
        case .legs: return Color(hex: "A855F7")
        case .core: return .success
        case .conditioning: return .warning
        }
    }
}

/// Fundamental human movement patterns (kinesiology classification).
enum MovementPattern: String, CaseIterable, Identifiable, Hashable {
    case horizontalPush, horizontalPull, verticalPush, verticalPull
    case squat, hinge, lunge, carry
    case rotation, antiRotation, coreFlexion, isolation, gait, mobility
    var id: String { rawValue }
    var label: String {
        switch self {
        case .horizontalPush: return "Horizontal Push"
        case .horizontalPull: return "Horizontal Pull"
        case .verticalPush: return "Vertical Push"
        case .verticalPull: return "Vertical Pull"
        case .squat: return "Squat"
        case .hinge: return "Hinge"
        case .lunge: return "Lunge / Split"
        case .carry: return "Loaded Carry"
        case .rotation: return "Rotation"
        case .antiRotation: return "Anti-Rotation"
        case .coreFlexion: return "Core Flexion"
        case .isolation: return "Isolation"
        case .gait: return "Gait / Locomotion"
        case .mobility: return "Mobility"
        }
    }
}

enum Equipment: String, CaseIterable, Identifiable, Hashable {
    case barbell, dumbbell, kettlebell, machine, cable, bodyweight, bands, trx, medicineBall, sled, cardioMachine
    var id: String { rawValue }
    var label: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .kettlebell: return "Kettlebell"
        case .machine: return "Machine"
        case .cable: return "Cable"
        case .bodyweight: return "Bodyweight"
        case .bands: return "Bands"
        case .trx: return "Suspension"
        case .medicineBall: return "Med Ball"
        case .sled: return "Sled"
        case .cardioMachine: return "Cardio"
        }
    }
    var icon: String {
        switch self {
        case .barbell: return "figure.strengthtraining.traditional"
        case .dumbbell: return "dumbbell.fill"
        case .kettlebell: return "figure.strengthtraining.functional"
        case .machine: return "gearshape.2.fill"
        case .cable: return "cablecar.fill"
        case .bodyweight: return "figure.gymnastics"
        case .bands: return "circle.dashed"
        case .trx: return "figure.flexibility"
        case .medicineBall: return "circle.circle.fill"
        case .sled: return "figure.american.football"
        case .cardioMachine: return "figure.run"
        }
    }
}

enum Mechanic: String, Hashable { case compound, isolation }
enum ForceType: String, Hashable { case push, pull, isometric }
enum TrainingModality: String, Hashable, CaseIterable {
    case strength, hypertrophy, power, endurance, conditioning, mobility
    var label: String { rawValue.capitalized }
}

// MARK: - Exercise Definition

/// A kinesiology-rich library entry. Distinct from `Exercise` (the lightweight plan row).
struct ExerciseDefinition: Identifiable, Hashable {
    let id: String                  // stable slug
    let name: String
    let primary: [MuscleGroup]
    let secondary: [MuscleGroup]
    let pattern: MovementPattern
    let equipment: Equipment
    let mechanic: Mechanic
    let force: ForceType
    let modality: TrainingModality
    let level: ExperienceLevel
    let unilateral: Bool
    let defaultSets: Int
    let repLow: Int
    let repHigh: Int
    let restSeconds: Int
    let tempo: String               // eccentric-pause-concentric, e.g. "3-1-1"
    let met: Double                 // metabolic equivalent for kcal modeling
    let rpeTarget: Int
    let cues: [String]
    let faults: [String]
    let painContraindications: [String]   // pain locations this load aggravates
    let regressions: [String]
    let progressions: [String]
    let substitutes: [String]
    let note: String

    var isCompound: Bool { mechanic == .compound }
    var repRangeLabel: String { repLow == repHigh ? "\(repLow)" : "\(repLow)–\(repHigh)" }
    var region: MuscleGroup.Region { primary.first?.region ?? .conditioning }
    var accent: Color { primary.first?.accent ?? .ember }

    var icon: String {
        switch pattern {
        case .horizontalPush, .verticalPush: return "arrow.up.forward"
        case .horizontalPull, .verticalPull: return "arrow.down.backward"
        case .squat: return "figure.strengthtraining.functional"
        case .hinge: return "figure.cross.training"
        case .lunge: return "figure.walk"
        case .carry: return "figure.walk.motion"
        case .rotation, .antiRotation: return "arrow.triangle.2.circlepath"
        case .coreFlexion: return "figure.core.training"
        case .gait: return "figure.run"
        case .mobility: return "figure.flexibility"
        case .isolation: return equipment.icon
        }
    }

    var muscleSummary: String {
        let p = primary.map { $0.label }.joined(separator: ", ")
        return secondary.isEmpty ? p : "\(p) · \(secondary.map { $0.label }.joined(separator: ", "))"
    }

    static func == (l: ExerciseDefinition, r: ExerciseDefinition) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

func forgeSlug(_ s: String) -> String {
    s.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: "-")
}

extension ExerciseDefinition {
    /// Compact factory so the library reads like a spec sheet.
    static func make(
        _ name: String, _ pattern: MovementPattern, _ equipment: Equipment,
        primary: [MuscleGroup], secondary: [MuscleGroup] = [],
        mechanic: Mechanic = .compound, force: ForceType = .push,
        modality: TrainingModality = .strength, level: ExperienceLevel = .beginner,
        unilateral: Bool = false, sets: Int = 3, repLow: Int = 8, repHigh: Int = 12,
        rest: Int = 90, tempo: String = "2-0-1", met: Double = 5.0, rpe: Int = 8,
        cues: [String] = [], faults: [String] = [], pain: [String] = [],
        regress: [String] = [], progress: [String] = [], subs: [String] = [], note: String = ""
    ) -> ExerciseDefinition {
        ExerciseDefinition(
            id: forgeSlug(name), name: name, primary: primary, secondary: secondary,
            pattern: pattern, equipment: equipment, mechanic: mechanic, force: force,
            modality: modality, level: level, unilateral: unilateral, defaultSets: sets,
            repLow: repLow, repHigh: repHigh, restSeconds: rest, tempo: tempo, met: met,
            rpeTarget: rpe, cues: cues, faults: faults, painContraindications: pain,
            regressions: regress, progressions: progress, substitutes: subs, note: note
        )
    }
}
// MARK: - Exercise Library (90+ movements)

enum ExerciseLibrary {

    static let all: [ExerciseDefinition] = pushChest + shoulders + pull + arms + legsQuad + legsPosterior + coreCarry + conditioning + mobility

    // ── Horizontal / chest push ──────────────────────────────────────────────
    static let pushChest: [ExerciseDefinition] = [
        .make("Barbell Bench Press", .horizontalPush, .barbell, primary: [.chest], secondary: [.frontDelts, .triceps],
              level: .intermediate, sets: 4, repLow: 5, repHigh: 8, rest: 150, tempo: "3-1-1", met: 6.0, rpe: 8,
              cues: ["Pin the shoulder blades down and back", "Bar to mid-chest, elbows ~45°", "Drive feet into the floor"],
              faults: ["Flared elbows", "Bouncing off the chest", "Hips leaving the bench"],
              pain: ["Shoulder", "Wrist"], regress: ["Dumbbell Bench Press"], progress: ["Close-Grip Bench Press"],
              subs: ["Dumbbell Bench Press", "Machine Chest Press", "Weighted Push-Up"], note: "Primary horizontal-press strength driver."),
        .make("Incline Barbell Bench Press", .horizontalPush, .barbell, primary: [.chest, .frontDelts], secondary: [.triceps],
              level: .intermediate, sets: 4, repLow: 6, repHigh: 10, rest: 120, tempo: "3-1-1", met: 6.0, rpe: 8,
              cues: ["Bench at 30–45°", "Bar to upper chest", "Keep wrists stacked"], faults: ["Too steep — becomes a press"],
              pain: ["Shoulder"], subs: ["Incline Dumbbell Press", "Machine Chest Press"], note: "Biases upper chest fibers."),
        .make("Dumbbell Bench Press", .horizontalPush, .dumbbell, primary: [.chest], secondary: [.frontDelts, .triceps],
              level: .beginner, sets: 4, repLow: 8, repHigh: 12, rest: 100, met: 5.5, rpe: 8,
              cues: ["Stretch at the bottom", "Press in a slight arc", "Control the eccentric"],
              pain: ["Shoulder"], subs: ["Barbell Bench Press", "Machine Chest Press"], note: "Greater range than the barbell; shoulder-friendly."),
        .make("Incline Dumbbell Press", .horizontalPush, .dumbbell, primary: [.chest, .frontDelts], secondary: [.triceps],
              level: .beginner, sets: 3, repLow: 8, repHigh: 12, rest: 90, met: 5.5,
              cues: ["Elbows under the wrists", "Full stretch up top"], pain: ["Shoulder"],
              subs: ["Incline Barbell Bench Press"], note: "Upper-chest hypertrophy staple."),
        .make("Decline Bench Press", .horizontalPush, .barbell, primary: [.chest], secondary: [.triceps],
              level: .intermediate, sets: 3, repLow: 6, repHigh: 10, rest: 120, met: 6.0,
              cues: ["Bar to lower chest"], pain: ["Shoulder"], subs: ["Dumbbell Bench Press"], note: "Lower-chest emphasis."),
        .make("Machine Chest Press", .horizontalPush, .machine, primary: [.chest], secondary: [.frontDelts, .triceps],
              level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 75, met: 4.5, rpe: 8,
              cues: ["Match handle height to mid-chest", "Squeeze at lockout"], subs: ["Dumbbell Bench Press"],
              note: "Stable, fatigue-friendly — great for finishing volume."),
        .make("Push-Up", .horizontalPush, .bodyweight, primary: [.chest], secondary: [.frontDelts, .triceps, .abs],
              level: .beginner, sets: 3, repLow: 10, repHigh: 20, rest: 60, met: 4.0, rpe: 7,
              cues: ["Body in one line", "Brace the core", "Full lockout"], faults: ["Sagging hips", "Half reps"],
              regress: ["Incline Push-Up"], progress: ["Weighted Push-Up"], subs: ["Machine Chest Press"], note: "Scalable anytime, anywhere."),
        .make("Weighted Push-Up", .horizontalPush, .bodyweight, primary: [.chest], secondary: [.triceps, .abs],
              level: .intermediate, sets: 4, repLow: 8, repHigh: 12, rest: 90, met: 5.0,
              cues: ["Plate on upper back", "Keep ribs down"], subs: ["Dumbbell Bench Press"], note: "Push-up progression with external load."),
        .make("Cable Chest Fly", .isolation, .cable, primary: [.chest], secondary: [.frontDelts],
              mechanic: .isolation, level: .beginner, sets: 3, repLow: 12, repHigh: 15, rest: 60, met: 4.0, rpe: 8,
              cues: ["Soft elbows, fixed angle", "Hug the midline", "Feel the stretch"], faults: ["Pressing instead of flying"],
              pain: ["Shoulder"], subs: ["Pec Deck Fly"], note: "Constant tension across the full arc."),
        .make("Pec Deck Fly", .isolation, .machine, primary: [.chest], mechanic: .isolation,
              level: .beginner, sets: 3, repLow: 12, repHigh: 15, rest: 60, met: 4.0, subs: ["Cable Chest Fly"], note: "Isolated chest squeeze."),
        .make("Chest Dip", .horizontalPush, .bodyweight, primary: [.chest], secondary: [.triceps, .frontDelts],
              level: .intermediate, sets: 3, repLow: 8, repHigh: 12, rest: 90, met: 5.0,
              cues: ["Lean forward for chest", "Control the depth"], pain: ["Shoulder"], regress: ["Bench Dip"],
              progress: ["Weighted Dip"], subs: ["Decline Bench Press"], note: "Deep stretch under load — ease into depth."),
    ]

    // ── Vertical push + delts ────────────────────────────────────────────────
    static let shoulders: [ExerciseDefinition] = [
        .make("Overhead Press", .verticalPush, .barbell, primary: [.frontDelts], secondary: [.sideDelts, .triceps, .traps],
              level: .intermediate, sets: 4, repLow: 5, repHigh: 8, rest: 120, tempo: "2-0-1", met: 6.0, rpe: 8,
              cues: ["Squeeze glutes, brace ribs", "Bar over mid-foot at lockout", "Head through at the top"],
              faults: ["Leaning back", "Pressing around the head"], pain: ["Shoulder", "Lower Back"],
              regress: ["Seated Dumbbell Shoulder Press"], progress: ["Push Press"], subs: ["Machine Shoulder Press"],
              note: "King of vertical pressing — demands a braced trunk."),
        .make("Seated Dumbbell Shoulder Press", .verticalPush, .dumbbell, primary: [.frontDelts], secondary: [.sideDelts, .triceps],
              level: .beginner, sets: 3, repLow: 8, repHigh: 12, rest: 90, met: 5.0,
              cues: ["Wrists stacked over elbows", "Stop just shy of lockout for tension"], pain: ["Shoulder"],
              subs: ["Machine Shoulder Press", "Arnold Press"], note: "Shoulder-friendly overhead volume."),
        .make("Arnold Press", .verticalPush, .dumbbell, primary: [.frontDelts], secondary: [.sideDelts, .triceps],
              level: .intermediate, sets: 3, repLow: 8, repHigh: 12, rest: 90, met: 5.0,
              cues: ["Rotate palms through the press"], pain: ["Shoulder"], subs: ["Seated Dumbbell Shoulder Press"], note: "Adds rotation for full deltoid sweep."),
        .make("Machine Shoulder Press", .verticalPush, .machine, primary: [.frontDelts], secondary: [.triceps],
              level: .beginner, sets: 3, repLow: 10, repHigh: 12, rest: 75, met: 4.5, subs: ["Seated Dumbbell Shoulder Press"], note: "Stable path for volume."),
        .make("Push Press", .verticalPush, .barbell, primary: [.frontDelts], secondary: [.triceps, .quads, .glutes],
              mechanic: .compound, modality: .power, level: .advanced, sets: 4, repLow: 3, repHigh: 5, rest: 150, met: 6.5, rpe: 8,
              cues: ["Short dip, violent drive", "Punch the bar up"], pain: ["Shoulder", "Lower Back"], subs: ["Overhead Press"], note: "Leg drive to overload the press."),
        .make("Landmine Press", .verticalPush, .barbell, primary: [.frontDelts], secondary: [.chest, .triceps],
              level: .beginner, unilateral: true, sets: 3, repLow: 8, repHigh: 12, rest: 75, met: 5.0,
              cues: ["Press up and in on the arc"], pain: [], subs: ["Seated Dumbbell Shoulder Press"], note: "Joint-friendly pressing angle."),
        .make("Lateral Raise", .isolation, .dumbbell, primary: [.sideDelts], mechanic: .isolation,
              level: .beginner, sets: 4, repLow: 12, repHigh: 20, rest: 45, met: 4.0, rpe: 8,
              cues: ["Lead with the elbows", "Soft elbows, pour the water", "No swinging"], faults: ["Using momentum", "Shrugging"],
              subs: ["Cable Lateral Raise"], note: "Width-builder — keep it strict and high-rep."),
        .make("Cable Lateral Raise", .isolation, .cable, primary: [.sideDelts], mechanic: .isolation,
              level: .beginner, unilateral: true, sets: 3, repLow: 12, repHigh: 20, rest: 45, met: 4.0,
              cues: ["Constant tension from the bottom"], subs: ["Lateral Raise"], note: "Tension where dumbbells lose it."),
        .make("Front Raise", .isolation, .dumbbell, primary: [.frontDelts], mechanic: .isolation,
              level: .beginner, sets: 3, repLow: 12, repHigh: 15, rest: 45, met: 4.0, subs: ["Landmine Press"], note: "Direct front-delt work — most get plenty from pressing."),
        .make("Rear Delt Fly", .isolation, .dumbbell, primary: [.rearDelts], secondary: [.upperBack], mechanic: .isolation,
              force: .pull, level: .beginner, sets: 3, repLow: 15, repHigh: 20, rest: 45, met: 4.0,
              cues: ["Hinge over, thumbs down", "Squeeze the shoulder blades"], subs: ["Reverse Pec Deck", "Face Pull"], note: "Posture + shoulder health."),
        .make("Reverse Pec Deck", .isolation, .machine, primary: [.rearDelts], secondary: [.upperBack], mechanic: .isolation,
              force: .pull, level: .beginner, sets: 3, repLow: 15, repHigh: 20, rest: 45, met: 4.0, subs: ["Rear Delt Fly"], note: "Supported rear-delt isolation."),
        .make("Face Pull", .horizontalPull, .cable, primary: [.rearDelts], secondary: [.upperBack, .traps], mechanic: .isolation,
              force: .pull, level: .beginner, sets: 3, repLow: 15, repHigh: 20, rest: 45, met: 4.0,
              cues: ["Pull to the eyes, elbows high", "Externally rotate at the end"], subs: ["Rear Delt Fly"], note: "Best single move for shoulder longevity."),
        .make("Upright Row", .verticalPull, .cable, primary: [.sideDelts], secondary: [.traps, .biceps], mechanic: .isolation,
              force: .pull, level: .intermediate, sets: 3, repLow: 12, repHigh: 15, rest: 60, met: 4.5,
              cues: ["Lead with elbows, stop at chest height"], pain: ["Shoulder"], subs: ["Lateral Raise"], note: "Wide grip to spare the shoulder."),
    ]

    // ── Pull (back) ──────────────────────────────────────────────────────────
    static let pull: [ExerciseDefinition] = [
        .make("Pull-Up", .verticalPull, .bodyweight, primary: [.lats], secondary: [.upperBack, .biceps, .forearms],
              force: .pull, level: .intermediate, sets: 4, repLow: 5, repHigh: 10, rest: 120, met: 5.0, rpe: 8,
              cues: ["Start from a dead hang", "Drive elbows to the floor", "Chest to the bar"],
              faults: ["Kipping for reps", "Half range"], regress: ["Lat Pulldown"], progress: ["Weighted Pull-Up"],
              subs: ["Lat Pulldown", "Neutral-Grip Pulldown"], note: "Gold-standard vertical pull."),
        .make("Weighted Pull-Up", .verticalPull, .bodyweight, primary: [.lats], secondary: [.upperBack, .biceps],
              force: .pull, level: .advanced, sets: 4, repLow: 4, repHigh: 8, rest: 150, met: 5.5,
              cues: ["Belt the load, stay controlled"], subs: ["Pull-Up", "Lat Pulldown"], note: "Overload the vertical pull."),
        .make("Chin-Up", .verticalPull, .bodyweight, primary: [.lats], secondary: [.biceps],
              force: .pull, level: .intermediate, sets: 3, repLow: 6, repHigh: 10, rest: 90, met: 5.0,
              cues: ["Supinated grip, drive elbows down"], subs: ["Lat Pulldown"], note: "More biceps than the pull-up."),
        .make("Lat Pulldown", .verticalPull, .cable, primary: [.lats], secondary: [.upperBack, .biceps],
              force: .pull, level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 75, met: 4.5, rpe: 8,
              cues: ["Bar to upper chest", "Lead with the elbows, not the hands"], subs: ["Pull-Up", "Neutral-Grip Pulldown"], note: "Scalable vertical pull for any level."),
        .make("Neutral-Grip Pulldown", .verticalPull, .cable, primary: [.lats], secondary: [.biceps],
              force: .pull, level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 75, met: 4.5, subs: ["Lat Pulldown"], note: "Shoulder-friendly grip."),
        .make("Straight-Arm Pulldown", .isolation, .cable, primary: [.lats], mechanic: .isolation, force: .pull,
              level: .beginner, sets: 3, repLow: 12, repHigh: 15, rest: 45, met: 4.0, cues: ["Fixed elbow, drive the bar to the thighs"], subs: ["Lat Pulldown"], note: "Isolates the lats without the biceps."),
        .make("Barbell Row", .horizontalPull, .barbell, primary: [.upperBack, .lats], secondary: [.biceps, .lowerBack],
              force: .pull, level: .intermediate, sets: 4, repLow: 6, repHigh: 10, rest: 120, tempo: "2-1-1", met: 6.0, rpe: 8,
              cues: ["Hinge to ~45°, flat back", "Pull to the lower ribs", "Squeeze the blades"],
              faults: ["Jerking with the lower back", "Standing too upright"], pain: ["Lower Back"],
              regress: ["Chest-Supported Row"], subs: ["Dumbbell Row", "Seated Cable Row"], note: "Heavy horizontal-pull mass builder."),
        .make("Pendlay Row", .horizontalPull, .barbell, primary: [.upperBack], secondary: [.lats, .lowerBack],
              force: .pull, level: .advanced, sets: 4, repLow: 4, repHigh: 8, rest: 120, met: 6.0,
              cues: ["Reset on the floor each rep", "Explosive pull, flat torso"], pain: ["Lower Back"], subs: ["Barbell Row"], note: "Strict, powerful row from a dead stop."),
        .make("Dumbbell Row", .horizontalPull, .dumbbell, primary: [.lats, .upperBack], secondary: [.biceps],
              force: .pull, level: .beginner, unilateral: true, sets: 3, repLow: 8, repHigh: 12, rest: 75, met: 5.0,
              cues: ["Brace on the bench", "Drive the elbow past the ribs"], subs: ["Chest-Supported Row", "Seated Cable Row"], note: "Big range, easy on the lower back."),
        .make("Chest-Supported Row", .horizontalPull, .machine, primary: [.upperBack, .lats], secondary: [.biceps],
              force: .pull, level: .beginner, sets: 3, repLow: 10, repHigh: 12, rest: 75, met: 4.5,
              cues: ["Let the pad take the lower back", "Pull and pause"], subs: ["Seated Cable Row"], note: "Rowing volume with zero spinal load."),
        .make("Seated Cable Row", .horizontalPull, .cable, primary: [.upperBack, .lats], secondary: [.biceps],
              force: .pull, level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 75, met: 4.5,
              cues: ["Tall chest, pull to the navel", "Don't rock"], subs: ["Chest-Supported Row"], note: "Smooth tension for the mid-back."),
        .make("T-Bar Row", .horizontalPull, .barbell, primary: [.upperBack, .lats], secondary: [.biceps, .lowerBack],
              force: .pull, level: .intermediate, sets: 4, repLow: 8, repHigh: 12, rest: 90, met: 5.5,
              cues: ["Hinge, neutral spine, drive elbows back"], pain: ["Lower Back"], subs: ["Barbell Row"], note: "Thick mid-back loading."),
        .make("Inverted Row", .horizontalPull, .bodyweight, primary: [.upperBack], secondary: [.lats, .biceps],
              force: .pull, level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 60, met: 4.0,
              cues: ["Rigid plank, chest to the bar"], subs: ["Seated Cable Row"], note: "Scalable bodyweight horizontal pull."),
        .make("Machine Row", .horizontalPull, .machine, primary: [.upperBack, .lats], secondary: [.biceps],
              force: .pull, level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 75, met: 4.5, subs: ["Seated Cable Row"], note: "Fixed-path rowing volume."),
    ]
    // ── Arms ─────────────────────────────────────────────────────────────────
    static let arms: [ExerciseDefinition] = [
        .make("Close-Grip Bench Press", .horizontalPush, .barbell, primary: [.triceps], secondary: [.chest, .frontDelts],
              level: .intermediate, sets: 3, repLow: 6, repHigh: 10, rest: 90, met: 5.5,
              cues: ["Shoulder-width grip", "Tuck elbows"], pain: ["Wrist", "Elbow"], subs: ["Triceps Pushdown"], note: "Compound triceps overload."),
        .make("Triceps Pushdown", .isolation, .cable, primary: [.triceps], mechanic: .isolation,
              level: .beginner, sets: 3, repLow: 12, repHigh: 15, rest: 45, met: 4.0,
              cues: ["Pin the elbows", "Full lockout, squeeze"], pain: ["Elbow"], subs: ["Overhead Triceps Extension"], note: "Triceps pump staple."),
        .make("Overhead Triceps Extension", .isolation, .dumbbell, primary: [.triceps], mechanic: .isolation,
              level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 60, met: 4.0,
              cues: ["Deep stretch behind the head", "Keep elbows in"], pain: ["Elbow"], subs: ["Triceps Pushdown"], note: "Loads the long head in the stretch."),
        .make("Skull Crusher", .isolation, .barbell, primary: [.triceps], mechanic: .isolation,
              level: .intermediate, sets: 3, repLow: 10, repHigh: 12, rest: 60, met: 4.0,
              cues: ["Lower to the forehead/behind", "Elbows steady"], pain: ["Elbow"], subs: ["Overhead Triceps Extension"], note: "Classic mass builder — go light if elbows complain."),
        .make("Bench Dip", .horizontalPush, .bodyweight, primary: [.triceps], secondary: [.chest],
              level: .beginner, sets: 3, repLow: 12, repHigh: 20, rest: 45, met: 4.0, cues: ["Stay close to the bench"], pain: ["Shoulder"], subs: ["Triceps Pushdown"], note: "No-equipment triceps."),
        .make("Barbell Curl", .isolation, .barbell, primary: [.biceps], secondary: [.forearms], mechanic: .isolation,
              force: .pull, level: .beginner, sets: 3, repLow: 8, repHigh: 12, rest: 60, met: 4.0,
              cues: ["Elbows pinned", "No swinging", "Squeeze the top"], faults: ["Heaving with the back"], pain: ["Wrist"],
              subs: ["Dumbbell Curl"], note: "Heaviest biceps loading."),
        .make("Dumbbell Curl", .isolation, .dumbbell, primary: [.biceps], secondary: [.forearms], mechanic: .isolation,
              force: .pull, level: .beginner, sets: 3, repLow: 10, repHigh: 12, rest: 45, met: 4.0,
              cues: ["Supinate as you curl"], subs: ["Barbell Curl", "Cable Curl"], note: "Even loading, easy on the wrists."),
        .make("Hammer Curl", .isolation, .dumbbell, primary: [.biceps, .forearms], mechanic: .isolation,
              force: .pull, level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 45, met: 4.0,
              cues: ["Neutral grip throughout"], subs: ["Dumbbell Curl"], note: "Brachialis + forearm thickness."),
        .make("Preacher Curl", .isolation, .machine, primary: [.biceps], mechanic: .isolation,
              force: .pull, level: .beginner, sets: 3, repLow: 10, repHigh: 12, rest: 60, met: 4.0,
              cues: ["Don't fully relax at the bottom"], pain: ["Elbow"], subs: ["Dumbbell Curl"], note: "Strict, stretch-biased curl."),
        .make("Incline Dumbbell Curl", .isolation, .dumbbell, primary: [.biceps], mechanic: .isolation,
              force: .pull, level: .intermediate, sets: 3, repLow: 10, repHigh: 12, rest: 60, met: 4.0,
              cues: ["Let the arms hang back for the stretch"], subs: ["Dumbbell Curl"], note: "Long-head stretch emphasis."),
        .make("Cable Curl", .isolation, .cable, primary: [.biceps], mechanic: .isolation,
              force: .pull, level: .beginner, sets: 3, repLow: 12, repHigh: 15, rest: 45, met: 4.0, subs: ["Dumbbell Curl"], note: "Constant tension curl."),
        .make("Wrist Curl", .isolation, .dumbbell, primary: [.forearms], mechanic: .isolation,
              force: .pull, level: .beginner, sets: 3, repLow: 15, repHigh: 20, rest: 45, met: 3.5, subs: ["Reverse Curl"], note: "Direct forearm flexor work."),
        .make("Reverse Curl", .isolation, .barbell, primary: [.forearms, .biceps], mechanic: .isolation,
              force: .pull, level: .beginner, sets: 3, repLow: 12, repHigh: 15, rest: 45, met: 3.5, cues: ["Pronated grip"], subs: ["Hammer Curl"], note: "Forearm extensors + brachialis."),
    ]

    // ── Legs · quad-dominant ─────────────────────────────────────────────────
    static let legsQuad: [ExerciseDefinition] = [
        .make("Back Squat", .squat, .barbell, primary: [.quads, .glutes], secondary: [.hamstrings, .lowerBack, .abs],
              level: .intermediate, sets: 4, repLow: 5, repHigh: 8, rest: 180, tempo: "3-1-1", met: 6.0, rpe: 8,
              cues: ["Brace, big breath at the top", "Knees track over toes", "Drive the floor away"],
              faults: ["Knees caving", "Heels rising", "Good-morning out of the hole"], pain: ["Knee", "Lower Back"],
              regress: ["Goblet Squat"], progress: ["Front Squat"], subs: ["Hack Squat", "Leg Press"], note: "Foundational lower-body strength lift."),
        .make("Front Squat", .squat, .barbell, primary: [.quads], secondary: [.glutes, .abs, .upperBack],
              level: .advanced, sets: 4, repLow: 4, repHigh: 8, rest: 180, met: 6.0,
              cues: ["Tall elbows, upright torso", "Stay over mid-foot"], pain: ["Knee", "Wrist"], subs: ["Hack Squat", "Goblet Squat"], note: "Quad-biased, spine-sparing squat."),
        .make("Goblet Squat", .squat, .dumbbell, primary: [.quads, .glutes], secondary: [.abs],
              level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 90, met: 5.0,
              cues: ["Elbows inside the knees", "Sit tall and deep"], pain: ["Knee"], subs: ["Leg Press"], note: "Best entry squat — teaches depth + bracing."),
        .make("Hack Squat", .squat, .machine, primary: [.quads], secondary: [.glutes],
              level: .beginner, sets: 3, repLow: 8, repHigh: 12, rest: 120, met: 5.5,
              cues: ["Feet low for quads", "Control the descent"], pain: ["Knee"], subs: ["Leg Press"], note: "Heavy quad loading, fixed path."),
        .make("Leg Press", .squat, .machine, primary: [.quads, .glutes], secondary: [.hamstrings],
              level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 120, met: 5.5,
              cues: ["Don't round the lower back at the bottom", "Knees track with toes"], pain: ["Knee"], subs: ["Hack Squat"], note: "High-volume quad work with low skill demand."),
        .make("Bulgarian Split Squat", .lunge, .dumbbell, primary: [.quads, .glutes], secondary: [.hamstrings, .abs],
              level: .intermediate, unilateral: true, sets: 3, repLow: 8, repHigh: 12, rest: 90, met: 5.5, rpe: 8,
              cues: ["Front shin near vertical for quads", "Torso lean for glutes", "Control the back leg"],
              faults: ["Pushing off the back foot"], pain: ["Knee"], subs: ["Walking Lunge", "Reverse Lunge"], note: "Unilateral strength + balance."),
        .make("Walking Lunge", .lunge, .dumbbell, primary: [.quads, .glutes], secondary: [.hamstrings],
              level: .beginner, unilateral: true, sets: 3, repLow: 10, repHigh: 12, rest: 75, met: 5.5,
              cues: ["Step long, drop straight down", "Tall posture"], pain: ["Knee"], subs: ["Reverse Lunge"], note: "Locomotor lunge pattern."),
        .make("Reverse Lunge", .lunge, .dumbbell, primary: [.quads, .glutes], secondary: [.hamstrings],
              level: .beginner, unilateral: true, sets: 3, repLow: 10, repHigh: 12, rest: 75, met: 5.0,
              cues: ["Step back, weight on the front heel"], pain: ["Knee"], subs: ["Walking Lunge", "Step-Up"], note: "Knee-friendlier lunge variation."),
        .make("Step-Up", .lunge, .dumbbell, primary: [.quads, .glutes], secondary: [.hamstrings],
              level: .beginner, unilateral: true, sets: 3, repLow: 10, repHigh: 12, rest: 75, met: 5.0,
              cues: ["Drive through the top foot", "Don't push off the bottom leg"], pain: ["Knee"], subs: ["Reverse Lunge"], note: "Athletic single-leg drive."),
        .make("Leg Extension", .isolation, .machine, primary: [.quads], mechanic: .isolation,
              level: .beginner, sets: 3, repLow: 12, repHigh: 20, rest: 60, met: 4.0,
              cues: ["Pause and squeeze at the top"], pain: ["Knee"], subs: ["Hack Squat"], note: "Isolated quad burn / rehab tool."),
    ]
    // ── Legs · posterior chain ──────────────────────────────────────────────
    static let legsPosterior: [ExerciseDefinition] = [
        .make("Conventional Deadlift", .hinge, .barbell, primary: [.hamstrings, .glutes, .lowerBack], secondary: [.lats, .traps, .forearms],
              force: .pull, level: .advanced, sets: 4, repLow: 3, repHigh: 6, rest: 210, tempo: "1-0-1", met: 6.5, rpe: 8,
              cues: ["Bar over mid-foot", "Wedge in, lats tight", "Push the floor away, hips and bar rise together"],
              faults: ["Rounding the lower back", "Bar drifting forward", "Hips shooting up early"], pain: ["Lower Back"],
              regress: ["Trap-Bar Deadlift"], subs: ["Romanian Deadlift", "Trap-Bar Deadlift"], note: "Maximal full-body pull — autoregulate hard on low readiness."),
        .make("Romanian Deadlift", .hinge, .barbell, primary: [.hamstrings, .glutes], secondary: [.lowerBack],
              force: .pull, level: .intermediate, sets: 3, repLow: 8, repHigh: 12, rest: 120, tempo: "3-1-1", met: 6.0, rpe: 8,
              cues: ["Soft knees, push hips back", "Bar drags the thighs", "Stretch the hamstrings, don't round"],
              faults: ["Turning it into a squat", "Lower-back rounding"], pain: ["Lower Back"], subs: ["Seated Leg Curl", "Cable Pull-Through"], note: "Premier hamstring builder via the stretch."),
        .make("Sumo Deadlift", .hinge, .barbell, primary: [.glutes, .hamstrings, .quads], secondary: [.adductors, .lowerBack],
              force: .pull, level: .advanced, sets: 4, repLow: 3, repHigh: 6, rest: 210, met: 6.5,
              cues: ["Wide stance, knees out", "Open the hips to the bar"], pain: ["Lower Back"], subs: ["Trap-Bar Deadlift"], note: "Upright torso — easier on the spine for many."),
        .make("Trap-Bar Deadlift", .hinge, .barbell, primary: [.glutes, .quads, .hamstrings], secondary: [.traps, .lowerBack],
              force: .pull, level: .intermediate, sets: 4, repLow: 5, repHigh: 8, rest: 180, met: 6.0,
              cues: ["Stand tall, push and pull together"], pain: ["Lower Back"], subs: ["Conventional Deadlift"], note: "Most accessible heavy hinge."),
        .make("Hip Thrust", .hinge, .barbell, primary: [.glutes], secondary: [.hamstrings],
              level: .beginner, sets: 4, repLow: 8, repHigh: 12, rest: 120, met: 5.5, rpe: 8,
              cues: ["Chin tucked, ribs down", "Drive through the heels", "Full lockout, squeeze the glutes"],
              faults: ["Overarching the lower back", "Short range"], subs: ["Glute Bridge", "Cable Pull-Through"], note: "Peak glute tension at lockout."),
        .make("Glute Bridge", .hinge, .bodyweight, primary: [.glutes], secondary: [.hamstrings],
              level: .beginner, sets: 3, repLow: 12, repHigh: 20, rest: 60, met: 4.0, cues: ["Posterior tilt, squeeze hard"], subs: ["Hip Thrust"], note: "Floor-based glute activation."),
        .make("Good Morning", .hinge, .barbell, primary: [.hamstrings, .lowerBack], secondary: [.glutes],
              force: .pull, level: .advanced, sets: 3, repLow: 8, repHigh: 12, rest: 120, met: 5.0,
              cues: ["Soft knees, hinge with a flat back"], pain: ["Lower Back"], subs: ["Romanian Deadlift"], note: "Loads the hamstrings + spinal erectors — go conservative."),
        .make("Back Extension", .hinge, .bodyweight, primary: [.lowerBack, .glutes], secondary: [.hamstrings],
              force: .pull, level: .beginner, sets: 3, repLow: 12, repHigh: 15, rest: 60, met: 4.0,
              cues: ["Round and extend under control", "Squeeze the glutes at the top"], pain: ["Lower Back"], subs: ["Glute Bridge"], note: "Posterior-chain endurance + spinal health."),
        .make("Kettlebell Swing", .hinge, .kettlebell, primary: [.glutes, .hamstrings], secondary: [.lowerBack, .cardio],
              modality: .power, level: .intermediate, sets: 4, repLow: 12, repHigh: 20, rest: 75, met: 9.0, rpe: 7,
              cues: ["Hike the bell back", "Snap the hips, float the bell", "Arms are ropes"], faults: ["Squatting the swing", "Lifting with the arms"],
              pain: ["Lower Back"], subs: ["Cable Pull-Through"], note: "Explosive hinge — power + conditioning."),
        .make("Cable Pull-Through", .hinge, .cable, primary: [.glutes, .hamstrings], secondary: [.lowerBack],
              level: .beginner, sets: 3, repLow: 12, repHigh: 15, rest: 60, met: 4.5, cues: ["Hinge back, snap forward, squeeze"], subs: ["Hip Thrust"], note: "Teaches the hinge with constant tension."),
        .make("Seated Leg Curl", .isolation, .machine, primary: [.hamstrings], mechanic: .isolation, force: .pull,
              level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 60, met: 4.0, cues: ["Pause at full flexion"], subs: ["Lying Leg Curl"], note: "Isolated knee-flexion hamstring work."),
        .make("Lying Leg Curl", .isolation, .machine, primary: [.hamstrings], mechanic: .isolation, force: .pull,
              level: .beginner, sets: 3, repLow: 10, repHigh: 15, rest: 60, met: 4.0, subs: ["Seated Leg Curl"], note: "Hamstring isolation, prone."),
        .make("Nordic Curl", .isolation, .bodyweight, primary: [.hamstrings], mechanic: .isolation, force: .pull,
              level: .advanced, sets: 3, repLow: 5, repHigh: 8, rest: 90, met: 4.5, cues: ["Resist the fall as long as possible"], subs: ["Lying Leg Curl"], note: "Elite eccentric hamstring strength + injury prevention."),
        .make("Standing Calf Raise", .isolation, .machine, primary: [.calves], mechanic: .isolation,
              level: .beginner, sets: 4, repLow: 12, repHigh: 20, rest: 45, tempo: "2-1-2", met: 4.0, cues: ["Full stretch, full squeeze", "Pause at the top"], subs: ["Seated Calf Raise"], note: "Gastrocnemius emphasis (knees straight)."),
        .make("Seated Calf Raise", .isolation, .machine, primary: [.calves], mechanic: .isolation,
              level: .beginner, sets: 3, repLow: 15, repHigh: 20, rest: 45, met: 4.0, subs: ["Standing Calf Raise"], note: "Soleus emphasis (knees bent)."),
        .make("Hip Adduction", .isolation, .machine, primary: [.adductors], mechanic: .isolation,
              level: .beginner, sets: 3, repLow: 12, repHigh: 20, rest: 45, met: 4.0, subs: ["Cossack Squat"], note: "Inner-thigh + groin resilience."),
        .make("Hip Abduction", .isolation, .machine, primary: [.abductors, .glutes], mechanic: .isolation,
              level: .beginner, sets: 3, repLow: 15, repHigh: 20, rest: 45, met: 4.0, subs: ["Hip Thrust"], note: "Glute medius — hip stability."),
        .make("Cossack Squat", .lunge, .bodyweight, primary: [.adductors, .quads], secondary: [.glutes], force: .isometric,
              modality: .mobility, level: .intermediate, unilateral: true, sets: 3, repLow: 6, repHigh: 10, rest: 60, met: 5.0, cues: ["Sit into one hip, keep the heel down"], pain: ["Knee"], subs: ["Hip Adduction"], note: "Mobility + adductor strength."),
    ]

    // ── Core + carries ───────────────────────────────────────────────────────
    static let coreCarry: [ExerciseDefinition] = [
        .make("Plank", .antiRotation, .bodyweight, primary: [.abs], secondary: [.obliques], force: .isometric,
              level: .beginner, sets: 3, repLow: 30, repHigh: 60, rest: 45, met: 3.5, cues: ["Posterior tilt, squeeze everything", "Don't sag or pike"], note: "Reps = seconds. Anti-extension foundation."),
        .make("Side Plank", .antiRotation, .bodyweight, primary: [.obliques], secondary: [.abs], force: .isometric,
              level: .beginner, unilateral: true, sets: 3, repLow: 30, repHigh: 45, rest: 45, met: 3.5, cues: ["Stack the hips, push the floor away"], subs: ["Pallof Press"], note: "Anti-lateral-flexion. Reps = seconds."),
        .make("Hanging Leg Raise", .coreFlexion, .bodyweight, primary: [.abs], secondary: [.hipFlexors],
              force: .pull, level: .intermediate, sets: 3, repLow: 8, repHigh: 15, rest: 60, met: 4.0, cues: ["Posterior tilt, lift with the abs not the hips", "No swinging"], subs: ["Cable Crunch"], note: "Hardest bodyweight ab flexion."),
        .make("Cable Crunch", .coreFlexion, .cable, primary: [.abs], mechanic: .isolation,
              level: .beginner, sets: 3, repLow: 12, repHigh: 20, rest: 45, met: 4.0, cues: ["Crunch the ribs to the pelvis", "Hips stay fixed"], subs: ["Hanging Leg Raise"], note: "Loadable ab flexion."),
        .make("Ab Wheel Rollout", .antiRotation, .bodyweight, primary: [.abs], secondary: [.obliques, .lats], force: .isometric,
              level: .advanced, sets: 3, repLow: 8, repHigh: 12, rest: 60, met: 4.0, cues: ["Brace, ribs down", "Don't let the lower back arch"], pain: ["Lower Back"], subs: ["Plank"], note: "Elite anti-extension strength."),
        .make("Russian Twist", .rotation, .medicineBall, primary: [.obliques], secondary: [.abs],
              level: .beginner, sets: 3, repLow: 16, repHigh: 24, rest: 45, met: 4.0, cues: ["Rotate from the ribcage", "Controlled, not frantic"], subs: ["Pallof Press"], note: "Rotational core endurance."),
        .make("Pallof Press", .antiRotation, .cable, primary: [.obliques], secondary: [.abs], force: .isometric,
              level: .beginner, sets: 3, repLow: 10, repHigh: 12, rest: 45, met: 3.5, cues: ["Resist the rotation", "Press straight out, stay square"], subs: ["Side Plank"], note: "Best anti-rotation builder for spine health."),
        .make("Dead Bug", .antiRotation, .bodyweight, primary: [.abs], force: .isometric, modality: .mobility,
              level: .beginner, sets: 3, repLow: 8, repHigh: 12, rest: 45, met: 3.0, cues: ["Lower back glued to the floor", "Slow opposite arm/leg"], subs: ["Bird Dog"], note: "Core control + lumbar protection."),
        .make("Bird Dog", .antiRotation, .bodyweight, primary: [.lowerBack], secondary: [.glutes, .abs], force: .isometric, modality: .mobility,
              level: .beginner, sets: 3, repLow: 8, repHigh: 12, rest: 45, met: 3.0, cues: ["Reach long, stay square", "No hip rotation"], subs: ["Dead Bug"], note: "Spinal stability + glute timing."),
        .make("Hollow Hold", .coreFlexion, .bodyweight, primary: [.abs], force: .isometric,
              level: .intermediate, sets: 3, repLow: 20, repHigh: 40, rest: 45, met: 3.5, cues: ["Lower back pressed down, long body line"], subs: ["Plank"], note: "Gymnastic core tension. Reps = seconds."),
        .make("Farmer's Carry", .carry, .dumbbell, primary: [.forearms, .traps], secondary: [.abs, .glutes], force: .isometric,
              modality: .conditioning, level: .beginner, sets: 3, repLow: 30, repHigh: 50, rest: 75, met: 6.0, cues: ["Tall and braced", "Crush the handles", "Even, quiet steps"], subs: ["Plank"], note: "Grip, trunk + work capacity. Reps = meters."),
    ]
    // ── Conditioning ─────────────────────────────────────────────────────────
    static let conditioning: [ExerciseDefinition] = [
        .make("Burpee", .gait, .bodyweight, primary: [.fullBody], secondary: [.cardio], modality: .conditioning,
              level: .beginner, sets: 4, repLow: 10, repHigh: 20, rest: 60, met: 9.0, rpe: 8, cues: ["Chest to floor, explode up", "Find a sustainable rhythm"], subs: ["Mountain Climbers"], note: "Full-body metabolic hit."),
        .make("Mountain Climbers", .gait, .bodyweight, primary: [.abs], secondary: [.cardio, .hipFlexors], modality: .conditioning,
              level: .beginner, sets: 3, repLow: 20, repHigh: 40, rest: 45, met: 8.0, cues: ["Flat back, fast knees"], subs: ["Burpee"], note: "Core-driven cardio bursts."),
        .make("Jump Rope", .gait, .cardioMachine, primary: [.calves], secondary: [.cardio], modality: .conditioning,
              level: .beginner, sets: 5, repLow: 30, repHigh: 60, rest: 45, met: 11.0, cues: ["Wrists turn the rope", "Light on the balls of the feet"], subs: ["Box Jump"], note: "Foot speed + conditioning. Reps = seconds."),
        .make("Rowing Erg", .gait, .cardioMachine, primary: [.fullBody], secondary: [.cardio, .upperBack], modality: .conditioning,
              force: .pull, level: .beginner, sets: 1, repLow: 250, repHigh: 1000, rest: 60, met: 8.5, cues: ["Legs → hips → arms, reverse on the return", "Drive with the legs"], subs: ["Assault Bike"], note: "Low-impact full-body cardio. Reps = meters."),
        .make("Assault Bike", .gait, .cardioMachine, primary: [.fullBody], secondary: [.cardio], modality: .conditioning,
              level: .beginner, sets: 1, repLow: 30, repHigh: 60, rest: 90, met: 9.5, cues: ["Push and pull the arms", "Pace the intervals"], subs: ["Rowing Erg"], note: "Brutal, scalable intervals. Reps = seconds."),
        .make("Box Jump", .squat, .bodyweight, primary: [.quads, .glutes], secondary: [.calves], modality: .power,
              level: .intermediate, sets: 4, repLow: 3, repHigh: 6, rest: 90, met: 7.0, rpe: 7, cues: ["Land soft, hips back", "Step down, don't bounce off"], pain: ["Knee", "Ankle"], subs: ["Kettlebell Swing"], note: "Lower-body power + rate of force."),
        .make("Battle Ropes", .gait, .bodyweight, primary: [.frontDelts], secondary: [.cardio, .abs], modality: .conditioning,
              level: .beginner, sets: 4, repLow: 20, repHigh: 40, rest: 60, met: 8.0, cues: ["Athletic stance, brace", "Big, fast waves"], subs: ["Assault Bike"], note: "Upper-body conditioning. Reps = seconds."),
        .make("Sled Push", .carry, .sled, primary: [.quads, .glutes], secondary: [.cardio, .calves], modality: .conditioning,
              level: .beginner, sets: 4, repLow: 15, repHigh: 30, rest: 90, met: 9.0, cues: ["Low angle, drive long strides"], subs: ["Walking Lunge"], note: "Quad + conditioning with zero eccentric. Reps = meters."),
        .make("Treadmill Run", .gait, .cardioMachine, primary: [.cardio], secondary: [.quads, .calves], modality: .endurance,
              level: .beginner, sets: 1, repLow: 600, repHigh: 1800, rest: 0, met: 9.0, cues: ["Relaxed shoulders, midfoot strike"], subs: ["Rowing Erg"], note: "Steady-state aerobic base. Reps = seconds."),
        .make("Stair Climber", .gait, .cardioMachine, primary: [.glutes, .quads], secondary: [.cardio, .calves], modality: .endurance,
              level: .beginner, sets: 1, repLow: 600, repHigh: 1200, rest: 0, met: 8.0, cues: ["Tall posture, don't lean on the rails"], subs: ["Treadmill Run"], note: "Glute-biased low-impact cardio. Reps = seconds."),
    ]

    // ── Mobility / warm-up ───────────────────────────────────────────────────
    static let mobility: [ExerciseDefinition] = [
        .make("World's Greatest Stretch", .mobility, .bodyweight, primary: [.hipFlexors], secondary: [.fullBody], force: .isometric, modality: .mobility,
              level: .beginner, unilateral: true, sets: 2, repLow: 5, repHigh: 8, rest: 30, met: 3.0, cues: ["Lunge, reach, rotate, breathe"], note: "Full-body dynamic warm-up."),
        .make("Band Pull-Apart", .horizontalPull, .bands, primary: [.rearDelts], secondary: [.upperBack], mechanic: .isolation, force: .pull, modality: .mobility,
              level: .beginner, sets: 3, repLow: 15, repHigh: 25, rest: 30, met: 3.0, cues: ["Squeeze the blades, pull to the chest"], subs: ["Face Pull"], note: "Shoulder prep + posture."),
        .make("Cat-Cow", .mobility, .bodyweight, primary: [.lowerBack], force: .isometric, modality: .mobility,
              level: .beginner, sets: 2, repLow: 8, repHigh: 12, rest: 20, met: 2.5, cues: ["Segment the spine slowly with the breath"], note: "Spinal mobility flow."),
        .make("90/90 Hip Rotation", .mobility, .bodyweight, primary: [.hipFlexors], secondary: [.glutes], force: .isometric, modality: .mobility,
              level: .beginner, sets: 2, repLow: 8, repHigh: 12, rest: 20, met: 2.5, cues: ["Rotate both knees together, stay tall"], note: "Hip internal/external rotation."),
        .make("Thoracic Rotation", .mobility, .bodyweight, primary: [.upperBack], force: .isometric, modality: .mobility,
              level: .beginner, unilateral: true, sets: 2, repLow: 6, repHigh: 10, rest: 20, met: 2.5, cues: ["Open the chest, follow the hand with the eyes"], note: "Upper-back rotation for pressing/pulling."),
        .make("Couch Stretch", .mobility, .bodyweight, primary: [.hipFlexors], secondary: [.quads], force: .isometric, modality: .mobility,
              level: .beginner, unilateral: true, sets: 2, repLow: 30, repHigh: 45, rest: 20, met: 2.5, cues: ["Tuck the pelvis, breathe into the stretch"], note: "Hip-flexor + quad length. Reps = seconds."),
        .make("Hip Flexor Stretch", .mobility, .bodyweight, primary: [.hipFlexors], force: .isometric, modality: .mobility,
              level: .beginner, unilateral: true, sets: 2, repLow: 30, repHigh: 45, rest: 20, met: 2.5, cues: ["Squeeze the back glute, tuck the tailbone"], note: "Counter to sitting. Reps = seconds."),
        .make("Shoulder Dislocates", .mobility, .bands, primary: [.frontDelts], secondary: [.upperBack], force: .isometric, modality: .mobility,
              level: .beginner, sets: 2, repLow: 8, repHigh: 12, rest: 20, met: 2.5, cues: ["Wide grip, smooth arc over the head"], note: "Shoulder range prep."),
        .make("Foam Roll Flow", .mobility, .bodyweight, primary: [.fullBody], force: .isometric, modality: .mobility,
              level: .beginner, sets: 1, repLow: 30, repHigh: 60, rest: 0, met: 2.5, cues: ["Slow passes, pause on tight spots"], note: "Self-myofascial down-regulation. Reps = seconds."),
    ]

    // MARK: Lookup + filtering

    private static let byID: [String: ExerciseDefinition] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    private static func normalized(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined()
    }

    /// Best-effort match from a lightweight plan row name to a rich definition.
    static func match(_ name: String) -> ExerciseDefinition? {
        if let d = byID[forgeSlug(name)] { return d }
        let target = normalized(name)
        if let exact = all.first(where: { normalized($0.name) == target }) { return exact }
        if let contains = all.first(where: { normalized($0.name).contains(target) || target.contains(normalized($0.name)) }) { return contains }
        // token-overlap fallback (e.g. "Incline DB Press" → "Incline Dumbbell Press")
        let tokens = Set(name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)).subtracting(["the", "a", "db"])
        return all.max { lhs, rhs in tokenScore(lhs, tokens) < tokenScore(rhs, tokens) }
            .flatMap { tokenScore($0, tokens) >= 1 ? $0 : nil }
    }

    private static func tokenScore(_ def: ExerciseDefinition, _ tokens: Set<String>) -> Int {
        let defTokens = Set(def.name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return tokens.intersection(defTokens).count
    }

    static func definition(for exercise: Exercise) -> ExerciseDefinition? { match(exercise.name) }

    static func filter(query: String, muscle: MuscleGroup?, equipment: Equipment?, pattern: MovementPattern?) -> [ExerciseDefinition] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { def in
            (q.isEmpty || def.name.lowercased().contains(q) || def.muscleSummary.lowercased().contains(q))
            && (muscle == nil || def.primary.contains(muscle!) || def.secondary.contains(muscle!))
            && (equipment == nil || def.equipment == equipment!)
            && (pattern == nil || def.pattern == pattern!)
        }
    }
}
// MARK: - Rep parsing

extension String {
    /// Parses "6-8", "12", "15-20", "30 sec" → (low, high). Non-numeric → (0,0).
    var repBounds: (low: Int, high: Int) {
        let nums = split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if nums.isEmpty { return (0, 0) }
        if nums.count == 1 { return (nums[0], nums[0]) }
        return (nums.min()!, nums.max()!)
    }
    var repMidpoint: Int {
        let b = repBounds
        return (b.low + b.high) / 2
    }
}

// MARK: - Adaptive Auto-Regulation Engine
//
// Grounded in established practice: RIR/RPE autoregulation (Helms/Zourdos), readiness-led
// volume-load scaling, pain-monitoring with movement substitution, and intra-set rest
// modulation off heart-rate recovery + oxygen saturation.

enum AutoRegAction: Equatable {
    case increaseLoad(Int)      // +lbs next set
    case decreaseLoad(Int)      // −lbs next set
    case hold
    case extendRest(Int)        // +seconds
    case reduceReps(Int)
    case addReps(Int)
    case substitute(reason: String)
    case deload                 // global volume cut
    case stopExercise(reason: String)

    var tone: Color {
        switch self {
        case .increaseLoad, .addReps: return .success
        case .hold: return .steel
        case .decreaseLoad, .reduceReps, .extendRest, .deload: return .warning
        case .substitute, .stopExercise: return .danger
        }
    }
    var icon: String {
        switch self {
        case .increaseLoad: return "arrow.up.circle.fill"
        case .decreaseLoad, .reduceReps: return "arrow.down.circle.fill"
        case .hold: return "equal.circle.fill"
        case .addReps: return "plus.circle.fill"
        case .extendRest: return "clock.badge.fill"
        case .substitute: return "arrow.triangle.swap"
        case .deload: return "tortoise.fill"
        case .stopExercise: return "hand.raised.fill"
        }
    }
}

struct SetRecommendation {
    var weightDelta: Int
    var repTarget: Int
    var restSeconds: Int
    var rpeTarget: Int
    var primaryAction: AutoRegAction
    var rationale: String
}

/// What the plan should look like given today's recovery state.
struct PlanScaling {
    var volumeMultiplier: Double   // applied to sets
    var intensityMultiplier: Double // applied to load
    var headline: String
    var detail: String
    var tone: Color
    var isModified: Bool { abs(volumeMultiplier - 1) > 0.01 || abs(intensityMultiplier - 1) > 0.01 }
}

enum AdaptiveEngine {

    // ── Pre-workout: scale the whole session to recovery ──────────────────────
    static func scaling(readiness: ReadinessData, experience: ExperienceLevel) -> PlanScaling {
        let r = readiness.overall
        switch r {
        case 85...:
            return PlanScaling(volumeMultiplier: 1.10, intensityMultiplier: 1.03,
                               headline: "Primed — green light",
                               detail: "Recovery is excellent. ARIA added a top-set and nudged loads up ~3%. Chase a rep PR on your first compound.",
                               tone: .success)
        case 70..<85:
            return PlanScaling(volumeMultiplier: 1.0, intensityMultiplier: 1.0,
                               headline: "On plan",
                               detail: "Readiness is solid. Run the session as written and let RPE guide your top sets.",
                               tone: .steel)
        case 55..<70:
            return PlanScaling(volumeMultiplier: 0.85, intensityMultiplier: 0.93,
                               headline: "Trim the volume",
                               detail: "Recovery is moderate. ARIA cut ~15% of volume and held loads ~7% lighter to protect tomorrow.",
                               tone: .warning)
        default:
            return PlanScaling(volumeMultiplier: 0.65, intensityMultiplier: 0.85,
                               headline: "Recovery day protocol",
                               detail: "Readiness is low. ARIA pulled volume and intensity back hard — move well, leave 3+ reps in reserve, prioritize sleep.",
                               tone: .danger)
        }
    }

    /// Applies scaling to a single plan row (non-destructive — returns a new Exercise).
    static func scaled(_ exercise: Exercise, by scaling: PlanScaling) -> Exercise {
        guard scaling.isModified else { return exercise }
        var ex = exercise
        ex.sets = max(1, Int((Double(exercise.sets) * scaling.volumeMultiplier).rounded()))
        if let w = exercise.weight, w > 0 {
            ex.weight = max(5, Int(((Double(w) * scaling.intensityMultiplier) / 5).rounded()) * 5)
        }
        return ex
    }

    // ── Intra-set: recommend the next set from live data ──────────────────────
    static func recommend(
        definition: ExerciseDefinition?,
        targetReps: Int, targetRPE: Int, baseRest: Int, currentWeight: Int,
        lastRPE: Int?, lastReps: Int?,
        readiness: ReadinessData, experience: ExperienceLevel,
        currentHR: Int, hrZone: Int, spO2: Int,
        painSeverity: Int?, painLocation: String?
    ) -> SetRecommendation {
        var rec = SetRecommendation(weightDelta: 0, repTarget: targetReps, restSeconds: baseRest,
                                    rpeTarget: targetRPE, primaryAction: .hold,
                                    rationale: "Match last set and own every rep.")

        // 1) Pain trumps everything (sports-medicine first principle).
        if let sev = painSeverity, sev >= 7 {
            rec.primaryAction = .stopExercise(reason: painLocation ?? "pain")
            rec.rationale = "Sharp \(painLocation?.lowercased() ?? "joint") pain at \(sev)/10 — stop this movement. ARIA will swap to a joint-friendly option."
            return rec
        }
        if let sev = painSeverity, sev >= 5, let loc = painLocation,
           (definition?.painContraindications.contains(loc) ?? false) {
            rec.primaryAction = .substitute(reason: loc)
            rec.rationale = "\(loc) discomfort on a movement that loads it — ARIA is lining up a substitution."
            return rec
        }

        // 2) Cardiopulmonary guardrails — extend rest before more load.
        if spO2 < 94 {
            rec.primaryAction = .extendRest(45)
            rec.restSeconds = baseRest + 45
            rec.rationale = "O₂ dipped to \(spO2)%. Breathe it back above 95% before the next set."
            return rec
        }
        if hrZone >= 5 {
            rec.primaryAction = .extendRest(30)
            rec.restSeconds = baseRest + 30
            rec.rationale = "HR is in Zone 5 (\(currentHR) bpm). +30s rest so strength output stays high."
            return rec
        }

        // 3) RIR/RPE autoregulation off the last set.
        let isCompound = definition?.isCompound ?? true
        let loadStep = isCompound ? (experience == .beginner ? 5 : 10) : 5
        if let rpe = lastRPE {
            let reps = lastReps ?? targetReps
            if rpe <= targetRPE - 2 && reps >= targetReps {
                rec.weightDelta = loadStep
                rec.primaryAction = .increaseLoad(loadStep)
                rec.rationale = "Last set was RPE \(rpe) with reps in the tank — add \(loadStep) lb and keep the bar speed."
            } else if rpe >= targetRPE + 1 || reps < max(1, targetReps - 2) {
                if readiness.overall < 60 {
                    rec.weightDelta = -loadStep
                    rec.primaryAction = .decreaseLoad(loadStep)
                    rec.rationale = "RPE \(rpe) on low readiness — drop \(loadStep) lb and keep crisp reps."
                } else {
                    rec.repTarget = max(1, targetReps - 2)
                    rec.primaryAction = .reduceReps(2)
                    rec.rationale = "RPE \(rpe) is past target — hold the load, aim for \(rec.repTarget) clean reps."
                }
            } else if rpe == targetRPE - 1 {
                rec.primaryAction = .hold
                rec.rationale = "Dialed in at RPE \(rpe). Repeat the load and chase one more rep if it moves well."
            }
        } else {
            // First working set — anchor to readiness.
            if readiness.overall >= 85 {
                rec.rationale = "Recovery is high — treat the first set as a primer, then push the top set."
            } else if readiness.overall < 60 {
                rec.rpeTarget = max(6, targetRPE - 1)
                rec.rationale = "Cap effort near RPE \(rec.rpeTarget) today and leave reps in reserve."
            }
        }

        // 4) Rest length: heavier compounds + higher effort → longer.
        if rec.restSeconds == baseRest {
            if isCompound && rec.rpeTarget >= 8 { rec.restSeconds = max(baseRest, 120) }
            else if !isCompound { rec.restSeconds = min(baseRest, 75) }
        }
        return rec
    }

    /// Finds a joint-friendly replacement for a flagged movement.
    static func substitution(for exercise: Exercise, painLocation: String) -> ExerciseDefinition? {
        let current = ExerciseLibrary.definition(for: exercise)
        // Prefer the movement's own listed substitutes that don't load the painful joint.
        if let subs = current?.substitutes {
            for name in subs {
                if let def = ExerciseLibrary.match(name), !def.painContraindications.contains(painLocation) {
                    return def
                }
            }
        }
        // Otherwise: same pattern/region, equipment-light, no contraindication.
        guard let current else { return nil }
        return ExerciseLibrary.all.first { def in
            def.id != current.id
            && def.region == current.region
            && !def.painContraindications.contains(painLocation)
            && def.mechanic == current.mechanic
        }
    }
}
// MARK: - ARIA Coach Service (Claude vision + briefings)

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
// MARK: - ARIA Session Snapshot (dashboard → coach)

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
    var muscleVolume: [MuscleGroup: Double]   // relative working-set load per group
    var zoneSeconds: [Int]                    // index 1...5
    var autoRegLog: [String]
    var painFlags: [String]
    var personalRecords: [String]

    /// Balance read: which regions got the most / least work.
    var regionShare: [(MuscleGroup.Region, Double)] {
        var totals: [MuscleGroup.Region: Double] = [:]
        for (m, v) in muscleVolume { totals[m.region, default: 0] += v }
        let sum = max(1, totals.values.reduce(0, +))
        return MuscleGroup.Region.allRegions.map { ($0, (totals[$0] ?? 0) / sum) }
    }

    var topMuscles: [(MuscleGroup, Double)] {
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

extension MuscleGroup.Region {
    static var allRegions: [MuscleGroup.Region] { [.push, .pull, .legs, .core, .conditioning] }
    var accent: Color {
        switch self {
        case .push: return .ember
        case .pull: return Color(hex: "38BDF8")
        case .legs: return Color(hex: "A855F7")
        case .core: return .success
        case .conditioning: return .warning
        }
    }
}

extension Int {
    var formattedVolume: String {
        self >= 1000 ? String(format: "%.1fk", Double(self) / 1000) : "\(self)"
    }
}

// MARK: - Camera Capture (real AVFoundation pipeline)

@MainActor
final class FormCameraController: NSObject, ObservableObject {
    enum Status { case idle, configuring, running, denied, unavailable, failed }
    @Published var status: Status = .idle
    @Published var usingFront = true

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "forge.camera.session")
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    func start() {
        #if targetEnvironment(simulator)
        status = .unavailable
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.configure() } else { self.status = .denied }
                }
            }
        default: status = .denied
        }
        #endif
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    func flip() {
        usingFront.toggle()
        queue.async { [weak self] in self?.reconfigureInput() }
    }

    private func configure() {
        status = .configuring
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            self.reconfigureInput()
            if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
            self.session.commitConfiguration()
            self.session.startRunning()
            Task { @MainActor in self.status = self.session.isRunning ? .running : .failed }
        }
    }

    private func reconfigureInput() {
        for input in session.inputs { session.removeInput(input) }
        let position: AVCaptureDevice.Position = usingFront ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            Task { @MainActor in self.status = .failed }
            return
        }
        session.addInput(input)
    }

    /// Captures one still and returns it as a UIImage.
    func capture() async -> UIImage? {
        guard status == .running else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            self.captureContinuation = cont
            let settings = AVCapturePhotoSettings()
            self.queue.async { [weak self] in
                guard let self else { cont.resume(returning: nil); return }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension FormCameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            self.captureContinuation?.resume(returning: image)
            self.captureContinuation = nil
        }
    }
}

/// Live preview backed by AVCaptureVideoPreviewLayer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
// MARK: - HR Zone

fileprivate struct WorkoutHRZone: Equatable {
    let label: String
    let color: Color
    let range: ClosedRange<Int>
    let index: Int
    static func == (l: WorkoutHRZone, r: WorkoutHRZone) -> Bool { l.label == r.label }
}

fileprivate let workoutHRZones: [WorkoutHRZone] = [
    WorkoutHRZone(label: "Rest",   color: .steel,               range: 0...99,    index: 0),
    WorkoutHRZone(label: "Zone 1", color: Color(hex: "38BDF8"),  range: 100...114, index: 1),
    WorkoutHRZone(label: "Zone 2", color: .success,              range: 115...133, index: 2),
    WorkoutHRZone(label: "Zone 3", color: Color(hex: "F59E0B"),  range: 134...152, index: 3),
    WorkoutHRZone(label: "Zone 4", color: .ember,                range: 153...171, index: 4),
    WorkoutHRZone(label: "Zone 5", color: .danger,               range: 172...220, index: 5),
]
fileprivate func workoutHRZone(for bpm: Int) -> WorkoutHRZone {
    workoutHRZones.first { $0.range.contains(bpm) } ?? workoutHRZones[0]
}

// MARK: - Data Models

fileprivate struct SetLogEntry: Identifiable {
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

fileprivate struct PainEntry: Identifiable {
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
    var muscleVolume:       [String: Double] = [:]   // MuscleGroup.rawValue → relative load
    var autoRegLog:         [String] = []
    var painFlags:          [String] = []
    var readiness:          Int = 0
    var workoutName:        String = ""

    var ariaSnapshot: ARIASessionSnapshot {
        var mv: [MuscleGroup: Double] = [:]
        for (k, v) in muscleVolume { if let g = MuscleGroup(rawValue: k) { mv[g] = v } }
        var zones = Array(repeating: 0, count: 6)
        for hr in hrHistory { zones[workoutHRZone(for: hr).index] += 2 }
        return ARIASessionSnapshot(
            title: workoutName.isEmpty ? "Workout" : workoutName,
            durationSec: duration, totalVolume: totalVolume, totalSets: totalSets,
            totalReps: totalReps, exercisesCompleted: exercisesCompleted, avgHR: avgHR,
            peakHR: peakHR, minO2: minO2, avgRPE: avgRPE, calories: caloriesBurned,
            readiness: readiness, muscleVolume: mv, zoneSeconds: Array(zones.dropFirst()),
            autoRegLog: autoRegLog, painFlags: painFlags, personalRecords: personalRecords)
    }
}

// MARK: - Tab Root

struct WorkoutView: View {
    @EnvironmentObject var store: AppStore
    @State private var summaryData: WorkoutSummaryData? = nil
    @State private var showSummary = false

    var body: some View {
        ZStack {
            if showSummary, let summary = summaryData {
                WorkoutSummaryView(data: summary, onDismiss: {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                        showSummary = false; summaryData = nil
                    }
                })
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94).combined(with: .opacity),
                    removal:   .scale(scale: 1.04).combined(with: .opacity)
                ))
                .zIndex(10)
            } else if store.isWorkoutActive {
                ActiveWorkoutView { data in
                    summaryData = data
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { showSummary = true }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                    removal:   .scale(scale: 1.04).combined(with: .opacity)
                ))
                .zIndex(5)
            } else {
                WorkoutIdleView()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal:   .scale(scale: 0.96).combined(with: .opacity)
                    ))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: store.isWorkoutActive)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: showSummary)
    }
}
// MARK: - Idle View

struct WorkoutIdleView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var music = MusicControllerFactory.make(for: .appleMusic)
    @State private var appeared = false
    @State private var pulseOrb = false
    @State private var selectedExerciseIndex: Int? = nil
    @State private var showLibrary = false
    @State private var showDashboard = false
    @State private var scalingApplied = false

    private var scaling: PlanScaling { AdaptiveEngine.scaling(readiness: store.readiness, experience: store.userProfile.experienceLevel) }

    var body: some View {
        ZStack {
            WorkoutBackground(accentColor: .ember).ignoresSafeArea()
            if let workout = store.todayWorkout {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        idleHeader(workout: workout)
                            .padding(.horizontal, 20).padding(.top, 60)

                        quickActions
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.22), value: appeared)

                        AdaptiveScalingCard(scaling: scaling, applied: scalingApplied) { applyScaling(workout: workout) }
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: appeared)

                        MusicControlBar(controller: music, compact: false)
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.36), value: appeared)

                        exerciseList(workout: workout).padding(.horizontal, 16)

                        WorkoutInsightsView(workout: workout)
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 18)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.48), value: appeared)

                        startButton(workout: workout)
                            .padding(.horizontal, 16).padding(.bottom, 110)
                    }
                }
            } else {
                WorkoutEmptyState()
            }
        }
        .sheet(isPresented: $showLibrary) { ExerciseLibraryView() }
        .sheet(isPresented: $showDashboard) {
            if let workout = store.todayWorkout {
                ARIADashboardView(snapshot: Self.plannedSnapshot(workout, readiness: store.readiness),
                                  isPreWorkout: true)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.8).delay(0.08)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulseOrb = true }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            idleActionTile(icon: "books.vertical.fill", title: "Library", subtitle: "\(ExerciseLibrary.all.count) moves", accent: Color(hex: "38BDF8")) { showLibrary = true }
            idleActionTile(icon: "brain.head.profile", title: "ARIA Brief", subtitle: "Plan readout", accent: .ember) { showDashboard = true }
        }
    }

    private func idleActionTile(icon: String, title: String, subtitle: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(); action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(accent.opacity(0.14)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                    Text(subtitle).font(.system(size: 11)).foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.surface).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func applyScaling(workout: WorkoutPlan) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            store.todayWorkout?.exercises = workout.exercises.map { AdaptiveEngine.scaled($0, by: scaling) }
            scalingApplied = true
        }
    }

    private func idleHeader(workout: WorkoutPlan) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.ember.opacity(0.18))
                    .frame(width: 90, height: 90).blur(radius: 22)
                    .scaleEffect(pulseOrb ? 1.45 : 0.85)
                    .opacity(pulseOrb ? 0.15 : 0.9)
                Circle()
                    .fill(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.75)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.ember.opacity(0.5), radius: 20, y: 6)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 36, weight: .black)).foregroundColor(.white)
            }
            .scaleEffect(appeared ? 1 : 0.7).opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.65, dampingFraction: 0.7).delay(0.1), value: appeared)

            VStack(spacing: 6) {
                Text(workout.name)
                    .font(.system(size: 32, weight: .bold)).foregroundColor(.textPrimary).multilineTextAlignment(.center)
                Text(workout.type.label.uppercased())
                    .font(.system(size: 11, weight: .black)).tracking(2.5).foregroundColor(.ember)
            }
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.18), value: appeared)

            HStack(spacing: 8) {
                WorkoutStatPill(icon: "list.bullet",    value: "\(workout.exercises.count)",   label: "exercises")
                WorkoutStatPill(icon: "clock.fill",     value: "~\(workout.duration)",         label: "min")
                WorkoutStatPill(icon: "flame.fill",     value: "\(workout.estimatedCalories)", label: "cal",  color: workout.intensity.color)
                WorkoutStatPill(icon: "scalemass.fill", value: totalVolumeStr(workout),        label: "vol",  color: .steel)
            }
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)
            .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.26), value: appeared)

            ReadinessIntensityArc(readiness: store.readiness.overall, intensity: workout.intensity)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.34), value: appeared)
        }
    }

    private func totalVolumeStr(_ w: WorkoutPlan) -> String {
        let v = w.exercises.reduce(0) { $0 + ($1.sets * (Int($1.reps) ?? $1.reps.repMidpoint) * ($1.weight ?? 0)) }
        return v > 0 ? v.formattedVolume : "—"
    }

    private func exerciseList(workout: WorkoutPlan) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("EXERCISES").font(.system(size: 10, weight: .black)).foregroundColor(.textTertiary).tracking(2.5)
                Spacer()
                Text("\(workout.exercises.count) total").font(.system(size: 12, weight: .medium)).foregroundColor(.textMuted)
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { idx, ex in
                WorkoutExerciseRow(exercise: ex, index: idx, isExpanded: selectedExerciseIndex == idx, onTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        selectedExerciseIndex = selectedExerciseIndex == idx ? nil : idx
                    }
                })
                .opacity(appeared ? 1 : 0).offset(x: appeared ? 0 : -22)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.32 + Double(idx) * 0.055), value: appeared)
                if idx < workout.exercises.count - 1 {
                    Divider().background(Color.borderColor.opacity(0.5)).padding(.leading, 72)
                }
            }
        }
        .padding(.vertical, 20).background(Color.surface).cornerRadius(24)
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }

    private func startButton(workout: WorkoutPlan) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            if music.nowPlaying?.isPlaying == false { music.togglePlayPause() }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { store.startWorkout() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill").font(.system(size: 20, weight: .black))
                Text("Start Workout").font(.system(size: 20, weight: .black))
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 18, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 28).padding(.vertical, 22)
            .background(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.82)],
                                       startPoint: .leading, endPoint: .trailing))
            .cornerRadius(22).shadow(color: Color.ember.opacity(0.55), radius: 24, y: 10)
        }
        .opacity(appeared ? 1 : 0).scaleEffect(appeared ? 1 : 0.92)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.52), value: appeared)
    }

    /// Build a pre-workout snapshot purely from the plan (estimated muscle distribution).
    static func plannedSnapshot(_ workout: WorkoutPlan, readiness: ReadinessData) -> ARIASessionSnapshot {
        var mv: [MuscleGroup: Double] = [:]
        var volume = 0
        for ex in workout.exercises {
            let reps = Int(ex.reps) ?? ex.reps.repMidpoint
            let load = Double(ex.sets * reps * (ex.weight ?? 0))
            volume += ex.sets * reps * (ex.weight ?? 0)
            let setLoad = Double(ex.sets) * (ex.weight.map { Double($0) } ?? 8)
            if let def = ExerciseLibrary.definition(for: ex) {
                for m in def.primary { mv[m, default: 0] += setLoad }
                for m in def.secondary { mv[m, default: 0] += setLoad * 0.4 }
            } else {
                mv[.fullBody, default: 0] += setLoad
            }
        }
        return ARIASessionSnapshot(
            title: workout.name, durationSec: workout.duration * 60, totalVolume: volume,
            totalSets: workout.exercises.reduce(0) { $0 + $1.sets },
            totalReps: workout.exercises.reduce(0) { $0 + $1.sets * (Int($1.reps) ?? $1.reps.repMidpoint) },
            exercisesCompleted: workout.exercises.count, avgHR: 0, peakHR: 0, minO2: 98, avgRPE: 0,
            calories: workout.estimatedCalories, readiness: readiness.overall, muscleVolume: mv,
            zoneSeconds: [0, 0, 0, 0, 0], autoRegLog: [], painFlags: [], personalRecords: [])
    }
}
// MARK: - Adaptive Scaling Card

private struct AdaptiveScalingCard: View {
    let scaling: PlanScaling
    let applied: Bool
    let onApply: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(scaling.tone.opacity(0.15)).frame(width: 30, height: 30)
                    Image(systemName: "wand.and.stars").font(.system(size: 13)).foregroundColor(scaling.tone)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("ARIA AUTO-SCALE").font(.system(size: 10, weight: .black)).tracking(2).foregroundColor(.textTertiary)
                    Text(scaling.headline).font(.system(size: 15, weight: .bold)).foregroundColor(.textPrimary)
                }
                Spacer()
                if scaling.isModified {
                    VStack(spacing: 1) {
                        Text("\(Int(scaling.volumeMultiplier * 100))%").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(scaling.tone)
                        Text("volume").font(.system(size: 8, weight: .semibold)).foregroundColor(.textMuted)
                    }
                }
            }
            Text(scaling.detail).font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)

            if scaling.isModified {
                Button(action: onApply) {
                    HStack(spacing: 8) {
                        Image(systemName: applied ? "checkmark.circle.fill" : "slider.horizontal.3").font(.system(size: 14, weight: .bold))
                        Text(applied ? "Auto-scaling applied" : "Apply to today's plan").font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .foregroundColor(applied ? scaling.tone : .white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(applied ? scaling.tone.opacity(0.12) : scaling.tone)
                    .cornerRadius(13)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(scaling.tone.opacity(applied ? 0.4 : 0), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(applied)
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(scaling.tone.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
    }
}

// MARK: - Music Control Bar

struct MusicControlBar: View {
    @ObservedObject var controller: AnyMusicController
    var compact: Bool = true

    private var accent: Color { controller.service.accentColor }

    var body: some View {
        Group {
            if let track = controller.nowPlaying {
                playingView(track: track)
            } else if controller.isAuthorized {
                emptyView
            } else {
                unauthorizedView
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: controller.nowPlaying?.isPlaying)
    }

    private func playingView(track: NowPlayingTrack) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .shadow(color: accent.opacity(0.4), radius: 8, y: 3)
                if track.isPlaying {
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { i in
                            TimelineView(.animation(minimumInterval: 0.1)) { tl in
                                let t = tl.date.timeIntervalSinceReferenceDate + Double(i) * 0.3
                                let h = 6.0 + abs(sin(t * 3.0 + Double(i))) * 10.0
                                RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 3, height: h)
                            }
                        }
                    }
                } else {
                    Image(systemName: controller.service.iconName).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(controller.service.rawValue)
                        .font(.system(size: 9, weight: .black)).foregroundColor(accent)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(accent.opacity(0.12)).cornerRadius(4)
                    Text(track.artist).font(.system(size: 12)).foregroundColor(.textTertiary).lineLimit(1)
                    if let bpm = track.bpm {
                        Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                        Text("\(bpm) BPM").font(.system(size: 11, weight: .bold)).foregroundColor(.steel)
                    }
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Button(action: controller.skipBack) {
                    Image(systemName: "backward.fill").font(.system(size: 15)).foregroundColor(.textSecondary).frame(width: 36, height: 36)
                }
                Button(action: controller.togglePlayPause) {
                    ZStack {
                        Circle().fill(accent).frame(width: 36, height: 36).shadow(color: accent.opacity(0.45), radius: 6, y: 2)
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    }
                }
                Button(action: controller.skipForward) {
                    Image(systemName: "forward.fill").font(.system(size: 15)).foregroundColor(.textSecondary).frame(width: 36, height: 36)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, compact ? 9 : 14)
        .background(Color.surface).cornerRadius(compact ? 16 : 20)
        .overlay(RoundedRectangle(cornerRadius: compact ? 16 : 20).stroke(accent.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    private var emptyView: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.list").font(.system(size: 18)).foregroundColor(.textMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing playing").font(.system(size: 14)).foregroundColor(.textMuted)
                Text(controller.service.rawValue).font(.system(size: 11, weight: .semibold)).foregroundColor(accent.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.surface).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
    }

    private var unauthorizedView: some View {
        Button {
            Task { await controller.requestAccess() }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(accent.opacity(0.12)).frame(width: 34, height: 34)
                    Image(systemName: controller.service.iconName).font(.system(size: 14)).foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connect \(controller.service.rawValue)").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                    Text("Tap to authorize").font(.system(size: 11)).foregroundColor(.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.textMuted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.surface).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Background (animated mesh)

private struct WorkoutBackground: View {
    let accentColor: Color
    var body: some View {
        ZStack {
            Color.background
            TimelineView(.animation(minimumInterval: 1/30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    let x1 = size.width  * (0.15 + 0.12 * sin(t * 0.17))
                    let y1 = size.height * (0.12 + 0.10 * cos(t * 0.13))
                    let r1 = size.width  * 0.55
                    var p1 = Path(); p1.addEllipse(in: CGRect(x: x1-r1/2, y: y1-r1/2, width: r1, height: r1))
                    ctx.fill(p1, with: .color(accentColor.opacity(0.045)))
                    let x2 = size.width  * (0.82 + 0.10 * cos(t * 0.11))
                    let y2 = size.height * (0.75 + 0.12 * sin(t * 0.14))
                    let r2 = size.width  * 0.48
                    var p2 = Path(); p2.addEllipse(in: CGRect(x: x2-r2/2, y: y2-r2/2, width: r2, height: r2))
                    ctx.fill(p2, with: .color(Color(hex: "38BDF8").opacity(0.028)))
                    let x3 = size.width  * (0.5 + 0.18 * sin(t * 0.09 + 1.0))
                    let y3 = size.height * (0.45 + 0.14 * cos(t * 0.12 + 0.5))
                    let r3 = size.width  * 0.38
                    var p3 = Path(); p3.addEllipse(in: CGRect(x: x3-r3/2, y: y3-r3/2, width: r3, height: r3))
                    ctx.fill(p3, with: .color(accentColor.opacity(0.025)))
                }
            }
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 1.6), value: accentColor)
    }
}

// MARK: - Readiness Intensity Arc

private struct ReadinessIntensityArc: View {
    let readiness: Int
    let intensity: WorkoutIntensity
    @State private var appeared = false

    private var readinessFraction: CGFloat { CGFloat(readiness) / 100 }
    private var intensityFraction: CGFloat {
        switch intensity {
        case .low: return 0.25
        case .moderate: return 0.50
        case .high: return 0.75
        case .max: return 1.0
        }
    }
    private var matchColor: Color {
        let diff = abs(readinessFraction - intensityFraction)
        return diff < 0.15 ? .success : diff < 0.35 ? Color(hex: "F59E0B") : .danger
    }
    private var matchLabel: String {
        let diff = abs(readinessFraction - intensityFraction)
        return diff < 0.15 ? "Well matched" : diff < 0.35 ? "Manageable" : "Intensity mismatch"
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.borderColor.opacity(0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 56, height: 56)
                Circle().trim(from: 0, to: appeared ? readinessFraction : 0)
                    .stroke(Color.success.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 56, height: 56).rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.1), value: appeared)
                Circle().trim(from: 0, to: appeared ? intensityFraction : 0)
                    .stroke(Color.ember.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 44, height: 44).rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.22), value: appeared)
                Text("\(readiness)").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(matchColor).frame(width: 6, height: 6).shadow(color: matchColor.opacity(0.5), radius: 3)
                    Text(matchLabel).font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                }
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.success.opacity(0.7)).frame(width: 6, height: 6)
                        Text("Readiness \(readiness)%").font(.system(size: 11)).foregroundColor(.textTertiary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.ember.opacity(0.8)).frame(width: 6, height: 6)
                        Text(intensity.label).font(.system(size: 11)).foregroundColor(.textTertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(16).background(Color.surface).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(matchColor.opacity(0.2), lineWidth: 1))
        .onAppear { appeared = true }
    }
}
// MARK: - Shared Components

struct WorkoutStatPill: View {
    let icon: String; let value: String; let label: String
    var color: Color = .textSecondary
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(color)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundColor(.textPrimary)
            Text(label).font(.system(size: 11)).foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.surface).cornerRadius(100)
        .overlay(Capsule().stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 5, y: 2)
    }
}

struct WorkoutExerciseRow: View {
    let exercise: Exercise; let index: Int
    let isExpanded: Bool; let onTap: () -> Void
    private var def: ExerciseDefinition? { ExerciseLibrary.definition(for: exercise) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [(def?.accent ?? .ember).opacity(0.18), (def?.accent ?? .ember).opacity(0.07)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 42, height: 42)
                        Text("\(index + 1)").font(.system(size: 16, weight: .bold)).foregroundColor(def?.accent ?? .ember)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary).lineLimit(isExpanded ? nil : 1)
                        HStack(spacing: 8) {
                            Label("\(exercise.sets) × \(exercise.reps)", systemImage: "repeat")
                                .font(.system(size: 12)).foregroundColor(.textSecondary)
                            if let w = exercise.weight {
                                Circle().fill(Color.textMuted).frame(width: 3, height: 3)
                                Text("\(w) lbs").font(.system(size: 12)).foregroundColor(.textSecondary)
                            }
                            if let def {
                                Circle().fill(Color.textMuted).frame(width: 3, height: 3)
                                Text(def.primary.first?.label ?? "").font(.system(size: 12, weight: .semibold)).foregroundColor(def.accent)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider().background(Color.borderColor.opacity(0.5)).padding(.horizontal, 20)
                        if let def {
                            // Muscle map + mechanics chips
                            HStack(spacing: 6) {
                                metaChip(def.pattern.label, "arrow.triangle.branch", def.accent)
                                metaChip(def.equipment.label, def.equipment.icon, .steel)
                                metaChip(def.isCompound ? "Compound" : "Isolation", "square.stack.3d.up.fill", .textTertiary)
                            }
                            .padding(.horizontal, 20)
                            if let cue = def.cues.first {
                                cueRow(icon: "checkmark.circle.fill", color: def.accent, text: cue)
                            }
                            if let fault = def.faults.first {
                                cueRow(icon: "exclamationmark.triangle.fill", color: .warning, text: "Avoid: \(fault)")
                            }
                        }
                        if let notes = exercise.notes {
                            cueRow(icon: "info.circle.fill", color: .steel, text: notes)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill").font(.system(size: 12)).foregroundColor(.textMuted)
                            Text("\(exercise.restSeconds)s rest between sets").font(.system(size: 12)).foregroundColor(.textTertiary)
                        }
                        .padding(.horizontal, 20).padding(.bottom, 14)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isExpanded)
    }

    private func cueRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
            Text(text).font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }
    private func metaChip(_ text: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color).padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.1)).cornerRadius(7)
    }
}

struct WorkoutInsightsView: View {
    let workout: WorkoutPlan
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    private var insights: [(icon: String, text: String, color: Color)] {
        var r: [(String, String, Color)] = []
        if store.readiness.overall >= 80 { r.append(("bolt.fill", "Readiness \(store.readiness.overall)% — primed for heavy top sets today.", .ember)) }
        else if store.readiness.overall < 65 { r.append(("bed.double.fill", "Recovery \(store.readiness.overall)% — ARIA trimmed volume to protect tomorrow.", .steel)) }
        // Balance read across the plan
        if let lean = planRegionLean() { r.append(("scale.3d", lean, Color(hex: "A855F7"))) }
        if workout.intensity == .high || workout.intensity == .max {
            r.append(("exclamationmark.triangle.fill", "High intensity — run the mobility warm-up before loading.", .warning))
        }
        r.append(("flame.fill", "≈\(workout.estimatedCalories) kcal projected at this output.", .success))
        return r
    }

    private func planRegionLean() -> String? {
        var counts: [MuscleGroup.Region: Int] = [:]
        for ex in workout.exercises {
            if let def = ExerciseLibrary.definition(for: ex) { counts[def.region, default: 0] += ex.sets }
        }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return "Session emphasis: \(top.key.rawValue) (\(top.value) working sets)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "brain.head.profile").font(.system(size: 14)).foregroundColor(.ember)
                Text("ARIA INSIGHTS").font(.system(size: 10, weight: .black)).foregroundColor(.textTertiary).tracking(2.5)
            }
            VStack(spacing: 10) {
                ForEach(Array(insights.enumerated()), id: \.offset) { idx, insight in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(insight.color.opacity(0.12)).frame(width: 32, height: 32)
                            Image(systemName: insight.icon).font(.system(size: 13)).foregroundColor(insight.color)
                        }
                        Text(insight.text).font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)
                        Spacer()
                    }
                    .padding(12).background(Color.surfaceElevated).cornerRadius(13)
                    .opacity(appeared ? 1 : 0).offset(x: appeared ? 0 : -14)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(idx) * 0.1), value: appeared)
                }
            }
        }
        .padding(20).background(Color.surface).cornerRadius(22)
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
        .onAppear { appeared = true }
    }
}

struct WorkoutEmptyState: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false
    @State private var showLibrary = false
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(Color.ember.opacity(0.08)).frame(width: 130, height: 130).blur(radius: 24)
                Image(systemName: "dumbbell.fill").font(.system(size: 58)).foregroundColor(.ember.opacity(0.5))
            }
            .scaleEffect(appeared ? 1 : 0.8).opacity(appeared ? 1 : 0)
            VStack(spacing: 10) {
                Text("No Workout Planned").font(.system(size: 24, weight: .bold)).foregroundColor(.textPrimary)
                Text("Chat with ARIA to generate a plan tailored to your readiness and goals — or explore the movement library.")
                    .font(.system(size: 15)).foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center).lineSpacing(5).padding(.horizontal, 44)
            }
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 18)
            VStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.activeTab = .chat
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill").font(.system(size: 16))
                        Text("Chat with ARIA").font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 32).padding(.vertical, 17)
                    .background(Color.ember).cornerRadius(18)
                    .shadow(color: Color.ember.opacity(0.45), radius: 18, y: 8)
                }
                Button { showLibrary = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "books.vertical.fill").font(.system(size: 14))
                        Text("Browse Exercise Library").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.steel).padding(.horizontal, 24).padding(.vertical, 13)
                    .background(Color.steel.opacity(0.1)).cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.steel.opacity(0.3), lineWidth: 1))
                }
            }
            .opacity(appeared ? 1 : 0).scaleEffect(appeared ? 1 : 0.92)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showLibrary) { ExerciseLibraryView() }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.18)) { appeared = true } }
    }
}

struct FeatureBadge: View {
    let icon: String; let label: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(label).font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color).padding(.horizontal, 9).padding(.vertical, 5)
        .background(color.opacity(0.1)).cornerRadius(7)
    }
}
// MARK: - Exercise Library Browser

struct ExerciseLibraryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var muscle: MuscleGroup? = nil
    @State private var equipment: Equipment? = nil
    @State private var selected: ExerciseDefinition? = nil

    private var results: [ExerciseDefinition] {
        ExerciseLibrary.filter(query: query, muscle: muscle, equipment: equipment, pattern: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    filterRow
                    if results.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "magnifyingglass").font(.system(size: 34)).foregroundColor(.textMuted)
                            Text("No movements match").font(.system(size: 15)).foregroundColor(.textTertiary)
                            Spacer()
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 8) {
                                HStack {
                                    Text("\(results.count) MOVEMENTS").font(.system(size: 10, weight: .black)).tracking(2).foregroundColor(.textTertiary)
                                    Spacer()
                                }
                                .padding(.horizontal, 4).padding(.top, 4)
                                ForEach(results) { def in
                                    libraryCard(def)
                                }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle("Exercise Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold) } }
            .sheet(item: $selected) { def in ExerciseDetailSheet(def: def) }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundColor(.textMuted)
            TextField("Search 90+ movements…", text: $query)
                .font(.system(size: 15)).foregroundColor(.textPrimary).tint(.ember)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundColor(.textMuted) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.surface).cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All muscles") { muscle = nil }
                    ForEach(MuscleGroup.allCases) { m in Button(m.label) { muscle = m } }
                } label: { filterChip(muscle?.label ?? "Muscle", active: muscle != nil, color: muscle?.accent ?? .steel) }
                Menu {
                    Button("All equipment") { equipment = nil }
                    ForEach(Equipment.allCases) { e in Button(e.label) { equipment = e } }
                } label: { filterChip(equipment?.label ?? "Equipment", active: equipment != nil, color: .ember) }
                if muscle != nil || equipment != nil {
                    Button { muscle = nil; equipment = nil } label: {
                        HStack(spacing: 4) { Image(systemName: "xmark"); Text("Clear") }
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.danger)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.danger.opacity(0.1)).cornerRadius(100)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
    }

    private func filterChip(_ text: String, active: Bool, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(text).font(.system(size: 13, weight: .semibold))
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(active ? .white : .textSecondary)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(active ? color : Color.surface).cornerRadius(100)
        .overlay(Capsule().stroke(active ? color : Color.borderColor.opacity(0.5), lineWidth: 1))
    }

    private func libraryCard(_ def: ExerciseDefinition) -> some View {
        Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); selected = def } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [def.accent.opacity(0.2), def.accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                    Image(systemName: def.icon).font(.system(size: 18, weight: .semibold)).foregroundColor(def.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(def.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary).lineLimit(1)
                    Text(def.muscleSummary).font(.system(size: 12)).foregroundColor(.textTertiary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(def.repRangeLabel).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.textSecondary)
                    Text(def.equipment.label).font(.system(size: 10, weight: .semibold)).foregroundColor(.textMuted)
                }
            }
            .padding(12).background(Color.surface).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ExerciseDetailSheet: View {
    let def: ExerciseDefinition
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var added = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Hero
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(LinearGradient(colors: [def.accent.opacity(0.25), def.accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 64, height: 64)
                                Image(systemName: def.icon).font(.system(size: 26, weight: .bold)).foregroundColor(def.accent)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(def.pattern.label.uppercased()).font(.system(size: 10, weight: .black)).tracking(1.5).foregroundColor(def.accent)
                                Text(def.name).font(.system(size: 22, weight: .bold)).foregroundColor(.textPrimary)
                                Text(def.muscleSummary).font(.system(size: 12)).foregroundColor(.textTertiary)
                            }
                            Spacer()
                        }
                        // Spec chips
                        FlowChips(items: [
                            ("\(def.defaultSets) × \(def.repRangeLabel)", "repeat", .steel),
                            ("\(def.restSeconds)s rest", "clock.fill", .textTertiary),
                            ("Tempo \(def.tempo)", "metronome.fill", .ember),
                            ("RPE \(def.rpeTarget)", "bolt.fill", .warning),
                            (def.level.label, "chart.bar.fill", Color(hex: "A855F7")),
                            (def.equipment.label, def.equipment.icon, .success),
                        ])
                        // Cues
                        if !def.cues.isEmpty { sectionCard("EXECUTION", icon: "checkmark.seal.fill", color: def.accent, lines: def.cues) }
                        if !def.faults.isEmpty { sectionCard("COMMON FAULTS", icon: "exclamationmark.triangle.fill", color: .warning, lines: def.faults) }
                        if !def.note.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "brain.head.profile").font(.system(size: 14)).foregroundColor(.ember)
                                Text(def.note).font(.system(size: 13, design: .serif).italic()).foregroundColor(.textSecondary).lineSpacing(4)
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.ember.opacity(0.06)).cornerRadius(16)
                        }
                        if !def.substitutes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ARIA SWAPS").font(.system(size: 10, weight: .black)).tracking(2).foregroundColor(.textTertiary)
                                ForEach(def.substitutes, id: \.self) { s in
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.triangle.swap").font(.system(size: 12)).foregroundColor(.steel)
                                        Text(s).font(.system(size: 13)).foregroundColor(.textSecondary)
                                    }
                                }
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surface).cornerRadius(16)
                        }
                        // Add
                        Button {
                            addToPlan()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill").font(.system(size: 18, weight: .bold))
                                Text(added ? "Added to today" : store.todayWorkout == nil ? "Start a plan with this" : "Add to today's workout").font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 54)
                            .background(added ? Color.success : def.accent).cornerRadius(16)
                            .shadow(color: (added ? Color.success : def.accent).opacity(0.4), radius: 14, y: 6)
                        }
                        .disabled(added)
                    }
                    .padding(20).padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold) } }
        }
    }

    private func addToPlan() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let ex = Exercise(id: UUID().uuidString, name: def.name, sets: def.defaultSets,
                          reps: def.repRangeLabel.replacingOccurrences(of: "–", with: "-"),
                          weight: def.mechanic == .compound && def.equipment != .bodyweight ? 95 : (def.equipment == .bodyweight ? nil : 25),
                          restSeconds: def.restSeconds, notes: def.cues.first, videoURL: nil, has3DModel: false)
        if store.todayWorkout == nil {
            store.todayWorkout = WorkoutPlan(id: UUID().uuidString, name: "Custom Session", type: .strength,
                                             duration: 45, intensity: .moderate, exercises: [ex])
        } else {
            store.todayWorkout?.exercises.append(ex)
        }
        withAnimation { added = true }
    }

    private func sectionCard(_ title: String, icon: String, color: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .black)).tracking(2).foregroundColor(.textTertiary)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
                    Text(line).font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface).cornerRadius(16)
    }
}

/// Simple wrapping chip row.
struct FlowChips: View {
    let items: [(String, String, Color)]
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    Image(systemName: item.1).font(.system(size: 10))
                    Text(item.0).font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(item.2).padding(.horizontal, 10).padding(.vertical, 8)
                .background(item.2.opacity(0.1)).cornerRadius(9)
            }
        }
    }
}
// MARK: - ARIA Performance Dashboard

@MainActor
struct ARIADashboardView: View {
    let snapshot: ARIASessionSnapshot
    var isPreWorkout: Bool = false
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var aria = ARIACoachService()
    @State private var sent = false
    @State private var briefing: String = ""
    @State private var loadingBrief = false
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0A").ignoresSafeArea()
                RadialGradient(colors: [Color.ember.opacity(appeared ? 0.10 : 0), .clear], center: .top, startRadius: 0, endRadius: 360)
                    .ignoresSafeArea().animation(.easeInOut(duration: 1.2), value: appeared)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        muscleBalanceCard
                        muscleEmphasisCard
                        if !isPreWorkout { zoneCard }
                        if !snapshot.autoRegLog.isEmpty { autoRegCard }
                        recommendationsCard
                        sendCard
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 50)
                }
            }
            .navigationTitle(isPreWorkout ? "Session Brief" : "Performance Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold) } }
            .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true }; briefing = snapshot.localBriefing }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.ember, Color(hex: "FF5A00")], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 50, height: 50)
                        .shadow(color: .ember.opacity(0.5), radius: 12, y: 4)
                    Image(systemName: "brain.head.profile").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPreWorkout ? "ARIA · PRE-FLIGHT" : "ARIA · DEBRIEF").font(.system(size: 10, weight: .black)).tracking(2).foregroundColor(.ember)
                    Text(snapshot.title).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                }
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric("\(snapshot.totalVolume.formattedVolume)", "Volume", .steel)
                metric("\(snapshot.totalSets)", "Sets", .ember)
                if isPreWorkout { metric("\(snapshot.readiness)", "Readiness", .success) }
                else { metric(snapshot.avgRPE > 0 ? String(format: "%.1f", snapshot.avgRPE) : "—", "Avg RPE", .warning) }
            }
        }
        .padding(18).background(Color.white.opacity(0.04)).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func metric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.white)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Color.white.opacity(0.04)).cornerRadius(12)
    }

    private var muscleBalanceCard: some View {
        dashCard("MOVEMENT BALANCE", icon: "scale.3d") {
            VStack(spacing: 10) {
                ForEach(snapshot.regionShare.filter { $0.1 > 0.001 }, id: \.0) { region, share in
                    HStack(spacing: 10) {
                        Text(region.rawValue.capitalized).font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.8)).frame(width: 90, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.06)).frame(height: 8)
                                Capsule().fill(LinearGradient(colors: [region.accent, region.accent.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, geo.size.width * (appeared ? share : 0)), height: 8)
                                    .animation(.spring(response: 0.8, dampingFraction: 0.8), value: appeared)
                            }
                        }
                        .frame(height: 8)
                        Text("\(Int(share * 100))%").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(region.accent).frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var muscleEmphasisCard: some View {
        dashCard("MUSCLE EMPHASIS", icon: "figure.arms.open") {
            VStack(spacing: 8) {
                ForEach(snapshot.topMuscles, id: \.0) { m, share in
                    HStack(spacing: 10) {
                        Circle().fill(m.accent).frame(width: 8, height: 8)
                        Text(m.label).font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text("\(Int(share * 100))%").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(m.accent)
                    }
                }
                if snapshot.topMuscles.isEmpty {
                    Text("Add library movements to see muscle targeting.").font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }

    private var zoneCard: some View {
        dashCard("HEART-RATE ZONES", icon: "waveform.path.ecg") {
            let maxV = max(1, snapshot.zoneSeconds.max() ?? 1)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(snapshot.zoneSeconds.enumerated()), id: \.offset) { idx, secs in
                    let z = workoutHRZones[idx + 1]
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)).frame(height: 70)
                            RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: [z.color, z.color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                                .frame(height: max(4, 70 * CGFloat(appeared ? Double(secs) / Double(maxV) : 0)))
                                .animation(.spring(response: 0.8, dampingFraction: 0.78).delay(Double(idx) * 0.06), value: appeared)
                        }
                        .frame(height: 70)
                        Text(secs >= 60 ? "\(secs/60)m" : "\(secs)s").font(.system(size: 9, weight: .bold)).foregroundColor(secs > 0 ? z.color : .white.opacity(0.25))
                        Text("Z\(idx+1)").font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var autoRegCard: some View {
        dashCard("AUTO-REGULATION LOG", icon: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(snapshot.autoRegLog.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundColor(.ember)
                        Text(line).font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).lineSpacing(3)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var recommendationsCard: some View {
        dashCard("HOW TO IMPROVE", icon: "lightbulb.fill") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(recommendations.enumerated()), id: \.offset) { _, rec in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundColor(.success)
                        Text(rec).font(.system(size: 13)).foregroundColor(.white.opacity(0.85)).lineSpacing(3)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var recommendations: [String] {
        var r: [String] = []
        if let weak = snapshot.regionShare.filter({ $0.1 > 0 }).min(by: { $0.1 < $1.1 }), snapshot.regionShare.filter({ $0.1 > 0 }).count > 1 {
            r.append("Add a \(weak.0.rawValue) movement next session to even out weekly volume.")
        }
        if snapshot.avgRPE > 0 && snapshot.avgRPE < 6 { r.append("Average RPE was low — there's room to add load or reps and drive progression.") }
        if snapshot.avgRPE >= 9 { r.append("Effort ran very high — schedule a deload-leaning session to bank recovery.") }
        if snapshot.minO2 < 95 && !isPreWorkout { r.append("O₂ dipped under 95% — build aerobic base with 1–2 easy Zone-2 sessions weekly.") }
        if !snapshot.painFlags.isEmpty { r.append("Pain flagged at \(snapshot.painFlags.joined(separator: ", ")) — ARIA will pre-screen loads next time.") }
        if snapshot.readiness >= 85 && isPreWorkout { r.append("Readiness is elite — attack your first compound for a rep PR.") }
        if r.isEmpty { r.append("Balanced, well-executed session. Keep the progression steady — small, consistent overload.") }
        return r
    }

    private var sendCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.bubble.fill").font(.system(size: 14)).foregroundColor(.ember)
                Text(briefing.isEmpty ? snapshot.localBriefing : briefing)
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.85)).lineSpacing(4)
                Spacer(minLength: 0)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ember.opacity(0.07)).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ember.opacity(0.2), lineWidth: 1))

            Button { Task { await sendToARIA() } } label: {
                HStack(spacing: 10) {
                    if loadingBrief { ProgressView().tint(.white) }
                    else { Image(systemName: sent ? "checkmark.circle.fill" : "paperplane.fill").font(.system(size: 17, weight: .bold)) }
                    Text(sent ? "Sent to ARIA — open chat" : loadingBrief ? "ARIA is reviewing…" : "Send this data to ARIA").font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 56)
                .background(LinearGradient(colors: sent ? [.success, .success.opacity(0.8)] : [.ember, Color(hex: "FF5A00")], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(16).shadow(color: (sent ? Color.success : Color.ember).opacity(0.5), radius: 16, y: 6)
            }
            .disabled(loadingBrief)
            if !aria.hasAPIKey {
                Text("Tip: add ANTHROPIC_API_KEY to enable ARIA's live Claude debrief. Using the on-device analysis for now.")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.35)).multilineTextAlignment(.center)
            }
        }
    }

    private func sendToARIA() async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !sent {
            loadingBrief = true
            // Prefer a live Claude debrief; fall back to the on-device briefing.
            if let live = await aria.briefing(for: snapshot) { briefing = live }
            loadingBrief = false
            let muscles = snapshot.topMuscles
            let chart = RichCardData(
                type: .dataChart,
                chartTitle: "Muscle Emphasis · \(snapshot.title)",
                chartValues: muscles.map { $0.1 * 100 },
                chartInsight: muscles.map { "\($0.0.label) \(Int($0.1*100))%" }.joined(separator: " · "),
                chartColor: .ember
            )
            let message = ChatMessage(id: UUID().uuidString, role: .trainer,
                                      content: briefing.isEmpty ? snapshot.localBriefing : briefing,
                                      timestamp: Date(), richCard: muscles.isEmpty ? nil : chart)
            store.chatMessages.append(message)
            withAnimation { sent = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            store.activeTab = .chat
            dismiss()
        }
    }

    @ViewBuilder
    private func dashCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(.ember)
                Text(title).font(.system(size: 10, weight: .black)).tracking(2).foregroundColor(.white.opacity(0.45))
            }
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04)).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}
// MARK: - Active Workout

@MainActor
struct ActiveWorkoutView: View {
    @EnvironmentObject var store: AppStore
    let onWorkoutEnd: (WorkoutSummaryData) -> Void

    // Bio metrics
    @State private var elapsedSecs:    Int    = 0
    @State private var simulatedHR:    Int    = 72
    @State private var peakHR:         Int    = 72
    @State private var hrHistory:      [Int]  = []
    @State private var estimatedCals:  Double = 0
    @State private var simulatedSpO2:  Int    = 98
    @State private var peakSpO2:       Int    = 98
    @State private var minSpO2:        Int    = 98
    @State private var showO2Warning:  Bool   = false

    // Rest
    @State private var isResting:      Bool   = false
    @State private var restTimeLeft:   Int    = 0
    @State private var restTotal:      Int    = 90

    // Coach
    @State private var coachIndex:     Int    = 0

    // Set logging
    @State private var setLog:         [SetLogEntry] = []
    @State private var showSetLogger:  Bool   = false
    @State private var loggedReps:     Int    = 0
    @State private var currentWeight:  Int    = 0
    @State private var loggedRPE:      Int    = 7
    @State private var showPRBanner:   Bool   = false
    @State private var prExerciseName: String = ""

    // Pain
    @State private var painLog:        [PainEntry] = []
    @State private var showPainLogger: Bool   = false

    // Adaptive / ARIA
    @StateObject private var aria = ARIACoachService()
    @State private var autoRegLog:     [String] = []
    @State private var muscleVolume:   [MuscleGroup: Double] = [:]
    @State private var pendingSwap:    ExerciseDefinition? = nil
    @State private var swapReason:     String = ""
    @State private var showSwapBanner: Bool   = false
    @State private var showFormCoach:  Bool   = false

    // End
    @State private var showEndConfirm: Bool   = false

    // Volume
    @State private var totalVolume:    Int    = 0

    // Demo
    @State private var selectedDemoTab: ExerciseDemoTab = .video

    // Music
    @StateObject private var music = MusicControllerFactory.make(for: .appleMusic)

    // Tasks
    @State private var elapsedTask: Task<Void, Never>? = nil
    @State private var hrTask:      Task<Void, Never>? = nil
    @State private var calTask:     Task<Void, Never>? = nil
    @State private var o2Task:      Task<Void, Never>? = nil
    @State private var restTask:    Task<Void, Never>? = nil
    @State private var coachTask:   Task<Void, Never>? = nil

    private var exercises:       [Exercise] { store.todayWorkout?.exercises ?? [] }
    private var currentExercise: Exercise?  { exercises.indices.contains(store.currentExerciseIndex) ? exercises[store.currentExerciseIndex] : nil }
    private var currentZone: WorkoutHRZone { workoutHRZone(for: simulatedHR) }
    private var currentDef: ExerciseDefinition? { currentExercise.flatMap { ExerciseLibrary.definition(for: $0) } }

    /// Live auto-regulation read for the current exercise.
    private var recommendation: SetRecommendation {
        let ex = currentExercise
        let prev = ex.map { e in setLog.filter { $0.exerciseName == e.name } } ?? []
        let target = ex?.reps.repMidpoint ?? 8
        let pain = ex.flatMap { e in painLog.filter { $0.exerciseName == e.name }.map { $0.severity }.max() }
        let painLoc = ex.flatMap { e in painLog.filter { $0.exerciseName == e.name }.last?.location }
        return AdaptiveEngine.recommend(
            definition: currentDef, targetReps: target, targetRPE: currentDef?.rpeTarget ?? 8,
            baseRest: ex?.restSeconds ?? 90, currentWeight: currentWeight,
            lastRPE: prev.last?.rpe, lastReps: prev.last?.repsPerformed,
            readiness: store.readiness, experience: store.userProfile.experienceLevel,
            currentHR: simulatedHR, hrZone: currentZone.index, spO2: simulatedSpO2,
            painSeverity: pain, painLocation: painLoc)
    }

    var body: some View {
        ZStack {
            WorkoutBackground(accentColor: currentZone.color).ignoresSafeArea()

            if let exercise = currentExercise {
                VStack(spacing: 0) {
                    cockpitHeader
                    exerciseNavStrip
                    liveMetricsBar
                    MusicControlBar(controller: music, compact: true)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                    mainContent(exercise: exercise)
                    coachBar
                }
            }

            // Overlays — highest zIndex first
            if showSwapBanner, let swap = pendingSwap {
                SubstitutionBanner(target: swap, reason: swapReason,
                                   onApply: { applySwap(swap) },
                                   onDismiss: { withAnimation { showSwapBanner = false } })
                .transition(.move(edge: .top).combined(with: .opacity)).zIndex(30)
            }
            if showO2Warning {
                O2WarningBanner(spO2: simulatedSpO2) { withAnimation { showO2Warning = false } }
                .transition(.move(edge: .top).combined(with: .opacity)).zIndex(25)
            }
            if showPRBanner {
                PRBannerView(exerciseName: prExerciseName)
                    .transition(.move(edge: .top).combined(with: .opacity)).zIndex(20)
            }
            if showSetLogger, let exercise = currentExercise {
                SetLoggerPanel(
                    exercise: exercise, definition: currentDef, currentSet: store.currentSet,
                    recommendation: recommendation,
                    proposedReps: $loggedReps, proposedWeight: $currentWeight, proposedRPE: $loggedRPE,
                    onConfirm: { confirmSet(exercise: exercise) },
                    onCancel: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showSetLogger = false } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity)).zIndex(15)
            }
            if showPainLogger, let exercise = currentExercise {
                PainLoggerPanel(
                    exerciseName: exercise.name,
                    onLog: { entry in handlePain(entry, exercise: exercise) },
                    onCancel: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showPainLogger = false } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity)).zIndex(15)
            }
        }
        .sheet(isPresented: $showFormCoach) {
            if let exercise = currentExercise {
                FormCheckCameraView(exercise: exercise, definition: currentDef, liveContext: liveContext(for: exercise))
            }
        }
        .onAppear  { startTasks(); setupCurrentWeight() }
        .onDisappear { cancelTasks() }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showPRBanner)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showO2Warning)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showSwapBanner)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showSetLogger)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showPainLogger)
    }

    private func liveContext(for exercise: Exercise) -> ARIALiveContext {
        ARIALiveContext(
            exerciseName: exercise.name,
            setLabel: "Set \(store.currentSet) of \(exercise.sets)",
            weight: currentWeight, reps: exercise.reps,
            heartRate: simulatedHR, hrZone: currentZone.index, spO2: simulatedSpO2,
            elapsed: formatTime(elapsedSecs, flashColon: true),
            cues: currentDef?.cues ?? [])
    }

    // MARK: Cockpit Header

    private var cockpitHeader: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(currentZone.color).frame(width: 3, height: 36)
                .shadow(color: currentZone.color.opacity(0.8), radius: 6)
                .animation(.easeInOut(duration: 0.8), value: currentZone.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.todayWorkout?.name ?? "").font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                HStack(spacing: 5) {
                    Text(store.todayWorkout?.type.label ?? "").font(.system(size: 11)).foregroundColor(.textTertiary)
                    Circle().fill(Color.textTertiary.opacity(0.5)).frame(width: 2.5, height: 2.5)
                    Text(store.todayWorkout?.intensity.label ?? "").font(.system(size: 11, weight: .semibold)).foregroundColor(currentZone.color)
                        .animation(.easeInOut(duration: 0.8), value: currentZone.label)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                headerBadge(icon: "scalemass.fill", iconColor: .steel, value: "\(totalVolume.formattedVolume)", unit: "vol")
                TimelineView(.animation(minimumInterval: 0.5)) { tl in
                    let flash = Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill").font(.system(size: 10)).foregroundColor(.textMuted)
                        Text(formatTime(elapsedSecs, flashColon: flash))
                            .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary).contentTransition(.numericText())
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6).background(Color.surface).cornerRadius(100)
                    .overlay(Capsule().stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
                }
                Button(action: handleEnd) {
                    Text(showEndConfirm ? "Confirm?" : "End")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(showEndConfirm ? .white : .danger)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(showEndConfirm ? Color.danger : Color.danger.opacity(0.12)).cornerRadius(9)
                        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: showEndConfirm)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }

    @ViewBuilder
    private func headerBadge(icon: String, iconColor: Color, value: String, unit: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(iconColor)
            Text(value).font(.system(size: 12, weight: .bold)).foregroundColor(.textPrimary).contentTransition(.numericText())
            if let u = unit { Text(u).font(.system(size: 10)).foregroundColor(.textTertiary) }
        }
        .padding(.horizontal, 9).padding(.vertical, 6).background(Color.surface).cornerRadius(100)
        .overlay(Capsule().stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
    }

    // MARK: Nav Strip

    private var exerciseNavStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { idx, ex in
                        HStack(spacing: 4) {
                            navDot(idx: idx, name: ex.name).id(idx)
                            if idx < exercises.count - 1 {
                                Rectangle().fill(idx < store.currentExerciseIndex ? Color.ember.opacity(0.6) : Color.borderColor.opacity(0.25)).frame(width: 12, height: 1.5)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }
            .onChange(of: store.currentExerciseIndex) { _, newIdx in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { proxy.scrollTo(newIdx, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func navDot(idx: Int, name: String) -> some View {
        let isCurrent = idx == store.currentExerciseIndex
        let isPast    = idx <  store.currentExerciseIndex
        Group {
            if isCurrent {
                HStack(spacing: 7) {
                    TimelineView(.animation(minimumInterval: 0.05)) { tl in
                        let p = (sin(tl.date.timeIntervalSinceReferenceDate * 2.5) + 1) / 2
                        Circle().fill(Color.ember).frame(width: 8, height: 8).shadow(color: Color.ember.opacity(0.5 + p * 0.4), radius: 3 + p * 3)
                    }
                    Text(name).font(.system(size: 12, weight: .bold)).foregroundColor(.ember).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 7).background(Color.ember.opacity(0.1)).cornerRadius(100)
                .overlay(Capsule().stroke(Color.ember.opacity(0.35), lineWidth: 1)).shadow(color: Color.ember.opacity(0.2), radius: 6)
            } else if isPast {
                ZStack {
                    Circle().fill(Color.success.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundColor(.success)
                }
            } else {
                ZStack {
                    Circle().fill(Color.surfaceElevated).frame(width: 28, height: 28).overlay(Circle().stroke(Color.borderColor.opacity(0.6), lineWidth: 1))
                    Text("\(idx+1)").font(.system(size: 10, weight: .semibold)).foregroundColor(.textMuted)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: store.currentExerciseIndex)
    }

    // MARK: Live Metrics Bar

    private var liveMetricsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                primaryMetricChip(icon: "heart.fill", iconColor: currentZone.color, value: "\(simulatedHR)", unit: "bpm", accent: currentZone.color, glowing: simulatedHR > 140)
                HStack(spacing: 5) {
                    TimelineView(.animation(minimumInterval: 0.05)) { tl in
                        let p = (sin(tl.date.timeIntervalSinceReferenceDate * 3) + 1) / 2
                        Circle().fill(currentZone.color).frame(width: 7, height: 7).scaleEffect(1 + p * 0.3).shadow(color: currentZone.color.opacity(0.6 + p * 0.3), radius: 4)
                    }
                    Text(currentZone.label).font(.system(size: 12, weight: .black)).foregroundColor(currentZone.color)
                }
                .padding(.horizontal, 12).padding(.vertical, 9).background(currentZone.color.opacity(0.13)).cornerRadius(100)
                .overlay(Capsule().stroke(currentZone.color.opacity(0.35), lineWidth: 1)).animation(.easeInOut(duration: 0.7), value: currentZone.label)
                let o2Color: Color = simulatedSpO2 < 94 ? .danger : simulatedSpO2 < 96 ? .warning : Color(hex: "38BDF8")
                primaryMetricChip(icon: "lungs.fill", iconColor: o2Color, value: "\(simulatedSpO2)%", unit: "O₂", accent: o2Color, glowing: simulatedSpO2 < 95)
                liveChip(icon: "flame.fill", iconColor: .ember, value: "\(Int(estimatedCals))", unit: "kcal", accent: .ember)
                liveChip(icon: "repeat", iconColor: .steel, value: "\(store.currentSet)/\(currentExercise?.sets ?? 0)", unit: "sets", accent: .steel)
                liveChip(icon: "scalemass.fill", iconColor: .steel, value: "\(totalVolume.formattedVolume)", unit: "vol", accent: .steel)
                if let bpm = music.nowPlaying?.bpm {
                    liveChip(icon: "music.note", iconColor: Color(hex: "1DB954"), value: "\(bpm)", unit: "BPM", accent: Color(hex: "1DB954"))
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func primaryMetricChip(icon: String, iconColor: Color, value: String, unit: String, accent: Color, glowing: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(iconColor)
            Text(value).font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.textPrimary).contentTransition(.numericText())
            Text(unit).font(.system(size: 11, weight: .semibold)).foregroundColor(accent.opacity(0.8))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(ZStack { Color.surface; accent.opacity(0.06) }).cornerRadius(100)
        .overlay(Capsule().stroke(accent.opacity(glowing ? 0.5 : 0.2), lineWidth: glowing ? 1.5 : 1))
        .shadow(color: glowing ? accent.opacity(0.3) : .clear, radius: 8)
    }

    @ViewBuilder
    private func liveChip(icon: String, iconColor: Color, value: String, unit: String, accent: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(iconColor)
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.textPrimary).contentTransition(.numericText())
            Text(unit).font(.system(size: 11)).foregroundColor(.textTertiary)
        }
        .padding(.horizontal, 11).padding(.vertical, 8).background(Color.surface).cornerRadius(100)
        .overlay(Capsule().stroke(accent.opacity(0.2), lineWidth: 1))
    }
    // MARK: Main Content

    @ViewBuilder
    private func mainContent(exercise: Exercise) -> some View {
        ScrollView(showsIndicators: false) {
            Group {
                if isResting {
                    RestTimerView(restTimeLeft: restTimeLeft, totalRest: restTotal,
                                  nextLabel: nextLabel(exercise: exercise), onSkip: skipRest)
                        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .scale(scale: 0.9).combined(with: .opacity)))
                } else {
                    exerciseCard(exercise: exercise)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isResting)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: store.currentExerciseIndex)
    }

    // MARK: Exercise Card

    @ViewBuilder
    private func exerciseCard(exercise: Exercise) -> some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                // Set strip
                HStack {
                    HStack(spacing: 8) {
                        Text("Set \(store.currentSet) of \(exercise.sets)").font(.system(size: 13, weight: .bold)).foregroundColor(.ember)
                        HStack(spacing: 4) {
                            ForEach(0..<exercise.sets, id: \.self) { i in
                                Circle()
                                    .fill(i < store.currentSet - 1 ? Color.success : i == store.currentSet - 1 ? Color.ember : Color.borderColor)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: i == store.currentSet - 1 ? Color.ember.opacity(0.6) : .clear, radius: 3)
                                    .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.currentSet)
                            }
                        }
                    }
                    Spacer()
                    Text("\(store.currentExerciseIndex + 1)/\(exercises.count)").font(.system(size: 12)).foregroundColor(.textMuted)
                }
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)

                Divider().background(Color.borderColor.opacity(0.4))

                VStack(alignment: .leading, spacing: 14) {
                    Text(exercise.name).font(.system(size: 26, weight: .bold)).foregroundColor(.textPrimary)
                    if let def = currentDef {
                        HStack(spacing: 6) {
                            ForEach(def.primary.prefix(3)) { m in
                                Text(m.label).font(.system(size: 10, weight: .bold)).foregroundColor(m.accent)
                                    .padding(.horizontal, 8).padding(.vertical, 4).background(m.accent.opacity(0.12)).cornerRadius(7)
                            }
                            Text("Tempo \(def.tempo)").font(.system(size: 10, weight: .semibold)).foregroundColor(.textMuted)
                                .padding(.horizontal, 8).padding(.vertical, 4).background(Color.surfaceElevated).cornerRadius(7)
                        }
                    }
                    ExerciseDemonstrationView(exercise: exercise, definition: currentDef, selectedTab: $selectedDemoTab,
                                              onLaunchCamera: { showFormCoach = true })
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 18)

                Divider().background(Color.borderColor.opacity(0.4))

                // Weight × Reps hero
                ZStack {
                    currentZone.color.opacity(0.04).animation(.easeInOut(duration: 0.8), value: currentZone.label)
                    HStack(spacing: 0) {
                        if exercise.weight != nil {
                            VStack(spacing: 4) {
                                HStack(spacing: 10) {
                                    Button {
                                        currentWeight = max(0, currentWeight - 5); UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        ZStack {
                                            Circle().fill(Color.surfaceElevated).frame(width: 36, height: 36).overlay(Circle().stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
                                            Image(systemName: "minus").font(.system(size: 14, weight: .bold)).foregroundColor(.textMuted)
                                        }
                                    }
                                    VStack(spacing: 1) {
                                        Text("\(currentWeight)").font(.system(size: 58, weight: .black, design: .rounded)).foregroundColor(.textPrimary).contentTransition(.numericText())
                                        Text("LBS").font(.system(size: 9, weight: .black)).foregroundColor(currentZone.color.opacity(0.8)).tracking(3).animation(.easeInOut(duration: 0.8), value: currentZone.label)
                                    }
                                    Button {
                                        currentWeight += 5; UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        ZStack {
                                            Circle().fill(Color.ember.opacity(0.12)).frame(width: 36, height: 36).overlay(Circle().stroke(Color.ember.opacity(0.3), lineWidth: 1))
                                            Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundColor(.ember)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            Rectangle().fill(Color.borderColor.opacity(0.35)).frame(width: 1, height: 60)
                        }
                        VStack(spacing: 1) {
                            Text(exercise.reps).font(.system(size: 58, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
                            Text("REPS").font(.system(size: 9, weight: .black)).foregroundColor(currentZone.color.opacity(0.8)).tracking(3).animation(.easeInOut(duration: 0.8), value: currentZone.label)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 26)
                }

                Divider().background(Color.borderColor.opacity(0.4))

                // Live auto-regulation read
                AutoRegStrip(recommendation: recommendation)
                    .padding(.horizontal, 20).padding(.vertical, 14)

                Divider().background(Color.borderColor.opacity(0.4))

                // Previous sets
                let prevSets = setLog.filter { $0.exerciseName == exercise.name }
                if !prevSets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PREVIOUS SETS").font(.system(size: 9, weight: .black)).foregroundColor(.textMuted).tracking(2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(prevSets) { entry in
                                    VStack(spacing: 3) {
                                        if entry.isPersonalRecord { Image(systemName: "crown.fill").font(.system(size: 9)).foregroundColor(.warning) }
                                        Text("\(entry.repsPerformed)").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(entry.isPersonalRecord ? .warning : .textPrimary)
                                        if entry.weightUsed > 0 { Text("\(entry.weightUsed)lb").font(.system(size: 10)).foregroundColor(.textTertiary) }
                                        Text("RPE \(entry.rpe)").font(.system(size: 9, weight: .bold)).foregroundColor(rpeColor(entry.rpe))
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(entry.isPersonalRecord ? Color.warning.opacity(0.1) : Color.surfaceElevated).cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(entry.isPersonalRecord ? Color.warning.opacity(0.4) : Color.borderColor.opacity(0.4), lineWidth: 1))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    Divider().background(Color.borderColor.opacity(0.4))
                }

                HStack(spacing: 5) {
                    Image(systemName: "clock.fill").font(.system(size: 11)).foregroundColor(.textMuted)
                    Text("\(recommendation.restSeconds)s rest").font(.system(size: 12)).foregroundColor(.textTertiary)
                    if let notes = exercise.notes {
                        Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                        Text(notes).font(.system(size: 12, design: .serif).italic()).foregroundColor(.textTertiary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .background(Color.surface).cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)

            actionButtons(exercise: exercise)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
    }

    // MARK: Action Buttons

    @ViewBuilder
    private func actionButtons(exercise: Exercise) -> some View {
        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx  = store.currentExerciseIndex >= exercises.count - 1
        let isFinish  = isLastSet && isLastEx
        VStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                loggedReps = recommendation.repTarget > 0 ? recommendation.repTarget : (Int(exercise.reps) ?? exercise.reps.repMidpoint)
                loggedRPE  = recommendation.rpeTarget
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { showSetLogger = true }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isFinish ? "checkmark.circle.fill" : "pencil.and.list.clipboard").font(.system(size: 19, weight: .black))
                    Text(isFinish ? "Log & Finish 🎉" : isLastSet ? "Log Set · Next Exercise →" : "Log Set →").font(.system(size: 17, weight: .black))
                    Spacer()
                }
                .foregroundColor(.white).padding(.horizontal, 24).padding(.vertical, 20).frame(maxWidth: .infinity)
                .background(LinearGradient(colors: isFinish ? [Color.success, Color.success.opacity(0.8)] : [Color.ember, Color.ember.opacity(0.82)], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(20).shadow(color: (isFinish ? Color.success : Color.ember).opacity(0.5), radius: 20, y: 8)
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isFinish)
            }
            HStack(spacing: 10) {
                actionMini(icon: "forward.fill", label: "Skip", color: .textSecondary) { skipExercise() }
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { showPainLogger = true }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
                        Text(painLog.isEmpty ? "Pain" : "Pain (\(painLog.count))").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.warning).frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color.warning.opacity(painLog.isEmpty ? 0.1 : 0.2)).cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.warning.opacity(0.3), lineWidth: 1))
                }
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(); showFormCoach = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder").font(.system(size: 13))
                        Text("Form").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.success).frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color.success.opacity(0.12)).cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.success.opacity(0.3), lineWidth: 1))
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.4)) { coachIndex += 1 }
                } label: {
                    Image(systemName: "brain.head.profile").font(.system(size: 14)).foregroundColor(.ember).frame(width: 46, height: 46)
                        .background(Color.ember.opacity(0.1)).cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ember.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }

    private func actionMini(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(color).frame(maxWidth: .infinity).frame(height: 46)
            .background(Color.surfaceElevated).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        }
    }

    // MARK: Coach Bar (contextual, data-driven)

    private var liveCoachCues: [String] {
        var cues: [String] = [recommendation.rationale]
        if let def = currentDef { cues.append(contentsOf: def.cues) }
        cues.append(currentZone.index >= 4 ? "HR is climbing — keep technique tight as you fatigue." : "O₂ is solid — you can hold this pace.")
        cues.append("Brace the core and own every rep.")
        return cues
    }

    private var coachBar: some View {
        HStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: 0.05)) { tl in
                let p = (sin(tl.date.timeIntervalSinceReferenceDate * 1.8) + 1) / 2
                RoundedRectangle(cornerRadius: 2).fill(Color.ember.opacity(0.5 + p * 0.5)).frame(width: 3).shadow(color: Color.ember.opacity(0.4 + p * 0.4), radius: 4 + p * 4)
            }
            .frame(width: 3)
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.ember.opacity(0.12)).frame(width: 36, height: 36)
                    Image(systemName: "brain.head.profile").font(.system(size: 14, weight: .semibold)).foregroundColor(.ember)
                }
                ZStack {
                    Text(liveCoachCues[coachIndex % liveCoachCues.count])
                        .font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading).id(coachIndex)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                }
                .animation(.easeInOut(duration: 0.4), value: coachIndex)
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
        }
        .background(ZStack { Color.surfaceElevated; LinearGradient(colors: [Color.ember.opacity(0.04), .clear], startPoint: .leading, endPoint: .trailing) })
        .cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ember.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 16).padding(.bottom, 20).padding(.top, 6)
    }

    // MARK: Logic

    private func rpeColor(_ rpe: Int) -> Color { rpe <= 4 ? .success : rpe <= 7 ? Color(hex: "F59E0B") : .danger }
    private func setupCurrentWeight() { currentWeight = currentExercise?.weight ?? 0 }

    private func confirmSet(exercise: Exercise) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { showSetLogger = false }
        let prev = setLog.filter { $0.exerciseName == exercise.name }
        let existingMax = prev.map { $0.weightUsed }.max() ?? 0
        let isPR = currentWeight > existingMax && currentWeight > 0

        // Auto-regulation logging: did load change vs the previous set on this lift?
        if let last = prev.last, last.weightUsed != currentWeight, currentWeight > 0 {
            let dir = currentWeight > last.weightUsed ? "↑" : "↓"
            autoRegLog.append("\(exercise.name): load \(last.weightUsed)→\(currentWeight) \(dir) (\(last.rpe >= 9 ? "RPE-capped" : "RPE-driven"))")
        }

        let entry = SetLogEntry(exerciseName: exercise.name, setNumber: store.currentSet,
                                repsPerformed: loggedReps, weightUsed: currentWeight, rpe: loggedRPE, isPersonalRecord: isPR)
        setLog.append(entry)
        totalVolume += entry.volume
        accrueMuscleVolume(for: exercise, volume: Double(max(entry.volume, loggedReps)))

        if isPR {
            prExerciseName = exercise.name
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { showPRBanner = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Task { try? await Task.sleep(nanoseconds: 2_500_000_000); withAnimation(.easeOut(duration: 0.4)) { showPRBanner = false } }
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        if loggedRPE >= 9 { withAnimation(.easeInOut(duration: 0.4)) { coachIndex += 1 } }

        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx  = store.currentExerciseIndex >= exercises.count - 1
        if isLastSet && isLastEx { endWorkout(); return }
        let restFor = recommendation.restSeconds
        if isLastSet { store.nextExercise(); setupCurrentWeight() } else { store.nextSet() }
        startRest(seconds: restFor)
    }

    private func accrueMuscleVolume(for exercise: Exercise, volume: Double) {
        guard let def = ExerciseLibrary.definition(for: exercise) else { muscleVolume[.fullBody, default: 0] += volume; return }
        for m in def.primary { muscleVolume[m, default: 0] += volume }
        for m in def.secondary { muscleVolume[m, default: 0] += volume * 0.4 }
    }

    private func handlePain(_ entry: PainEntry, exercise: Exercise) {
        painLog.append(entry)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showPainLogger = false }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        let def = ExerciseLibrary.definition(for: exercise)
        let contraindicated = def?.painContraindications.contains(entry.location) ?? false
        if entry.severity >= 7 || (entry.severity >= 5 && contraindicated) {
            if let swap = AdaptiveEngine.substitution(for: exercise, painLocation: entry.location) {
                pendingSwap = swap
                swapReason = "\(entry.location) at \(entry.severity)/10"
                withAnimation { showSwapBanner = true }
                autoRegLog.append("\(entry.location) pain \(entry.severity)/10 → ARIA proposed \(swap.name)")
            }
        }
    }

    private func applySwap(_ def: ExerciseDefinition) {
        guard exercises.indices.contains(store.currentExerciseIndex) else { return }
        let old = exercises[store.currentExerciseIndex].name
        let new = Exercise(id: UUID().uuidString, name: def.name, sets: exercises[store.currentExerciseIndex].sets,
                           reps: def.repRangeLabel.replacingOccurrences(of: "–", with: "-"),
                           weight: def.equipment == .bodyweight ? nil : max(20, (exercises[store.currentExerciseIndex].weight ?? 45) * 7 / 10),
                           restSeconds: def.restSeconds, notes: def.cues.first, videoURL: nil, has3DModel: false)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            store.todayWorkout?.exercises[store.currentExerciseIndex] = new
            store.currentSet = 1
            showSwapBanner = false
        }
        autoRegLog.append("Swapped \(old) → \(def.name) (\(swapReason))")
        setupCurrentWeight()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func endWorkout() {
        cancelTasks()
        let avgHR  = hrHistory.isEmpty ? simulatedHR : hrHistory.reduce(0, +) / hrHistory.count
        let rpes   = setLog.map { Double($0.rpe) }
        let avgRPE = rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
        let prs    = Array(Set(setLog.filter { $0.isPersonalRecord }.map { $0.exerciseName }))
        let painFlags = Array(Set(painLog.map { "\($0.location) (\($0.severity)/10)" }))
        var mvStr: [String: Double] = [:]
        for (m, v) in muscleVolume { mvStr[m.rawValue] = v }
        let data = WorkoutSummaryData(
            duration: elapsedSecs, totalVolume: totalVolume, totalSets: setLog.count,
            totalReps: setLog.reduce(0) { $0 + $1.repsPerformed }, peakHR: peakHR, avgHR: avgHR,
            peakO2: peakSpO2, minO2: minSpO2, caloriesBurned: Int(estimatedCals), personalRecords: prs,
            exercisesCompleted: min(store.currentExerciseIndex + 1, exercises.count), avgRPE: avgRPE, hrHistory: hrHistory,
            muscleVolume: mvStr, autoRegLog: autoRegLog, painFlags: painFlags,
            readiness: store.readiness.overall, workoutName: store.todayWorkout?.name ?? "Workout")
        store.endWorkout()
        onWorkoutEnd(data)
    }

    private func skipExercise() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if store.currentExerciseIndex >= exercises.count - 1 { endWorkout() }
        else { store.nextExercise(); isResting = false; restTimeLeft = 0; restTask?.cancel(); setupCurrentWeight() }
    }
    private func skipRest() {
        restTask?.cancel(); restTask = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { isResting = false }
        restTimeLeft = 0; UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    private func handleEnd() {
        if showEndConfirm { endWorkout() }
        else {
            showEndConfirm = true; UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            Task { try? await Task.sleep(nanoseconds: 3_000_000_000); showEndConfirm = false }
        }
    }
    private func startRest(seconds: Int) {
        restTotal = max(1, seconds); restTimeLeft = seconds
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { isResting = true }
        restTask?.cancel()
        restTask = Task {
            while restTimeLeft > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                if restTimeLeft <= 1 {
                    restTimeLeft = 0
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { isResting = false }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    return
                }
                restTimeLeft -= 1
            }
        }
    }
    private func nextLabel(exercise: Exercise) -> String {
        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx  = store.currentExerciseIndex >= exercises.count - 1
        if isLastSet && isLastEx { return "Workout Complete 🎉" }
        if isLastSet {
            let next = exercises.indices.contains(store.currentExerciseIndex + 1) ? exercises[store.currentExerciseIndex + 1].name : "Done"
            return "Next: \(next)"
        }
        return "Set \(store.currentSet) of \(exercise.sets) done"
    }

    // MARK: Tasks

    private func startTasks() {
        elapsedTask = Task {
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000_000); guard !Task.isCancelled else { return }; elapsedSecs += 1 }
        }
        hrTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000); guard !Task.isCancelled else { return }
                let target = isResting ? (108 + Double.random(in: 0...18)) : (140 + Double.random(in: 0...26))
                simulatedHR = Int((Double(simulatedHR) + (target - Double(simulatedHR)) * 0.12 + Double.random(in: -4...4)).rounded().clamped(to: 55...200))
                hrHistory.append(simulatedHR)
                if simulatedHR > peakHR { peakHR = simulatedHR }
            }
        }
        calTask = Task {
            let weightKg = store.userProfile.weight ?? 80
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000); guard !Task.isCancelled else { return }
                // MET-based expenditure: kcal/sec = MET · 3.5 · kg / 200 / 60, scaled by HR drive.
                let met = isResting ? 1.5 : (currentDef?.met ?? 5.0)
                let hrScale = simulatedHR > 150 ? 1.15 : simulatedHR > 130 ? 1.05 : 1.0
                estimatedCals += (met * 3.5 * weightKg / 200 / 60) * hrScale
            }
        }
        o2Task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000); guard !Task.isCancelled else { return }
                let drop     = simulatedHR > 160 ? Double.random(in: 1...3) : simulatedHR > 140 ? Double.random(in: 0...1.5) : 0.0
                let recovery = isResting ? Double.random(in: 0...1) : 0
                simulatedSpO2 = Int((Double(simulatedSpO2) - drop + recovery).rounded().clamped(to: 90.0...100.0))
                if simulatedSpO2 > peakSpO2 { peakSpO2 = simulatedSpO2 }
                if simulatedSpO2 < minSpO2  { minSpO2  = simulatedSpO2 }
                if simulatedSpO2 < 94 && !showO2Warning {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showO2Warning = true }
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    Task { try? await Task.sleep(nanoseconds: 5_000_000_000); withAnimation { showO2Warning = false } }
                }
            }
        }
        coachTask = Task {
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 9_000_000_000); guard !Task.isCancelled else { return }; withAnimation(.easeInOut(duration: 0.4)) { coachIndex += 1 } }
        }
    }
    private func cancelTasks() {
        [elapsedTask, hrTask, calTask, o2Task, restTask, coachTask].forEach { $0?.cancel() }
        elapsedTask = nil; hrTask = nil; calTask = nil; o2Task = nil; restTask = nil; coachTask = nil
    }
    private func formatTime(_ s: Int, flashColon: Bool = true) -> String {
        let sep = flashColon ? ":" : " "
        return String(format: "%02d\(sep)%02d", s / 60, s % 60)
    }
}

// MARK: - Auto-Regulation Strip

private struct AutoRegStrip: View {
    let recommendation: SetRecommendation
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(recommendation.primaryAction.tone.opacity(0.14)).frame(width: 36, height: 36)
                Image(systemName: recommendation.primaryAction.icon).font(.system(size: 15, weight: .semibold)).foregroundColor(recommendation.primaryAction.tone)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("ARIA AUTO-REG").font(.system(size: 9, weight: .black)).tracking(1.5).foregroundColor(.textTertiary)
                    if recommendation.weightDelta != 0 {
                        Text("\(recommendation.weightDelta > 0 ? "+" : "")\(recommendation.weightDelta) lb")
                            .font(.system(size: 9, weight: .black)).foregroundColor(recommendation.primaryAction.tone)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(recommendation.primaryAction.tone.opacity(0.14)).cornerRadius(4)
                    }
                }
                Text(recommendation.rationale).font(.system(size: 12)).foregroundColor(.textSecondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(Color.surfaceElevated).cornerRadius(13)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(recommendation.primaryAction.tone.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Substitution Banner

private struct SubstitutionBanner: View {
    let target: ExerciseDefinition
    let reason: String
    let onApply: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        VStack {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.steel.opacity(0.2)).frame(width: 40, height: 40)
                        Image(systemName: "arrow.triangle.swap").font(.system(size: 17)).foregroundColor(.steel)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ARIA SUGGESTS A SWAP").font(.system(size: 10, weight: .black)).tracking(1.5).foregroundColor(.steel)
                        Text("\(reason) — try \(target.name)").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                    }
                    Spacer()
                    Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.textMuted).frame(width: 28, height: 28).background(Color.surfaceElevated).clipShape(Circle()) }
                }
                Button(action: onApply) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .bold))
                        Text("Swap to \(target.name)").font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 44).background(Color.steel).cornerRadius(12)
                }
            }
            .padding(16)
            .background(ZStack { Color.surface; LinearGradient(colors: [Color.steel.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing) })
            .cornerRadius(18).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.steel.opacity(0.4), lineWidth: 1.5))
            .shadow(color: Color.steel.opacity(0.25), radius: 20, y: 6)
            .padding(.horizontal, 16).padding(.top, 56)
            Spacer()
        }
    }
}
// MARK: - O2 Warning Banner

private struct O2WarningBanner: View {
    let spO2: Int
    let onDismiss: () -> Void
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.danger.opacity(0.2)).frame(width: 40, height: 40)
                    Image(systemName: "lungs.fill").font(.system(size: 18)).foregroundColor(.danger)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOW O₂ SATURATION").font(.system(size: 11, weight: .black)).foregroundColor(.danger).tracking(1.5)
                    Text("\(spO2)% — Slow down and breathe deeply").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                }
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.textMuted).frame(width: 28, height: 28).background(Color.surfaceElevated).clipShape(Circle()) }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(ZStack { Color.surface; LinearGradient(colors: [Color.danger.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing) })
            .cornerRadius(18).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.danger.opacity(0.45), lineWidth: 1.5))
            .shadow(color: Color.danger.opacity(0.25), radius: 20, y: 6)
            .padding(.horizontal, 16).padding(.top, 56)
            Spacer()
        }
    }
}

// MARK: - Set Logger Panel (adaptive)

private struct SetLoggerPanel: View {
    let exercise: Exercise
    let definition: ExerciseDefinition?
    let currentSet: Int
    let recommendation: SetRecommendation
    @Binding var proposedReps: Int
    @Binding var proposedWeight: Int
    @Binding var proposedRPE: Int
    let onConfirm: () -> Void
    let onCancel:  () -> Void
    @State private var rpePulsing: Int? = nil

    private func rpeLabel(_ r: Int) -> String {
        switch r {
        case 1...3: return "Easy"
        case 4...5: return "Moderate"
        case 6...7: return "Hard"
        case 8: return "Very Hard"
        case 9: return "Max Effort"
        default: return "All Out 🔥"
        }
    }
    private func rpeColor(_ r: Int) -> Color { r <= 4 ? .success : r <= 7 ? Color(hex: "F59E0B") : .danger }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { onCancel() }
            VStack {
                Spacer()
                VStack(spacing: 0) {
                    VStack(spacing: 14) {
                        Capsule().fill(Color.white.opacity(0.18)).frame(width: 36, height: 4)
                        Text("SET \(currentSet) — \(exercise.name.uppercased())").font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.45)).tracking(2.5)
                    }
                    .padding(.top, 16).padding(.bottom, 14)

                    // ARIA recommendation
                    HStack(spacing: 10) {
                        Image(systemName: recommendation.primaryAction.icon).font(.system(size: 13)).foregroundColor(recommendation.primaryAction.tone)
                        Text(recommendation.rationale).font(.system(size: 12)).foregroundColor(.white.opacity(0.7)).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24).padding(.bottom, 14)

                    Divider().background(Color.white.opacity(0.08))
                    VStack(spacing: 18) {
                        VStack(spacing: 10) {
                            Text("REPS PERFORMED").font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                            HStack(spacing: 32) {
                                stepperButton("minus", tint: .white.opacity(0.7), bg: .white.opacity(0.08)) { if proposedReps > 1 { proposedReps -= 1 } }
                                Text("\(proposedReps)").font(.system(size: 72, weight: .black, design: .rounded)).foregroundColor(.white).frame(minWidth: 90).contentTransition(.numericText())
                                stepperButton("plus", tint: .ember, bg: .ember.opacity(0.22)) { proposedReps += 1 }
                            }
                        }
                        if exercise.weight != nil && proposedWeight > 0 {
                            VStack(spacing: 10) {
                                Text("WEIGHT (LBS)").font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                                HStack(spacing: 7) {
                                    ForEach([(-10, "-10"), (-5, "-5"), (5, "+5"), (10, "+10")], id: \.0) { delta, lbl in
                                        Button {
                                            proposedWeight = max(0, proposedWeight + delta); UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        } label: {
                                            Text(lbl).font(.system(size: 14, weight: .bold)).foregroundColor(delta > 0 ? .ember : .white.opacity(0.6))
                                                .frame(maxWidth: .infinity).frame(height: 40)
                                                .background(delta > 0 ? Color.ember.opacity(0.15) : Color.white.opacity(0.07)).cornerRadius(10)
                                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(delta > 0 ? Color.ember.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1))
                                        }
                                    }
                                    Text("\(proposedWeight)").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.white).contentTransition(.numericText()).frame(minWidth: 52)
                                }
                            }
                        }
                        VStack(spacing: 10) {
                            HStack {
                                Text("EFFORT").font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                                Spacer()
                                Text("RPE \(proposedRPE) — \(rpeLabel(proposedRPE))").font(.system(size: 12, weight: .bold)).foregroundColor(rpeColor(proposedRPE)).animation(.spring(response: 0.3, dampingFraction: 0.7), value: proposedRPE)
                            }
                            HStack(spacing: 3) {
                                ForEach(1...10, id: \.self) { level in
                                    Button {
                                        proposedRPE = level; rpePulsing = level; UISelectionFeedbackGenerator().selectionChanged()
                                        Task { try? await Task.sleep(nanoseconds: 180_000_000); rpePulsing = nil }
                                    } label: {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(level <= proposedRPE ? rpeColor(level) : Color.white.opacity(0.07))
                                            .frame(maxWidth: .infinity).frame(height: 36)
                                            .overlay(Text("\(level)").font(.system(size: 11, weight: .black)).foregroundColor(level <= proposedRPE ? .white : .white.opacity(0.25)))
                                            .scaleEffect(rpePulsing == level ? 1.18 : 1.0).animation(.spring(response: 0.2, dampingFraction: 0.5), value: rpePulsing)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Button(action: onConfirm) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                                Text("Log Set").font(.system(size: 20, weight: .black))
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 60)
                            .background(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.82)], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(20).shadow(color: Color.ember.opacity(0.55), radius: 20, y: 6)
                        }
                        Button(action: onCancel) { Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.4)) }.padding(.bottom, 8)
                    }
                    .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 28)
                }
                .background(ZStack { Color(hex: "0E0E0E"); LinearGradient(colors: [Color.ember.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .bottomTrailing) })
                .roundedCorners(32, corners: [.topLeft, .topRight])
                .overlay(RoundedRectangle(cornerRadius: 32).stroke(Color.white.opacity(0.09), lineWidth: 1).mask(Rectangle().padding(.bottom, -40)))
            }
        }
        .ignoresSafeArea()
    }

    private func stepperButton(_ icon: String, tint: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button { action(); UIImpactFeedbackGenerator(style: .light).impactOccurred() } label: {
            ZStack {
                Circle().fill(bg).frame(width: 44, height: 44).overlay(Circle().stroke(tint.opacity(0.4), lineWidth: 1))
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundColor(tint)
            }
        }
    }
}

// MARK: - Pain Logger Panel

private struct PainLoggerPanel: View {
    let exerciseName: String
    let onLog:    (PainEntry) -> Void
    let onCancel: () -> Void
    @State private var selectedLocation = "Knee"
    @State private var severity = 5
    private let locations = ["Shoulder", "Elbow", "Wrist", "Lower Back", "Hip", "Knee", "Ankle", "Neck", "Other"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Capsule().fill(Color.textTertiary.opacity(0.4)).frame(width: 36, height: 4).padding(.top, 12)
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15)).foregroundColor(.warning)
                    Text("LOG PAIN / DISCOMFORT").font(.system(size: 11, weight: .black)).foregroundColor(.textTertiary).tracking(2)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("LOCATION").font(.system(size: 10, weight: .black)).foregroundColor(.textMuted).tracking(2)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(locations, id: \.self) { loc in
                            Button { selectedLocation = loc; UISelectionFeedbackGenerator().selectionChanged() } label: {
                                Text(loc).font(.system(size: 13, weight: .medium)).foregroundColor(selectedLocation == loc ? .white : .textSecondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(selectedLocation == loc ? Color.warning : Color.surfaceElevated).cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedLocation == loc ? Color.warning.opacity(0.5) : Color.borderColor.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("SEVERITY").font(.system(size: 10, weight: .black)).foregroundColor(.textMuted).tracking(2)
                        Spacer()
                        Text("\(severity)/10").font(.system(size: 13, weight: .bold)).foregroundColor(severity >= 7 ? .danger : .warning)
                    }
                    HStack(spacing: 3) {
                        ForEach(1...10, id: \.self) { level in
                            Button { severity = level; UIImpactFeedbackGenerator(style: .light).impactOccurred() } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(level <= severity ? (severity >= 7 ? Color.danger : Color.warning) : Color.surfaceElevated)
                                    .frame(maxWidth: .infinity).frame(height: 32)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.borderColor.opacity(0.3), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(severity >= 7 ? "Sharp pain — ARIA will pull you off this movement." : severity >= 5 ? "ARIA may swap to a joint-friendly variant." : "Logged for ARIA to monitor.")
                        .font(.system(size: 11)).foregroundColor(.textTertiary)
                }
                Button { onLog(PainEntry(location: selectedLocation, severity: severity, exerciseName: exerciseName)) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18))
                        Text("Log Pain").font(.system(size: 18, weight: .black))
                    }
                    .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 56)
                    .background(LinearGradient(colors: [Color.warning, Color.warning.opacity(0.82)], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(18).shadow(color: Color.warning.opacity(0.5), radius: 16, y: 6)
                }
                .padding(.horizontal, 4)
                Button(action: onCancel) { Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundColor(.textSecondary) }.padding(.bottom, 32)
            }
            .padding(.horizontal, 24).background(Color.surface).roundedCorners(28, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.22), radius: 40, y: -10)
        }
        .ignoresSafeArea()
    }
}

// MARK: - PR Banner

private struct PRBannerView: View {
    let exerciseName: String
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.warning.opacity(0.2)).frame(width: 40, height: 40)
                    Image(systemName: "trophy.fill").font(.system(size: 18)).foregroundColor(.warning)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("PERSONAL RECORD 🏆").font(.system(size: 12, weight: .black)).foregroundColor(.warning).tracking(1.5)
                    Text(exerciseName).font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(ZStack { Color.surface; LinearGradient(colors: [Color.warning.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing) })
            .cornerRadius(18).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.warning.opacity(0.4), lineWidth: 1.5))
            .shadow(color: Color.warning.opacity(0.25), radius: 20, y: 6)
            .padding(.horizontal, 16).padding(.top, 56)
            Spacer()
        }
    }
}
// MARK: - Rest Timer

struct RestTimerView: View {
    let restTimeLeft: Int
    let totalRest:    Int
    let nextLabel:    String
    let onSkip:       () -> Void
    @State private var breathPhase = false

    private var progress: CGFloat { totalRest > 0 ? CGFloat(restTimeLeft) / CGFloat(totalRest) : 0 }
    private var urgency: Bool { restTimeLeft <= 5 && restTimeLeft > 0 }
    private var ringColor: Color { urgency ? .danger : Color(hex: "38BDF8") }
    private var breathLabel: String { breathPhase ? "Exhale slowly" : "Breathe in" }

    var body: some View {
        VStack(spacing: 20) {
            Text("REST").font(.system(size: 11, weight: .black)).foregroundColor(.textMuted).tracking(4)
                .padding(.horizontal, 14).padding(.vertical, 6).background(Color.surfaceElevated).cornerRadius(100)
                .overlay(Capsule().stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
            ZStack {
                Circle().fill(ringColor.opacity(0.06)).frame(width: 220, height: 220).animation(.easeInOut(duration: 1.0), value: ringColor)
                Circle().stroke(Color.borderColor.opacity(0.25), style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 170, height: 170)
                Circle().trim(from: 0, to: progress).stroke(ringColor.opacity(0.5), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 170, height: 170).rotationEffect(.degrees(-90)).blur(radius: 6).animation(.linear(duration: 1), value: progress)
                Circle().trim(from: 0, to: progress)
                    .stroke(LinearGradient(colors: [ringColor, ringColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 170, height: 170).rotationEffect(.degrees(-90)).animation(.linear(duration: 1), value: progress).animation(.easeInOut(duration: 0.6), value: ringColor)
                ZStack {
                    Circle().stroke(Color(hex: "38BDF8").opacity(breathPhase ? 0.15 : 0.0), lineWidth: 1.5).frame(width: breathPhase ? 130 : 80, height: breathPhase ? 130 : 80).animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathPhase)
                    Circle().stroke(Color(hex: "38BDF8").opacity(breathPhase ? 0.25 : 0.08), lineWidth: 2).frame(width: breathPhase ? 100 : 60, height: breathPhase ? 100 : 60).animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathPhase)
                    Circle().fill(Color(hex: "38BDF8").opacity(breathPhase ? 0.15 : 0.04)).frame(width: breathPhase ? 80 : 50, height: breathPhase ? 80 : 50).animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathPhase)
                }
                .opacity(urgency ? 0 : 1)
                VStack(spacing: 3) {
                    Text("\(restTimeLeft)").font(.system(size: 62, weight: .black, design: .rounded)).foregroundColor(urgency ? .danger : .textPrimary).contentTransition(.numericText())
                        .scaleEffect(urgency ? 1.1 : 1.0).animation(.spring(response: 0.3, dampingFraction: 0.55), value: urgency)
                    Text("sec").font(.system(size: 12, weight: .semibold)).foregroundColor(.textMuted)
                }
            }
            .frame(width: 220, height: 220)
            if !urgency {
                Text(breathLabel).font(.system(size: 13, weight: .medium)).foregroundColor(Color(hex: "38BDF8").opacity(0.8)).animation(.easeInOut(duration: 0.5), value: breathPhase)
            }
            Text(nextLabel).font(.system(size: 14, weight: .medium)).foregroundColor(.textTertiary).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button(action: onSkip) {
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill").font(.system(size: 13))
                    Text("Skip Rest").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.textSecondary).padding(.horizontal, 28).padding(.vertical, 14).background(Color.surfaceElevated).cornerRadius(100)
                .overlay(Capsule().stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .onAppear { withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breathPhase = true } }
    }
}

// MARK: - Workout Summary

struct WorkoutSummaryView: View {
    let data: WorkoutSummaryData
    let onDismiss: () -> Void
    @State private var appeared = false
    @State private var scoreAppeared = false
    @State private var showDashboard = false

    private var workoutScore: Int {
        var s = 60
        if data.personalRecords.count > 0 { s += min(20, data.personalRecords.count * 7) }
        if data.avgRPE >= 6 && data.avgRPE <= 8.5 { s += 10 }
        if data.minO2 >= 95 { s += 5 }
        if data.totalSets >= 12 { s += 5 }
        return min(100, s)
    }
    private var scoreLabel: String {
        switch workoutScore { case 90...: return "Elite"; case 80...: return "Excellent"; case 70...: return "Strong"; case 60...: return "Solid"; default: return "Good" }
    }
    private var scoreColor: Color {
        switch workoutScore { case 90...: return Color(hex: "F59E0B"); case 80...: return .success; case 70...: return .ember; default: return .steel }
    }

    var body: some View {
        ZStack {
            Color(hex: "0A0A0A").ignoresSafeArea()
            RadialGradient(colors: [scoreColor.opacity(appeared ? 0.12 : 0), .clear], center: .top, startRadius: 0, endRadius: 400)
                .ignoresSafeArea().animation(.easeInOut(duration: 1.5).delay(0.5), value: appeared)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero score
                    VStack(spacing: 24) {
                        ZStack {
                            Circle().stroke(scoreColor.opacity(appeared ? 0.12 : 0), lineWidth: 1).frame(width: 220, height: 220).animation(.easeInOut(duration: 1.0).delay(0.4), value: appeared)
                            Circle().stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 8, lineCap: .round)).frame(width: 180, height: 180)
                            Circle().trim(from: 0, to: scoreAppeared ? CGFloat(workoutScore) / 100 : 0)
                                .stroke(LinearGradient(colors: [scoreColor.opacity(0.7), scoreColor, scoreColor.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 180, height: 180).rotationEffect(.degrees(-90)).shadow(color: scoreColor.opacity(0.5), radius: 12)
                                .animation(.spring(response: 1.4, dampingFraction: 0.75).delay(0.5), value: scoreAppeared)
                            VStack(spacing: 4) {
                                Image(systemName: "checkmark").font(.system(size: 22, weight: .black)).foregroundColor(scoreColor)
                                    .scaleEffect(appeared ? 1 : 0.4).opacity(appeared ? 1 : 0).animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.3), value: appeared)
                                Text("\(workoutScore)").font(.system(size: 52, weight: .black, design: .rounded)).foregroundColor(.white)
                                    .scaleEffect(appeared ? 1 : 0.6).opacity(appeared ? 1 : 0).animation(.spring(response: 0.65, dampingFraction: 0.7).delay(0.2), value: appeared)
                                Text(scoreLabel.uppercased()).font(.system(size: 10, weight: .black)).foregroundColor(scoreColor).tracking(2.5)
                                    .opacity(appeared ? 1 : 0).animation(.easeOut(duration: 0.5).delay(0.55), value: appeared)
                            }
                        }
                        .frame(width: 220, height: 220)
                        VStack(spacing: 8) {
                            Text("Workout Complete").font(.system(size: 26, weight: .bold)).foregroundColor(.white)
                            HStack(spacing: 16) {
                                HStack(spacing: 5) {
                                    Image(systemName: "clock.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                                    Text(formatDuration(data.duration)).font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                                }
                                if !data.personalRecords.isEmpty {
                                    HStack(spacing: 5) {
                                        Image(systemName: "crown.fill").font(.system(size: 12)).foregroundColor(.warning)
                                        Text("\(data.personalRecords.count) PR\(data.personalRecords.count == 1 ? "" : "s")").font(.system(size: 14, weight: .bold)).foregroundColor(.warning)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 5).background(Color.warning.opacity(0.15)).cornerRadius(100)
                                    .overlay(Capsule().stroke(Color.warning.opacity(0.3), lineWidth: 1))
                                }
                            }
                        }
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: appeared)
                    }
                    .padding(.top, 64).padding(.bottom, 28)

                    // ARIA dashboard CTA
                    Button { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); showDashboard = true } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.ember.opacity(0.18)).frame(width: 38, height: 38)
                                Image(systemName: "brain.head.profile").font(.system(size: 17)).foregroundColor(.ember)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open ARIA Dashboard").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                                Text("Muscle balance, auto-reg log & how to improve").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.4))
                        }
                        .padding(16).background(Color.white.opacity(0.05)).cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ember.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16).padding(.bottom, 20)
                    .opacity(appeared ? 1 : 0).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: appeared)

                    if !data.hrHistory.isEmpty {
                        HRSparklineCard(hrHistory: data.hrHistory, peakHR: data.peakHR, avgHR: data.avgHR)
                            .padding(.horizontal, 16).padding(.bottom, 20)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.45), value: appeared)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach([
                            ("scalemass.fill", "\(data.totalVolume.formattedVolume)", "Volume", Color.steel),
                            ("flame.fill", "\(data.caloriesBurned)", "Kcal", Color.ember),
                            ("repeat", "\(data.totalSets)", "Sets", Color.success),
                            ("hand.raised.fill", "\(data.totalReps)", "Reps", Color(hex: "F59E0B")),
                            ("heart.fill", "\(data.peakHR)", "Peak HR", Color.danger),
                            ("waveform.path.ecg", "\(data.avgHR)", "Avg HR", Color.steel),
                            ("lungs.fill", "\(data.minO2)%", "Min O₂", data.minO2 < 94 ? Color.danger : Color(hex: "38BDF8")),
                            ("bolt.fill", String(format: "%.1f", data.avgRPE), "Avg RPE", rpeColor(data.avgRPE)),
                            ("dumbbell.fill", "\(data.exercisesCompleted)", "Exercises", Color.ember),
                        ], id: \.0) { icon, value, label, color in darkStatCard(icon, value, label, color) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5), value: appeared)

                    ZoneBreakdownCard(hrHistory: data.hrHistory)
                        .padding(.horizontal, 16).padding(.bottom, 20)
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.55), value: appeared)

                    if !data.personalRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Image(systemName: "crown.fill").font(.system(size: 14)).foregroundColor(.warning)
                                Text("PERSONAL RECORDS").font(.system(size: 10, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                            }
                            ForEach(data.personalRecords, id: \.self) { pr in
                                HStack(spacing: 12) {
                                    ZStack { Circle().fill(Color.warning.opacity(0.15)).frame(width: 38, height: 38); Image(systemName: "crown.fill").font(.system(size: 15)).foregroundColor(.warning) }
                                    Text(pr).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                                    Spacer()
                                    Text("NEW PR").font(.system(size: 10, weight: .black)).foregroundColor(.warning).tracking(1)
                                        .padding(.horizontal, 8).padding(.vertical, 5).background(Color.warning.opacity(0.15)).cornerRadius(100).overlay(Capsule().stroke(Color.warning.opacity(0.3), lineWidth: 1))
                                }
                                .padding(16).background(Color.white.opacity(0.05)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.warning.opacity(0.2), lineWidth: 1))
                            }
                        }
                        .padding(20).background(Color.white.opacity(0.04)).cornerRadius(22).overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07), lineWidth: 1))
                        .padding(.horizontal, 16).padding(.bottom, 20)
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.6), value: appeared)
                    }

                    VStack(spacing: 12) {
                        Button { showDashboard = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "paperplane.fill").font(.system(size: 16))
                                Text("Send to ARIA").font(.system(size: 17, weight: .bold))
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 58)
                            .background(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.82)], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(18).shadow(color: Color.ember.opacity(0.5), radius: 18, y: 6)
                        }
                        Button(action: onDismiss) {
                            HStack(spacing: 8) {
                                Image(systemName: "house.fill").font(.system(size: 15))
                                Text("Back to Dashboard").font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity).frame(height: 50)
                            .background(Color.white.opacity(0.07)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 60)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.7), value: appeared)
                }
            }
        }
        .sheet(isPresented: $showDashboard) { ARIADashboardView(snapshot: data.ariaSnapshot, isPreWorkout: false) }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.8).delay(0.1)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scoreAppeared = true }
        }
    }

    private func darkStatCard(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 10) {
            ZStack { Circle().fill(color.opacity(0.15)).frame(width: 40, height: 40); Image(systemName: icon).font(.system(size: 16)).foregroundColor(color) }
            Text(value).font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.white)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.4)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18).background(Color.white.opacity(0.05)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
    private func rpeColor(_ rpe: Double) -> Color { rpe <= 4 ? .success : rpe <= 7 ? Color(hex: "F59E0B") : .danger }
    private func formatDuration(_ s: Int) -> String { let m = s / 60; let sec = s % 60; return m > 0 ? "\(m)m \(sec)s" : "\(sec)s" }
}
// MARK: - Zone Breakdown Card

private struct ZoneBreakdownCard: View {
    let hrHistory: [Int]
    @State private var barsAppeared = false
    private struct ZoneBar { let zone: String; let color: Color; let range: ClosedRange<Int>; var count: Int = 0 }
    private var zoneBars: [ZoneBar] {
        var bars = [
            ZoneBar(zone: "Z1", color: Color(hex: "38BDF8"), range: 100...114),
            ZoneBar(zone: "Z2", color: .success, range: 115...133),
            ZoneBar(zone: "Z3", color: Color(hex: "F59E0B"), range: 134...152),
            ZoneBar(zone: "Z4", color: .ember, range: 153...171),
            ZoneBar(zone: "Z5", color: .danger, range: 172...220),
        ]
        for hr in hrHistory { for i in bars.indices where bars[i].range.contains(hr) { bars[i].count += 1 } }
        return bars
    }
    var body: some View {
        let bars = zoneBars
        let maxCount = max(1, bars.map { $0.count }.max() ?? 1)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 13)).foregroundColor(.danger)
                Text("HEART RATE ZONES").font(.system(size: 10, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                Spacer()
                Text("\(hrHistory.count) samples").font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(bars.enumerated()), id: \.element.zone) { idx, bar in
                    VStack(spacing: 8) {
                        let fraction = barsAppeared ? CGFloat(bar.count) / CGFloat(maxCount) : 0
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)).frame(maxWidth: .infinity, maxHeight: .infinity)
                            RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [bar.color, bar.color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                                .frame(maxWidth: .infinity).frame(height: max(4, 80 * fraction)).shadow(color: bar.color.opacity(0.4), radius: 4)
                        }
                        .frame(height: 80).animation(.spring(response: 0.9, dampingFraction: 0.75).delay(Double(idx) * 0.08), value: barsAppeared)
                        Text(formatZoneTime(bar.count)).font(.system(size: 10, weight: .bold)).foregroundColor(bar.count > 0 ? bar.color : .white.opacity(0.2))
                        Text(bar.zone).font(.system(size: 10, weight: .black)).foregroundColor(.white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20).background(Color.white.opacity(0.04)).cornerRadius(22).overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { barsAppeared = true } }
    }
    private func formatZoneTime(_ count: Int) -> String { let secs = count * 2; return secs < 60 ? "\(secs)s" : "\(secs / 60)m" }
}

// MARK: - HR Sparkline Card

private struct HRSparklineCard: View {
    let hrHistory: [Int]
    let peakHR: Int
    let avgHR:  Int
    @State private var lineAppeared = false
    private var smoothed: [Int] {
        guard hrHistory.count > 4 else { return hrHistory }
        let step = max(1, hrHistory.count / 60)
        return stride(from: 0, to: hrHistory.count, by: step).map { hrHistory[$0] }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.system(size: 13)).foregroundColor(.danger)
                    Text("HEART RATE").font(.system(size: 10, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                }
                Spacer()
                HStack(spacing: 18) {
                    VStack(spacing: 1) { Text("\(peakHR)").font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.danger); Text("peak").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.35)) }
                    VStack(spacing: 1) { Text("\(avgHR)").font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.white); Text("avg").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.35)) }
                }
            }
            GeometryReader { geo in
                Canvas { ctx, size in
                    let pts = smoothed
                    guard pts.count > 1 else { return }
                    let minV = Double(pts.min() ?? 60); let maxV = Double(pts.max() ?? 200); let rng = max(maxV - minV, 1)
                    let xStep = size.width / Double(pts.count - 1)
                    func y(_ v: Int) -> Double { size.height - (Double(v) - minV) / rng * size.height }
                    func pt(_ i: Int) -> CGPoint { CGPoint(x: Double(i) * xStep, y: y(pts[i])) }
                    let zoneDefs: [(min: Int, max: Int, col: Color)] = [(100,114,Color(hex:"38BDF8")),(115,133,.success),(134,152,Color(hex:"F59E0B")),(153,171,.ember),(172,220,.danger)]
                    for z in zoneDefs {
                        let yT = max(0.0, size.height - (Double(z.max) - minV) / rng * size.height)
                        let yB = min(size.height, size.height - (Double(z.min) - minV) / rng * size.height)
                        if yB > yT { ctx.fill(Path(CGRect(x: 0, y: yT, width: size.width, height: yB - yT)), with: .color(z.col.opacity(0.09))) }
                    }
                    var area = Path(); area.move(to: CGPoint(x: 0, y: size.height))
                    for i in pts.indices { i == 0 ? area.move(to: pt(0)) : area.addLine(to: pt(i)) }
                    area.addLine(to: CGPoint(x: size.width, y: size.height)); area.closeSubpath()
                    ctx.fill(area, with: .color(Color.danger.opacity(0.10)))
                    var line = Path(); for i in pts.indices { i == 0 ? line.move(to: pt(0)) : line.addLine(to: pt(i)) }
                    ctx.stroke(line, with: .color(Color.danger.opacity(0.85)), lineWidth: 2)
                }
                .opacity(lineAppeared ? 1 : 0).animation(.easeInOut(duration: 0.8), value: lineAppeared)
            }
            .frame(height: 88)
        }
        .padding(20).background(Color.white.opacity(0.04)).cornerRadius(22).overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { lineAppeared = true } }
    }
}

// MARK: - Exercise Demonstration

enum ExerciseDemoTab: CaseIterable { case video, formCheck }

struct ExerciseDemonstrationView: View {
    let exercise: Exercise
    var definition: ExerciseDefinition? = nil
    @Binding var selectedTab: ExerciseDemoTab
    var onLaunchCamera: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ExerciseDemoTab.allCases, id: \.self) { tab in
                    Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) { selectedTab = tab } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab == .video ? "play.circle.fill" : "camera.fill").font(.system(size: 12))
                            Text(tab == .video ? "Technique" : "ARIA Form Check").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(selectedTab == tab ? .white : .textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.ember : Color.surfaceElevated).cornerRadius(10)
                        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: selectedTab)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Group {
                switch selectedTab {
                case .video:     ExerciseTechniqueView(exercise: exercise, definition: definition)
                case .formCheck: ExerciseFormCheckView(exercise: exercise, onLaunch: onLaunchCamera)
                }
            }
            .id(selectedTab)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(height: 190)
            .background(Color.background.opacity(0.5)).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: selectedTab)
        }
    }
}

struct ExerciseTechniqueView: View {
    let exercise: Exercise
    var definition: ExerciseDefinition?
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.ember.opacity(0.09), Color.ember.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: definition?.icon ?? "figure.strengthtraining.traditional").font(.system(size: 36)).foregroundColor(.ember.opacity(0.55))
                if let def = definition {
                    VStack(spacing: 6) {
                        ForEach(def.cues.prefix(3), id: \.self) { cue in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundColor(def.accent)
                                Text(cue).font(.system(size: 12)).foregroundColor(.textSecondary).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    Text(exercise.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                    Text("Focus on controlled tempo and full range.").font(.system(size: 12)).foregroundColor(.textTertiary)
                }
            }
            .padding(.vertical, 14)
        }
    }
}

struct ExerciseFormCheckView: View {
    let exercise: Exercise
    var onLaunch: (() -> Void)? = nil
    @State private var showCamera = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.success.opacity(0.08), Color.success.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: "camera.viewfinder").font(.system(size: 38)).foregroundColor(.success.opacity(0.5))
                Text("ARIA Live Form Check").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                Text("Show ARIA your set — get real-time cues via the Claude vision API.").font(.system(size: 11)).foregroundColor(.textTertiary).multilineTextAlignment(.center).padding(.horizontal, 24)
                Button {
                    if let onLaunch { onLaunch() } else { showCamera = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.system(size: 13))
                        Text("Open Camera Coach").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.success).cornerRadius(20).shadow(color: Color.success.opacity(0.35), radius: 8, y: 3)
                }
            }
        }
        .sheet(isPresented: $showCamera) { FormCheckCameraView(exercise: exercise, definition: ExerciseLibrary.definition(for: exercise), liveContext: nil) }
    }
}
// MARK: - Form Check Camera (live ARIA vision coaching)

@MainActor
struct FormCheckCameraView: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    var definition: ExerciseDefinition?
    var liveContext: ARIALiveContext?

    @StateObject private var camera = FormCameraController()
    @StateObject private var aria = ARIACoachService()
    @State private var feedback: FormFeedback?
    @State private var autoCoach = false
    @State private var autoTask: Task<Void, Never>? = nil
    @State private var captureFlash = false

    private var context: ARIALiveContext {
        liveContext ?? ARIALiveContext(
            exerciseName: exercise.name,
            setLabel: "Working set",
            weight: exercise.weight ?? 0, reps: exercise.reps,
            heartRate: 0, hrZone: 0, spO2: 98, elapsed: "—",
            cues: definition?.cues ?? [])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                cameraLayer
                if captureFlash { Color.white.opacity(0.6).ignoresSafeArea().transition(.opacity) }
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if aria.isAnalyzing { analyzingPill.padding(.bottom, 12) }
                    if let fb = feedback { feedbackCard(fb).padding(.horizontal, 16).padding(.bottom, 12) }
                    controlBar.padding(.bottom, 28)
                }
            }
            .navigationBarHidden(true)
            .onAppear { camera.start() }
            .onDisappear { camera.stop(); autoTask?.cancel() }
        }
    }

    // ── Camera surface / permission states ────────────────────────────────────
    @ViewBuilder
    private var cameraLayer: some View {
        switch camera.status {
        case .running, .configuring:
            CameraPreview(session: camera.session).ignoresSafeArea()
        case .denied:
            statePlaceholder(icon: "lock.fill", title: "Camera access needed",
                             subtitle: "Enable camera in Settings so ARIA can watch your form.")
        case .unavailable:
            statePlaceholder(icon: "camera.metering.unknown", title: "No camera here",
                             subtitle: "Run on a device to use ARIA's live form coach. You can still preview ARIA's analysis below.")
        default:
            ZStack { Color.black; ProgressView().tint(.white) }.ignoresSafeArea()
        }
    }

    private func statePlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44)).foregroundColor(.white.opacity(0.5))
            Text(title).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            Text(subtitle).font(.system(size: 13)).foregroundColor(.white.opacity(0.5)).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: "0A0A0A"))
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.white).frame(width: 38, height: 38).background(.ultraThinMaterial).clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                HStack(spacing: 5) {
                    Circle().fill(aria.hasAPIKey ? Color.success : Color.warning).frame(width: 6, height: 6)
                    Text(aria.hasAPIKey ? "ARIA vision live" : "On-device preview").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
            if camera.status == .running {
                Button { camera.flip() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill").font(.system(size: 15, weight: .semibold)).foregroundColor(.white).frame(width: 38, height: 38).background(.ultraThinMaterial).clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 16)
        .background(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var analyzingPill: some View {
        HStack(spacing: 8) {
            ProgressView().tint(.white)
            Text("ARIA is reading your form…").font(.system(size: 13, weight: .medium)).foregroundColor(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial).clipShape(Capsule())
    }

    private func feedbackCard(_ fb: FormFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 5).frame(width: 54, height: 54)
                    Circle().trim(from: 0, to: CGFloat(fb.score) / 100)
                        .stroke(fb.status.color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).frame(width: 54, height: 54).rotationEffect(.degrees(-90))
                    Text("\(fb.score)").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: fb.status.icon).font(.system(size: 12)).foregroundColor(fb.status.color)
                        Text(fb.status.label).font(.system(size: 14, weight: .bold)).foregroundColor(fb.status.color)
                        if !fb.isLive { Text("DEMO").font(.system(size: 8, weight: .black)).foregroundColor(.white.opacity(0.5)).padding(.horizontal, 4).padding(.vertical, 1).background(Color.white.opacity(0.12)).cornerRadius(3) }
                    }
                    Text(fb.summary).font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !fb.cues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(fb.cues, id: \.self) { cue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill").font(.system(size: 12)).foregroundColor(.ember)
                            Text(cue).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineSpacing(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(16).background(.ultraThinMaterial).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(fb.status.color.opacity(0.4), lineWidth: 1))
    }

    private var controlBar: some View {
        HStack(spacing: 20) {
            // Auto-coach toggle
            Button { toggleAuto() } label: {
                VStack(spacing: 4) {
                    Image(systemName: autoCoach ? "bolt.fill" : "bolt.slash.fill").font(.system(size: 18)).foregroundColor(autoCoach ? .ember : .white.opacity(0.6))
                    Text("Auto").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                }
                .frame(width: 56, height: 56).background(.ultraThinMaterial).clipShape(Circle())
            }
            // Shutter
            Button { Task { await analyze() } } label: {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 4).frame(width: 74, height: 74)
                    Circle().fill(aria.isAnalyzing ? Color.white.opacity(0.4) : Color.white).frame(width: 60, height: 60)
                    Image(systemName: "camera.fill").font(.system(size: 22, weight: .bold)).foregroundColor(.black)
                }
            }
            .disabled(aria.isAnalyzing || (camera.status != .running && camera.status != .unavailable))
            // Done
            Button { dismiss() } label: {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundColor(.success)
                    Text("Done").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                }
                .frame(width: 56, height: 56).background(.ultraThinMaterial).clipShape(Circle())
            }
        }
    }

    private func analyze() async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.12)) { captureFlash = true }
        let image = await camera.capture()
        withAnimation(.easeIn(duration: 0.25)) { captureFlash = false }
        // On a real device we send the captured frame; otherwise ARIA returns an on-device read.
        let fb: FormFeedback
        if let image { fb = await aria.analyzeForm(image: image, context: context) }
        else { fb = ARIACoachService.heuristicFeedback(for: context) }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { feedback = fb }
        if fb.status == .stop { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    private func toggleAuto() {
        autoCoach.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if autoCoach {
            autoTask = Task {
                while !Task.isCancelled && autoCoach {
                    await analyze()
                    try? await Task.sleep(nanoseconds: 7_000_000_000)
                }
            }
        } else {
            autoTask?.cancel(); autoTask = nil
        }
    }
}

// MARK: - Corner Radius Helper

private extension View {
    func roundedCorners(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(WorkoutRoundedCorner(radius: radius, corners: corners))
    }
}

private struct WorkoutRoundedCorner: Shape {
    let radius: CGFloat; let corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

// MARK: - Comparable clamp

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}



















