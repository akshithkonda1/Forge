import SwiftUI

/// Major muscle groups used for volume balance + targeting.
enum TargetMuscle: String, CaseIterable, Identifiable, Hashable {
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
    enum Region: String, CaseIterable {
        case push, pull, legs, core, conditioning
        var label: String {
            switch self {
            case .push: return "Push"
            case .pull: return "Pull"
            case .legs: return "Legs"
            case .core: return "Core"
            case .conditioning: return "Conditioning"
            }
        }
    }
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

    /// Spoken aliases so “hit my calves” / “bicep day” resolve to a catalog muscle.
    /// Longer phrases win so “hip flexor” does not collapse into “hip”.
    static func mentioned(in text: String) -> TargetMuscle? {
        let lower = text.lowercased()
        let aliases: [(String, TargetMuscle)] = [
            ("hip flexor", .hipFlexors),
            ("upper back", .upperBack),
            ("lower back", .lowerBack),
            ("rear delt", .rearDelts),
            ("front delt", .frontDelts),
            ("side delt", .sideDelts),
            ("full body", .fullBody),
            ("abductor", .abductors),
            ("adductor", .adductors),
            ("hamstring", .hamstrings),
            ("forearm", .forearms),
            ("oblique", .obliques),
            ("shoulder", .sideDelts),
            ("glute", .glutes),
            ("bicep", .biceps),
            ("tricep", .triceps),
            ("calves", .calves),
            ("calf", .calves),
            ("quad", .quads),
            ("chest", .chest),
            ("pec", .chest),
            ("lats", .lats),
            ("lat ", .lats),
            ("trap", .traps),
            ("core", .abs),
            ("abs", .abs),
            ("ab ", .abs),
            ("cardio", .cardio),
        ]
        return aliases.first(where: { lower.contains($0.0) })?.1
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

enum GearType: String, CaseIterable, Identifiable, Hashable {
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

/// A kinesiology-rich library entry. Distinct from `Exercise` (the lightweight plan row).
struct ExerciseDefinition: Identifiable, Hashable {
    let id: String                  // stable slug
    let name: String
    let primary: [TargetMuscle]
    let secondary: [TargetMuscle]
    let pattern: MovementPattern
    let equipment: GearType
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
    var region: TargetMuscle.Region { primary.first?.region ?? .conditioning }
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
        _ name: String, _ pattern: MovementPattern, _ equipment: GearType,
        primary: [TargetMuscle], secondary: [TargetMuscle] = [],
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
        .make("Rowing Erg", .gait, .cardioMachine, primary: [.fullBody], secondary: [.cardio, .upperBack], force: .pull, modality: .conditioning,
              level: .beginner, sets: 1, repLow: 250, repHigh: 1000, rest: 60, met: 8.5, cues: ["Legs → hips → arms, reverse on the return", "Drive with the legs"], subs: ["Assault Bike"], note: "Low-impact full-body cardio. Reps = meters."),
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

    static func filter(query: String, muscle: TargetMuscle?, equipment: GearType?, pattern: MovementPattern?) -> [ExerciseDefinition] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { def in
            (q.isEmpty || def.name.lowercased().contains(q) || def.muscleSummary.lowercased().contains(q))
            && (muscle == nil || def.primary.contains(muscle!) || def.secondary.contains(muscle!))
            && (equipment == nil || def.equipment == equipment!)
            && (pattern == nil || def.pattern == pattern!)
        }
    }

    static func count(matching muscle: TargetMuscle) -> Int {
        all.filter { $0.primary.contains(muscle) || $0.secondary.contains(muscle) }.count
    }

    enum OrganizeBy: String, CaseIterable, Identifiable {
        case region, muscle, pattern, equipment
        var id: String { rawValue }
        var label: String {
            switch self {
            case .region: return "Region"
            case .muscle: return "Muscle"
            case .pattern: return "Pattern"
            case .equipment: return "Gear"
            }
        }
    }

    struct Section: Identifiable {
        let id: String
        let title: String
        let accent: Color
        let items: [ExerciseDefinition]
    }

    static func grouped(
        query: String,
        muscle: TargetMuscle?,
        equipment: GearType?,
        pattern: MovementPattern?,
        by organize: OrganizeBy
    ) -> [Section] {
        let rows = filter(query: query, muscle: muscle, equipment: equipment, pattern: pattern)
        func sorted(_ items: [ExerciseDefinition]) -> [ExerciseDefinition] {
            items.sorted {
                if $0.isCompound != $1.isCompound { return $0.isCompound && !$1.isCompound }
                return $0.name < $1.name
            }
        }
        switch organize {
        case .region:
            return TargetMuscle.Region.allCases.compactMap { region in
                let items = sorted(rows.filter { $0.region == region })
                guard !items.isEmpty else { return nil }
                return Section(id: region.rawValue, title: region.label, accent: items[0].accent, items: items)
            }
        case .muscle:
            return TargetMuscle.allCases.compactMap { m in
                let items = sorted(rows.filter { $0.primary.contains(m) })
                guard !items.isEmpty else { return nil }
                return Section(id: m.rawValue, title: m.label, accent: m.accent, items: items)
            }
        case .pattern:
            return MovementPattern.allCases.compactMap { p in
                let items = sorted(rows.filter { $0.pattern == p })
                guard !items.isEmpty else { return nil }
                return Section(id: p.rawValue, title: p.label, accent: items[0].accent, items: items)
            }
        case .equipment:
            return GearType.allCases.compactMap { g in
                let items = sorted(rows.filter { $0.equipment == g })
                guard !items.isEmpty else { return nil }
                return Section(id: g.rawValue, title: g.label, accent: items[0].accent, items: items)
            }
        }
    }

    /// Spoken walkthrough ARIA uses for Show me how.
    static func howToScript(for def: ExerciseDefinition) -> String {
        var parts: [String] = ["Here's how to do \(def.name)."]
        parts.append("It's a \(def.pattern.label.lowercased()) on \(def.equipment.label.lowercased()). Primary: \(def.primary.map(\.label).joined(separator: ", ")).")
        if !def.cues.isEmpty {
            let numbered = def.cues.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ")
            parts.append("Cues: \(numbered)")
        }
        if !def.faults.isEmpty {
            parts.append("Watch for: \(def.faults.joined(separator: ". ")).")
        }
        if let regress = def.regressions.first {
            parts.append("If it feels off, switch to \(regress).")
        }
        return parts.joined(separator: " ")
    }
}

/// Tappable regions on the Train library body map. Coordinates are
/// normalized (0…1) inside the figure canvas — left/right copies of the
/// same muscle share one `TargetMuscle` so a bicep tap is just biceps.
struct BodyMapHotspot: Identifiable, Equatable {
    let id: String
    let muscle: TargetMuscle
    let face: BodyMapFace
    /// Center X in unit space of the figure.
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat

    enum BodyMapFace: String, CaseIterable, Hashable {
        case front, back
        var label: String { rawValue.capitalized }
    }

    static func spots(on face: BodyMapFace) -> [BodyMapHotspot] {
        all.filter { $0.face == face }
    }

    static let extraChips: [TargetMuscle] = [.fullBody, .cardio]

    private static func pair(
        _ muscle: TargetMuscle,
        face: BodyMapFace,
        lx: CGFloat, rx: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    ) -> [BodyMapHotspot] {
        [
            BodyMapHotspot(id: "\(muscle.rawValue)-L-\(face.rawValue)", muscle: muscle, face: face, x: lx, y: y, w: w, h: h),
            BodyMapHotspot(id: "\(muscle.rawValue)-R-\(face.rawValue)", muscle: muscle, face: face, x: rx, y: y, w: w, h: h),
        ]
    }

    static let all: [BodyMapHotspot] = {
        var spots: [BodyMapHotspot] = []
        // Front — torso
        spots.append(BodyMapHotspot(id: "chest-front", muscle: .chest, face: .front, x: 0.50, y: 0.26, w: 0.30, h: 0.11))
        spots.append(BodyMapHotspot(id: "abs-front", muscle: .abs, face: .front, x: 0.50, y: 0.38, w: 0.20, h: 0.11))
        spots.append(contentsOf: pair(.obliques, face: .front, lx: 0.32, rx: 0.68, y: 0.38, w: 0.10, h: 0.12))
        spots.append(contentsOf: pair(.frontDelts, face: .front, lx: 0.30, rx: 0.70, y: 0.20, w: 0.13, h: 0.07))
        spots.append(contentsOf: pair(.sideDelts, face: .front, lx: 0.20, rx: 0.80, y: 0.22, w: 0.10, h: 0.07))
        spots.append(contentsOf: pair(.biceps, face: .front, lx: 0.18, rx: 0.82, y: 0.31, w: 0.11, h: 0.09))
        spots.append(contentsOf: pair(.forearms, face: .front, lx: 0.12, rx: 0.88, y: 0.42, w: 0.11, h: 0.09))
        spots.append(BodyMapHotspot(id: "hipflex-front", muscle: .hipFlexors, face: .front, x: 0.50, y: 0.48, w: 0.26, h: 0.06))
        spots.append(contentsOf: pair(.adductors, face: .front, lx: 0.42, rx: 0.58, y: 0.56, w: 0.10, h: 0.10))
        spots.append(contentsOf: pair(.quads, face: .front, lx: 0.38, rx: 0.62, y: 0.62, w: 0.14, h: 0.16))
        spots.append(contentsOf: pair(.calves, face: .front, lx: 0.38, rx: 0.62, y: 0.84, w: 0.12, h: 0.12))
        // Back
        spots.append(BodyMapHotspot(id: "traps-back", muscle: .traps, face: .back, x: 0.50, y: 0.18, w: 0.28, h: 0.07))
        spots.append(BodyMapHotspot(id: "upperback-back", muscle: .upperBack, face: .back, x: 0.50, y: 0.26, w: 0.28, h: 0.08))
        spots.append(contentsOf: pair(.lats, face: .back, lx: 0.32, rx: 0.68, y: 0.32, w: 0.14, h: 0.12))
        spots.append(contentsOf: pair(.rearDelts, face: .back, lx: 0.28, rx: 0.72, y: 0.20, w: 0.12, h: 0.07))
        spots.append(contentsOf: pair(.triceps, face: .back, lx: 0.16, rx: 0.84, y: 0.32, w: 0.11, h: 0.10))
        spots.append(BodyMapHotspot(id: "lowback-back", muscle: .lowerBack, face: .back, x: 0.50, y: 0.42, w: 0.22, h: 0.08))
        spots.append(BodyMapHotspot(id: "glutes-back", muscle: .glutes, face: .back, x: 0.50, y: 0.52, w: 0.28, h: 0.09))
        spots.append(contentsOf: pair(.abductors, face: .back, lx: 0.28, rx: 0.72, y: 0.52, w: 0.10, h: 0.08))
        spots.append(contentsOf: pair(.hamstrings, face: .back, lx: 0.38, rx: 0.62, y: 0.66, w: 0.14, h: 0.14))
        spots.append(contentsOf: pair(.calves, face: .back, lx: 0.38, rx: 0.62, y: 0.84, w: 0.12, h: 0.12))
        return spots
    }()
}

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

extension TargetMuscle.Region {
    static var allRegions: [TargetMuscle.Region] { [.push, .pull, .legs, .core, .conditioning] }
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
