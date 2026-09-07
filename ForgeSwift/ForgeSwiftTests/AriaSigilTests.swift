import XCTest
@testable import ForgeSwift

/// Locks the living 4-lobe ember: no ping, freeze on Reduce Motion.
final class AriaSigilTests: XCTestCase {

    func testFourLobesAndStillPose() {
        XCTAssertEqual(AriaSigilGeometry.lobeCount, 4)
        XCTAssertGreaterThan(AriaSigilGeometry.stillPose, 1)
        let a = AriaSigilGeometry.lobe(index: 0, time: AriaSigilGeometry.stillPose, state: .idle, reduceMotion: true)
        let b = AriaSigilGeometry.lobe(index: 0, time: 99, state: .idle, reduceMotion: true)
        XCTAssertEqual(a.x, b.x, accuracy: 0.0001)
        XCTAssertEqual(a.y, b.y, accuracy: 0.0001)
        XCTAssertEqual(a.r, b.r, accuracy: 0.0001)
    }

    func testIdleIsSlowerThanSpeaking() {
        XCTAssertLessThan(AriaSigilGeometry.idleBreathHz, AriaSigilGeometry.speakingBreathHz)
        XCTAssertLessThan(AriaSigilGeometry.idleBreathHz, 0.55)
    }

    func testGazeStaysInsideTheMark() {
        for t in stride(from: 0.0, through: 40, by: 0.37) {
            for state in [AROrbState.idle, .listening, .processing, .speaking] {
                let g = AriaSigilGeometry.gaze(time: t, state: state, reduceMotion: false)
                XCTAssertLessThanOrEqual(abs(g.x), AriaSigilGeometry.maxGaze + 0.0001)
                XCTAssertLessThanOrEqual(abs(g.y), AriaSigilGeometry.maxGaze + 0.0001)
            }
        }
        XCTAssertEqual(AriaSigilGeometry.clampGaze(1), AriaSigilGeometry.maxGaze)
        XCTAssertEqual(AriaSigilGeometry.clampGaze(-1), -AriaSigilGeometry.maxGaze)
    }

    func testLobesMoveWhenAliveAndFreezeWhenReduced() {
        let a = AriaSigilGeometry.lobe(index: 1, time: 0.4, state: .idle, reduceMotion: false)
        let b = AriaSigilGeometry.lobe(index: 1, time: 1.1, state: .idle, reduceMotion: false)
        XCTAssertFalse(abs(a.x - b.x) < 0.00001 && abs(a.y - b.y) < 0.00001 && abs(a.r - b.r) < 0.00001)
        let stillA = AriaSigilGeometry.coreRadius(time: 1, state: .speaking, reduceMotion: true)
        let stillB = AriaSigilGeometry.coreRadius(time: 40, state: .speaking, reduceMotion: true)
        XCTAssertEqual(stillA, stillB, accuracy: 0.0001)
    }

    func testSpeakingCoreIsLargerThanIdle() {
        let idle = AriaSigilGeometry.coreRadius(time: 0.4, state: .idle, reduceMotion: false)
        let talk = AriaSigilGeometry.coreRadius(time: 0.4, state: .speaking, reduceMotion: false)
        XCTAssertGreaterThan(talk, idle)
        XCTAssertLessThan(talk, 0.4)
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
