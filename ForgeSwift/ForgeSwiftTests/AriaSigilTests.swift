import XCTest
@testable import ForgeSwift

/// Locks the kinetic orange ring-field: five ellipses, `#FF4D00`, freeze on Reduce Motion.
final class AriaSigilTests: XCTestCase {

    func testFiveEllipsesOrangeAndStillPose() {
        XCTAssertEqual(AriaSigilGeometry.ellipseCount, 5)
        XCTAssertEqual(AriaSigilGeometry.forgeOrangeHex, "FF4D00")
        XCTAssertEqual(AriaSigilPalette.forgeOrangeHex, "FF4D00")
        XCTAssertEqual(AriaSigilPalette.emberHex, "FF4D00")
        XCTAssertEqual(AriaSigilGeometry.stillPose, 1.72, accuracy: 0.0001)
        let a = AriaSigilGeometry.ellipse(index: 0, time: AriaSigilGeometry.stillPose, state: .idle, reduceMotion: true)
        let b = AriaSigilGeometry.ellipse(index: 0, time: 99, state: .idle, reduceMotion: true)
        XCTAssertEqual(a.rx, b.rx, accuracy: 0.0001)
        XCTAssertEqual(a.ry, b.ry, accuracy: 0.0001)
        XCTAssertEqual(a.rotation, b.rotation, accuracy: 0.0001)
        XCTAssertEqual(a.opacity, b.opacity, accuracy: 0.0001)
    }

    func testStillPoseIgnoresStateAndClock() {
        let idle = AriaSigilGeometry.ellipse(index: 2, time: 1, state: .idle, reduceMotion: true)
        let talk = AriaSigilGeometry.ellipse(index: 2, time: 40, state: .speaking, reduceMotion: true)
        XCTAssertEqual(idle.rx, talk.rx, accuracy: 0.0001)
        XCTAssertEqual(idle.ry, talk.ry, accuracy: 0.0001)
        XCTAssertEqual(idle.rotation, talk.rotation, accuracy: 0.0001)
    }

    func testIdleSpinIsSofterThanSpeaking() {
        XCTAssertLessThan(AriaSigilGeometry.idleSpinHz, AriaSigilGeometry.speakingSpinHz)
        XCTAssertLessThan(AriaSigilGeometry.idleSpinHz, 0.20)
        XCTAssertLessThan(AriaSigilGeometry.speakingSpinHz, 0.25)
    }

    func testEllipsesMoveWhenAliveAndFreezeWhenReduced() {
        let a = AriaSigilGeometry.ellipse(index: 1, time: 0.4, state: .idle, reduceMotion: false)
        let b = AriaSigilGeometry.ellipse(index: 1, time: 1.1, state: .idle, reduceMotion: false)
        XCTAssertFalse(
            abs(a.rotation - b.rotation) < 0.00001
                && abs(a.rx - b.rx) < 0.00001
                && abs(a.ry - b.ry) < 0.00001
        )
        let stillA = AriaSigilGeometry.ellipse(index: 4, time: 1, state: .speaking, reduceMotion: true)
        let stillB = AriaSigilGeometry.ellipse(index: 4, time: 40, state: .speaking, reduceMotion: true)
        XCTAssertEqual(stillA.rotation, stillB.rotation, accuracy: 0.0001)
    }

    func testFiveRingsOverlapAtDistinctTilts() {
        var rotations = Set<String>()
        for index in 0..<AriaSigilGeometry.ellipseCount {
            let pose = AriaSigilGeometry.ellipse(
                index: index,
                time: AriaSigilGeometry.stillPose,
                state: .idle,
                reduceMotion: true
            )
            XCTAssertGreaterThan(pose.rx, pose.ry)
            XCTAssertGreaterThan(pose.ry, 0.3)
            XCTAssertLessThan(pose.rx, 1.05)
            rotations.insert(String(format: "%.4f", pose.rotation))
        }
        XCTAssertEqual(rotations.count, AriaSigilGeometry.ellipseCount)
    }

    func testStrokeWidthStaysVisibleAtTabAndHero() {
        XCTAssertGreaterThanOrEqual(AriaSigilGeometry.strokeWidth(size: 22, index: 0), 1.15)
        XCTAssertGreaterThan(AriaSigilGeometry.strokeWidth(size: 168, index: 0), 3)
    }

    func testMeetCopyIsARIANotAForgePairing() {
        XCTAssertEqual(AriaMeetCopy.title, "This is ARIA")
        XCTAssertTrue(AriaMeetCopy.lead.contains("designed for Forge"))
        XCTAssertFalse(AriaMeetCopy.lead.contains(AriaMeetCopy.pairingForbidden))
        XCTAssertFalse(AriaMeetCopy.title.contains("FORGE"))
        XCTAssertEqual(AriaMeetCopy.capabilities.count, 4)
    }

    func testPaletteStaysPreciousNotNeon() {
        XCTAssertEqual(AriaSigilPalette.goldHex, "C9A36A")
        XCTAssertEqual(AriaSigilPalette.voidDeepHex, "030207")
        XCTAssertEqual(AriaSigilPalette.bloodHex, "4A1018")
        XCTAssertEqual(AriaSigilPalette.ivoryHex, "F3EBDD")
        XCTAssertEqual(AriaSigilPalette.emberHex, "FF4D00")
        XCTAssertNotEqual(AriaSigilPalette.photonPrimary(for: .energized), "00D2FF")
        XCTAssertNotEqual(AriaSigilPalette.photonPrimary(for: .focused), "22C55E")
    }

    func testRetiredEmberIsNotTheBrandMark() {
        XCTAssertEqual(AriaSigilEmberLegacy.lobeCount, 4)
        XCTAssertEqual(AriaSigilEmberLegacy.hearthHex, "FF6A1A")
        XCTAssertNotEqual(AriaSigilEmberLegacy.hearthHex, AriaSigilGeometry.forgeOrangeHex)
        XCTAssertNotEqual(AriaSigilEmberLegacy.lobeCount, AriaSigilGeometry.ellipseCount)
    }
}
