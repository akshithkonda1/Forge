import XCTest
@testable import ForgeCore

final class QualityOfLifeCalculatorTests: XCTestCase {

    // MARK: - Core behavior

    // No signal at all is the only case that yields no grade — reported honestly
    // (confidence 0) instead of the old fabricated 82.
    func testNoSignalsProducesZeroConfidenceNotAFabricatedDefault() {
        let score = QualityOfLifeCalculator.score(from: QualityOfLifeInputs())
        XCTAssertEqual(score.confidence, 0)
        XCTAssertEqual(score.overall, 0)
        XCTAssertEqual(score.gradedAspects, 0)
        XCTAssertNotEqual(score.overall, 82, "must never fall back to the old invented 82")
    }

    // A single available aspect still produces a grade — it does not refuse.
    func testSingleAspectStillGrades() {
        let score = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(steps: 8_000))
        XCTAssertEqual(score.gradedAspects, 1)
        XCTAssertEqual(score.score(for: .activity), 100)
        XCTAssertEqual(score.overall, 100)
        // One of activity's three signals: weight * (0.6 + 0.4 * 1/3).
        XCTAssertEqual(score.confidence, 0.132, accuracy: 0.001)
    }

    // Full depth across every pillar → full confidence.
    func testFullDepthAcrossAllPillarsGivesFullConfidence() {
        let inputs = QualityOfLifeInputs(
            sleepHours: 8, deepSleepMinutes: 70, remSleepMinutes: 95,
            steps: 11_000, activeCalories: 600, exerciseMinutes: 40,
            proteinGrams: 150, totalCalories: 2_400, fiberGrams: 32, addedSugarGrams: 10,
            waterGlasses: 9,
            hrvMs: 60, hrvBaselineMs: 50, restingHR: 52, restingHRBaseline: 55,
            vo2Max: 48, oxygenSaturationPercent: 98, respiratoryRate: 14,
            mindfulMinutes: 15, stressLevel0to1: 0.2, selfReportedMood0to10: 8,
            socialConnection0to10: 9, meaningfulSocialInteractions: 3,
            bodyMassKg: 75
        )
        let score = QualityOfLifeCalculator.score(from: inputs)
        XCTAssertEqual(score.confidence, 1.0, accuracy: 0.0001)
        XCTAssertEqual(score.gradedAspects, QualityOfLifePillar.allCases.count)
        XCTAssertEqual(score.band, .thriving)
    }

    // The blend is an independent, renormalized weighting — not a naive average.
    func testHolisticBlendIsWeightedAndRenormalized() {
        // activity: steps 4000 → rising(0.5)=75 (w 0.18); mind: stress 0 → 100 (w 0.12)
        let score = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(steps: 4_000, stressLevel0to1: 0))
        XCTAssertEqual(score.score(for: .activity), 75)
        XCTAssertEqual(score.score(for: .mind), 100)
        // (75*0.18 + 100*0.12) / (0.18 + 0.12) = 25.5 / 0.30 = 85
        XCTAssertEqual(score.overall, 85)
        XCTAssertEqual(score.confidence, 0.22, accuracy: 0.001)
    }

    // Missing aspects lower confidence, not the score.
    func testMissingAspectsLowerConfidenceNotScore() {
        let full = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(
            sleepHours: 8, steps: 9_000, proteinGrams: 150, totalCalories: 2_400,
            waterGlasses: 8, hrvMs: 55, hrvBaselineMs: 50, mindfulMinutes: 12,
            socialConnection0to10: 8
        ))
        let sleepOnly = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(sleepHours: 8))
        XCTAssertLessThan(sleepOnly.confidence, full.confidence)
        XCTAssertGreaterThanOrEqual(sleepOnly.score(for: .sleep) ?? 0, 95)
        XCTAssertEqual(sleepOnly.overall, sleepOnly.score(for: .sleep) ?? -1)
    }

    // MARK: - Accuracy: response curves

    // "More is better" credits the mid-range more than the top (diminishing returns).
    func testRisingCurveHasDiminishingReturns() {
        let lowGain = QualityOfLifeCalculator.rising(0.75) - QualityOfLifeCalculator.rising(0.50)
        let highGain = QualityOfLifeCalculator.rising(1.15) - QualityOfLifeCalculator.rising(0.90)
        XCTAssertGreaterThan(lowGain, highGain)
        XCTAssertEqual(QualityOfLifeCalculator.rising(1.0), 100, accuracy: 0.0001)
    }

    // Gross overshoot (a data glitch or over-training) is not scored as perfect.
    func testRisingCurvePenalizesGrossOvershoot() {
        XCTAssertLessThan(QualityOfLifeCalculator.rising(3.0), 100)
        XCTAssertGreaterThanOrEqual(QualityOfLifeCalculator.rising(3.0), 60)
    }

    // Signals with a real optimum score lower on both sides of the target.
    func testOptimumCurveIsInvertedU() {
        let peak = QualityOfLifeCalculator.optimum(1.0, sigma: 0.16)
        XCTAssertEqual(peak, 100, accuracy: 0.0001)
        XCTAssertLessThan(QualityOfLifeCalculator.optimum(0.8, sigma: 0.16), peak)
        XCTAssertLessThan(QualityOfLifeCalculator.optimum(1.2, sigma: 0.16), peak)
    }

    // Oversleeping is not rewarded like hitting the need (uses the optimum curve).
    func testOversleepScoresBelowMeetingNeed() {
        let onTarget = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(sleepHours: 8))
        let oversleep = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(sleepHours: 11))
        XCTAssertLessThan(oversleep.score(for: .sleep) ?? 100, onTarget.score(for: .sleep) ?? 0)
    }

    // MARK: - Accuracy: plausibility

    func testImplausibleValuesAreTreatedAsUnmeasured() {
        // HRV 400 ms and 500k steps are data errors, not perfect scores.
        XCTAssertNil(QualityOfLifeCalculator.score(from: QualityOfLifeInputs(steps: 500_000)).score(for: .activity))
        XCTAssertNil(QualityOfLifeCalculator.score(from: QualityOfLifeInputs(hrvMs: 400)).score(for: .vitals))
        // A whole day of only-implausible signals grades nothing rather than 100.
        let garbage = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(steps: 500_000, hrvMs: 400))
        XCTAssertEqual(garbage.gradedAspects, 0)
        XCTAssertEqual(garbage.overall, 0)
    }

    // MARK: - Accuracy: depth-aware confidence

    func testDeeperMeasurementRaisesConfidence() {
        let shallow = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(hrvMs: 55, hrvBaselineMs: 50))
        let deep = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(
            hrvMs: 55, hrvBaselineMs: 50, restingHR: 55, vo2Max: 45,
            oxygenSaturationPercent: 98, respiratoryRate: 15
        ))
        XCTAssertGreaterThan(deep.confidence, shallow.confidence)
    }

    // MARK: - Accuracy: personalization

    func testPersonalizationTunesNutritionTarget() {
        let light = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(proteinGrams: 100, bodyMassKg: 50))
        let heavy = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(proteinGrams: 100, bodyMassKg: 100))
        XCTAssertEqual(light.score(for: .nutrition), 95)   // target 80 g → rising(1.25) → 95
        XCTAssertEqual(heavy.score(for: .nutrition), 86)   // target 160 g → rising(0.625) → 86
        XCTAssertGreaterThan(light.overall, heavy.overall)
    }

    // MARK: - Accuracy: day-to-day smoothing

    func testSmoothingPullsNoisyDayTowardHistoryAndScalesWithConfidence() {
        let priorGoodDay = 80

        // A single low-confidence bad signal should barely move a good trend.
        let noisy = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(sleepHours: 4))
        let smoothedNoisy = noisy.smoothed(previousOverall: priorGoodDay)
        XCTAssertGreaterThan(smoothedNoisy.overall, noisy.rawOverall)
        XCTAssertLessThanOrEqual(smoothedNoisy.overall, priorGoodDay)

        // A high-confidence bad day should move the trend more than the noisy one.
        let richBad = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(
            sleepHours: 4, steps: 800, proteinGrams: 20, totalCalories: 900, addedSugarGrams: 120,
            waterGlasses: 1, hrvMs: 20, hrvBaselineMs: 55, stressLevel0to1: 0.9,
            meaningfulSocialInteractions: 0
        ))
        let smoothedRichBad = richBad.smoothed(previousOverall: priorGoodDay)
        XCTAssertGreaterThan(priorGoodDay - smoothedRichBad.overall, priorGoodDay - smoothedNoisy.overall)

        // No history → unchanged.
        XCTAssertEqual(noisy.smoothed(previousOverall: nil).overall, noisy.overall)
    }

    // MARK: - Range, bands, independence

    func testExtremeInputsClampTo0Through100() {
        let extreme = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(
            sleepHours: 14, steps: 79_000, proteinGrams: 480, totalCalories: 11_000,
            waterGlasses: 39, hrvMs: 240, hrvBaselineMs: 50, restingHR: 26,
            vo2Max: 88, oxygenSaturationPercent: 100, respiratoryRate: 39,
            mindfulMinutes: 590, stressLevel0to1: 0, selfReportedMood0to10: 10,
            socialConnection0to10: 10, meaningfulSocialInteractions: 39
        ))
        XCTAssertTrue((0...100).contains(extreme.overall))
        for pillar in QualityOfLifePillar.allCases {
            if let value = extreme.score(for: pillar) {
                XCTAssertTrue((0...100).contains(value), "\(pillar) out of range: \(value)")
            }
        }
    }

    func testDepletedDayGradesLow() {
        let score = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(
            sleepHours: 4, steps: 800, proteinGrams: 20, totalCalories: 900, addedSugarGrams: 120,
            waterGlasses: 1, hrvMs: 20, hrvBaselineMs: 55, mindfulMinutes: 0, stressLevel0to1: 0.9,
            meaningfulSocialInteractions: 0
        ))
        XCTAssertLessThan(score.overall, 50)
        XCTAssertEqual(score.band, .depleted)
        XCTAssertGreaterThan(score.confidence, 0.7, "a data-rich day is high confidence even when the score is low")
    }

    func testBandBoundaries() {
        XCTAssertEqual(QualityOfLifeBand(score: 85), .thriving)
        XCTAssertEqual(QualityOfLifeBand(score: 84), .steady)
        XCTAssertEqual(QualityOfLifeBand(score: 70), .steady)
        XCTAssertEqual(QualityOfLifeBand(score: 69), .strained)
        XCTAssertEqual(QualityOfLifeBand(score: 50), .strained)
        XCTAssertEqual(QualityOfLifeBand(score: 49), .depleted)
    }

    func testMindAndSocialAreIndependentAspects() {
        let biometricOnly = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(
            sleepHours: 8, steps: 9_000, hrvMs: 55, hrvBaselineMs: 50
        ))
        XCTAssertNil(biometricOnly.score(for: .mind))
        XCTAssertNil(biometricOnly.score(for: .social))

        let withLifeContext = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(
            sleepHours: 8, steps: 9_000, hrvMs: 55, hrvBaselineMs: 50,
            mindfulMinutes: 15, socialConnection0to10: 9
        ))
        XCTAssertNotNil(withLifeContext.score(for: .mind))
        XCTAssertNotNil(withLifeContext.score(for: .social))
        XCTAssertGreaterThan(withLifeContext.gradedAspects, biometricOnly.gradedAspects)
    }
}
