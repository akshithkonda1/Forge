import Foundation
import SwiftUI

/// Running personalization from period-end feedbacks (what to do next cycle).
struct PeriodCoachingPreferences: Codable, Equatable {
    /// 0…1 extra recovery bias during menstruation.
    var recoveryBias: Double
    var preferLighterTraining: Bool
    var preferHeatComfort: Bool
    var preferEmpathyTone: Bool
    var preferHydrationSleep: Bool
    var preferNutritionTips: Bool
    var preferMobility: Bool
    var avoidIntensityPush: Bool
    /// Prefer sleep-focused tips when periods tend to disrupt sleep.
    var preferSleepFocus: Bool
    /// Prefer mood-aware / softer check-ins.
    var preferMoodSupport: Bool
    var sampleCount: Int
    var averageSeverity: Double
    var averageHelpfulness: Double
    var averageLifeImpact: Double
    var averageStress: Double
    var lastLearnedSummary: String?

    static let neutral = PeriodCoachingPreferences(
        recoveryBias: 0.35,
        preferLighterTraining: true,
        preferHeatComfort: false,
        preferEmpathyTone: true,
        preferHydrationSleep: true,
        preferNutritionTips: true,
        preferMobility: false,
        avoidIntensityPush: true,
        preferSleepFocus: false,
        preferMoodSupport: false,
        sampleCount: 0,
        averageSeverity: 0.5,
        averageHelpfulness: 0.5,
        averageLifeImpact: 0.35,
        averageStress: 0.4,
        lastLearnedSummary: nil
    )

    enum CodingKeys: String, CodingKey {
        case recoveryBias, preferLighterTraining, preferHeatComfort, preferEmpathyTone
        case preferHydrationSleep, preferNutritionTips, preferMobility, avoidIntensityPush
        case preferSleepFocus, preferMoodSupport
        case sampleCount, averageSeverity, averageHelpfulness, averageLifeImpact, averageStress
        case lastLearnedSummary
    }

    init(
        recoveryBias: Double,
        preferLighterTraining: Bool,
        preferHeatComfort: Bool,
        preferEmpathyTone: Bool,
        preferHydrationSleep: Bool,
        preferNutritionTips: Bool,
        preferMobility: Bool,
        avoidIntensityPush: Bool,
        preferSleepFocus: Bool = false,
        preferMoodSupport: Bool = false,
        sampleCount: Int,
        averageSeverity: Double,
        averageHelpfulness: Double,
        averageLifeImpact: Double = 0.35,
        averageStress: Double = 0.4,
        lastLearnedSummary: String?
    ) {
        self.recoveryBias = recoveryBias
        self.preferLighterTraining = preferLighterTraining
        self.preferHeatComfort = preferHeatComfort
        self.preferEmpathyTone = preferEmpathyTone
        self.preferHydrationSleep = preferHydrationSleep
        self.preferNutritionTips = preferNutritionTips
        self.preferMobility = preferMobility
        self.avoidIntensityPush = avoidIntensityPush
        self.preferSleepFocus = preferSleepFocus
        self.preferMoodSupport = preferMoodSupport
        self.sampleCount = sampleCount
        self.averageSeverity = averageSeverity
        self.averageHelpfulness = averageHelpfulness
        self.averageLifeImpact = averageLifeImpact
        self.averageStress = averageStress
        self.lastLearnedSummary = lastLearnedSummary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recoveryBias = try c.decodeIfPresent(Double.self, forKey: .recoveryBias) ?? 0.35
        preferLighterTraining = try c.decodeIfPresent(Bool.self, forKey: .preferLighterTraining) ?? true
        preferHeatComfort = try c.decodeIfPresent(Bool.self, forKey: .preferHeatComfort) ?? false
        preferEmpathyTone = try c.decodeIfPresent(Bool.self, forKey: .preferEmpathyTone) ?? true
        preferHydrationSleep = try c.decodeIfPresent(Bool.self, forKey: .preferHydrationSleep) ?? true
        preferNutritionTips = try c.decodeIfPresent(Bool.self, forKey: .preferNutritionTips) ?? true
        preferMobility = try c.decodeIfPresent(Bool.self, forKey: .preferMobility) ?? false
        avoidIntensityPush = try c.decodeIfPresent(Bool.self, forKey: .avoidIntensityPush) ?? true
        preferSleepFocus = try c.decodeIfPresent(Bool.self, forKey: .preferSleepFocus) ?? false
        preferMoodSupport = try c.decodeIfPresent(Bool.self, forKey: .preferMoodSupport) ?? false
        sampleCount = try c.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
        averageSeverity = try c.decodeIfPresent(Double.self, forKey: .averageSeverity) ?? 0.5
        averageHelpfulness = try c.decodeIfPresent(Double.self, forKey: .averageHelpfulness) ?? 0.5
        averageLifeImpact = try c.decodeIfPresent(Double.self, forKey: .averageLifeImpact) ?? 0.35
        averageStress = try c.decodeIfPresent(Double.self, forKey: .averageStress) ?? 0.4
        lastLearnedSummary = try c.decodeIfPresent(String.self, forKey: .lastLearnedSummary)
    }

    mutating func learn(from feedback: PeriodEndFeedback) {
        sampleCount += 1
        let alpha = min(0.45, 1.0 / Double(max(2, sampleCount)))

        let severityScore: Double = {
            switch feedback.severity {
            case .mild: return 0.2
            case .moderate: return 0.55
            case .severe: return 0.9
            }
        }()
        averageSeverity = averageSeverity * (1 - alpha) + severityScore * alpha
        averageHelpfulness = averageHelpfulness * (1 - alpha) + feedback.coachingHelpfulness.score * alpha

        let impactScore: Double = {
            switch feedback.lifeImpact {
            case .low?: return 0.15
            case .medium?: return 0.5
            case .high?: return 0.9
            case nil: return averageLifeImpact
            }
        }()
        averageLifeImpact = averageLifeImpact * (1 - alpha) + impactScore * alpha

        let stressScore: Double = {
            switch feedback.stressLevel {
            case .low?: return 0.2
            case .medium?: return 0.5
            case .high?: return 0.85
            case nil: return averageStress
            }
        }()
        averageStress = averageStress * (1 - alpha) + stressScore * alpha

        let painBoost = Double(min(10, max(0, feedback.peakPain))) / 10.0
        let energyLow = feedback.energy == .low ? 0.25 : 0
        let sleepRough = feedback.sleepQuality == .poor ? 0.15 : 0
        let moodRough = feedback.moodOverall == .rough ? 0.1 : 0
        recoveryBias = min(1, max(0.1, recoveryBias * (1 - alpha) + (severityScore * 0.45 + painBoost * 0.25 + energyLow + sleepRough + moodRough + impactScore * 0.15) * alpha))

        if feedback.sleepQuality == .poor {
            preferSleepFocus = true
            preferHydrationSleep = true
        }
        if feedback.moodOverall == .rough || feedback.stressLevel == .high {
            preferMoodSupport = true
            preferEmpathyTone = true
        }
        if feedback.lifeImpact == .high {
            avoidIntensityPush = true
            preferLighterTraining = true
        }
        if feedback.flowFeel == .heavier {
            preferNutritionTips = true
            recoveryBias = min(1, recoveryBias + 0.05)
        }

        func boost(_ topic: PeriodCoachingTopic, helped: Bool, wantMore: Bool, wantLess: Bool) {
            let positive = (helped ? 1 : 0) + (wantMore ? 1 : 0) - (wantLess ? 1 : 0)
            guard positive != 0 else { return }
            switch topic {
            case .rest:
                if positive > 0 { recoveryBias = min(1, recoveryBias + 0.08) }
            case .lighterTraining:
                preferLighterTraining = positive > 0 || preferLighterTraining
                if positive < 0 { preferLighterTraining = false }
            case .heat:
                preferHeatComfort = positive > 0
            case .hydration, .sleep:
                preferHydrationSleep = positive >= 0 ? (positive > 0 || preferHydrationSleep) : false
                if topic == .sleep, positive > 0 { preferSleepFocus = true }
            case .nutrition:
                preferNutritionTips = positive >= 0 ? (positive > 0 || preferNutritionTips) : false
            case .empathy:
                preferEmpathyTone = positive >= 0 ? (positive > 0 || preferEmpathyTone) : false
                if positive > 0 { preferMoodSupport = true }
            case .mobility:
                preferMobility = positive > 0
            }
        }

        for t in PeriodCoachingTopic.allCases {
            boost(
                t,
                helped: feedback.whatHelped.contains(t),
                wantMore: feedback.wantMore.contains(t),
                wantLess: feedback.wantLess.contains(t)
            )
        }

        if feedback.severity == .severe || feedback.peakPain >= 7 || feedback.energy == .low {
            avoidIntensityPush = true
            preferLighterTraining = true
            recoveryBias = min(1, recoveryBias + 0.1)
        }
        if feedback.coachingHelpfulness == .notHelpful {
            preferEmpathyTone = true
            preferLighterTraining = true
            recoveryBias = min(1, recoveryBias + 0.12)
        }

        var bits: [String] = []
        if preferLighterTraining { bits.append("lighter training") }
        if preferHeatComfort { bits.append("heat/comfort") }
        if preferSleepFocus || preferHydrationSleep { bits.append("sleep & hydration") }
        if preferNutritionTips { bits.append("nutrition") }
        if preferMobility { bits.append("mobility") }
        if preferEmpathyTone || preferMoodSupport { bits.append("softer tone") }
        if avoidIntensityPush { bits.append("no intensity push") }
        if averageLifeImpact >= 0.6 { bits.append("more recovery buffer") }
        lastLearnedSummary = bits.isEmpty
            ? "Logged episode · adapting coaching"
            : "Next period: lean on " + bits.prefix(4).joined(separator: ", ")
    }

    var ariaTags: [String] {
        var tags = ["cycle:period_feedback_n:\(sampleCount)"]
        tags.append("cycle:recovery_pref:\(Int(recoveryBias * 100))")
        if preferLighterTraining { tags.append("cycle:prefer:lighter_training") }
        if preferHeatComfort { tags.append("cycle:prefer:heat") }
        if preferEmpathyTone { tags.append("cycle:prefer:empathy") }
        if preferHydrationSleep { tags.append("cycle:prefer:hydration_sleep") }
        if preferNutritionTips { tags.append("cycle:prefer:nutrition") }
        if preferMobility { tags.append("cycle:prefer:mobility") }
        if avoidIntensityPush { tags.append("cycle:prefer:avoid_intensity") }
        if preferSleepFocus { tags.append("cycle:prefer:sleep_focus") }
        if preferMoodSupport { tags.append("cycle:prefer:mood_support") }
        if averageLifeImpact >= 0.55 { tags.append("cycle:life_impact:high") }
        if averageStress >= 0.6 { tags.append("cycle:stress:elevated") }
        return tags
    }

    var coachingDirective: String {
        guard sampleCount > 0 else { return "" }
        var parts: [String] = [
            "User has given \(sampleCount) period-end feedback(s). Adapt menstruation coaching to their learned preferences. This data is for personal coaching only — never for ads, sale, or third-party profiling."
        ]
        if recoveryBias >= 0.6 || avoidIntensityPush {
            parts.append("Strongly favor recovery, auto-regulation, and optional sessions — do not push intensity on period days.")
        }
        if preferLighterTraining {
            parts.append("They respond well to lighter training suggestions (walk, technique, mobility).")
        }
        if preferHeatComfort {
            parts.append("Mention heat packs / comfort strategies when relevant.")
        }
        if preferHydrationSleep || preferSleepFocus {
            parts.append("Prioritize sleep quality and hydration tips.")
        }
        if preferSleepFocus {
            parts.append("Periods often disrupt their sleep — offer wind-down and sleep hygiene cues early in menstruation.")
        }
        if preferNutritionTips {
            parts.append("Include iron/magnesium/anti-inflammatory food cues briefly.")
        }
        if preferMobility {
            parts.append("Offer gentle mobility or yoga as a default movement option.")
        }
        if preferEmpathyTone || preferMoodSupport {
            parts.append("Use a warm, validating tone — never minimize symptoms.")
        }
        if preferMoodSupport {
            parts.append("Mood can dip during their period — check in gently; avoid toxic positivity.")
        }
        if averageLifeImpact >= 0.55 {
            parts.append("Their period often limits daily life/training — default to optional sessions and recovery framing.")
        }
        if averageStress >= 0.55 {
            parts.append("Cycles often coincide with higher stress — keep plans simple and stress-aware.")
        }
        if averageHelpfulness < 0.4 {
            parts.append("Prior coaching was not helpful enough — be more concrete and less generic.")
        }
        if let summary = lastLearnedSummary {
            parts.append("Personal summary: \(summary).")
        }
        return parts.joined(separator: " ")
    }
}
