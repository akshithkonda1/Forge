import XCTest
@testable import ForgeCore

final class ForgeStabilityTests: XCTestCase {

    func testThermalAndMemoryShedNonessentialWork() {
        XCTAssertTrue(ForgeRuntimeGuard.shouldShed(thermal: "serious"))
        XCTAssertTrue(ForgeRuntimeGuard.shouldShed(thermal: "critical"))
        XCTAssertTrue(ForgeRuntimeGuard.shouldShed(thermal: "nominal", memoryWarning: true))
        XCTAssertFalse(ForgeRuntimeGuard.shouldShed(thermal: "nominal"))
        XCTAssertEqual(ForgeRuntimeGuard.thermalLabel("ProcessInfo.ThermalState.serious"), "serious")
        XCTAssertTrue(ForgeRuntimeGuard.compactOffMainThread)
        XCTAssertTrue(ForgeRuntimeGuard.noAlwaysOnTimers)
        XCTAssertTrue(ForgeRuntimeGuard.noPolling)
        XCTAssertEqual(ForgeRuntimeGuard.clockHzCap, 12)
        XCTAssertTrue(ForgeRuntimeGuard.clockPausedWhenIdle)
        XCTAssertLessThanOrEqual(HomeReadinessTokens.eventHz, HomeReadinessTokens.eventHzCeiling)
        XCTAssertEqual(Int(HomeReadinessTokens.eventHzCeiling), ForgeRuntimeGuard.clockHzCap)
        XCTAssertFalse(
            HomeReadinessTokens.shouldRunClock(
                reduceMotion: false, sceneActive: true, onscreen: true, eventGlow: false
            )
        )
    }

    func testContextStoreCapsAndFileBudgetAtLargeSize() {
        var snap = AriaContextMemory.Snapshot(caps: .sane)
        let start = Date()
        for i in 0..<ForgeRuntimeGuard.largeStoreFacts {
            snap = AriaContextMemory.ingest(
                snap,
                text: "I slept \(6 + i % 3) hours and walked after pottery",
                source: "chat",
                now: Date(timeIntervalSince1970: 1_700_000_000 + Double(i))
            )
        }
        snap = AriaContextMemory.compact(snap)
        XCTAssertLessThanOrEqual(snap.items.filter { $0.layer == .stm && $0.isActive }.count, snap.caps.stm)
        XCTAssertLessThanOrEqual(snap.items.filter { $0.layer == .vault && $0.isActive }.count, snap.caps.vault)
        let fitted = AriaContextMemoryStore.fitToFileBudget(snap)
        let data = try? JSONEncoder().encode(fitted)
        XCTAssertNotNil(data)
        XCTAssertLessThanOrEqual(data?.count ?? 0, ForgeRuntimeGuard.maxFileBytes)
        XCTAssertLessThan(
            Date().timeIntervalSince(start),
            ForgeRuntimeGuard.storeCompactBaselineSeconds
        )
        let page = AriaContextMemory.retrieve(fitted)
        XCTAssertLessThanOrEqual(page.items.count, fitted.caps.pageSize)
    }

    func testStoreAndDiscoveryUseClockCPUAndMemoryMetrics() {
        var snap = AriaContextMemory.Snapshot()
        for i in 0..<80 {
            snap = AriaContextMemory.ingest(
                snap,
                text: "I slept well and stretched \(i)",
                source: "chat"
            )
        }
        let catalog = (0..<120).map {
            ForgeExerciseDiscovery.Exercise(id: "e\($0)", name: "Move \($0)", equipment: "dumbbell")
        }
        let memory = ForgeExerciseDiscovery.Memory(gymType: "home gym", equipmentNotes: "dumbbells")
        let rankStart = Date()
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            _ = AriaContextMemory.compact(snap)
            _ = AriaContextMemory.retrieve(snap)
            _ = ForgeExerciseDiscovery.rank(
                catalog: catalog,
                memory: memory,
                trainingModel: "structure",
                goals: ["strength"],
                readiness: 72,
                load: 40,
                engagement: 0.4
            )
        }
        XCTAssertLessThan(
            Date().timeIntervalSince(rankStart),
            ForgeRuntimeGuard.discoveryRankBaselineSeconds + 8
        )
    }

    func testSmokeHomeOnboardingTutorialSoulAndDiscovery() {
        XCTAssertEqual(HomeReadinessTokens.Band.allCases.map(\.label), ["Peak", "Good", "Fair", "Low"])
        XCTAssertEqual(HomeReadinessTokens.tickCount, 0)
        XCTAssertFalse(HomeReadinessTokens.scanlines)
        XCTAssertFalse(HomeReadinessTokens.brackets)

        let paused = ForgeTutorial.State(beat: .welcome, ariaPaused: true)
        let walked = ForgeTutorial.apply(state: paused, gesture: .acknowledge, latency: 0.4)
        XCTAssertEqual(walked.state.beat, .home)
        let skipped = ForgeTutorial.apply(state: walked.state, gesture: .skip, latency: 0)
        XCTAssertTrue(skipped.state.isComplete)

        var live = AriaSoul.Config(blend: .coach)
        let first = AriaSoul.nextReply(draft: "Next move is easy.", config: live)
        live = AriaSoul.Config(blend: .friend)
        let second = AriaSoul.nextReply(draft: "Next move is easy.", config: live)
        XCTAssertNotEqual(first.soul, second.soul)

        var discovery = ForgeExerciseDiscovery.Memory(gymType: "home gym", equipmentNotes: "dumbbells")
        let catalog = [
            ForgeExerciseDiscovery.Exercise(id: "goblet", name: "Goblet Squat", equipment: "dumbbell"),
            ForgeExerciseDiscovery.Exercise(id: "pushup", name: "Push-Up", equipment: "bodyweight"),
        ]
        let ranked = ForgeExerciseDiscovery.rank(
            catalog: catalog, memory: discovery, trainingModel: "steady", goals: ["squat"], readiness: 80
        )
        XCTAssertEqual(ranked.first?.id, "goblet")
        discovery = ForgeExerciseDiscovery.applyFeedback(discovery, id: "goblet", feedback: .tried, catalog: catalog)
        let next = ForgeExerciseDiscovery.rank(
            catalog: catalog, memory: discovery, trainingModel: "steady", goals: [], readiness: 80
        )
        XCTAssertEqual(next.first?.id, "pushup")
        XCTAssertFalse(AriaSoul.containsRailBreak(ForgeExerciseDiscovery.suggestLine))
    }
}
