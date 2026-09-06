import XCTest
@testable import ForgeSwift

/// Locks the fluid ember so it stays alive without stretching.
final class AriaSigilTests: XCTestCase {

    func testStillPoseIsStableAndNonZero() {
        XCTAssertGreaterThan(AriaSigilGeometry.stillPose, 1)
        XCTAssertLessThan(AriaSigilGeometry.stillPose, 3)
        let a = AriaSigilGeometry.breath(time: AriaSigilGeometry.stillPose, state: .idle, reduceMotion: true)
        let b = AriaSigilGeometry.breath(time: 99, state: .idle, reduceMotion: true)
        XCTAssertEqual(a, b, "Reduce Motion must freeze breath")
        XCTAssertEqual(
            AriaSigilGeometry.hueShiftDegrees(time: 0, state: .idle, reduceMotion: true),
            AriaSigilGeometry.hueShiftDegrees(time: 40, state: .idle, reduceMotion: true)
        )
        XCTAssertEqual(AriaSigilGeometry.uniformScale(breath: 1, reduceMotion: true), 1)
    }

    func testIdleIsSlowerThanProcessing() {
        XCTAssertLessThan(AriaSigilGeometry.idleBreathHz, AriaSigilGeometry.processingBreathHz)
        XCTAssertLessThan(AriaSigilGeometry.idleBreathHz, 0.55, "idle is a coach breath, not a spinner")
    }

    func testScaleIsUniformAndVisible() {
        XCTAssertEqual(AriaSigilGeometry.maxEdgeUndulation, 0, "never nonuniform stretch")
        XCTAssertEqual(AriaSigilGeometry.breathScale, 0.04, accuracy: 0.0001)
        let still = AriaSigilGeometry.uniformScale(breath: 0, reduceMotion: false)
        let peak = AriaSigilGeometry.uniformScale(breath: 1, reduceMotion: false)
        XCTAssertEqual(still, 1, accuracy: 0.0001)
        XCTAssertEqual(peak, 1.04, accuracy: 0.0001)
    }

    func testHueShimmerIsVisibleButBounded() {
        XCTAssertEqual(AriaSigilGeometry.maxHueDegrees, 12, accuracy: 0.001)
        for t in stride(from: 0.0, through: 40, by: 0.37) {
            let hue = AriaSigilGeometry.hueShiftDegrees(time: t, state: .idle, reduceMotion: false)
            XCTAssertLessThanOrEqual(abs(hue), AriaSigilGeometry.maxHueDegrees + 0.0001)
        }
    }

    func testSpeakingCoreIsWarmerThanIdle() {
        let idle = AriaSigilGeometry.corePulse(time: 0.4, state: .idle, reduceMotion: false)
        let talk = AriaSigilGeometry.corePulse(time: 0.4, state: .speaking, reduceMotion: false)
        XCTAssertGreaterThan(talk, idle)
        XCTAssertLessThan(talk, 0.22, "speaking stays a glow, not a strobe")
    }

    func testReduceMotionFreezesCoreAndHue() {
        let a = AriaSigilGeometry.corePulse(time: 1, state: .speaking, reduceMotion: true)
        let b = AriaSigilGeometry.corePulse(time: 40, state: .speaking, reduceMotion: true)
        XCTAssertEqual(a, b)
        XCTAssertEqual(
            AriaSigilGeometry.hueShiftDegrees(time: 3, state: .listening, reduceMotion: true),
            0
        )
    }

    func testPaletteStaysPreciousNotNeon() {
        XCTAssertEqual(AriaSigilPalette.goldHex, "C9A36A")
        XCTAssertEqual(AriaSigilPalette.voidDeepHex, "030207")
        XCTAssertEqual(AriaSigilPalette.bloodHex, "4A1018")
        XCTAssertEqual(AriaSigilPalette.ivoryHex, "F3EBDD")
        XCTAssertEqual(AriaSigilPalette.emberHex, "FF6A1A")
        XCTAssertNotEqual(AriaSigilPalette.photonPrimary(for: .energized), "00D2FF")
        XCTAssertNotEqual(AriaSigilPalette.photonPrimary(for: .focused), "22C55E")
    }
}
