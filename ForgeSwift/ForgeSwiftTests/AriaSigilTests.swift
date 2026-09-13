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
        XCTAssertEqual(AriaSigilGeometry.idleSpinHz, 0.04, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.speakingSpinHz, 0.075, accuracy: 0.0001)
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

    func testCoveContrastFloor() {
        XCTAssertEqual(AriaSigilGeometry.ringOpacities, [0.40, 0.72, 0.78, 0.45, 0.55])
        XCTAssertEqual(AriaSigilGeometry.contrastFloor, 0.70, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(AriaSigilGeometry.strokeWidthCompact, 1.5)
        XCTAssertGreaterThanOrEqual(
            AriaSigilGeometry.ringOpacities.filter { $0 >= AriaSigilGeometry.contrastFloor }.count,
            2
        )
        XCTAssertEqual(AriaSigilGeometry.contrastRingIndices, [1, 2])
        XCTAssertEqual(AriaSigilGeometry.compactRingIndices.count, 3)
        XCTAssertEqual(AriaSigilGeometry.compactRingIndices, [1, 2, 4])
        XCTAssertEqual(
            AriaSigilGeometry.compactRingIndices.filter { AriaSigilGeometry.ringOpacities[$0] >= 0.70 }.count,
            2
        )
        for index in 0..<AriaSigilGeometry.ellipseCount {
            XCTAssertGreaterThanOrEqual(
                AriaSigilGeometry.strokeWidth(size: AriaSigilGeometry.compactRecommend, index: index),
                AriaSigilGeometry.strokeWidthCompact
            )
        }
        XCTAssertEqual(AriaSigilGeometry.visibleRingIndices(size: 28), AriaSigilGeometry.compactRingIndices)
        XCTAssertEqual(AriaSigilGeometry.visibleRingIndices(size: 90), Array(0..<5))
    }

    func testLexRadiiAndHzUnchanged() {
        XCTAssertEqual(AriaSigilGeometry.radii, [0.38, 0.48, 0.58, 0.68, 0.78])
        XCTAssertEqual(AriaSigilGeometry.eccentricity, [0.1, 0.14, 0.08, 0.16, 0.11])
        XCTAssertEqual(AriaSigilGeometry.tiltDeg, [14, -22, 28, -10, 18])
        XCTAssertEqual(AriaSigilGeometry.phaseOffsets, [0, 0.18, 0.41, 0.63, 0.88])
        XCTAssertEqual(AriaSigilGeometry.idleSpinHz, 0.04, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.speakingSpinHz, 0.075, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.stillPoseAngleDeg, 18, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.strokeWidthHero, 1.85, accuracy: 0.0001)
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
