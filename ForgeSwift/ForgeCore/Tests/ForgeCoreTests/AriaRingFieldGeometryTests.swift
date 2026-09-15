import XCTest
@testable import ForgeCore

/// Locks the kinetic orange ring-field shared by phone and Watch.
final class AriaRingFieldGeometryTests: XCTestCase {

    func testMatchesLexRingFieldContract() {
        XCTAssertEqual(AriaRingFieldGeometry.kind, "ring-field")
        XCTAssertEqual(AriaRingFieldGeometry.assetName, "AriaMark")
        XCTAssertEqual(AriaRingFieldGeometry.ringCount, 5)
        XCTAssertEqual(AriaRingFieldGeometry.ellipseCount, 5)
        XCTAssertEqual(AriaRingFieldGeometry.forgeOrangeHex, "FF4D00")
        XCTAssertEqual(AriaRingFieldGeometry.brandHueLightHex, "FF6B2B")
        XCTAssertEqual(AriaRingFieldGeometry.radii, [0.38, 0.48, 0.58, 0.68, 0.78])
        XCTAssertEqual(AriaRingFieldGeometry.eccentricity, [0.1, 0.14, 0.08, 0.16, 0.11])
        XCTAssertEqual(AriaRingFieldGeometry.tiltDeg, [14, -22, 28, -10, 18])
        XCTAssertEqual(AriaRingFieldGeometry.phaseOffsets, [0, 0.18, 0.41, 0.63, 0.88])
        XCTAssertEqual(AriaRingFieldGeometry.ringOpacities, [0.40, 0.72, 0.78, 0.45, 0.55])
        XCTAssertEqual(AriaRingFieldGeometry.idleSpinHz, 0.04, accuracy: 0.0001)
        XCTAssertEqual(AriaRingFieldGeometry.speakingSpinHz, 0.075, accuracy: 0.0001)
        XCTAssertEqual(AriaRingFieldGeometry.stillPoseAngleDeg, 18, accuracy: 0.0001)
        XCTAssertEqual(AriaRingFieldGeometry.strokeWidthCompact, 1.5, accuracy: 0.0001)
        XCTAssertEqual(AriaRingFieldGeometry.strokeWidthHero, 1.85, accuracy: 0.0001)
        XCTAssertEqual(AriaRingFieldGeometry.heroMinimumSize, 90)
        XCTAssertEqual(AriaRingFieldGeometry.compactRecommend, 28)
        XCTAssertLessThan(AriaRingFieldGeometry.idleSpinHz, AriaRingFieldGeometry.speakingSpinHz)
    }

    func testCoveContrastFloorAndCompactThreeRing() {
        XCTAssertEqual(AriaRingFieldGeometry.contrastFloor, 0.70, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(
            AriaRingFieldGeometry.ringOpacities.filter { $0 >= AriaRingFieldGeometry.contrastFloor }.count,
            2
        )
        XCTAssertEqual(AriaRingFieldGeometry.contrastRingIndices, [1, 2])
        XCTAssertEqual(AriaRingFieldGeometry.compactRingIndices, [1, 2, 4])
        XCTAssertEqual(AriaRingFieldGeometry.compactRingIndices.count, 3)
        XCTAssertEqual(
            AriaRingFieldGeometry.compactRingIndices.filter {
                AriaRingFieldGeometry.ringOpacities[$0] >= 0.70
            }.count,
            2
        )
        XCTAssertEqual(
            AriaRingFieldGeometry.visibleRingIndices(size: 32),
            AriaRingFieldGeometry.compactRingIndices
        )
        XCTAssertEqual(
            AriaRingFieldGeometry.visibleRingIndices(size: AriaRingFieldGeometry.compactRecommend),
            AriaRingFieldGeometry.compactRingIndices
        )
        XCTAssertEqual(
            AriaRingFieldGeometry.visibleRingIndices(size: 89),
            AriaRingFieldGeometry.compactRingIndices
        )
        XCTAssertEqual(
            AriaRingFieldGeometry.visibleRingIndices(size: 90),
            Array(0..<5)
        )
        XCTAssertEqual(
            AriaRingFieldGeometry.strokeWidth(size: 32),
            AriaRingFieldGeometry.strokeWidthCompact
        )
        XCTAssertEqual(
            AriaRingFieldGeometry.strokeWidth(size: 90),
            AriaRingFieldGeometry.strokeWidthHero
        )
    }

    func testReduceMotionFreezesAtStillPoseAngle() {
        let a = AriaRingFieldGeometry.ellipse(index: 0, time: 1, speaking: false, reduceMotion: true)
        let b = AriaRingFieldGeometry.ellipse(index: 0, time: 99, speaking: true, reduceMotion: true)
        XCTAssertEqual(a.rx, b.rx, accuracy: 0.0001)
        XCTAssertEqual(a.ry, b.ry, accuracy: 0.0001)
        XCTAssertEqual(a.rotation, b.rotation, accuracy: 0.0001)
        XCTAssertEqual(a.opacity, b.opacity, accuracy: 0.0001)

        let expected =
            AriaRingFieldGeometry.tiltDeg[0] * .pi / 180
            + AriaRingFieldGeometry.phaseOffsets[0] * .pi * 2
            + AriaRingFieldGeometry.stillPoseAngleDeg * .pi / 180
        XCTAssertEqual(a.rotation, expected, accuracy: 0.0001)
    }

    func testIdleRingsSpinAndSpeakingIsFaster() {
        let a = AriaRingFieldGeometry.ellipse(index: 1, time: 0.4, speaking: false, reduceMotion: false)
        let b = AriaRingFieldGeometry.ellipse(index: 1, time: 1.1, speaking: false, reduceMotion: false)
        XCTAssertGreaterThan(abs(a.rotation - b.rotation), 0.00001)

        let idleDelta =
            AriaRingFieldGeometry.ellipse(index: 1, time: 1.1, speaking: false, reduceMotion: false).rotation
            - AriaRingFieldGeometry.ellipse(index: 1, time: 0, speaking: false, reduceMotion: false).rotation
        let talkDelta =
            AriaRingFieldGeometry.ellipse(index: 1, time: 1.1, speaking: true, reduceMotion: false).rotation
            - AriaRingFieldGeometry.ellipse(index: 1, time: 0, speaking: true, reduceMotion: false).rotation
        XCTAssertGreaterThan(talkDelta, idleDelta)
        XCTAssertEqual(AriaRingFieldGeometry.spinHz(speaking: false), AriaRingFieldGeometry.idleSpinHz)
        XCTAssertEqual(AriaRingFieldGeometry.spinHz(speaking: true), AriaRingFieldGeometry.speakingSpinHz)
    }

    func testFiveRingsOverlapAtDistinctTilts() {
        var rotations = Set<String>()
        for index in 0..<AriaRingFieldGeometry.ellipseCount {
            let pose = AriaRingFieldGeometry.ellipse(
                index: index,
                time: AriaRingFieldGeometry.stillPose,
                speaking: false,
                reduceMotion: true
            )
            XCTAssertGreaterThan(pose.rx, pose.ry)
            XCTAssertGreaterThan(pose.ry, 0.3)
            XCTAssertLessThan(pose.rx, 1.05)
            rotations.insert(String(format: "%.4f", pose.rotation))
        }
        XCTAssertEqual(rotations.count, AriaRingFieldGeometry.ellipseCount)
    }
}
