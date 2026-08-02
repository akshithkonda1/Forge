import Foundation

// MARK: - Plan result

struct AriaPlanResult {
    let theme: AriaTrainingTheme
    let readiness: Int
    let narrative: String
    let richCard: RichCardData
    let workoutPlan: WorkoutPlan
    let suggestedActions: [String]
    /// When true, caller should persist `theme` on the user profile / context tags.
    let shouldPersistTheme: Bool
}

// MARK: - Aria Plan Engine

/// Dynamic training-plan builder. Blends readiness, goals, equipment, constraints,
/// and narrative theme (e.g. Solo Leveling daily quests) into a concrete session.
enum AriaPlanEngine {

    // MARK: Public API

    static func evaluate(
        input: String,
        context: TrainerContext
    ) -> AriaPlanResult {
        let theme = AriaThemeResolver.resolve(
            input: input,
            preferred: context.userProfile.trainingTheme,
            lifestyleTags: context.lifestyleTags,
            freeTimeTags: context.userProfile.interestTags
        )
        let shouldPersist =
            AriaThemeResolver.detect(in: input) != nil
            || AriaThemeResolver.isThemePreferenceLock(input)

        // Programming readiness softens expected cycle-related dips so ARIA stays accurate.
        let readiness = context.programmingReadiness
        var band = readinessBand(readiness)
        let goals = context.userProfile.fitnessGoals
        let equipment = context.userProfile.trainingEquipment
        let experience = context.userProfile.experienceLevel
        let guidanceOnly = context.constraints.contains { $0.contains("guidance_only") }
            || context.constraints.contains { $0.hasPrefix("condition:") }

        // Cycle recovery bias can step the band down one level (never up past recover).
        if let cycle = context.cycleSnapshot,
           cycle.trackingEnabled,
           cycle.recommendRecoveryBias {
            band = stepDown(band)
        }

        var session = buildSession(
            theme: theme,
            band: band,
            goals: goals,
            equipment: equipment,
            experience: experience,
            guidanceOnly: guidanceOnly
        )

        // Annotate session title when cycle is actively shaping the plan.
        if let cycle = context.cycleSnapshot, cycle.trackingEnabled, cycle.phase != .unknown {
            session = SessionBlueprint(
                title: session.title + " · \(cycle.phase.shortLabel)",
                duration: session.duration,
                intensity: session.intensity,
                workoutType: session.workoutType,
                moves: session.moves,
                flavorLine: session.flavorLine + " " + cycle.trainingNote
            )
        }

        let narrative = buildNarrative(
            theme: theme,
            context: context,
            session: session,
            band: band,
            guidanceOnly: guidanceOnly,
            input: input
        )

        let exercises = session.moves.map { move in
            Exercise(
                id: UUID().uuidString,
                name: move.name,
                sets: move.sets,
                reps: move.reps,
                weight: nil,
                restSeconds: move.restSeconds,
                notes: move.note
            )
        }

        let plan = WorkoutPlan(
            id: "aria-\(theme.rawValue)-\(band.rawValue)-\(Int(Date().timeIntervalSince1970))",
            name: session.title,
            type: session.workoutType,
            duration: session.duration,
            intensity: session.intensity,
            exercises: exercises
        )

        let card = RichCardData(
            type: .workoutPlan,
            workoutName: session.title,
            workoutDuration: session.duration,
            workoutExercises: session.moves.map {
                RichCardExercise(name: $0.name, sets: $0.sets, reps: $0.reps)
            }
        )

        let actions = suggestedActions(theme: theme, band: band, guidanceOnly: guidanceOnly)

        return AriaPlanResult(
            theme: theme,
            readiness: readiness,
            narrative: narrative,
            richCard: card,
            workoutPlan: plan,
            suggestedActions: actions,
            shouldPersistTheme: shouldPersist && theme != .classic
        )
    }

    // MARK: Bands

    enum ReadinessBand: String {
        case peak, solid, moderate, recover
    }

    private static func readinessBand(_ score: Int) -> ReadinessBand {
        if score >= 80 { return .peak }
        if score >= 65 { return .solid }
        if score >= 50 { return .moderate }
        return .recover
    }

    private static func stepDown(_ band: ReadinessBand) -> ReadinessBand {
        switch band {
        case .peak: return .solid
        case .solid: return .moderate
        case .moderate: return .recover
        case .recover: return .recover
        }
    }

    // MARK: Session model

    private struct Move {
        let name: String
        let sets: Int
        let reps: String
        let restSeconds: Int
        let note: String?
    }

    private struct SessionBlueprint {
        let title: String
        let duration: Int
        let intensity: WorkoutIntensity
        let workoutType: WorkoutType
        let moves: [Move]
        let flavorLine: String
    }

    private static func buildSession(
        theme: AriaTrainingTheme,
        band: ReadinessBand,
        goals: [UserFitnessGoal],
        equipment: TrainingEquipment,
        experience: ExperienceLevel,
        guidanceOnly: Bool
    ) -> SessionBlueprint {
        // Guidance-only: always cap intensity and favor controlled patterns.
        let effectiveBand: ReadinessBand = guidanceOnly && (band == .peak || band == .solid)
            ? .moderate
            : band

        switch theme {
        case .soloLeveling:
            return soloLevelingSession(band: effectiveBand, goals: goals, equipment: equipment, experience: experience)
        case .demonSlayer:
            return demonSlayerSession(band: effectiveBand, equipment: equipment)
        case .onePiece:
            return onePieceSession(band: effectiveBand, equipment: equipment)
        case .martialArts:
            return martialArtsSession(band: effectiveBand, equipment: equipment)
        case .military:
            return militarySession(band: effectiveBand, equipment: equipment)
        case .superhero:
            return superheroSession(band: effectiveBand, equipment: equipment)
        case .athlete:
            return athleteSession(band: effectiveBand, goals: goals, equipment: equipment)
        case .classic:
            return classicSession(band: effectiveBand, goals: goals, equipment: equipment)
        }
    }

    // MARK: - Solo Leveling

    /// Inspired by the System's daily quests + progressive hunter rank-up:
    /// calisthenics volume, compound strength, and a "gate" finisher when ready.
    private static func soloLevelingSession(
        band: ReadinessBand,
        goals: [UserFitnessGoal],
        equipment: TrainingEquipment,
        experience: ExperienceLevel
    ) -> SessionBlueprint {
        let bodyOnly = equipment == .bodyweight || equipment == .hotelGym
        let muscleBias = goals.contains(.buildMuscle) || goals.contains(.athleticPerformance)

        switch band {
        case .peak:
            let compounds: [Move] = bodyOnly
                ? [
                    Move(name: "Hunter Push-Ups (tempo 3-1-1)", sets: 5, reps: "12-15", restSeconds: 60, note: "Quest log: chest / triceps"),
                    Move(name: "Pike Push-Ups or HS Hold", sets: 4, reps: "8-12", restSeconds: 75, note: "Shoulder press pattern"),
                    Move(name: "Bulgarian Split Squats", sets: 4, reps: "10/leg", restSeconds: 75, note: "Single-leg power"),
                    Move(name: "Inverted Rows / Table Rows", sets: 4, reps: "10-12", restSeconds: 60, note: "Pull strength"),
                    Move(name: "Hanging Knee Raises", sets: 4, reps: "12-15", restSeconds: 45, note: "Core armor"),
                    Move(name: "Gate Clear Finisher — Burpee Broad Jumps", sets: 3, reps: "8", restSeconds: 90, note: "S-Rank optional push"),
                ]
                : [
                    Move(name: "Barbell or DB Bench Press", sets: 4, reps: "5-8", restSeconds: 120, note: "Main quest — press power"),
                    Move(name: "Weighted Pull-Ups or Lat Pulldown", sets: 4, reps: "6-8", restSeconds: 120, note: "Back rank-up"),
                    Move(name: "Front Squat or Goblet Squat", sets: 4, reps: "6-8", restSeconds: 120, note: "Leg foundation"),
                    Move(name: "DB Romanian Deadlift", sets: 3, reps: "8-10", restSeconds: 90, note: "Posterior chain"),
                    Move(name: "Daily Quest Circuit — Push-Ups", sets: 1, reps: "50 total", restSeconds: 0, note: "System mandatory volume"),
                    Move(name: "Daily Quest — Sit-Ups", sets: 1, reps: "50 total", restSeconds: 0, note: "Core quest"),
                    Move(name: "Shadow Step Run / Row", sets: 1, reps: "10 min hard", restSeconds: 0, note: "Gate sprint conditioning"),
                ]
            return SessionBlueprint(
                title: "Solo Leveling — S-Rank Clear",
                duration: bodyOnly ? 45 : 55,
                intensity: .high,
                workoutType: muscleBias ? .strength : .hiit,
                moves: compounds,
                flavorLine: "Readiness is high. The System opens a high-rank gate — compounds first, then daily quest volume. No wasted reps."
            )

        case .solid:
            let moves: [Move] = bodyOnly
                ? [
                    Move(name: "Push-Up Ladder", sets: 4, reps: "10-12", restSeconds: 45, note: "Steady rank grind"),
                    Move(name: "Bodyweight Squats", sets: 4, reps: "15-20", restSeconds: 45, note: nil),
                    Move(name: "Superman Pulls / YTW", sets: 3, reps: "12", restSeconds: 40, note: "Upper-back armor"),
                    Move(name: "Walking Lunges", sets: 3, reps: "12/leg", restSeconds: 50, note: nil),
                    Move(name: "Plank", sets: 3, reps: "40 sec", restSeconds: 30, note: "Hold the line"),
                    Move(name: "Daily Quest Jog", sets: 1, reps: "12 min easy-mod", restSeconds: 0, note: "Mandatory cardio quest"),
                ]
                : [
                    Move(name: "DB Bench Press", sets: 3, reps: "8-10", restSeconds: 90, note: "Quality over ego"),
                    Move(name: "One-Arm DB Row", sets: 3, reps: "10/side", restSeconds: 75, note: nil),
                    Move(name: "Leg Press or Goblet Squat", sets: 3, reps: "10-12", restSeconds: 90, note: nil),
                    Move(name: "Face Pulls", sets: 3, reps: "15", restSeconds: 45, note: "Shoulder durability"),
                    Move(name: "Daily Quest — Push-Ups", sets: 1, reps: "40 total", restSeconds: 0, note: "System minimum"),
                    Move(name: "Daily Quest — Sit-Ups", sets: 1, reps: "40 total", restSeconds: 0, note: "System minimum"),
                    Move(name: "Easy Run or Bike", sets: 1, reps: "10 min", restSeconds: 0, note: "Zone 2 quest"),
                ]
            return SessionBlueprint(
                title: "Solo Leveling — Daily Quest (B-Rank)",
                duration: 45,
                intensity: .moderate,
                workoutType: .strength,
                moves: moves,
                flavorLine: "Solid hunter day. Clear the daily quest cleanly — volume without sloppy form. Rank climbs on consistency."
            )

        case .moderate:
            let moves: [Move] = [
                Move(name: "Incline Push-Ups or Light Press", sets: 3, reps: "12", restSeconds: 45, note: "Controlled tempo"),
                Move(name: "Band or Cable Row", sets: 3, reps: "12-15", restSeconds: 45, note: nil),
                Move(name: "Box Squat to Parallel (light)", sets: 3, reps: "12", restSeconds: 50, note: "Groove the pattern"),
                Move(name: "Dead Bugs", sets: 3, reps: "10/side", restSeconds: 30, note: "Core control"),
                Move(name: "Reduced Daily Quest — Push-Ups", sets: 1, reps: "25 total", restSeconds: 0, note: "System scaled"),
                Move(name: "Walk or Easy Bike", sets: 1, reps: "12 min", restSeconds: 0, note: "Active clear, not a wipe"),
            ]
            return SessionBlueprint(
                title: "Solo Leveling — Scaled Quest",
                duration: 35,
                intensity: .moderate,
                workoutType: .strength,
                moves: moves,
                flavorLine: "The System scales the quest when the player is not fully recovered. Show up, complete, live to rank up tomorrow."
            )

        case .recover:
            let moves: [Move] = [
                Move(name: "Breathing + Cat-Cow", sets: 2, reps: "8", restSeconds: 20, note: "Nervous system reset"),
                Move(name: "World's Greatest Stretch", sets: 2, reps: "6/side", restSeconds: 20, note: nil),
                Move(name: "Band Pull-Aparts", sets: 3, reps: "15", restSeconds: 30, note: "Blood flow"),
                Move(name: "Glute Bridges", sets: 2, reps: "12", restSeconds: 30, note: nil),
                Move(name: "Easy Shadow Walk", sets: 1, reps: "15-20 min", restSeconds: 0, note: "Mandatory light movement only"),
            ]
            return SessionBlueprint(
                title: "Solo Leveling — Safe Zone Recovery",
                duration: 25,
                intensity: .low,
                workoutType: .mobility,
                moves: moves,
                flavorLine: "Entering a gate under-recovered is how hunters die. Safe zone today — mobility, breath, light walk. Return stronger."
            )
        }
    }

    // MARK: - Demon Slayer

    private static func demonSlayerSession(band: ReadinessBand, equipment: TrainingEquipment) -> SessionBlueprint {
        switch band {
        case .peak, .solid:
            return SessionBlueprint(
                title: band == .peak ? "Total Concentration — Full Forms" : "Breathing Forms — Corps Day",
                duration: band == .peak ? 50 : 42,
                intensity: band == .peak ? .high : .moderate,
                workoutType: .hiit,
                moves: [
                    Move(name: "Diaphragmatic Breathing Ladder", sets: 3, reps: "8 breaths", restSeconds: 20, note: "Total concentration prep"),
                    Move(name: "Jump Rope or High Knees", sets: 4, reps: "45 sec", restSeconds: 30, note: "Footwork cadence"),
                    Move(name: equipment == .bodyweight ? "Push-Up Waves" : "DB Thrusters", sets: 4, reps: "10", restSeconds: 45, note: "Explosive form"),
                    Move(name: "Reverse Lunges + Reach", sets: 3, reps: "10/leg", restSeconds: 40, note: "Hip mobility under load"),
                    Move(name: "Hollow Body Hold", sets: 3, reps: "30 sec", restSeconds: 30, note: "Core steel"),
                    Move(name: "Farmer Carry or Suitcase Carry", sets: 3, reps: "40m", restSeconds: 45, note: "Grip + posture"),
                    Move(name: "Cool-down Flow Stretch", sets: 1, reps: "5 min", restSeconds: 0, note: nil),
                ],
                flavorLine: "Breath first. Form second. Power third. Train like the Corps — controlled intensity, never sloppy swings."
            )
        case .moderate, .recover:
            return SessionBlueprint(
                title: "Breath Recovery — Soft Forms",
                duration: 28,
                intensity: .low,
                workoutType: .mobility,
                moves: [
                    Move(name: "Box Breathing 4-4-4-4", sets: 4, reps: "1 min", restSeconds: 0, note: "Settle the nervous system"),
                    Move(name: "Hip Openers + Thoracic Rotations", sets: 2, reps: "8/side", restSeconds: 15, note: nil),
                    Move(name: "Slow Bodyweight Squats", sets: 2, reps: "12", restSeconds: 30, note: "Quality only"),
                    Move(name: "Wall Angels", sets: 2, reps: "12", restSeconds: 20, note: nil),
                    Move(name: "Easy Walk", sets: 1, reps: "10 min", restSeconds: 0, note: nil),
                ],
                flavorLine: "Even Hashira rest. Breath work and soft forms today — protect the blade for the next fight."
            )
        }
    }

    // MARK: - One Piece

    private static func onePieceSession(band: ReadinessBand, equipment: TrainingEquipment) -> SessionBlueprint {
        switch band {
        case .peak, .solid:
            return SessionBlueprint(
                title: band == .peak ? "Grand Line Strength" : "Crew Training Block",
                duration: 48,
                intensity: band == .peak ? .high : .moderate,
                workoutType: .strength,
                moves: [
                    Move(name: equipment == .bodyweight ? "Plyo Push-Ups" : "Overhead Press", sets: 4, reps: "6-8", restSeconds: 90, note: "Power for the open sea"),
                    Move(name: equipment == .bodyweight ? "Pull-Up Negatives" : "Barbell or Trap-Bar Deadlift", sets: 4, reps: "5-6", restSeconds: 120, note: "Zoro-grade posterior chain"),
                    Move(name: "Walking Lunges", sets: 3, reps: "12/leg", restSeconds: 60, note: nil),
                    Move(name: "Battle Rope or Slam Alternates", sets: 3, reps: "30 sec", restSeconds: 40, note: "Haki intensity finisher"),
                    Move(name: "Hanging Leg Raises", sets: 3, reps: "10", restSeconds: 40, note: nil),
                    Move(name: "Steady Cardio (run/row)", sets: 1, reps: "8 min", restSeconds: 0, note: "Ship-deck conditioning"),
                ],
                flavorLine: "Adventure strength: lift heavy enough to matter, then earn your sea legs with conditioning."
            )
        default:
            return SessionBlueprint(
                title: "Dockside Recovery",
                duration: 25,
                intensity: .low,
                workoutType: .mobility,
                moves: [
                    Move(name: "Foam Roll + Hip Flexors", sets: 1, reps: "6 min", restSeconds: 0, note: nil),
                    Move(name: "Light Goblet Squats", sets: 2, reps: "12", restSeconds: 40, note: nil),
                    Move(name: "Band Rows", sets: 2, reps: "15", restSeconds: 30, note: nil),
                    Move(name: "Dock Walk", sets: 1, reps: "12 min", restSeconds: 0, note: nil),
                ],
                flavorLine: "Even pirates need a calm port. Light movement, then sleep like you mean it."
            )
        }
    }

    // MARK: - Martial Arts

    private static func martialArtsSession(band: ReadinessBand, equipment: TrainingEquipment) -> SessionBlueprint {
        switch band {
        case .peak, .solid:
            return SessionBlueprint(
                title: band == .peak ? "Fight Camp Intensity" : "Technical Spar Prep",
                duration: 45,
                intensity: band == .peak ? .high : .moderate,
                workoutType: .hiit,
                moves: [
                    Move(name: "Shadowbox or Jump Rope", sets: 4, reps: "2 min", restSeconds: 30, note: "Rounds"),
                    Move(name: "Sprawl + Push-Up", sets: 4, reps: "8", restSeconds: 45, note: nil),
                    Move(name: "Medicine Ball Rotational Throws or Twists", sets: 3, reps: "10/side", restSeconds: 40, note: "Rotational power"),
                    Move(name: "Reverse Lunges", sets: 3, reps: "10/leg", restSeconds: 40, note: nil),
                    Move(name: "Plank Shoulder Taps", sets: 3, reps: "20", restSeconds: 30, note: nil),
                    Move(name: "Neck-friendly Hip Escape Flow (slow)", sets: 2, reps: "6/side", restSeconds: 30, note: "Grappling mobility"),
                ],
                flavorLine: "Train like you fight: rounds, rotation, and hips that can change levels."
            )
        default:
            return SessionBlueprint(
                title: "Mobility & Film Day",
                duration: 25,
                intensity: .low,
                workoutType: .mobility,
                moves: [
                    Move(name: "90/90 Hip Switches", sets: 2, reps: "8/side", restSeconds: 15, note: nil),
                    Move(name: "Thoracic Openers", sets: 2, reps: "8/side", restSeconds: 15, note: nil),
                    Move(name: "Light Shadow Movement", sets: 2, reps: "90 sec", restSeconds: 30, note: "Technique only"),
                    Move(name: "Easy Walk", sets: 1, reps: "10 min", restSeconds: 0, note: nil),
                ],
                flavorLine: "Champions protect joints. Soft skills and recovery today."
            )
        }
    }

    // MARK: - Military

    private static func militarySession(band: ReadinessBand, equipment: TrainingEquipment) -> SessionBlueprint {
        switch band {
        case .peak, .solid:
            return SessionBlueprint(
                title: band == .peak ? "Green-Light PT" : "Standard Operator Block",
                duration: 40,
                intensity: band == .peak ? .high : .moderate,
                workoutType: .hiit,
                moves: [
                    Move(name: "Push-Ups", sets: 5, reps: "max quality 10-20", restSeconds: 45, note: "Strict form"),
                    Move(name: "Air Squats or Goblet Squats", sets: 4, reps: "15", restSeconds: 45, note: nil),
                    Move(name: "Pull-Ups or Inverted Rows", sets: 4, reps: "AMRAP clean", restSeconds: 60, note: nil),
                    Move(name: "Walking Lunges", sets: 3, reps: "20 steps", restSeconds: 40, note: nil),
                    Move(name: "Plank", sets: 3, reps: "45 sec", restSeconds: 30, note: nil),
                    Move(name: "Ruck Walk or Brisk March", sets: 1, reps: "12-15 min", restSeconds: 0, note: "Optional light pack"),
                ],
                flavorLine: "Standards over vibes. Hit the block clean, log it, stack the days."
            )
        default:
            return SessionBlueprint(
                title: "Admin Recovery",
                duration: 22,
                intensity: .low,
                workoutType: .mobility,
                moves: [
                    Move(name: "Joint Circles Flow", sets: 1, reps: "5 min", restSeconds: 0, note: nil),
                    Move(name: "Slow Push-Ups", sets: 2, reps: "8", restSeconds: 40, note: nil),
                    Move(name: "Easy March", sets: 1, reps: "12 min", restSeconds: 0, note: nil),
                ],
                flavorLine: "Admin day. Maintain the machine — don't break it."
            )
        }
    }

    // MARK: - Superhero

    private static func superheroSession(band: ReadinessBand, equipment: TrainingEquipment) -> SessionBlueprint {
        switch band {
        case .peak, .solid:
            return SessionBlueprint(
                title: band == .peak ? "Hero Mode Strength" : "Patrol Fitness",
                duration: 48,
                intensity: band == .peak ? .high : .moderate,
                workoutType: .strength,
                moves: [
                    Move(name: equipment == .bodyweight ? "Diamond Push-Ups" : "Bench or Floor Press", sets: 4, reps: "6-8", restSeconds: 100, note: nil),
                    Move(name: "Chin-Ups or Assisted", sets: 4, reps: "6-10", restSeconds: 90, note: nil),
                    Move(name: "Jump Squats or Box Jumps (soft land)", sets: 3, reps: "6", restSeconds: 75, note: "Explosive legs"),
                    Move(name: "Farmer Carries", sets: 3, reps: "40m", restSeconds: 60, note: "Grip of justice"),
                    Move(name: "Hanging Knee Raises", sets: 3, reps: "12", restSeconds: 40, note: nil),
                    Move(name: "Agility Line Hops", sets: 3, reps: "20 sec", restSeconds: 30, note: nil),
                ],
                flavorLine: "Strength, agility, presence. Train like the city needs you tonight."
            )
        default:
            return SessionBlueprint(
                title: "Cave Recovery",
                duration: 24,
                intensity: .low,
                workoutType: .mobility,
                moves: [
                    Move(name: "Mobility Circuit", sets: 2, reps: "5 moves × 8", restSeconds: 20, note: nil),
                    Move(name: "Light Band Work", sets: 2, reps: "15", restSeconds: 30, note: nil),
                    Move(name: "Night Walk", sets: 1, reps: "12 min", restSeconds: 0, note: nil),
                ],
                flavorLine: "Even heroes vanish into the cave. Recover so the next call-up counts."
            )
        }
    }

    // MARK: - Athlete

    private static func athleteSession(
        band: ReadinessBand,
        goals: [UserFitnessGoal],
        equipment: TrainingEquipment
    ) -> SessionBlueprint {
        let endurance = goals.contains(.improveEndurance)
        switch band {
        case .peak:
            return SessionBlueprint(
                title: "Performance Power Day",
                duration: 50,
                intensity: .high,
                workoutType: endurance ? .hiit : .strength,
                moves: [
                    Move(name: "A-Skips + Bounds Warm-up", sets: 2, reps: "20m each", restSeconds: 30, note: nil),
                    Move(name: equipment == .bodyweight ? "Pistol Assist Squats" : "Trap-Bar Jump or Box Squat", sets: 4, reps: "5", restSeconds: 120, note: "Power"),
                    Move(name: "Push Press or Pike Push-Ups", sets: 4, reps: "5-6", restSeconds: 100, note: nil),
                    Move(name: "Single-Leg RDL", sets: 3, reps: "8/leg", restSeconds: 75, note: nil),
                    Move(name: endurance ? "Bike Intervals" : "Med Ball Slams", sets: 6, reps: endurance ? "30s on/30s off" : "8", restSeconds: 30, note: nil),
                    Move(name: "Core Anti-Rotation", sets: 3, reps: "10/side", restSeconds: 30, note: nil),
                ],
                flavorLine: "High readiness = quality power. Speed of bar and intent over junk volume."
            )
        case .solid, .moderate:
            return SessionBlueprint(
                title: "Quality Volume Block",
                duration: 42,
                intensity: .moderate,
                workoutType: .strength,
                moves: [
                    Move(name: "Goblet Squat", sets: 3, reps: "10", restSeconds: 75, note: nil),
                    Move(name: "DB Bench or Push-Ups", sets: 3, reps: "10", restSeconds: 75, note: nil),
                    Move(name: "Chest-Supported Row", sets: 3, reps: "12", restSeconds: 60, note: nil),
                    Move(name: "Lateral Bounds", sets: 3, reps: "6/side", restSeconds: 45, note: nil),
                    Move(name: "Dead Bugs", sets: 3, reps: "10/side", restSeconds: 30, note: nil),
                ],
                flavorLine: "Solid day for technical volume. Leave a rep or two in the tank."
            )
        case .recover:
            return classicSession(band: .recover, goals: goals, equipment: equipment)
        }
    }

    // MARK: - Classic

    private static func classicSession(
        band: ReadinessBand,
        goals: [UserFitnessGoal],
        equipment: TrainingEquipment
    ) -> SessionBlueprint {
        let upperBias = goals.contains(.buildMuscle)
        switch band {
        case .peak:
            return SessionBlueprint(
                title: upperBias ? "Upper Body Power" : "Full Body Strength",
                duration: 55,
                intensity: .high,
                workoutType: .strength,
                moves: upperBias
                    ? [
                        Move(name: "Barbell Bench Press", sets: 4, reps: "6-8", restSeconds: 120, note: nil),
                        Move(name: "Weighted Pull-Ups", sets: 4, reps: "6-8", restSeconds: 120, note: nil),
                        Move(name: "Overhead Press", sets: 3, reps: "8-10", restSeconds: 90, note: nil),
                        Move(name: "Barbell Rows", sets: 3, reps: "8-10", restSeconds: 90, note: nil),
                        Move(name: "Incline DB Press", sets: 3, reps: "10-12", restSeconds: 75, note: nil),
                        Move(name: "Face Pulls", sets: 3, reps: "15-20", restSeconds: 45, note: nil),
                    ]
                    : [
                        Move(name: "Back Squat or Goblet Squat", sets: 4, reps: "6-8", restSeconds: 120, note: nil),
                        Move(name: "Bench Press", sets: 4, reps: "6-8", restSeconds: 120, note: nil),
                        Move(name: "Romanian Deadlift", sets: 3, reps: "8", restSeconds: 100, note: nil),
                        Move(name: "Pull-Ups or Lat Pulldown", sets: 3, reps: "8-10", restSeconds: 90, note: nil),
                        Move(name: "Walking Lunges", sets: 2, reps: "10/leg", restSeconds: 60, note: nil),
                    ],
                flavorLine: "Body is ready for hard work. Compounds, controlled intensity, clean execution."
            )
        case .solid:
            return SessionBlueprint(
                title: "Upper Body Volume",
                duration: 50,
                intensity: .moderate,
                workoutType: .strength,
                moves: [
                    Move(name: "Barbell Bench Press", sets: 3, reps: "8-10", restSeconds: 90, note: nil),
                    Move(name: "Lat Pulldown", sets: 3, reps: "10-12", restSeconds: 75, note: nil),
                    Move(name: "Dumbbell Press", sets: 3, reps: "10-12", restSeconds: 75, note: nil),
                    Move(name: "Cable Row", sets: 3, reps: "10-12", restSeconds: 75, note: nil),
                    Move(name: "Lateral Raises", sets: 3, reps: "12-15", restSeconds: 45, note: nil),
                    Move(name: "Tricep Pushdowns", sets: 3, reps: "12-15", restSeconds: 45, note: nil),
                ],
                flavorLine: "Good enough to train — not a PR hunt. Quality volume."
            )
        case .moderate:
            return SessionBlueprint(
                title: "Controlled Full Body",
                duration: 40,
                intensity: .moderate,
                workoutType: .strength,
                moves: [
                    Move(name: "Goblet Squats", sets: 3, reps: "12", restSeconds: 60, note: nil),
                    Move(name: "Push-Ups", sets: 3, reps: "12", restSeconds: 45, note: nil),
                    Move(name: "DB Rows", sets: 3, reps: "12", restSeconds: 45, note: nil),
                    Move(name: "Hip Hinges (light)", sets: 3, reps: "12", restSeconds: 60, note: nil),
                    Move(name: "Plank", sets: 2, reps: "40 sec", restSeconds: 30, note: nil),
                ],
                flavorLine: "Keep the signal high and the stress honest. Movement quality wins today."
            )
        case .recover:
            return SessionBlueprint(
                title: "Active Recovery",
                duration: 30,
                intensity: .low,
                workoutType: .mobility,
                moves: [
                    Move(name: "Foam Rolling", sets: 1, reps: "5 min", restSeconds: 0, note: nil),
                    Move(name: "World's Greatest Stretch", sets: 2, reps: "8 each side", restSeconds: 20, note: nil),
                    Move(name: "Band Pull-Aparts", sets: 3, reps: "15", restSeconds: 30, note: nil),
                    Move(name: "Goblet Squats (light)", sets: 2, reps: "10", restSeconds: 40, note: nil),
                    Move(name: "Dead Hangs", sets: 3, reps: "30 sec", restSeconds: 30, note: nil),
                    Move(name: "Walk or Bike (easy)", sets: 1, reps: "10 min", restSeconds: 0, note: nil),
                ],
                flavorLine: "Recovery is training. Light movement, blood flow, no ego."
            )
        }
    }

    // MARK: - Narrative (combinatorial voice)

    private static func buildNarrative(
        theme: AriaTrainingTheme,
        context: TrainerContext,
        session: SessionBlueprint,
        band: ReadinessBand,
        guidanceOnly: Bool,
        input: String
    ) -> String {
        let detected = AriaThemeResolver.detect(in: input)
        var flavor = session.flavorLine

        // Theme-band appendages stay structural; voice engine revoices delivery.
        if theme == .soloLeveling {
            switch band {
            case .peak:
                flavor += " Daily quest upgraded: compounds as main gate clears; bodyweight volume is System minimum."
            case .solid:
                flavor += " Clear the daily quest cleanly — ranks move on logged volume."
            case .moderate:
                flavor += " Scaled quest — completion over heroics."
            case .recover:
                flavor += " Safe zone. Sleep, protein, and a walk are the XP."
            }
        }

        let facts = AriaSpeechFacts(
            sessionTitle: session.title,
            sessionDuration: session.duration,
            sessionIntensity: session.intensity.label.lowercased() + " intensity",
            sessionFlavor: flavor,
            themeJustLocked: detected != nil && detected != .classic,
            themeLabel: theme.label
        )

        var speech = AriaVoiceEngine.speak(
            intent: .trainingPlan,
            context: context,
            input: input,
            facts: facts,
            themeOverride: theme
        )

        // Accurate cycle coaching line (lifestyle only) when shared with ARIA.
        if let cycle = context.cycleSnapshot, cycle.trackingEnabled, cycle.phase != .unknown {
            var cycleLine = "Cycle: \(cycle.phase.label)"
            if let day = cycle.dayInCycle { cycleLine += " · day \(day)" }
            cycleLine += " · conf \(Int(cycle.confidence * 100))%."
            cycleLine += " \(cycle.readinessNote)"
            speech += "\n\n" + cycleLine
            _ = facts
        }

        return speech
    }

    private static func suggestedActions(
        theme: AriaTrainingTheme,
        band: ReadinessBand,
        guidanceOnly: Bool
    ) -> [String] {
        var actions: [String] = ["Start this session", "Swap for easier day"]
        if theme == .soloLeveling {
            actions.append("Explain daily quest rules")
            if band == .peak { actions.append("Add S-Rank finisher") }
        } else if theme != .classic {
            actions.append("Switch to classic plan")
        } else {
            actions.append("Try Solo Leveling style")
        }
        if band == .recover || guidanceOnly {
            actions.append("Recovery checklist")
        } else {
            actions.append("Plan the rest of my week")
        }
        return actions
    }
}
