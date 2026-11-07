import XCTest
import ForgeCore
@testable import ForgeSwift

@MainActor
final class AriaMorningPrivacyTests: XCTestCase {

    func testReadinessWhyCopyNeverSaysRecovery() {
        let store = AppStore()
        store.readiness = ReadinessData(
            overall: 80,
            sleepQuality: 82,
            recoveryScore: 80,
            stressLevel: 20,
            energyBank: 70
        )
        store.dailyMetrics.totalSleep = 430
        let line = readinessWhyCopy(store: store)
        XCTAssertFalse(line.localizedCaseInsensitiveContains("recovery"))
        XCTAssertFalse(line.localizedCaseInsensitiveContains("seizure"))
        XCTAssertFalse(line.localizedCaseInsensitiveContains("medication"))
    }

    func testEasySessionCTAReplacesRecoverySession() {
        XCTAssertEqual(TrainDayCall.recover.cta, "Start easy session")
        XCTAssertFalse(TrainDayCall.recover.cta.localizedCaseInsensitiveContains("recovery"))
    }

    func testServerVoiceDefaultsOffAndGymLabelsStayPlain() {
        XCTAssertFalse(AriaCompanionPreferences.default.serverVoiceEnabled)
        XCTAssertEqual(AriaCompanionPreferences.default.talkativeness, .balanced)
        XCTAssertEqual(AriaPersonalPatternStore.gymLabel(.homeGym), "home")
        XCTAssertEqual(AriaPersonalPatternStore.gymLabel(.commercialGym), "the gym")
    }

    func testPlanSafetySwapsClimbingWhenEpilepsyIsDeclared() {
        var profile = UserProfile(
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
        profile.lifestyleProfile.healthConstraints = [.epilepsy]
        var context = TrainerContext(
            userProfile: profile,
            readiness: ReadinessData(overall: 78, sleepQuality: 80, recoveryScore: 76, stressLevel: 30, energyBank: 70),
            dailyMetrics: DailyMetrics(steps: 8000, activeCalories: 400, hrv: 52, restingHR: 58, deepSleep: 90, totalSleep: 300),
            sleepData: [
                SleepData(
                    date: "2026-03-01",
                    totalHours: 5.2,
                    deepMinutes: 40,
                    remMinutes: 50,
                    lightMinutes: 180,
                    awakeMinutes: 20,
                    score: 58
                )
            ],
            workoutHistory: [],
            currentTime: Date(),
            conversationHistory: []
        )
        context.lifestyleTags = ["heat:high"]
        let plan = AriaPlanEngine.evaluate(input: "climbing workout", context: context)
        let blob = (plan.narrative + " " + plan.workoutPlan.exercises.map(\.name).joined(separator: " ")).lowercased()
        XCTAssertFalse(blob.contains("seizure"))
        XCTAssertFalse(blob.contains("medication"))
        XCTAssertFalse(blob.contains("recovery"))
        XCTAssertFalse(plan.workoutPlan.exercises.contains { $0.name.localizedCaseInsensitiveContains("climb") })
        XCTAssertTrue(plan.workoutPlan.exercises.contains { $0.name.localizedCaseInsensitiveContains("floor") })
        let notes = plan.workoutPlan.exercises.compactMap(\.notes).joined(separator: " ").lowercased()
        XCTAssertTrue(
            plan.narrative.lowercased().contains("safety rule") || notes.contains("safety rule"),
            "ARIA must say when a rule changed the plan"
        )
    }

    func testRemoteInferenceSendsBandsNotSamples() {
        var payload = ARIAContextPayload(
            timestamp: "2026-03-02T00:00:00Z",
            sleep: .init(durationMinutes: 324, hrv: 38),
            readiness: .init(recoveryScore: 48),
            training: .init(),
            activity: .init(),
            chronotype: .init(),
            body: .init(),
            nutrition: .init(),
            profile: .init(constraints: [
                "A safety rule swapped swimming for easy pool-side mobility."
            ]),
            progress: .init(),
            lifestyle: .init()
        )
        payload = AriaOnDeviceHealthPolicy.strippedForRemoteInference(payload)
        XCTAssertNil(payload.sleep.durationMinutes)
        XCTAssertNil(payload.sleep.hrv)
        XCTAssertNil(payload.readiness.recoveryScore)
        XCTAssertTrue(payload.lifestyle.tags.contains("sleep_band:short"))
        XCTAssertTrue(payload.lifestyle.tags.contains("readiness_band:low"))
        XCTAssertTrue(payload.lifestyle.tags.contains("safety_changed:true"))
        XCTAssertFalse(payload.lifestyle.tags.contains { $0.contains("324") || $0.contains("38") })
        XCTAssertFalse(payload.lifestyle.recentPatterns.contains { $0.lowercased().contains("hrv") })
        XCTAssertFalse(payload.profile.constraints.contains { ForgeConditionSafety.containsBannedSpeech($0) })
    }
}
