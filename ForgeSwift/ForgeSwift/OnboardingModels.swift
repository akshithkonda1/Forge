import SwiftUI

extension LinearGradient {
    static let ember = LinearGradient(
        colors: [Color.ember, Color.ember.opacity(0.82)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let deepEmber = LinearGradient(
        colors: [Color(hex: "1A0800"), Color(hex: "0A0A0A")],
        startPoint: .top, endPoint: .bottom
    )
}

enum OnboardingFitnessGoal: String, CaseIterable, Identifiable {
    case loseWeight, buildMuscle, improveEndurance, increaseFlexibility,
         betterSleep, reducStress, athleticPerformance, generalHealth
    var id: String { rawValue }
    var label: String {
        switch self {
        case .loseWeight:           return "Lose Weight"
        case .buildMuscle:          return "Build Muscle"
        case .improveEndurance:     return "Endurance"
        case .increaseFlexibility:  return "Flexibility"
        case .betterSleep:          return "Better Sleep"
        case .reducStress:          return "Reduce Stress"
        case .athleticPerformance:  return "Athletic Performance"
        case .generalHealth:        return "General Health"
        }
    }
    var icon: String {
        switch self {
        case .loseWeight:           return "arrow.down.circle.fill"
        case .buildMuscle:          return "dumbbell.fill"
        case .improveEndurance:     return "figure.run"
        case .increaseFlexibility:  return "figure.flexibility"
        case .betterSleep:          return "moon.zzz.fill"
        case .reducStress:          return "brain.head.profile"
        case .athleticPerformance:  return "trophy.fill"
        case .generalHealth:        return "heart.fill"
        }
    }
    var coreGoal: UserFitnessGoal {
        switch self {
        case .loseWeight:           return .loseFat
        case .buildMuscle:          return .buildMuscle
        case .improveEndurance:     return .improveEndurance
        case .athleticPerformance:  return .athleticPerformance
        default:                    return .generalFitness
        }
    }
}

enum OnboardingWorkoutType: String, CaseIterable, Identifiable {
    case weightlifting, hiit, running, cycling, yoga, swimming,
         boxing, calisthenics, crossfit, pilates, climbing, martial_arts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weightlifting:  return "Weightlifting"
        case .hiit:           return "HIIT"
        case .running:        return "Running"
        case .cycling:        return "Cycling"
        case .yoga:           return "Yoga"
        case .swimming:       return "Swimming"
        case .boxing:         return "Boxing"
        case .calisthenics:   return "Calisthenics"
        case .crossfit:       return "CrossFit"
        case .pilates:        return "Pilates"
        case .climbing:       return "Climbing"
        case .martial_arts:   return "Martial Arts"
        }
    }
    var coreType: WorkoutType {
        switch self {
        case .weightlifting, .calisthenics, .crossfit: return .strength
        case .hiit:                                    return .hiit
        case .running, .cycling, .swimming:            return .cardio
        case .yoga, .pilates:                          return .yoga
        default:                                       return .strength
        }
    }
}

enum OnboardingCoachingStyle: String, CaseIterable, Identifiable {
    case driven, balanced, supportive, scientist, elite
    var id: String { rawValue }
    var label: String {
        switch self {
        case .driven:     return "Driven"
        case .balanced:   return "Balanced"
        case .supportive: return "Supportive"
        case .scientist:  return "The Scientist"
        case .elite:      return "Elite"
        }
    }
    var description: String {
        switch self {
        case .driven:     return "Intense accountability. Clear standards."
        case .balanced:   return "Science-backed intensity with room to breathe."
        case .supportive: return "Patient coaching that celebrates every win."
        case .scientist:  return "Data-first — explain the why."
        case .elite:      return "Performance system: readiness, output, recovery."
        }
    }
    var icon: String {
        switch self {
        case .driven:     return "bolt.fill"
        case .balanced:   return "scale.3d"
        case .supportive: return "heart.fill"
        case .scientist:  return "waveform.path.ecg"
        case .elite:      return "crown.fill"
        }
    }
    var color: Color {
        switch self {
        case .driven:     return .ember
        case .balanced:   return .steel
        case .supportive: return Color(hex: "22C55E")
        case .scientist:  return Color(hex: "A855F7")
        case .elite:      return Color(hex: "F59E0B")
        }
    }
    var coreStyle: CoachingStyle {
        switch self {
        case .driven:     return .pushHard
        case .balanced:   return .balanced
        case .supportive: return .patient
        case .scientist:  return .dataDriven
        case .elite:      return .ultraElite
        }
    }
}

struct OnboardingProfile {
    var name: String = ""
    var birthday: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    var gender: Gender = .preferNotToSay
    var heightCm: Double = 170
    var weightKg: Double = 70
    var fitnessGoals: [OnboardingFitnessGoal] = []
    var experienceLevel: ExperienceLevel = .intermediate
    var preferredWorkouts: [OnboardingWorkoutType] = []
    var coachingStyle: OnboardingCoachingStyle = .balanced

    // Lifestyle
    var sleepBand: SleepRhythmBand?
    var freeTimeInterests: [LifestyleInterest] = []
    var lifeContext: LifeContextOption?
    /// How ARIA should frame plans (Solo Leveling, classic coach, etc.).
    var trainingTheme: AriaTrainingTheme = .classic

    // Coach constraints (not a clinical record)
    var reportedConditions: [ReportedCondition] = []
    var conditionsNote: String?
    var guidanceOnlyMode: Bool = false

    // Biological sex — drives cycle auto-enable and educational mode
    var biologicalSex: BiologicalSex? = nil
    var educationalCycleMode: Bool = false

    func toCoreProfile() -> UserProfile {
        UserProfile(
            name: name,
            gender: gender,
            fitnessGoals: fitnessGoals.map(\.coreGoal).reduce(into: [UserFitnessGoal]()) { acc, goal in
                if !acc.contains(goal) { acc.append(goal) }   // several onboarding goals map to .generalFitness; dedupe to avoid duplicate Identifiable IDs
            },
            experienceLevel: experienceLevel,
            preferredWorkouts: Array(Set(preferredWorkouts.map(\.coreType))),
            coachingStyle: coachingStyle.coreStyle,
            connectedDevices: [],
            weeklySchedule: [],
            trainingEquipment: .commercialGym,
            age: Calendar.current.dateComponents([.year], from: birthday, to: Date()).year,
            weight: weightKg,
            height: heightCm,
            trainingTheme: trainingTheme,
            interestTags: freeTimeInterests.map(\.tag),
            biologicalSex: biologicalSex,
            educationalCycleMode: educationalCycleMode
        )
    }

    func lifestyleTagsForContext() -> [String] {
        var tags: [String] = []
        if let sleepBand { tags.append(sleepBand.tag) }
        tags.append(contentsOf: freeTimeInterests.map(\.tag))
        if let lifeContext, let t = lifeContext.tag { tags.append(t) }
        if trainingTheme != .classic { tags.append(trainingTheme.lifestyleTag) }
        if !name.trimmingCharacters(in: .whitespaces).isEmpty {
            tags.append("name:\(name.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        tags.append(contentsOf: preferredWorkouts.prefix(4).map { "likes:\($0.rawValue)" })
        tags.append("experience:\(experienceLevel.rawValue)")
        tags.append("coach:\(coachingStyle.rawValue)")
        return Array(Set(tags)).sorted()
    }

    func constraintsForContext() -> [String] {
        var c: [String] = []
        for cond in reportedConditions {
            if let tag = cond.tag { c.append(tag) }
        }
        if guidanceOnlyMode {
            c.append("guidance_only:true")
            c.append("role:lifestyle_coach_not_doctor")
        }
        if let note = conditionsNote, !note.isEmpty {
            c.append("condition_note:\(note.prefix(80))")
        }
        return c
    }
}

extension AppStore {
    /// Shared draft filled during immersive sign-up (name + first quest).
    static var _signUpDraftProfile = OnboardingProfile()
    var tempOnboardingProfile: OnboardingProfile {
        get { Self._signUpDraftProfile }
        set { Self._signUpDraftProfile = newValue }
    }
}
