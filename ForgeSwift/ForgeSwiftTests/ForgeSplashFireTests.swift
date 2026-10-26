import XCTest
import ForgeCore
@testable import ForgeSwift

/// Locks the splash as a beat, not a wait, and the strike on the splash only.
final class ForgeSplashFireTests: XCTestCase {

    func testSplashHoldIsABeatNotAWait() {
        XCTAssertEqual(ForgeSplashTiming.hold, 2.10, accuracy: 0.001)
        XCTAssertEqual(ForgeSplashTiming.reduceMotionHold, 0.40, accuracy: 0.001)
        XCTAssertEqual(ForgeSplashTiming.fadeOut, 0.35, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(ForgeSplashTiming.hold, ForgeSplashTiming.brandFloor)
        XCTAssertLessThanOrEqual(ForgeSplashTiming.hold + ForgeSplashTiming.fadeOut, ForgeSplashTiming.freezeCeiling)
        XCTAssertLessThanOrEqual(ForgeSplashTiming.hold + ForgeSplashTiming.fadeOut, 2.50)
        XCTAssertLessThan(ForgeSplashTiming.reduceMotionHold, ForgeSplashTiming.hold)
        XCTAssertEqual(
            ForgeSplashTiming.pauseNanoseconds(reduceMotion: false),
            2_100_000_000
        )
        XCTAssertEqual(
            ForgeSplashTiming.pauseNanoseconds(reduceMotion: true),
            400_000_000
        )
        XCTAssertEqual(ForgeSplashTiming.signedInHold, 0.40, accuracy: 0.001)
        XCTAssertLessThan(
            ForgeSplashTiming.signedInHold + ForgeSplashTiming.fadeOut,
            ForgeSplashTiming.freezeCeiling
        )
        XCTAssertEqual(
            ForgeSplashTiming.hold + ForgeSplashTiming.fadeOut,
            2.45,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ForgeSplashTiming.pauseNanoseconds(reduceMotion: false, signedIn: true),
            400_000_000
        )
        XCTAssertEqual(
            ForgeSplashTiming.pauseNanoseconds(reduceMotion: true, signedIn: true),
            400_000_000
        )
        XCTAssertEqual(ForgeHaptics.strikeToken, "rigid")
        XCTAssertEqual(ForgeHaptic.press.token, "light")
        XCTAssertNotEqual(ForgeHaptics.strikeToken, ForgeHaptic.press.token)
    }

    func testLaunchScreenMatchesSplashField() {
        XCTAssertEqual(ForgeSplashScreen.backdropHex, "09090B")
        XCTAssertEqual(ForgeSplashScreen.launchColorName, "LaunchBackground")
    }

    func testNotificationPromptWaitsForOnboarding() {
        XCTAssertEqual(ForgeNotificationScheduler.promptPolicy, "onboarding-after-sign-in")
        XCTAssertFalse(ForgeNotificationScheduler.syncPromptsWhenUndetermined)
        XCTAssertFalse(SleepAlarmScheduler.promptsWhenUndetermined)
    }

    func testImpactGlowStaysLocalized() {
        XCTAssertLessThanOrEqual(ForgeStrikeGeometry.maxLocalizedGlow, 0.28)
        XCTAssertEqual(ForgeFireGeometry.tickHz, 12, accuracy: 0.001)
        XCTAssertLessThanOrEqual(ForgeStrikeGeometry.paintHz, 60)
    }

    func testStrikeLivesOnSplashNotWelcome() {
        XCTAssertEqual(ForgeStrikeGeometry.host, "splash")
        XCTAssertNotEqual(ForgeStrikeGeometry.host, "welcome")
        XCTAssertEqual(ForgeStrikeGeometry.duration, ForgeStrikeGeometry.splashDuration, accuracy: 0.001)
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
        XCTAssertLessThanOrEqual(ForgeFireGeometry.tickHz, 12)
        XCTAssertGreaterThanOrEqual(ForgeFireGeometry.tickHz, 12)
        let a = ForgeFireGeometry.flickerTime(0.04)
        let b = ForgeFireGeometry.flickerTime(0.07)
        XCTAssertEqual(a, b, accuracy: 0.0001, "12 Hz bucket holds both samples")
        XCTAssertGreaterThan(ForgeFireGeometry.flickerTime(0.12), a)
    }

    func testSplashStrikeFinishesInsideTheHold() {
        XCTAssertEqual(ForgeStrikeGeometry.splashImpactTime, 0.777, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(ForgeStrikeGeometry.splashImpactTime, 0.74)
        XCTAssertLessThanOrEqual(ForgeStrikeGeometry.splashImpactTime, 0.82)
        XCTAssertLessThan(ForgeStrikeGeometry.splashImpactTime + 0.1, ForgeSplashTiming.hold)
        XCTAssertLessThanOrEqual(ForgeSplashTiming.hold + ForgeSplashTiming.fadeOut, ForgeSplashTiming.freezeCeiling)
        let sparks = ForgeStrikeGeometry.pose(
            time: ForgeStrikeGeometry.splashImpactTime + 0.05,
            duration: ForgeStrikeGeometry.splashDuration,
            reduceMotion: false
        )
        XCTAssertGreaterThan(sparks.impact, 0.08, "sparks still flying after impact")
        let reduced = ForgeStrikeGeometry.pose(
            time: ForgeStrikeGeometry.splashImpactTime,
            duration: ForgeStrikeGeometry.splashDuration,
            reduceMotion: true
        )
        XCTAssertLessThan(reduced.impact, 0.08, "Reduce Motion: static pose, no sparks")
        let windup = ForgeStrikeGeometry.pose(
            time: 0,
            duration: ForgeStrikeGeometry.splashDuration,
            reduceMotion: false
        )
        let hit = ForgeStrikeGeometry.pose(
            time: ForgeStrikeGeometry.splashImpactTime,
            duration: ForgeStrikeGeometry.splashDuration,
            reduceMotion: false
        )
        let settled = ForgeStrikeGeometry.pose(
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

    func testStrikeAnticipatesThenHits() {
        let duration = ForgeStrikeGeometry.splashDuration
        let start = ForgeStrikeGeometry.pose(time: 0, duration: duration, reduceMotion: false)
        let gather = ForgeStrikeGeometry.pose(
            time: ForgeStrikeGeometry.anticipationEnd * duration,
            duration: duration,
            reduceMotion: false
        )
        let hit = ForgeStrikeGeometry.pose(
            time: ForgeStrikeGeometry.strikeImpactFraction * duration,
            duration: duration,
            reduceMotion: false
        )
        XCTAssertGreaterThan(gather.hammerAngle, start.hammerAngle, "anticipation pulls the hammer back")
        XCTAssertGreaterThan(hit.impact, start.impact)
        XCTAssertLessThan(hit.hammerAngle, start.hammerAngle)
        XCTAssertGreaterThan(hit.flameScale, start.flameScale)
    }

    func testReduceMotionFreezesTheStrike() {
        let settled = ForgeStrikeGeometry.pose(time: 0, duration: 1.85, reduceMotion: true)
        let later = ForgeStrikeGeometry.pose(time: 4, duration: 1.85, reduceMotion: true)
        XCTAssertEqual(settled.hammerAngle, later.hammerAngle, accuracy: 0.0001)
        XCTAssertEqual(settled.impact, later.impact, accuracy: 0.0001)
        XCTAssertEqual(settled.flameScale, later.flameScale, accuracy: 0.0001)
        XCTAssertEqual(settled.sparkTravel, later.sparkTravel, accuracy: 0.0001)
        let windup = ForgeStrikeGeometry.pose(time: 0, duration: 1.85, reduceMotion: false)
        XCTAssertGreaterThan(abs(settled.hammerAngle - windup.hammerAngle), 0.15)
    }

    func testStrikeAcceleratesThenRebounds() {
        let duration = ForgeStrikeGeometry.splashDuration
        func pose(_ time: Double) -> ForgeStrikePose {
            ForgeStrikeGeometry.pose(
                time: time,
                duration: duration,
                reduceMotion: false
            )
        }
        let windup = pose(0)
        let mid = pose(ForgeStrikeGeometry.splashImpactTime * 0.5)
        let hit = pose(ForgeStrikeGeometry.splashImpactTime)
        let bounce = pose(ForgeStrikeGeometry.splashImpactTime + 0.06)
        let linearMid = windup.hammerAngle + (hit.hammerAngle - windup.hammerAngle) * 0.5
        XCTAssertGreaterThan(mid.hammerAngle, linearMid, "quartic ease-in stays high at midpoint")
        XCTAssertGreaterThan(bounce.hammerAngle, hit.hammerAngle, "spring overshoot after impact")
        XCTAssertGreaterThanOrEqual(ForgeStrikeGeometry.splashImpactTime, 0.74)
        XCTAssertLessThanOrEqual(ForgeStrikeGeometry.splashImpactTime, 0.82)
        XCTAssertEqual(ForgeStrikeMotion.style, .accelerateRebound, "default ships Option A")
        XCTAssertTrue(ForgeStrikeMotion.allowsRebound)
        XCTAssertTrue(ForgeStrikeMotion.allowsImpactShake)
    }

    func testForgeAndRestLandsWithoutRebound() {
        let duration = ForgeStrikeGeometry.splashDuration
        func pose(_ time: Double) -> ForgeStrikePose {
            ForgeStrikeGeometry.pose(
                time: time,
                duration: duration,
                reduceMotion: false,
                style: .forgeAndRest
            )
        }
        let windup = pose(0)
        let mid = pose(ForgeStrikeGeometry.splashImpactTime * 0.5)
        let hit = pose(ForgeStrikeGeometry.splashImpactTime)
        let after = pose(ForgeStrikeGeometry.splashImpactTime + 0.06)
        let settled = pose(duration)
        let linearMid = windup.hammerAngle + (hit.hammerAngle - windup.hammerAngle) * 0.5
        XCTAssertGreaterThan(mid.hammerAngle, linearMid, "B still eases in, never linear")
        XCTAssertEqual(after.hammerAngle, hit.hammerAngle, accuracy: 0.001, "no rebound")
        XCTAssertEqual(settled.hammerAngle, hit.hammerAngle, accuracy: 0.001, "rests on the hearth")
        XCTAssertGreaterThan(settled.flameScale, windup.flameScale, "flame gathers, does not die")
        XCTAssertLessThan(settled.flameScale, 1.20, "rise, not a burst")
    }

    func testSparksAreOneShotCanvasChips() {
        XCTAssertEqual(ForgeSparkBurst.kind, "canvas")
        XCTAssertEqual(ForgeSparkBurst.shape, "chip")
        XCTAssertNotEqual(ForgeSparkBurst.shape, "circle")
        XCTAssertGreaterThan(ForgeSparkBurst.gravity, 0)
        XCTAssertTrue(ForgeSparkBurst.oneShot)
        XCTAssertLessThanOrEqual(ForgeSparkBurst.maxLifetime, 0.6)
        XCTAssertEqual(ForgeSparkBurst.count, 10)
        XCTAssertEqual(ForgeSparkBurst.chips.count, ForgeSparkBurst.count)
        XCTAssertEqual(ForgeStrikeMotion.sparkBackend, "canvas")
        XCTAssertEqual(ForgeStrikeMotion.swingEasing, "anticipate+easeInQuart+spring")
        XCTAssertFalse(ForgeStrikeMotion.swingIsLinear)
    }
}
