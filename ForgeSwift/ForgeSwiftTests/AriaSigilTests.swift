import XCTest
@testable import ForgeSwift

/// Locks the ember mark's motion so ARIA stays friendly — alive, not a spinner.
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
        let still = AriaSigilGeometry.edgeUndulation(time: 12, reduceMotion: true)
        XCTAssertEqual(still.x, 0)
        XCTAssertEqual(still.y, 0)
    }

    func testIdleIsSlowerThanProcessing() {
        XCTAssertLessThan(AriaSigilGeometry.idleBreathHz, AriaSigilGeometry.processingBreathHz)
        XCTAssertLessThan(AriaSigilGeometry.idleBreathHz, 0.4, "idle must feel like a coach, not a spinner")
    }

    func testMotionStaysGentle() {
        XCTAssertLessThanOrEqual(AriaSigilGeometry.maxHueDegrees, 8, "iridescence is a shimmer, not a carnival")
        XCTAssertLessThanOrEqual(AriaSigilGeometry.maxEdgeUndulation, 0.02)
        XCTAssertLessThanOrEqual(AriaSigilGeometry.breathScale, 0.04)
        XCTAssertLessThanOrEqual(AriaSigilGeometry.corePulseAmount, 0.05)
        for t in stride(from: 0.0, through: 40, by: 0.37) {
            let hue = AriaSigilGeometry.hueShiftDegrees(time: t, state: .idle, reduceMotion: false)
            XCTAssertLessThanOrEqual(abs(hue), AriaSigilGeometry.maxHueDegrees + 0.0001)
            let edge = AriaSigilGeometry.edgeUndulation(time: t, reduceMotion: false)
            XCTAssertLessThanOrEqual(abs(edge.x), AriaSigilGeometry.maxEdgeUndulation + 0.0001)
            XCTAssertLessThanOrEqual(abs(edge.y), AriaSigilGeometry.maxEdgeUndulation + 0.0001)
        }
    }

    func testSpeakingCoreIsWarmerThanIdle() {
        let idle = AriaSigilGeometry.corePulse(time: 0.4, state: .idle, reduceMotion: false)
        let talk = AriaSigilGeometry.corePulse(time: 0.4, state: .speaking, reduceMotion: false)
        XCTAssertGreaterThan(talk, idle)
        XCTAssertLessThan(talk, 0.12, "speaking stays a glow, not a strobe")
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

    func testVeinPulseTracksBreathAndFreezesUnderReduceMotion() {
        let a = AriaSigilGeometry.veinPulse(time: 5, state: .idle, reduceMotion: true)
        let b = AriaSigilGeometry.veinPulse(time: 50, state: .idle, reduceMotion: true)
        XCTAssertEqual(a, b, "Reduce Motion must freeze the vein pulse")
        for t in stride(from: 0.0, through: 20, by: 0.41) {
            let v = AriaSigilGeometry.veinPulse(time: t, state: .speaking, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    func testSparkTwinklesAreIndependentPerIndexAndFreezeUnderReduceMotion() {
        let t = 3.3
        let sparks = (0..<3).map { AriaSigilGeometry.sparkTwinkle(time: t, index: $0, reduceMotion: false) }
        XCTAssertNotEqual(sparks[0], sparks[1])
        XCTAssertNotEqual(sparks[1], sparks[2])
        for s in sparks {
            XCTAssertGreaterThanOrEqual(s, 0)
            XCTAssertLessThanOrEqual(s, 1)
        }
        XCTAssertEqual(
            AriaSigilGeometry.sparkTwinkle(time: 9, index: 0, reduceMotion: true),
            AriaSigilGeometry.sparkTwinkle(time: 90, index: 0, reduceMotion: true),
            "Reduce Motion must freeze spark twinkle"
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
