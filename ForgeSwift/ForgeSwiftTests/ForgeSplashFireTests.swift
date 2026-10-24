import XCTest
@testable import ForgeSwift

/// Locks the splash as a beat, not a wait, and rage-fire vs ember.
final class ForgeSplashFireTests: XCTestCase {

    func testSplashHoldIsABeatNotAWait() {
        XCTAssertEqual(ForgeSplashTiming.hold, 0.5, accuracy: 0.001)
        XCTAssertEqual(ForgeSplashTiming.reduceMotionHold, 0.3, accuracy: 0.001)
        XCTAssertEqual(ForgeSplashTiming.fadeOut, 0.3, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(ForgeSplashTiming.hold, ForgeSplashTiming.brandFloor)
        XCTAssertLessThan(ForgeSplashTiming.hold, ForgeSplashTiming.freezeCeiling)
        // The splash curtains an already-rendered frame — Home is right
        // behind it — so the total forced wait must stay under a second.
        XCTAssertLessThan(ForgeSplashTiming.hold + ForgeSplashTiming.fadeOut, 1.0)
        XCTAssertLessThan(ForgeSplashTiming.reduceMotionHold, ForgeSplashTiming.hold)
        XCTAssertEqual(
            ForgeSplashTiming.pauseNanoseconds(reduceMotion: false),
            500_000_000
        )
        XCTAssertEqual(
            ForgeSplashTiming.pauseNanoseconds(reduceMotion: true),
            300_000_000
        )
    }

    func testWelcomeFireIsRageNotEmber() {
        // Geometry lock — auth/onboarding screens no longer paint this field.
        XCTAssertEqual(ForgeFireGeometry.kind, "rage-fire")
        XCTAssertNotEqual(ForgeFireGeometry.kind, AriaSigilGeometry.kind)
        XCTAssertGreaterThan(ForgeFireIntensity.rage.tongueCount, ForgeFireIntensity.ember.tongueCount)
        XCTAssertGreaterThan(ForgeFireIntensity.rage.sparkCount, ForgeFireIntensity.ember.sparkCount)
        XCTAssertGreaterThan(ForgeFireIntensity.rage.heightScale, ForgeFireIntensity.ember.heightScale)
        XCTAssertGreaterThan(ForgeFireIntensity.rage.coreHeat, ForgeFireIntensity.ember.coreHeat)
        XCTAssertEqual(ForgeFireIntensity.rage.tongueCount, 28)
        XCTAssertEqual(ForgeFireIntensity.ember.tongueCount, 8)
        XCTAssertGreaterThan(ForgeFireIntensity.rage.heightScale, 0.8)
        XCTAssertLessThan(ForgeFireIntensity.ember.heightScale, 0.4)
    }

    func testRageTonguesRiseHigherThanEmber() {
        let rage = ForgeFireGeometry.tongue(
            index: 3,
            count: ForgeFireIntensity.rage.tongueCount,
            time: 0.4,
            intensity: .rage,
            origin: .floor,
            reduceMotion: false
        )
        let ember = ForgeFireGeometry.tongue(
            index: 3,
            count: ForgeFireIntensity.ember.tongueCount,
            time: 0.4,
            intensity: .ember,
            origin: .floor,
            reduceMotion: false
        )
        XCTAssertLessThan(rage.tipY, ember.tipY, "rage tips sit higher (smaller y) than ember")
        XCTAssertGreaterThan(rage.heat, ember.heat)
        XCTAssertGreaterThan(rage.width, ember.width * 0.8)
    }

    func testFireMovesWhenAliveAndFreezesWhenReduced() {
        let a = ForgeFireGeometry.tongue(
            index: 5,
            count: 28,
            time: 0.2,
            intensity: .rage,
            origin: .floor,
            reduceMotion: false
        )
        let b = ForgeFireGeometry.tongue(
            index: 5,
            count: 28,
            time: 1.1,
            intensity: .rage,
            origin: .floor,
            reduceMotion: false
        )
        XCTAssertFalse(
            abs(a.tipX - b.tipX) < 0.00001 && abs(a.tipY - b.tipY) < 0.00001,
            "rage tongues flicker"
        )
        let stillA = ForgeFireGeometry.tongue(
            index: 5,
            count: 28,
            time: 0.2,
            intensity: .rage,
            origin: .floor,
            reduceMotion: true
        )
        let stillB = ForgeFireGeometry.tongue(
            index: 5,
            count: 28,
            time: 9,
            intensity: .rage,
            origin: .floor,
            reduceMotion: true
        )
        XCTAssertEqual(stillA.tipX, stillB.tipX, accuracy: 0.0001)
        XCTAssertEqual(stillA.tipY, stillB.tipY, accuracy: 0.0001)
    }

    func testLogoLifeDoesNotRewriteRingPose() {
        XCTAssertEqual(AriaSigilLife.tickHz, 12, accuracy: 0.001)
        XCTAssertLessThanOrEqual(AriaSigilLife.tickHz, 12)
        XCTAssertEqual(AriaSigilLife.flicker(index: 1, time: 0.4, reduceMotion: true), 1, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilLife.wobble(index: 1, time: 0.4, reduceMotion: true), 0, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilLife.breathScale(time: 0.4, hero: true, reduceMotion: true), 1, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilLife.breathScale(time: 0.4, hero: false, reduceMotion: false), 1, accuracy: 0.0001)
        let f0 = AriaSigilLife.flicker(index: 0, time: 0.2, reduceMotion: false)
        let f1 = AriaSigilLife.flicker(index: 0, time: 1.0, reduceMotion: false)
        XCTAssertGreaterThan(abs(f0 - f1), 0.00001)
        XCTAssertGreaterThan(AriaSigilLife.breathScale(time: 0.4, hero: true, reduceMotion: false), 0.95)

        let poseA = AriaSigilGeometry.ellipse(index: 1, time: 0.4, state: .idle, reduceMotion: false)
        let poseB = AriaSigilGeometry.ellipse(index: 1, time: 0.4, state: .idle, reduceMotion: false)
        XCTAssertEqual(poseA.rotation, poseB.rotation, accuracy: 0.0001)
        XCTAssertEqual(poseA.opacity, poseB.opacity, accuracy: 0.0001)
    }

    func testContrastFlickerNeverDropsBelowCoveFloor() {
        for index in AriaSigilGeometry.contrastRingIndices {
            var t = 0.0
            while t < 4 {
                let painted = AriaSigilLife.paintedOpacity(index: index, time: t, reduceMotion: false)
                XCTAssertGreaterThanOrEqual(painted, AriaSigilGeometry.contrastFloor)
                t += 0.05
            }
        }
    }

    func testFirePaintCadenceIsCapped() {
        XCTAssertEqual(ForgeFireGeometry.tickHz, 12, accuracy: 0.001)
        XCTAssertLessThanOrEqual(ForgeFireGeometry.tickHz, 15)
        XCTAssertGreaterThanOrEqual(ForgeFireGeometry.tickHz, 12)
    }

    func testSplashStrikeFinishesInsideTheHold() {
        XCTAssertLessThanOrEqual(ForgeStrikeGeometry.splashDuration, ForgeSplashTiming.hold)
        XCTAssertGreaterThanOrEqual(ForgeStrikeGeometry.splashDuration, ForgeSplashTiming.brandFloor)
        let windup = ForgeStrikeGeometry.pose(
            variation: .strike,
            time: 0,
            duration: ForgeStrikeGeometry.splashDuration,
            reduceMotion: false
        )
        let hit = ForgeStrikeGeometry.pose(
            variation: .strike,
            time: 0.38 * ForgeStrikeGeometry.splashDuration,
            duration: ForgeStrikeGeometry.splashDuration,
            reduceMotion: false
        )
        let settled = ForgeStrikeGeometry.pose(
            variation: .strike,
            time: ForgeStrikeGeometry.splashDuration,
            duration: ForgeStrikeGeometry.splashDuration,
            reduceMotion: false
        )
        XCTAssertGreaterThan(hit.impact, 0.9)
        XCTAssertLessThan(settled.hammerAngle, windup.hammerAngle)
        XCTAssertGreaterThan(settled.flameScale, windup.flameScale)
        XCTAssertEqual(settled.sparkTravel, 1, accuracy: 0.001)
        XCTAssertLessThan(settled.impact, 0.05)
    }

    func testStrikeVariationsReadDifferently() {
        let duration = ForgeStrikeGeometry.duration
        let strikeStart = ForgeStrikeGeometry.pose(variation: .strike, time: 0, duration: duration, reduceMotion: false)
        let strikeHit = ForgeStrikeGeometry.pose(variation: .strike, time: 0.38 * duration, duration: duration, reduceMotion: false)
        let quenchStart = ForgeStrikeGeometry.pose(variation: .quench, time: 0, duration: duration, reduceMotion: false)
        let quenchEnd = ForgeStrikeGeometry.pose(variation: .quench, time: duration, duration: duration, reduceMotion: false)
        let sparkHit = ForgeStrikeGeometry.pose(variation: .spark, time: 0.34 * duration, duration: duration, reduceMotion: false)
        let sparkLate = ForgeStrikeGeometry.pose(variation: .spark, time: 0.80 * duration, duration: duration, reduceMotion: false)
        let temperStart = ForgeStrikeGeometry.pose(variation: .temper, time: 0, duration: duration, reduceMotion: false)
        let temperHit = ForgeStrikeGeometry.pose(variation: .temper, time: 0.42 * duration, duration: duration, reduceMotion: false)

        XCTAssertGreaterThan(strikeHit.impact, strikeStart.impact)
        XCTAssertGreaterThan(strikeHit.flameScale, 1.05)
        XCTAssertLessThan(strikeHit.hammerAngle, strikeStart.hammerAngle)

        XCTAssertGreaterThan(quenchStart.flameScale, quenchEnd.flameScale + 0.5)
        XCTAssertGreaterThan(quenchEnd.hammerAngle, quenchStart.hammerAngle + 0.7)
        XCTAssertLessThan(quenchEnd.flameScale, 0.35)

        XCTAssertLessThan(sparkHit.flameScale, 0.95)
        XCTAssertGreaterThan(sparkLate.sparkTravel, 0.6)
        XCTAssertGreaterThan(sparkLate.flameScale, 0.5)

        XCTAssertLessThan(temperStart.hammerAngle, strikeStart.hammerAngle)
        XCTAssertLessThan(temperHit.impact, strikeHit.impact)
        XCTAssertEqual(Set(ForgeStrikeVariation.allCases.map(\.title)).count, 4)
    }

    func testReduceMotionFreezesEveryStrike() {
        for variation in ForgeStrikeVariation.allCases {
            let settled = ForgeStrikeGeometry.pose(variation: variation, time: 0, duration: 1.05, reduceMotion: true)
            let later = ForgeStrikeGeometry.pose(variation: variation, time: 4, duration: 1.05, reduceMotion: true)
            XCTAssertEqual(settled.hammerAngle, later.hammerAngle, accuracy: 0.0001)
            XCTAssertEqual(settled.impact, later.impact, accuracy: 0.0001)
            XCTAssertEqual(settled.flameScale, later.flameScale, accuracy: 0.0001)
            XCTAssertEqual(settled.sparkTravel, later.sparkTravel, accuracy: 0.0001)
            let windup = ForgeStrikeGeometry.pose(variation: variation, time: 0, duration: 1.05, reduceMotion: false)
            XCTAssertGreaterThan(abs(settled.hammerAngle - windup.hammerAngle), 0.15)
        }
    }
}
