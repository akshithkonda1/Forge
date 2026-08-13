import Foundation
import ForgeCore

/// Personalized lifestyle targets derived from profile + optional user overrides.
struct LifestyleTargets: Equatable {
    let proteinGrams: Int
    let calorieTarget: Int
    let stepTarget: Int
    let sleepHoursTarget: Double
    let waterGlassesTarget: Int
    let activeCalorieTarget: Int

    static func resolve(profile: UserProfile, overrides: NutritionPreferences? = nil) -> LifestyleTargets {
        let weightKg = profile.weight ?? 75
        let computed = computedDefaults(profile: profile, weightKg: weightKg)

        return LifestyleTargets(
            proteinGrams: overrides?.proteinGrams ?? computed.proteinGrams,
            calorieTarget: overrides?.calorieTarget ?? computed.calorieTarget,
            stepTarget: overrides?.stepTarget ?? computed.stepTarget,
            sleepHoursTarget: overrides?.sleepHoursTarget ?? computed.sleepHoursTarget,
            waterGlassesTarget: overrides?.waterGlassesTarget ?? computed.waterGlassesTarget,
            activeCalorieTarget: overrides?.activeCalorieTarget ?? computed.activeCalorieTarget
        )
    }

    private static func computedDefaults(profile: UserProfile, weightKg: Double) -> LifestyleTargets {
        let bmr = mifflinStJeorBMR(weightKg: weightKg, age: profile.age ?? 30, gender: profile.gender)
        let activityMultiplier: Double = switch profile.experienceLevel {
        case .beginner: 1.45
        case .intermediate: 1.55
        case .advanced, .elite: 1.65
        }
        let goalFactor: Double = {
            if profile.fitnessGoals.contains(.loseFat) { return 0.88 }
            if profile.fitnessGoals.contains(.buildMuscle) || profile.fitnessGoals.contains(.athleticPerformance) { return 1.08 }
            return 1.0
        }()
        let calories = Int((bmr * activityMultiplier * goalFactor).rounded())

        let proteinPerKg: Double = {
            if profile.fitnessGoals.contains(.buildMuscle) || profile.fitnessGoals.contains(.athleticPerformance) { return 1.0 }
            if profile.fitnessGoals.contains(.loseFat) { return 0.95 }
            return 0.8
        }()
        let protein = Int((weightKg * proteinPerKg).rounded())

        let steps: Int = switch profile.experienceLevel {
        case .beginner: 8_000
        case .intermediate: 10_000
        case .advanced, .elite: 12_000
        }

        return LifestyleTargets(
            proteinGrams: max(protein, 100),
            calorieTarget: max(calories, 1_800),
            stepTarget: steps,
            sleepHoursTarget: 8.0,
            waterGlassesTarget: max(4, Int(HydrationEngine.glasses(
                fromMilliliters: HydrationEngine.targetMilliliters(weightKilograms: weightKg)
            ).rounded())),
            activeCalorieTarget: 600
        )
    }

    private static func mifflinStJeorBMR(weightKg: Double, age: Int, gender: Gender) -> Double {
        let base = 10 * weightKg + 6.25 * 175 - 5 * Double(age)
        switch gender {
        case .male: return base + 5
        case .female: return base - 161
        default: return base - 78
        }
    }
}

struct NutritionPreferences: Codable, Equatable {
    var proteinGrams: Int?
    var calorieTarget: Int?
    var stepTarget: Int?
    var sleepHoursTarget: Double?
    var waterGlassesTarget: Int?
    var activeCalorieTarget: Int?
}