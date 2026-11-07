import XCTest
@testable import ForgeCore

final class OnDeviceFormCheckTests: XCTestCase {

    func testMissingPersonAsksForReframe() {
        let read = OnDeviceFormCheck.evaluate(
            exerciseName: "Back Squat",
            setLabel: "Set 1",
            cues: [],
            personInFrame: false,
            jointCount: 0
        )
        XCTAssertEqual(read.status, "adjust")
        XCTAssertFalse(read.personInFrame)
        XCTAssertFalse(read.usedFoundationModels)
        XCTAssertFalse(read.summary.contains("188"))
    }

    func testFoundationLineIsUsedWhenPresent() {
        let read = OnDeviceFormCheck.evaluate(
            exerciseName: "Hinge",
            setLabel: "Set 2",
            cues: ["Soft knees"],
            personInFrame: true,
            jointCount: 12,
            foundationLine: "Hips are stacked. Keep the bar close."
        )
        XCTAssertTrue(read.usedFoundationModels)
        XCTAssertEqual(read.status, "good")
        XCTAssertTrue(read.summary.contains("Hips are stacked"))
    }

    func testNeverNeedsANetworkOrFrameUpload() throws {
        // Tests/ForgeCoreTests/ThisFile.swift → ForgeCore/Sources/...
        let production = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ForgeCore/Intelligence/OnDeviceFormCheck.swift")
        let source = try String(contentsOf: production, encoding: .utf8)
        XCTAssertFalse(source.contains("/workouts/form-check"), source)
        XCTAssertFalse(source.contains("image_base64"), source)
        XCTAssertFalse(source.contains("URLSession"), source)
    }
}
