import Foundation
import Combine
import UIKit
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Pure consume of a Home / tab → chat handoff. Lives next to `openChat`
/// so the one-shot voice launch cannot drift from how ChatView reads it.
enum ARIAChatHandoff {
    struct Intake: Equatable {
        var pendingPrompt: String?
        var voiceLaunch: Bool
    }

    struct Result: Equatable {
        var prompt: String?
        var startVoice: Bool
        var autoSend: Bool
    }

    static func consume(_ intake: Intake) -> Result {
        let trimmed = intake.pendingPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = (trimmed?.isEmpty == false) ? trimmed : nil
        return Result(
            prompt: prompt,
            startVoice: intake.voiceLaunch,
            autoSend: prompt != nil && !intake.voiceLaunch
        )
    }
}

extension AppStore {

    /// Widget taps enqueue milliliters. Write them to HealthKit now that we
    /// are in the app process that actually holds the entitlement.
    func flushPendingWidgetWater() async {
        let pending = PendingWaterLog.drain()
        guard pending > 0 else { return }
        try? await HealthKitManager.shared.logWater(milliliters: pending)
        await HealthKitManager.shared.refreshHydration()
    }

    func publishHomeWidgets() {
        let nights = sleepData.compactMap { entry -> CircadianRhythm.Night? in
            guard let onset = entry.onset, let wake = entry.wake, wake > onset else { return nil }
            return CircadianRhythm.Night(onset: onset, wake: wake, asleepHours: entry.totalHours)
        }.sorted { $0.wake < $1.wake }
        let phase = CircadianRhythm.phase(from: nights)
        let nowHour = CircadianRhythm.hourOfDay(Date())
        let windowTitle = phase.map { CircadianRhythm.window(atHour: nowHour, phase: $0).title }

        let cycle = MenstrualHealthStore.shared
        let waterMl = HealthKitManager.shared.todayWaterMilliliters
        let waterTarget = LifestyleTargets.hydrationMilliliters(
            profile: userProfile,
            overrides: nutritionPreferences,
            activeCalories: Double(dailyMetrics.activeCalories),
            cycle: {
                guard cycle.settings.enabled else { return .none }
                switch cycle.snapshot.phase {
                case .menstruation: return .menstruation
                case .luteal: return .luteal
                default: return .none
                }
            }()
        )

        HomeWidgetSnapshotStore.save(
            HomeWidgetSnapshot(
                readiness: readiness.overall,
                readinessLabel: ReadinessBand(score: readiness.overall).label,
                sleepHours: sleepData.first?.totalHours ?? Double(dailyMetrics.totalSleep) / 60,
                sleepScore: sleepData.first?.score,
                sleepWindowTitle: windowTitle,
                hydrationMl: waterMl,
                hydrationTargetMl: waterTarget,
                cyclePhase: cycle.settings.enabled ? cycle.snapshot.phase.rawValue : nil,
                cycleDay: cycle.settings.enabled ? cycle.snapshot.dayInCycle : nil,
                qol: LifestyleWidgetBridge.currentQOL(),
                topRecommendation: LifestyleWidgetBridge.currentRecommendation(),
                workoutName: todayWorkout?.name
            )
        )
    }

    func openChat(with prompt: String, voice: Bool = false, isProactive: Bool = false) {
        if quietMode, !voice, isProactive { return }
        ariaPendingChatPrompt = prompt
        ariaVoiceMode = voice
        ariaVoiceLaunch = voice
        activeTab = .chat
    }

    /// Train → library card + ARIA talking the athlete through the lift.
    func showHowToPerform(_ name: String, speakLocally: Bool = true, openChat: Bool = false) {
        let def = ExerciseLibrary.match(name)
        if let def {
            pendingShowHow = def
            if speakLocally {
                AriaPresence.shared.speak(ExerciseLibrary.howToScript(for: def))
            }
        }
        if openChat || def == nil {
            self.openChat(
                with: "Show me how to do \(name). Walk me through setup, cues, common faults, and a regression if my joints complain.",
                voice: true
            )
        }
    }

    /// Deep-link into the shell Cycle Health cover (optional Support pane).
    /// Home no longer hosts its own cover — two full-screen presenters on the
    /// same published flag blanked or stuck the page when opened from Home.
    func openCycleHealth(pane: String? = nil, sharing: Bool = false) {
        let resolved = CycleHealthLaunch.pane(
            requested: pane,
            selfTrackingEnabled: MenstrualHealthStore.shared.settings.enabled,
            hasConsentedPeople: !MenstrualHealthStore.shared.consentedPeople.isEmpty,
            defaultToSupport: userProfile.gender != .female
                && userProfile.biologicalSex?.cycleAutoEnabled != true
        )
        pendingCyclePane = resolved.rawValue
        pendingCycleSharingOpen = sharing
        pendingCycleHealthOpen = true
    }

    func openHydration() {
        pendingHydrationOpen = true
    }

    func logGlassFromWidget() async {
        try? await HealthKitManager.shared.logWater(
            milliliters: HydrationEngine.glassMilliliters
        )
        await HealthKitManager.shared.refreshHydration()
        publishHomeWidgets()
    }

    /// Route a `forge://` URL. Returns false for anything unrecognised so the
    /// caller can leave the app where it was rather than guessing.
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "forge" else { return false }
        // forge://cycle/sharing  →  host "cycle", first path component "sharing"
        let segments = ([url.host] + url.pathComponents.filter { $0 != "/" })
            .compactMap { $0?.lowercased() }
        switch segments.first {
        case "cycle":
            let leaf = segments.dropFirst().first
            if leaf == "period-finished" || leaf == "finished" {
                Task { await MenstrualHealthStore.shared.syncSharedPeriodFinished() }
                openCycleHealth()
                return true
            }
            if leaf == "support" {
                openCycleHealth(pane: "partner")
                return true
            }
            openCycleHealth(pane: leaf == "sharing" ? "me" : nil, sharing: leaf == "sharing")
            return true
        case "hydration", "water":
            if segments.dropFirst().first == "log" {
                Task { await logGlassFromWidget() }
            }
            openHydration()
            return true
        case "home":
            activeTab = .home
            return true
        case "sleep":
            activeTab = .sleep
            if let leaf = segments.dropFirst().first, leaf == "wake" || leaf == "alarms" {
                pendingSleepTab = "alarms"
            }
            return true
        case "wake":
            activeTab = .sleep
            pendingSleepTab = "alarms"
            let alarmID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name.lowercased() == "alarm" })?
                .value
                .flatMap(UUID.init(uuidString:))
            SleepWakeStore.shared.ringFromNotification(alarmID: alarmID)
            return true
        case "workout", "train":
            activeTab = .workout
            return true
        case "lifestyle":
            activeTab = .lifestyle
            return true
        case "aria":
            if segments.dropFirst().first == "weekly" {
                WeeklyAriaReviewStore.shared.showSheet = true
            } else {
                activeTab = .chat
            }
            return true
        default:
            return false
        }
    }

    func setQuietMode(_ on: Bool) {
        quietMode = on
    }
}
