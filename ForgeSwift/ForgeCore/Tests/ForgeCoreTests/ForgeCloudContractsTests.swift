import XCTest
@testable import ForgeCore

final class ForgeCloudContractsTests: XCTestCase {

    private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testWorkoutPlanRichCardReadsNestedExercises() throws {
        let json = """
        {
          "type": "workout-plan",
          "data": {
            "id": "w1",
            "name": "Upper Body Power",
            "duration": 55,
            "exercises": [
              { "name": "Barbell Bench Press", "sets": 4, "reps": "6-8" },
              { "name": "Weighted Pull-Ups", "sets": 4, "reps": 8 }
            ]
          }
        }
        """
        let card = try decode(json, as: CloudRichCard.self)
        XCTAssertTrue(card.isWorkoutPlan)
        XCTAssertEqual(card.workoutName, "Upper Body Power")
        XCTAssertEqual(card.durationMinutes, 55)
        XCTAssertEqual(card.exercises.count, 2)
        XCTAssertEqual(card.exercises[0].name, "Barbell Bench Press")
        XCTAssertEqual(card.exercises[0].sets, 4)
        XCTAssertEqual(card.exercises[0].reps, "6-8")
        XCTAssertEqual(card.exercises[1].reps, "8")
        XCTAssertEqual(card.type, "workout-plan")
    }

    func testSnakeCaseChatEnvelopeStillDecodes() throws {
        let json = """
        {
          "type": "workout_plan",
          "workout_name": "Recovery Flow",
          "duration_minutes": 30,
          "exercises": [{ "name": "Walk", "sets": 1, "reps": "20 min" }]
        }
        """
        let card = try decode(json, as: CloudRichCard.self)
        XCTAssertTrue(card.isWorkoutPlan)
        XCTAssertEqual(card.workoutName, "Recovery Flow")
        XCTAssertEqual(card.durationMinutes, 30)
        XCTAssertEqual(card.exercises.first?.name, "Walk")
    }

    func testDataChartNestedPayload() throws {
        let json = """
        {
          "type": "data-chart",
          "data": {
            "title": "Sleep Quality (7-day)",
            "values": [72, 80, 68],
            "insight": "Average sleep score: 73.",
            "color": "3B82F6"
          }
        }
        """
        let card = try decode(json, as: CloudRichCard.self)
        XCTAssertTrue(card.isDataChart)
        XCTAssertEqual(card.title, "Sleep Quality (7-day)")
        XCTAssertEqual(card.values, [72, 80, 68])
        XCTAssertEqual(card.insight, "Average sleep score: 73.")
        XCTAssertEqual(card.color, "3B82F6")
    }

    func testChatThreadMergesCamelCaseRichCard() throws {
        let json = """
        {
          "threadId": "current",
          "messages": [
            {
              "id": "user-1",
              "role": "user",
              "content": "What should I train?",
              "timestamp": "2026-05-06T13:00:00+00:00"
            },
            {
              "id": "m4",
              "role": "trainer",
              "content": "Upper body power.",
              "timestamp": "2026-05-06T13:00:10+00:00",
              "richCard": {
                "type": "workout-plan",
                "data": { "name": "Upper Body Power", "duration": 55, "exercises": [] }
              }
            }
          ]
        }
        """
        let thread = try decode(json, as: CloudChatThread.self)
        XCTAssertEqual(thread.threadId, "current")
        XCTAssertEqual(thread.messages.count, 2)
        XCTAssertTrue(thread.looksLikeDemoSeed == false)
        XCTAssertEqual(thread.messages[1].richCard?.workoutName, "Upper Body Power")
        XCTAssertTrue(thread.messages[1].isDemoSeed)
    }

    func testDemoSeedDetectionRequiresAllDefaultIds() throws {
        let thread = CloudChatThread(
            threadId: "current",
            messages: [
                CloudChatMessage(id: "m1", role: "trainer", content: "Hi", timestamp: Date()),
                CloudChatMessage(id: "m2", role: "user", content: "Hey", timestamp: Date()),
                CloudChatMessage(id: "m3", role: "trainer", content: "Plan", timestamp: Date()),
                CloudChatMessage(id: "m4", role: "trainer", content: "Card", timestamp: Date()),
            ]
        )
        XCTAssertTrue(thread.looksLikeDemoSeed)
    }

    func testHealthBatchCanonicalizesAliases() {
        let metrics = CloudHealthMetricType.metrics(from: [
            (type: "active_calories", value: 420, unit: "kcal", timestamp: "2026-09-07T12:00:00Z", source: "HealthKit"),
            (type: "resting_hr", value: 54, unit: "bpm", timestamp: "2026-09-07T12:00:00Z", source: "apple-health"),
            (type: "sleep", value: 420, unit: "min", timestamp: "2026-09-07T12:00:00Z", source: "apple-health"),
            (type: "hrv", value: 48, unit: "ms", timestamp: "2026-09-07T12:00:00Z", source: "oura"),
        ])
        XCTAssertEqual(metrics.map(\.metricType), ["active-calories", "resting-heart-rate", "hrv"])
        XCTAssertEqual(metrics[0].source, "apple-health")
        XCTAssertEqual(metrics[2].source, "oura")
    }

    func testDashboardPrefersComputedReadinessOverEmpty() throws {
        let json = """
        {
          "readiness": { "overall": 74, "sleepQuality": 80, "recoveryScore": 70, "stressLevel": 30, "energyBank": 74, "available": true },
          "dailyMetrics": { "date": "2026-09-07", "steps": 8120, "hrv": 49, "sources": ["apple-health"] },
          "todayWorkout": { "name": "Recovery Flow", "type": "mobility", "duration": 30, "intensity": "low", "exercises": [] },
          "recentSleep": [],
          "recentWorkouts": [],
          "personalRecords": [],
          "connections": [{ "provider": "apple-health", "status": "connected" }]
        }
        """
        let dash = try decode(json, as: CloudDashboardToday.self)
        XCTAssertTrue(dash.readiness?.isUsable == true)
        XCTAssertEqual(dash.readiness?.overall, 74)
        XCTAssertEqual(dash.dailyMetrics?.sources, ["apple-health"])
        XCTAssertEqual(dash.todayWorkout?.name, "Recovery Flow")
        XCTAssertEqual(CloudSourceLabel.displayName(for: "apple-health"), "Apple Health")
        XCTAssertEqual(CloudSourceLabel.displayName(for: "oura"), "Oura via Terra")
    }

    func testEmptyReadinessIsNotUsable() throws {
        let json = """
        { "overall": null, "sleepQuality": null, "available": false }
        """
        let readiness = try decode(json, as: CloudReadiness.self)
        XCTAssertFalse(readiness.isUsable)
    }

    func testCoachPlanAndSleepInsight() throws {
        let planJSON = """
        {
          "baseline": { "focus": "recovery", "suggestedType": "mobility", "intensity": "low" },
          "todayPlan": { "name": "Recovery Focus", "duration": 40, "type": "mobility", "intensity": "low", "exercises": [] },
          "explanation": "Keep volume easy after a short night.",
          "fallback": true
        }
        """
        let plan = try decode(planJSON, as: CloudCoachWorkoutPlan.self)
        XCTAssertEqual(plan.todayPlan?.name, "Recovery Focus")
        XCTAssertEqual(plan.baseline?.focus, "recovery")
        XCTAssertTrue(plan.fallback)

        let sleep = try decode(
            """
            { "insight": "Protect a consistent wind-down.", "fallback": false }
            """,
            as: CloudCoachSleepInsight.self
        )
        XCTAssertEqual(sleep.insight, "Protect a consistent wind-down.")
    }
}
