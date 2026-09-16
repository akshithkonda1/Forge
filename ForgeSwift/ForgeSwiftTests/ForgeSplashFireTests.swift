import XCTest
@testable import ForgeSwift

/// Locks splash hold (branded, not frozen) and rage-fire vs ember.
final class ForgeSplashFireTests: XCTestCase {

    func testSplashHoldIsForgedNotFrozen() {
        XCTAssertEqual(ForgeSplashTiming.hold, 2.45, accuracy: 0.001)
        XCTAssertEqual(ForgeSplashTiming.reduceMotionHold, 0.65, accuracy: 0.001)
        XCTAssertEqual(ForgeSplashTiming.fadeOut, 0.38, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(ForgeSplashTiming.hold, ForgeSplashTiming.brandFloor)
        XCTAssertLessThan(ForgeSplashTiming.hold, ForgeSplashTiming.freezeCeiling)
        XCTAssertGreaterThan(ForgeSplashTiming.hold, 1.1)
        XCTAssertLessThan(ForgeSplashTiming.reduceMotionHold, 1.0)
        XCTAssertEqual(
            ForgeSplashTiming.pauseNanoseconds(reduceMotion: false),
            2_450_000_000
        )
        XCTAssertEqual(
            ForgeSplashTiming.pauseNanoseconds(reduceMotion: true),
            650_000_000
        )
    }

    func testWelcomeFireIsRageNotEmber() {
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
}
