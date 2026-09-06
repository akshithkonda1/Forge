import XCTest
@testable import ForgeSwift

/// Locks the mark so ARIA cannot drift back into a fidgety AI blob.
final class AriaSigilTests: XCTestCase {

    func testStillPoseIsStableAndNonZero() {
        XCTAssertGreaterThan(AriaSigilGeometry.stillPose, 1)
        XCTAssertLessThan(AriaSigilGeometry.stillPose, 3)
        let a = AriaSigilGeometry.breath(time: AriaSigilGeometry.stillPose, state: .idle, reduceMotion: true)
        let b = AriaSigilGeometry.breath(time: 99, state: .idle, reduceMotion: true)
        XCTAssertEqual(a, b, "Reduce Motion must freeze breath")
        XCTAssertEqual(
            AriaSigilGeometry.photonSpinDegrees(time: 0, state: .idle, reduceMotion: true),
            AriaSigilGeometry.photonSpinDegrees(time: 40, state: .idle, reduceMotion: true)
        )
    }

    func testIdleIsSlowerThanProcessing() {
        let idle = AriaSigilGeometry.photonSpinDegrees(time: 10, state: .idle, reduceMotion: false)
        let thinking = AriaSigilGeometry.photonSpinDegrees(time: 10, state: .processing, reduceMotion: false)
        XCTAssertLessThan(idle, thinking)
        XCTAssertLessThan(idle / 10, 8, "idle spin must feel like a watch, not a spinner")
    }

    func testGazeNeverLeavesTheIris() {
        for t in stride(from: 0.0, through: 40, by: 0.37) {
            for state in [AROrbState.idle, .listening, .processing, .speaking] {
                let g = AriaSigilGeometry.gaze(time: t, state: state, reduceMotion: false)
                XCTAssertLessThanOrEqual(abs(g.x), AriaSigilGeometry.maxGazeRatio + 0.0001)
                XCTAssertLessThanOrEqual(abs(g.y), AriaSigilGeometry.maxGazeRatio + 0.0001)
            }
        }
        XCTAssertEqual(AriaSigilGeometry.clampGaze(1), AriaSigilGeometry.maxGazeRatio)
        XCTAssertEqual(AriaSigilGeometry.clampGaze(-1), -AriaSigilGeometry.maxGazeRatio)
    }

    func testPhotonRingStaysBroken() {
        XCTAssertGreaterThan(AriaSigilGeometry.photonTrimStart, 0)
        XCTAssertLessThan(AriaSigilGeometry.photonTrimEnd, 1)
        XCTAssertGreaterThan(
            AriaSigilGeometry.photonTrimEnd - AriaSigilGeometry.photonTrimStart,
            0.7,
            "enough ring to read as a mark"
        )
        XCTAssertLessThan(
            AriaSigilGeometry.photonTrimEnd - AriaSigilGeometry.photonTrimStart,
            0.9,
            "the gap is the mystery"
        )
    }

    func testMindIsAPupilNotAFill() {
        XCTAssertLessThan(AriaSigilGeometry.mindRatio, AriaSigilGeometry.horizonRatio)
        XCTAssertLessThan(AriaSigilGeometry.horizonRatio, AriaSigilGeometry.photonRatio)
        XCTAssertLessThan(AriaSigilGeometry.photonRatio, AriaSigilGeometry.voidRatio)
    }

    func testSpeakingGlowsMoreThanIdle() {
        let idle = AriaSigilGeometry.mindGlow(amplitude: 0.3, state: .idle, breath: 0.5)
        let talk = AriaSigilGeometry.mindGlow(amplitude: 0.3, state: .speaking, breath: 0.5)
        XCTAssertGreaterThan(talk, idle)
        XCTAssertLessThanOrEqual(talk, 1)
    }

    func testPaletteStaysPreciousNotNeon() {
        XCTAssertEqual(AriaSigilPalette.goldHex, "C9A36A")
        XCTAssertEqual(AriaSigilPalette.voidDeepHex, "030207")
        XCTAssertEqual(AriaSigilPalette.bloodHex, "4A1018")
        XCTAssertEqual(AriaSigilPalette.ivoryHex, "F3EBDD")
        XCTAssertNotEqual(AriaSigilPalette.photonPrimary(for: .energized), "00D2FF")
        XCTAssertNotEqual(AriaSigilPalette.photonPrimary(for: .focused), "22C55E")
    }
}
