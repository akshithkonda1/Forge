import Foundation
import SwiftUI

enum CycleQualityGrade: String, Codable, CaseIterable {
    case sparse, noisy, mixed, solid, highSignal

    var label: String {
        switch self {
        case .sparse: return "Sparse"
        case .noisy: return "Noisy"
        case .mixed: return "Mixed"
        case .solid: return "Solid"
        case .highSignal: return "High signal"
        }
    }

    var accentHex: String {
        switch self {
        case .sparse: return "6B7280"
        case .noisy: return "F59E0B"
        case .mixed: return "38BDF8"
        case .solid: return "22C55E"
        case .highSignal: return "A855F7"
        }
    }
}

enum CycleEvalIssue: String, Codable, CaseIterable, Identifiable {
    case sparseCycles
    case highVariability
    case signalConflictLhBbt
    case spottingAmbiguous
    case missingBbtInWindow
    case missingOpkInWindow
    case hormonalSimplified
    case overdueWindow
    case lowFeedback
    case partnerSparse

    var id: String { rawValue }

    var lifestyleCopy: String {
        switch self {
        case .sparseCycles:
            return "Only a few cycles logged — estimates stay wide until history grows."
        case .highVariability:
            return "Cycle lengths jump around — we keep a wider window on purpose."
        case .signalConflictLhBbt:
            return "Mid-cycle signals don’t fully agree — hierarchy applies, confidence stays humble."
        case .spottingAmbiguous:
            return "Spotting alone may not mark a full period start — confirm if flow increased."
        case .missingBbtInWindow:
            return "High-accuracy mode is on but BBT is thin near the fertile window."
        case .missingOpkInWindow:
            return "Optional OPK logging near fertile days can sharpen mid-cycle labels."
        case .hormonalSimplified:
            return "Hormonal contraception noted — phase labels are simplified for coaching."
        case .overdueWindow:
            return "Past the usual window — range widened and confidence tempered."
        case .lowFeedback:
            return "Few confirmed starts vs forecasts — confirm starts to teach the model."
        case .partnerSparse:
            return "Support logs are light — coaching stays general until more starts are shared."
        }
    }
}

struct CycleDataEvaluation: Codable, Equatable {
    var qualityGrade: CycleQualityGrade
    var issues: [CycleEvalIssue]
    var trustForPrediction: String // low | medium | high
    var userFacingSummary: String
    var recommendedActions: [String]
    var understoodSummary: String
    var teachingSummary: String

    static let empty = CycleDataEvaluation(
        qualityGrade: .sparse,
        issues: [],
        trustForPrediction: "low",
        userFacingSummary: "Not enough cycle signal yet for a sharp lifestyle estimate.",
        recommendedActions: ["log_period_start"],
        understoodSummary: "No active cycle data.",
        teachingSummary: "Log period starts so Forge can learn your personal timing."
    )
}

/// Redacted context for ARIA — numbers from engine only.
struct CycleAIContext: Codable, Equatable {
    var phase: String
    /// Lifecycle stage — distinguishes "on her period" from "period just finished",
    /// which phase alone cannot express.
    var stage: String = CycleStage.unknown.rawValue
    var periodEndConfirmed: Bool = false
    var daysSincePeriodEnd: Int?
    var daysUntilNextPeriod: Int?
    var dayInCycle: Int?
    var cycleLengthMedian: Double
    var cycleLengthMAD: Double
    var nextMedian: String?
    var nextEarliest: String?
    var nextLatest: String?
    var ovulationMethod: String?
    var confidence: Double
    var periodTimingConfidence: Double
    var ovulationConfidence: Double
    var accuracyMAE: Double?
    var accuracySampleCount: Int
    var qualityGrade: String
    var issues: [String]
    var highAccuracyMode: Bool
    var hormonal: Bool
    var irregular: Bool
    var lastUserAction: String?
    var isPartner: Bool
}

/// One actual period start vs the prediction that was live before it.
struct CyclePredictionFeedback: Codable, Equatable, Identifiable {
    var id: String { actualStartDayKey + "|" + predictedMedianDayKey }
    var predictedMedianDayKey: String
    var actualStartDayKey: String
    /// Signed error: actual − predicted (days). Negative = period came early.
    var errorDays: Int
    var recordedAt: Date
}

struct CycleAccuracyReport: Codable, Equatable {
    var sampleCount: Int
    var maeDays: Double?
    var medianAbsErrorDays: Double?
    var withinOneDayRate: Double?
    var withinTwoDayRate: Double?
    /// EMA of signed errors applied as offset on next predictions.
    var calibrationOffsetDays: Double
    /// learning | solid | excellent | market_leading
    var gradeLabel: String
    var gradeDetail: String

    static let empty = CycleAccuracyReport(
        sampleCount: 0,
        maeDays: nil,
        medianAbsErrorDays: nil,
        withinOneDayRate: nil,
        withinTwoDayRate: nil,
        calibrationOffsetDays: 0,
        gradeLabel: "learning",
        gradeDetail: "Log a few period starts so we can measure prediction error."
    )

    static func compute(from feedback: [CyclePredictionFeedback], calibrationOffset: Double) -> CycleAccuracyReport {
        guard !feedback.isEmpty else {
            return .empty
        }
        let absErrors = feedback.map { abs($0.errorDays) }
        let mae = Double(absErrors.reduce(0, +)) / Double(absErrors.count)
        let sorted = absErrors.sorted()
        let med: Double = {
            let m = sorted.count / 2
            if sorted.count % 2 == 0 {
                return Double(sorted[m - 1] + sorted[m]) / 2
            }
            return Double(sorted[m])
        }()
        let w1 = Double(absErrors.filter { $0 <= 1 }.count) / Double(absErrors.count)
        let w2 = Double(absErrors.filter { $0 <= 2 }.count) / Double(absErrors.count)

        let grade: (String, String)
        if feedback.count >= 6, mae <= 1.2, w1 >= 0.7 {
            grade = ("market_leading", "Among the most accurate consumer cycle predictors — multi-signal + feedback-corrected.")
        } else if feedback.count >= 4, mae <= 1.8, w2 >= 0.75 {
            grade = ("excellent", "Excellent personal accuracy with feedback auto-correction active.")
        } else if feedback.count >= 2, mae <= 2.5 {
            grade = ("solid", "Solid personalization — keep logging starts to tighten the window.")
        } else {
            grade = ("learning", "Still learning your rhythm. Accuracy improves after 2–3 confirmed starts.")
        }

        return CycleAccuracyReport(
            sampleCount: feedback.count,
            maeDays: mae,
            medianAbsErrorDays: med,
            withinOneDayRate: w1,
            withinTwoDayRate: w2,
            calibrationOffsetDays: calibrationOffset,
            gradeLabel: grade.0,
            gradeDetail: grade.1
        )
    }
}
