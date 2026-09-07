import XCTest
@testable import ForgeSwift
import ForgeCore

/// Locks the dummy orchestra as a local fill-in for the unfinished backend:
/// multi-causal turns, transcript follow-ups, Forge-local events, refer-out,
/// and no off-device LLM.
@MainActor
final class AriaDummyOrchestratorTests: XCTestCase {

    func testStaysLocalFillIn() {
        XCTAssertFalse(AriaDummyOrchestrator.usesOffDeviceLLM)
        XCTAssertFalse(AriaDummyOrchestrator.writesCalendarEvents)
        XCTAssertFalse(AriaDummyTurn.usesOffDeviceLLM)
        XCTAssertFalse(AriaDummyTurn.writesCalendarEvents)
    }

    func testClausesSplitMultiIntentButKeepDecimals() {
        let parts = AriaDummyTurn.clauses(
            in: "I slept badly — what should I train and eat?"
        )
        XCTAssertGreaterThanOrEqual(parts.count, 2)
        XCTAssertTrue(parts.contains { $0.lowercased().contains("slept") })
        XCTAssertTrue(parts.contains { $0.lowercased().contains("train") })
        XCTAssertTrue(parts.contains { $0.lowercased().contains("eat") })
        XCTAssertEqual(
            AriaDummyTurn.clauses(in: "Rest 2.5 minutes then go."),
            ["Rest 2.5 minutes then go."]
        )
        XCTAssertEqual(AriaDummyTurn.clauses(in: ""), [])
    }

    func testFollowUpTable() {
        XCTAssertEqual(AriaDummyTurn.followUp(in: "make it easier"), .easier)
        XCTAssertEqual(AriaDummyTurn.followUp(in: "skip it"), .decline)
        XCTAssertEqual(AriaDummyTurn.followUp(in: "do it"), .accept)
        XCTAssertEqual(AriaDummyTurn.followUp(in: "less legs"), .lessLegs)
        XCTAssertEqual(AriaDummyTurn.followUp(in: "what about sleep"), .askSleep)
        XCTAssertEqual(
            AriaDummyTurn.followUp(in: "I slept badly — what should I train and eat?"),
            .none
        )
    }

    func testReminderIsForgeLocalNotCalendar() {
        let water = AriaDummyTurn.reminder(in: "remind me to drink water")
        XCTAssertEqual(water, .scheduleReminder(kind: .hydration, hour: nil))
        let meal = AriaDummyTurn.reminder(in: "remind me to eat at 1")
        XCTAssertEqual(meal, .scheduleReminder(kind: .meal, hour: 13))
        XCTAssertNil(AriaDummyTurn.reminder(in: "what should I eat"))
    }

    func testInterpretUnionsSleepTrainEat() {
        let signals = AriaIntentInput(
            text: "I slept badly — what should I train and eat?",
            readiness: 48,
            sleepMinutesLastNight: 300,
            consecutiveShortNights: 2,
            rememberedFacts: []
        )
        let turn = AriaDummyTurn.interpret(
            text: "I slept badly — what should I train and eat?",
            agent: .aria,
            agents: [.sleep, .workout, .lifestyle],
            signals: signals,
            sleepWeak: true,
            readinessLow: true
        )
        XCTAssertTrue(turn.domains.contains(.sleep))
        XCTAssertTrue(turn.domains.contains(.training))
        XCTAssertTrue(turn.domains.contains(.nutrition))
        XCTAssertTrue(turn.keepLight)
        XCTAssertEqual(turn.primaryAgent, .workout)
    }

    func testKneeConstrainsPlanInput() {
        let signals = AriaIntentInput(
            text: "knee is angry, skip legs, still train",
            rememberedFacts: ["Injury context: knee"]
        )
        let turn = AriaDummyTurn.interpret(
            text: "knee is angry, skip legs, still train",
            agent: .workout,
            agents: [.workout],
            signals: signals,
            sleepWeak: false,
            readinessLow: false
        )
        XCTAssertTrue(turn.skipLegs)
        XCTAssertTrue(turn.joints.contains("knee"))
        XCTAssertTrue(turn.constrainedPlanInput.lowercased().contains("skip legs"))
    }

    func testReferOutShortCircuitsBeforeTraining() async {
        let store = makeStore()
        let reply = await AriaDummyOrchestrator.reply(
            text: "I have chest pain, what should I train?",
            store: store,
            agent: .workout,
            agents: ["workout"]
        )
        let lower = reply.message.lowercased()
        XCTAssertTrue(lower.contains("chest") || lower.contains("emergency") || lower.contains("medical"))
        XCTAssertNil(reply.richCard)
        XCTAssertTrue(reply.confidenceReason?.contains("referred out") == true)
    }

    func testIdentityStillShortCircuits() async {
        let store = makeStore()
        let reply = await AriaDummyOrchestrator.reply(
            text: "Who are you?",
            store: store,
            agent: .aria
        )
        XCTAssertTrue(reply.message.contains("I'm ARIA"))
    }

    func testMultiIntentReplyMentionsSleepSessionAndFood() async {
        let store = makeStore()
        store.sleepData = [
            SleepData(
                date: "2026-09-07",
                totalHours: 5.0,
                deepMinutes: 40,
                remMinutes: 50,
                lightMinutes: 180,
                awakeMinutes: 30,
                score: 48
            )
        ]
        store.readiness = ReadinessData(
            overall: 46,
            sleepQuality: 42,
            recoveryScore: 44,
            stressLevel: 60,
            energyBank: 40
        )
        let text = "I slept badly — what should I train and eat?"
        let reply = await AriaDummyOrchestrator.reply(
            text: text,
            store: store,
            agent: .workout,
            agents: ["sleep", "workout", "lifestyle"]
        )
        let lower = reply.message.lowercased()
        XCTAssertTrue(
            lower.contains("sleep") || lower.contains("night") || lower.contains("slept"),
            "expected a sleep cause in \(reply.message)"
        )
        XCTAssertTrue(
            lower.contains("minute") || lower.contains("session") || store.todayWorkout != nil,
            "expected a session in \(reply.message)"
        )
        XCTAssertTrue(
            lower.contains("eat") || lower.contains("food") || lower.contains("protein"),
            "expected a food beat in \(reply.message)"
        )
        XCTAssertEqual(reply.richCard?.type, "workout_plan")
        XCTAssertNotNil(store.todayWorkout)
        XCTAssertTrue(reply.confidenceReason?.contains("Local fill-in") == true)
    }

    func testKneePlanIsNotHeavyLegs() async throws {
        let store = makeStore()
        store.durableMemoryAnchors = ["Injury context: knee"]
        let reply = await AriaDummyOrchestrator.reply(
            text: "knee is angry, skip legs, still train",
            store: store,
            agent: .workout,
            agents: ["workout"]
        )
        let workout = try XCTUnwrap(store.todayWorkout)
        XCTAssertFalse(
            workout.exercises.contains { AriaDummyTurn.isLegMove($0.name) && workout.exercises.count > 2 },
            "leg-heavy session leaked through: \(workout.exercises.map(\.name))"
        )
        XCTAssertTrue(
            workout.name.lowercased().contains("upper")
                || workout.exercises.contains { !AriaDummyTurn.isLegMove($0.name) }
        )
        XCTAssertTrue(store.durableMemoryAnchors.contains { $0.lowercased().contains("knee") })
        XCTAssertTrue(reply.message.lowercased().contains("leg") || reply.message.lowercased().contains("knee"))
    }

    func testFollowUpEasierMutatesTodayWorkout() async {
        let store = makeStore()
        store.todayWorkout = WorkoutPlan(
            id: "t1",
            name: "Heavy Lower",
            type: .strength,
            duration: 55,
            intensity: .high,
            exercises: [
                Exercise(id: "e1", name: "Back Squat", sets: 4, reps: "5", weight: nil, restSeconds: 120, notes: nil)
            ]
        )
        let reply = await AriaDummyOrchestrator.reply(
            text: "make it easier",
            store: store,
            agent: .aria
        )
        XCTAssertEqual(store.todayWorkout?.intensity, .moderate)
        XCTAssertTrue(reply.message.lowercased().contains("scaled") || reply.message.lowercased().contains("moderate"))
        XCTAssertTrue(AriaDummyOrchestrator.lastAppliedActions.contains(.scaleEasier))
    }

    func testWaterReminderCreatesLocalEventNotCalendar() async {
        let store = makeStore()
        SmartNotificationManager.shared.scheduledReminders.removeAll {
            $0.id.hasPrefix("aria.dummy")
        }
        let reply = await AriaDummyOrchestrator.reply(
            text: "remind me to drink water",
            store: store,
            agent: .lifestyle,
            agents: ["lifestyle"]
        )
        XCTAssertTrue(
            SmartNotificationManager.shared.scheduledReminders.contains { $0.id == "aria.dummy.hydration" }
        )
        XCTAssertTrue(
            AriaDummyOrchestrator.lastAppliedActions.contains {
                if case .scheduleReminder(let kind, _) = $0 { return kind == .hydration }
                return false
            }
        )
        XCTAssertTrue(reply.message.lowercased().contains("water") || reply.message.lowercased().contains("nudge"))
        XCTAssertFalse(AriaDummyOrchestrator.writesCalendarEvents)
    }

    func testLogsWaterWithoutOffDeviceLLM() async {
        let store = makeStore()
        let reply = await AriaDummyOrchestrator.reply(
            text: "log that I drank water",
            store: store,
            agent: .lifestyle,
            agents: ["lifestyle"]
        )
        XCTAssertTrue(
            AriaDummyOrchestrator.lastAppliedActions.contains {
                if case .logWater(let ml) = $0 { return ml >= 200 }
                return false
            }
        )
        XCTAssertTrue(reply.message.lowercased().contains("water"))
        XCTAssertTrue(store.durableMemoryAnchors.contains { $0.lowercased().contains("water") })
        XCTAssertFalse(AriaDummyOrchestrator.usesOffDeviceLLM)
    }

    func testWritesANoteToTheBoard() async {
        let store = makeStore()
        let reply = await AriaDummyOrchestrator.reply(
            text: "write that down: race on Saturday",
            store: store,
            agent: .aria
        )
        XCTAssertTrue(
            AriaDummyOrchestrator.lastAppliedActions.contains {
                if case .writeNote(let note) = $0 { return note.lowercased().contains("race") }
                return false
            }
        )
        XCTAssertTrue(store.durableMemoryAnchors.contains { $0.lowercased().contains("race") })
        XCTAssertTrue(reply.message.lowercased().contains("race") || reply.message.lowercased().contains("wrote"))
    }

    func testCalisthenicsAskPullsLibraryMoves() async throws {
        let store = makeStore()
        let reply = await AriaDummyOrchestrator.reply(
            text: "give me a calisthenics session",
            store: store,
            agent: .workout,
            agents: ["workout"]
        )
        let workout = try XCTUnwrap(store.todayWorkout)
        XCTAssertTrue(workout.name.localizedCaseInsensitiveContains("calisthenic"))
        XCTAssertFalse(workout.exercises.isEmpty)
        XCTAssertTrue(
            workout.exercises.contains { ExerciseLibrary.match($0.name)?.trainingStyle == .calisthenics }
        )
        XCTAssertTrue(reply.message.lowercased().contains("calisthenic") || reply.message.lowercased().contains("minute"))
    }

    func testRecordsSportAsPartOfTheSession() async throws {
        let store = makeStore()
        store.todayWorkout = WorkoutPlan(
            id: "t1",
            name: "Upper Calisthenics",
            type: .strength,
            duration: 30,
            intensity: .moderate,
            exercises: [
                Exercise(id: "e1", name: "Push-Up", sets: 3, reps: "10", weight: nil, restSeconds: 60, notes: nil)
            ]
        )
        let reply = await AriaDummyOrchestrator.reply(
            text: "I played basketball for 45 minutes",
            store: store,
            agent: .workout,
            agents: ["workout"]
        )
        XCTAssertTrue(
            AriaDummyOrchestrator.lastAppliedActions.contains {
                if case .recordSport(let name, let minutes, let completed) = $0 {
                    return name == "Basketball" && minutes == 45 && completed
                }
                return false
            }
        )
        XCTAssertTrue(store.todayWorkout?.exercises.contains { $0.name == "Basketball" } == true)
        XCTAssertTrue(store.workoutHistory.contains { $0.name == "Basketball" && $0.type == .sportSpecific })
        XCTAssertTrue(reply.message.lowercased().contains("basketball"))
        XCTAssertTrue(reply.message.lowercased().contains("45") || reply.message.lowercased().contains("minute"))
    }

    func testIdentityNamesReadWriteAndSports() async {
        let store = makeStore()
        let reply = await AriaDummyOrchestrator.reply(
            text: "what can you do",
            store: store,
            agent: .aria
        )
        XCTAssertTrue(reply.message.contains("I'm ARIA"))
        let lower = reply.message.lowercased()
        XCTAssertTrue(lower.contains("read"))
        XCTAssertTrue(lower.contains("write") || lower.contains("board"))
        XCTAssertTrue(lower.contains("calisthenics") || lower.contains("sports"))
        XCTAssertTrue(lower.contains("not a doctor") || lower.contains("not a clinic") || lower.contains("lifestyle coach"))
    }

    private func makeStore() -> AppStore {
        let store = AppStore()
        store.chatMessages = []
        store.todayWorkout = nil
        store.userProfile = UserProfile(
            name: "Sam",
            gender: .male,
            fitnessGoals: [.buildMuscle],
            experienceLevel: .intermediate,
            preferredWorkouts: [.strength],
            coachingStyle: .balanced,
            connectedDevices: [],
            weeklySchedule: [1, 3, 5],
            trainingEquipment: .commercialGym
        )
        store.readiness = ReadinessData(
            overall: 70,
            sleepQuality: 70,
            recoveryScore: 70,
            stressLevel: 30,
            energyBank: 70
        )
        return store
    }
}
