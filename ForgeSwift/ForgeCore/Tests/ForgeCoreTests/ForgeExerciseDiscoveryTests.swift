import XCTest
@testable import ForgeCore

final class ForgeExerciseDiscoveryTests: XCTestCase {

    func testFeedbackChangesTheNextSuggestions() {
        let catalog = [
            ForgeExerciseDiscovery.Exercise(id: "goblet", name: "Goblet Squat", equipment: "dumbbell"),
            ForgeExerciseDiscovery.Exercise(id: "hang", name: "Hang Clean", equipment: "barbell"),
            ForgeExerciseDiscovery.Exercise(id: "pushup", name: "Push-Up", equipment: "bodyweight"),
        ]
        var memory = ForgeExerciseDiscovery.Memory(gymType: "home gym", equipmentNotes: "dumbbells")
        let first = ForgeExerciseDiscovery.rank(
            catalog: catalog,
            memory: memory,
            trainingModel: "intense physical, intense mental",
            goals: ["strength"],
            readiness: 78
        )
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first.first?.id, "goblet")
        XCTAssertTrue(first.contains { $0.reasons.contains("Adaptive training model") })
        XCTAssertFalse(first.contains { $0.reasons.joined().lowercased().contains("recovery") })

        memory = ForgeExerciseDiscovery.applyFeedback(memory, id: "goblet", feedback: .notInterested)
        let second = ForgeExerciseDiscovery.rank(
            catalog: catalog,
            memory: memory,
            trainingModel: "intense physical, intense mental",
            goals: ["strength"],
            readiness: 78
        )
        XCTAssertFalse(second.contains { $0.id == "goblet" })
        XCTAssertTrue(ForgeExerciseDiscovery.suggestLine.lowercased().contains("could try"))
    }

    func testRankStaysBoundedAtCatalogScale() {
        let catalog = (0..<200).map {
            ForgeExerciseDiscovery.Exercise(id: "e\($0)", name: "Move \($0)", equipment: "dumbbell")
        }
        measure {
            _ = ForgeExerciseDiscovery.rank(
                catalog: catalog,
                memory: ForgeExerciseDiscovery.Memory(gymType: "home gym", equipmentNotes: "dumbbells"),
                trainingModel: "structure",
                goals: ["strength"],
                readiness: 72
            )
        }
    }

    func testThermalShedAndCaps() {
        XCTAssertTrue(ForgeRuntimeGuard.shouldShed(thermal: "serious"))
        XCTAssertTrue(ForgeRuntimeGuard.shouldShed(thermal: "critical"))
        XCTAssertTrue(ForgeRuntimeGuard.shouldShed(thermal: "nominal", memoryWarning: true))
        XCTAssertFalse(ForgeRuntimeGuard.shouldShed(thermal: "nominal"))
        XCTAssertEqual(AriaContextMemory.Caps.sane.vault, 320)
        XCTAssertLessThanOrEqual(AriaContextMemory.Caps.sane.pageSize, 20)
        XCTAssertEqual(ForgeRuntimeGuard.maxFileBytes, 512_000)
        XCTAssertTrue(ForgeRuntimeGuard.compactOffMainThread)
    }
}
