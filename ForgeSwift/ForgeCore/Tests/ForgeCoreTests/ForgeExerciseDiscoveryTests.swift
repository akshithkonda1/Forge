import XCTest
@testable import ForgeCore

final class ForgeExerciseDiscoveryTests: XCTestCase {

    func testFeedbackChangesTheNextSuggestions() {
        let catalog = [
            ForgeExerciseDiscovery.Exercise(id: "goblet", name: "Goblet Squat", equipment: "dumbbell"),
            ForgeExerciseDiscovery.Exercise(id: "curl", name: "Dumbbell Curl", equipment: "dumbbell"),
            ForgeExerciseDiscovery.Exercise(id: "hang", name: "Hang Clean", equipment: "barbell"),
            ForgeExerciseDiscovery.Exercise(id: "pushup", name: "Push-Up", equipment: "bodyweight"),
        ]
        var memory = ForgeExerciseDiscovery.Memory(gymType: "home gym", equipmentNotes: "dumbbells")
        let first = ForgeExerciseDiscovery.rank(
            catalog: catalog,
            memory: memory,
            trainingModel: "intense physical, intense mental",
            goals: ["squat"],
            readiness: 78,
            load: 30,
            engagement: 0.4
        )
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first.first?.id, "goblet")
        XCTAssertFalse(first.contains { $0.id == "hang" }, "barbell should not fit a dumbbell home gym")
        XCTAssertTrue(first.contains { $0.reasons.contains("Adaptive training model") })
        XCTAssertTrue(first.contains { $0.reasons.contains(where: { $0.contains("Score") }) })
        XCTAssertTrue(first.contains { $0.reasons.contains("Past engagement") })
        XCTAssertFalse(first.contains { $0.reasons.joined().lowercased().contains("recovery") })
        XCTAssertTrue(ForgeExerciseDiscovery.suggestLine.lowercased().contains("could try"))
        XCTAssertFalse(ForgeReinforcement.containsBlame(ForgeExerciseDiscovery.suggestLine))

        memory = ForgeExerciseDiscovery.applyFeedback(
            memory, id: "goblet", feedback: .notInterested, catalog: catalog
        )
        let afterSkip = ForgeExerciseDiscovery.rank(
            catalog: catalog,
            memory: memory,
            trainingModel: "intense physical, intense mental",
            goals: ["squat"],
            readiness: 78
        )
        XCTAssertFalse(afterSkip.contains { $0.id == "goblet" })
        XCTAssertFalse(afterSkip.contains { $0.id == "curl" }, "similar dumbbell moves decay with not-interested")
        XCTAssertEqual(afterSkip.first?.id, "pushup")

        memory = ForgeExerciseDiscovery.applyFeedback(memory, id: "pushup", feedback: .tried, catalog: catalog)
        let afterTried = ForgeExerciseDiscovery.rank(
            catalog: catalog,
            memory: memory,
            trainingModel: "intense physical, intense mental",
            goals: ["squat"],
            readiness: 78
        )
        XCTAssertFalse(afterTried.contains { $0.id == "pushup" })
        XCTAssertTrue(memory.tried.contains("pushup"))

        memory = ForgeExerciseDiscovery.Memory(gymType: "home gym", equipmentNotes: "dumbbells")
        memory = ForgeExerciseDiscovery.applyFeedback(memory, id: "goblet", feedback: .saved, catalog: catalog)
        let afterSave = ForgeExerciseDiscovery.rank(
            catalog: catalog,
            memory: memory,
            trainingModel: "intense physical, intense mental",
            goals: ["squat"],
            readiness: 78
        )
        XCTAssertTrue(memory.saved.contains("goblet"))
        XCTAssertFalse(afterSave.contains { $0.id == "goblet" }, "saved moves wait in the later list")
        XCTAssertEqual(afterSave.first?.id, "curl")
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

    func testLearnEquipmentFromChatKeepsUserNotes() {
        let first = ForgeExerciseDiscovery.learnEquipment(notes: "", from: "I train with dumbbells and a rack")
        XCTAssertTrue(first.contains("dumbbell"))
        XCTAssertTrue(first.contains("rack"))
        let kept = ForgeExerciseDiscovery.learnEquipment(notes: first, from: "also a bike on recovery days")
        XCTAssertTrue(kept.contains("dumbbell"))
        XCTAssertTrue(kept.contains("bike"))
        XCTAssertFalse(kept.lowercased().contains("recovery days"))
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
