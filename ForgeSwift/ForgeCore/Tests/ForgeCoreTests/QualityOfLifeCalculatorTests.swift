import XCTest
@testable import ForgeCore

final class QualityOfLifeCalculatorTests: XCTestCase {

    // No signal at all is the only case that yields no grade — and it reports
    // that honestly (confidence 0) instead of the old fabricated 82.
    func testNoSignalsProducesZeroConfidenceNotAFabricatedDefault() {
        let score = QualityOfLifeCalculator.score(from: QualityOfLifeInputs())
        XCTAssertEqual(score.confidence, 0)
        XCTAssertEqual(score.overall, 0)
        XCTAssertEqual(score.gradedAspects, 0)
        XCTAssertNotEqual(score.overall, 82, "must never fall back to the old invented 82")
    }

    // A single available aspect still produces a grade — it does not refuse
    // with "insufficient data".
    func testSingleAspectStillGrades() {
        let score = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(steps: 8_000))
        XCTAssertEqual(score.gradedAspects, 1)
        XCTAssertEqual(score.score(for: .activity), 100)
        XCTAssertEqual(score.overall, 100)
        // Confidence reflects that only one pillar (activity, weight 0.18) was covered.
        XCTAssertEqual(score.confidence, QualityOfLifePillar.activity.weight, accuracy: 0.0001)
    }

    // Every pillar present → full confidence and all seven aspects graded.
    func testAllAspectsProduceFullConfidence() {
        let inputs = QualityOfLifeInputs(
            sleepHours: 8,
            steps: 9_000,
            proteinGrams: 150, totalCalories: 2_400,
            waterGlasses: 8,
            hrvMs: 55, hrvBaselineMs: 50,
            mindfulMinutes: 12,
            socialConnection0to10: 8
        )
        let score = QualityOfLifeCalculator.score(from: inputs)
        XCTAssertEqual(score.confidence, 1.0, accuracy: 0.0001)
        XCTAssertEqual(score.gradedAspects, QualityOfLifePillar.allCases.count)
        XCTAssertTrue((0...100).contains(score.overall))
    }

    // The blend is an independent, renormalized weighting — not a naive /5 with
    // overlapping inputs. Two clean pillars must combine by their weights.
    func testHolisticBlendIsWeightedAndRenormalized() {
        // activity: steps 4000 → 50 (weight 0.18); mind: stress 0 → 100 (weight 0.12)
        let inputs = QualityOfLifeInputs(steps: 4_000, stressLevel0to1: 0)
        let score = QualityOfLifeCalculator.score(from: inputs)
        XCTAssertEqual(score.score(for: .activity), 50)
        XCTAssertEqual(score.score(for: .mind), 100)
        // (50*0.18 + 100*0.12) / (0.18 + 0.12) = 21 / 0.30 = 70
        XCTAssertEqual(score.overall, 70)
        XCTAssertEqual(score.confidence, 0.30, accuracy: 0.0001)
        XCTAssertEqual(score.gradedAspects, 2)
    }

    // Missing aspects lower confidence, not the score: great sleep alone is not
    // punished for the absence of other pillars.
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

    // Personalized targets: the same protein intake grades higher for a lighter
    // person than for a heavier one (1.6 g/kg target).
    func testPersonalizationTunesNutritionTarget() {
        let light = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(proteinGrams: 100, bodyMassKg: 50))
        let heavy = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(proteinGrams: 100, bodyMassKg: 100))
        XCTAssertEqual(light.score(for: .nutrition), 100)          // target 80 g, capped
        XCTAssertEqual(heavy.score(for: .nutrition), 63)           // target 160 g → 62.5 → 63
        XCTAssertGreaterThan(light.overall, heavy.overall)
    }

    // Oversleeping is not rewarded past the need; scores stay clamped.
    func testExtremeInputsClampTo0Through100() {
        let extreme = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(
            sleepHours: 14,
            steps: 500_000,
            proteinGrams: 900, totalCalories: 12_000,
            waterGlasses: 40,
            hrvMs: 400, hrvBaselineMs: 20,
            restingHR: 20, restingHRBaseline: 90,
            vo2Max: 120, oxygenSaturationPercent: 100, respiratoryRate: 12,
            mindfulMinutes: 600, stressLevel0to1: 0, selfReportedMood0to10: 10,
            socialConnection0to10: 10, meaningfulSocialInteractions: 40
        ))
        XCTAssertTrue((0...100).contains(extreme.overall))
        for pillar in QualityOfLifePillar.allCases {
            if let value = extreme.score(for: pillar) {
                XCTAssertTrue((0...100).contains(value), "\(pillar) out of range: \(value)")
            }
        }
    }

    // A day that is genuinely poor across aspects grades low — the score has
    // real range, it does not float near a flattering constant.
    func testDepletedDayGradesLow() {
        let score = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(
            sleepHours: 4,
            steps: 800,
            proteinGrams: 20, totalCalories: 900, addedSugarGrams: 120,
            waterGlasses: 1,
            hrvMs: 20, hrvBaselineMs: 55,
            mindfulMinutes: 0, stressLevel0to1: 0.9,
            meaningfulSocialInteractions: 0
        ))
        XCTAssertLessThan(score.overall, 50)
        XCTAssertEqual(score.band, .depleted)
        XCTAssertGreaterThan(score.confidence, 0.8, "a data-rich day should be high confidence even when the score is low")
    }

    func testBandBoundaries() {
        XCTAssertEqual(QualityOfLifeBand(score: 85), .thriving)
        XCTAssertEqual(QualityOfLifeBand(score: 84), .steady)
        XCTAssertEqual(QualityOfLifeBand(score: 70), .steady)
        XCTAssertEqual(QualityOfLifeBand(score: 69), .strained)
        XCTAssertEqual(QualityOfLifeBand(score: 50), .strained)
        XCTAssertEqual(QualityOfLifeBand(score: 49), .depleted)
    }

    // Mind and connection are real, independent aspects — not proxies of HRV.
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
