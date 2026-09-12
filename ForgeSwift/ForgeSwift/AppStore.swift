import Foundation
import Combine
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AppStore: ObservableObject {

    // MARK: - Published State
    
    // Onboarding
    @Published var isOnboarded: Bool = false {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: Self.onboardedDefaultsKey) }
    }
    @Published var onboardingStep: Int = 0

    // Auth (local session gate — production wires IdP tokens)
    @Published var isAuthenticated: Bool = false {
        didSet { UserDefaults.standard.set(isAuthenticated, forKey: Self.authDefaultsKey) }
    }
    @Published var authProvider: String = ""
    @Published var authEmail: String = ""

    // User Profile
    @Published var userProfile: UserProfile = emptyProfile {
        didSet { persistUserProfile() }
    }

    // Readiness & Metrics — empty until Apple Health (or a log) writes something real.
    @Published var readiness: ReadinessData = emptyReadiness
    @Published var dailyMetrics: DailyMetrics = emptyMetrics

    // Today's Workout — written by AriaPlanEngine from this person's life, never a catalog default.
    @Published var todayWorkout: WorkoutPlan? = nil

    // Active Workout State
    @Published var isWorkoutActive: Bool = false
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSet: Int = 1

    // Chat
    @Published var chatMessages: [ChatMessage] = []
    @Published var isGeneratingResponse: Bool = false

    /// Durable memory anchors (goals, injuries, standing insights) — not full history.
    @Published var durableMemoryAnchors: [String] = []

    // Chat momentum — lives here (not in the view) so XP and level survive
    // relaunches and stay consistent with the rest of the ARIA context.
    @Published var chatXP: Int = UserDefaults.standard.integer(forKey: AppStore.chatXPKey) {
        didSet { UserDefaults.standard.set(chatXP, forKey: Self.chatXPKey) }
    }
    @Published var chatLevel: Int = max(1, UserDefaults.standard.integer(forKey: AppStore.chatLevelKey)) {
        didSet { UserDefaults.standard.set(chatLevel, forKey: Self.chatLevelKey) }
    }

    // Sleep
    @Published var sleepData: [SleepData] = []

    // History & Records
    @Published var workoutHistory: [WorkoutHistory] = []
    @Published var personalRecords: [PersonalRecord] = []
    /// Lifecycle of refreshDailyData(), the load that populates the two properties
    /// above. Progress's skeleton keys off `.loading` for the first-load case only
    /// -- see ProgressPageView.isInitialLoading.
    @Published var dataLoadState: DataLoadState = .idle

    // Navigation
    @Published var activeTab: TabItem = .home
    @Published var pendingProfileSubTab: String? = nil
    /// When true, main shell presents Cycle Health full-screen (Settings / Home deep-link).
    @Published var pendingCycleHealthOpen: Bool = false
    /// Optional Cycle pane: "me" or "partner".
    @Published var pendingCyclePane: String? = nil
    /// When true, Cycle Health opens the sharing sheet on top. Set by the
    /// `forge://cycle/sharing` deep link the Messages extension uses when it has
    /// no invite staged and has to hand the user back to the app.
    @Published var pendingCycleSharingOpen: Bool = false
    /// Lifestyle sub-segment deep link: `nutrition` | `restaurants` | `wellbeing` | `aiOptimization`
    @Published var pendingLifestyleSegment: String? = nil
    /// When true, main shell presents Hydration full-screen.
    @Published var pendingHydrationOpen: Bool = false
    /// Sleep page leaf: `alarms` / `wake` opens the Wake tab.
    @Published var pendingSleepTab: String? = nil
    /// Shell presents the Medicine / clinical-data (non-PHI) page.
    @Published var pendingClinicalOpen: Bool = false

    // Quiet mode — damp proactive noise (persisted)
    @Published var quietMode: Bool = UserDefaults.standard.bool(forKey: "forge.quiet.mode.v1") {
        didSet {
            UserDefaults.standard.set(quietMode, forKey: "forge.quiet.mode.v1")
            AriaContextStore.shared.setQuietMode(quietMode)
        }
    }

    /// Nil means ARIA picks the specialist. Persisted so the same coach comes back.
    @Published var pinnedCoachAgent: AriaCoachAgent? = {
        let raw = UserDefaults.standard.string(forKey: "forge.aria.pinnedCoach.v1") ?? ""
        return AriaCoachAgent(rawValue: raw)
    }() {
        didSet {
            UserDefaults.standard.set(pinnedCoachAgent?.rawValue ?? "", forKey: "forge.aria.pinnedCoach.v1")
        }
    }

    /// Last specialist that actually answered. Header and bubbles read this.
    @Published var lastRoutedCoachAgent: AriaCoachAgent = .aria
    /// Every worker spawned for the last turn. Header lists them when there
    /// is more than one.
    @Published var lastCoachWorkers: [AriaCoachWorker] = []

    // Settings — @Published so SwiftUI observes them directly, instead of
    // decoding UserDefaults on every access with a manual objectWillChange.
    // didSet persists (and reschedules notifications) the same way as before.
    @Published var notificationSettings: AppNotificationSettings = ForgePersistence.loadNotificationSettings() {
        didSet {
            ForgePersistence.saveNotificationSettings(notificationSettings)
            Task { await resyncNotifications() }
        }
    }
    @Published var briefNotificationsEnabled: Bool = ForgePersistence.loadBriefNotificationsEnabled() {
        didSet {
            ForgePersistence.saveBriefNotificationsEnabled(briefNotificationsEnabled)
            Task { await resyncNotifications() }
        }
    }
    @Published var nutritionPreferences: NutritionPreferences = ForgePersistence.loadNutritionPreferences() {
        didSet { ForgePersistence.saveNutritionPreferences(nutritionPreferences) }
    }

    // ARIA bridge
    /// When set, Train presents the library detail so ARIA can show the move.
    @Published var pendingShowHow: ExerciseDefinition? = nil
    @Published var ariaVoiceMode: Bool = false
    /// One-shot: open the voice orb on the next chat appear / handoff. Cleared
    /// after consume so a sticky Voice tab does not re-listen on every visit.
    @Published var ariaVoiceLaunch: Bool = false
    @Published var ariaPendingChatPrompt: String? = nil
    /// Cycle intimacy CTA → seeded ARIA conversation (user opener + ARIA opening).
    @Published var pendingIntimacySession: IntimacyChatSession? = nil
    @Published var lastSuggestedActions: [String] = []
    @Published var healthKitLive: Bool = false
    /// Last successful metrics refresh (Home status pill).
    @Published var lastMetricsRefresh: Date? = nil
    /// True when today's numbers came from ForgeCore's Test-Ready Health pack
    /// because Apple Health had nothing. Never set from a real sample.
    @Published var usingTestReadyHealthPack: Bool = false
    /// Ingest sources last seen on `/dashboard/today` (Apple Health, Oura, …).
    @Published var metricSources: [String] = []
    /// Server-side sync failures that should not be dressed up as coaching.
    @Published var lastCloudSyncError: String? = nil
    /// Health / calendar ingest failures with a reason, never a silent crash.
    @Published var lastLifeIngestError: String? = nil
    @Published var lastCloudSyncAt: Date? = nil
    @Published var remoteSleepInsight: String? = nil
    @Published var remoteProgressReview: String? = nil

    /// Visual first-meet page. Completes once; first login or first ARIA tap.
    @Published var hasMetAria: Bool = UserDefaults.standard.bool(forKey: AppStore.ariaMeetKey) {
        didSet { UserDefaults.standard.set(hasMetAria, forKey: AppStore.ariaMeetKey) }
    }
    @Published var showAriaMeetOnLaunch: Bool = true

    func meetAria() {
        hasMetAria = true
        showAriaMeetOnLaunch = false
    }

    /// First conversation with ARIA. Completes once; replay from Settings.
    @Published var hasCompletedAriaUseOnboarding: Bool = UserDefaults.standard.bool(forKey: AriaUseOnboarding.storageKey) {
        didSet { UserDefaults.standard.set(hasCompletedAriaUseOnboarding, forKey: AriaUseOnboarding.storageKey) }
    }
    @Published var isInAriaFirstBond: Bool = false
    var ariaFirstBondBeat: AriaFirstBond.Beat = .opening
    var ariaFirstBondForceReplay: Bool = false
    @Published var showContextInspector: Bool = false

    func completeAriaUseOnboarding() {
        isInAriaFirstBond = false
        hasCompletedAriaUseOnboarding = true
    }

    func replayAriaUseOnboarding() {
        hasCompletedAriaUseOnboarding = false
        ariaFirstBondForceReplay = true
        activeTab = .chat
        startAriaFirstBondIfNeeded()
    }
    
    // Streak tracking — consecutive calendar days with a completed session.
    @Published var currentStreak: Int = 0
    
    // AI Configuration
    @Published var aiModelAvailable: Bool = false
    
    // MARK: - Private Properties
    
    var responseGenerator: TrainerResponseGenerator
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // Initialize AI response generator
        #if canImport(FoundationModels)
        let foundationModelsGenerator = FoundationModelsResponseGenerator()
        self.aiModelAvailable = foundationModelsGenerator.isAvailable
        self.responseGenerator = foundationModelsGenerator.isAvailable ?
            foundationModelsGenerator : RuleBasedResponseGenerator()
        #else
        self.responseGenerator = RuleBasedResponseGenerator()
        self.aiModelAvailable = false
        #endif
        
        AriaContextStore.shared.configure()
        AriaPersonRegistry.shared.bootstrapFromPartnerSettingsIfNeeded()

        // Restore persisted onboarding so a returning user skips setup entirely.
        restoreOnboardingState()

        // Chat transcript is restored synchronously so the first render of
        // ChatView already has real history — no mock flash on cold launch.
        restoreChatHistory()

        // Real nights, history, and today's session come from Apple Health + this
        // person's profile — never demo sleep or "Upper Body Power".
        Task { @MainActor in
            // Let the first frame (and splash dismiss) land before HealthKit /
            // EventKit work. Test-Ready year writes and pack rewrites run off
            // the main actor and only when the day's seed changes, so Home is
            // not frozen under the splash.
            try? await Task.sleep(for: .milliseconds(450))
            await self.refreshDailyData()
            await self.resyncNotifications()
        }
    }

    // MARK: - Chat Persistence & Momentum

    /// Versioned single-document session: transcript + XP/level + durable anchors.
    /// Survives app restarts without mock flash; migrates from legacy v1/v2 keys.
    static let chatSessionKey = "forge.chat.session.v3"
    static let chatHistoryKeyLegacyV2 = "forge.chat.history.v2"
    static let chatHistoryKeyLegacyV1 = "forge.chat.history.v1"
    static let chatXPKey = "forge.chat.xp.v1"
    static let chatLevelKey = "forge.chat.level.v1"
    static let durableMemoryKey = "forge.chat.durable_memory.v1"

    func persistenceUserId() -> String {
        let id = AriaContextStore.shared.context.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { return id }
        if !authEmail.isEmpty { return authEmail.lowercased() }
        return "local"
    }

    func chatSessionStorageKey() -> String {
        let userId = persistenceUserId()
        if userId == "local" { return Self.chatSessionKey }
        return "\(Self.chatSessionKey).\(userId)"
    }

    func profileStorageKey() -> String {
        let userId = persistenceUserId()
        if userId == "local" { return Self.profileDefaultsKey }
        return "\(Self.profileDefaultsKey).\(userId)"
    }

    /// Message currently being typewriter-revealed (nil when idle).
    @Published var streamingMessageId: String? = nil
    @Published var streamingVisibleCount: Int = 0
    var streamingRevealTask: Task<Void, Never>?
    private     var persistProfileTask: Task<Void, Never>?
    /// Serializes overlapping refreshDailyData() so the empty-profile launch
    /// fetch and the post-interview prep fetch cannot clobber each other.
    var refreshDailyDataTail: Task<Void, Never>?
    /// 30-day HealthKit history, cloud dashboard, and EventKit year writes.
    /// Home does not wait on this.
    var backgroundLifeHydrateTask: Task<Void, Never>?

    static let onboardedDefaultsKey = "forge.onboarding.completed"
    static let profileDefaultsKey = "forge.user.profile.v1"
    static let authDefaultsKey = "forge.auth.session.v1"
    static let authProviderKey = "forge.auth.provider.v1"
    static let authEmailKey = "forge.auth.email.v1"
    static let ariaMeetKey = "forge.aria.meet.v1"

    /// `forge.user.profile.v1` is one of `SecureStoreMigration.sensitiveKeys`, so
    /// the unscoped key gets swept into the Keychain on every launch the same way
    /// `forge.sleep.userProfile` does — read/write it anywhere but here and the
    /// same reset/plaintext-leak cycle comes back. The per-user suffixed variant
    /// (`profileStorageKey()` once someone is signed in) is never in that static
    /// list — migration runs in `ForgeSwiftApp.init()`, before any session exists
    /// to know a user id — so `loadUserProfile(forKey:)` below migrates it the
    /// moment the real scoped key is known, instead of leaving it in `UserDefaults`
    /// indefinitely.
    private static let secureStore: SecureStore = KeychainStore()

    private func persistUserProfile() {
        persistProfileTask?.cancel()
        let snapshot = userProfile
        let key = profileStorageKey()
        persistProfileTask = Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            try? Self.secureStore.setValue(snapshot, forKey: key)
        }
    }

    /// Reads a profile from the Keychain, migrating a plaintext `UserDefaults`
    /// copy under the same key in place the first time that key is read — the
    /// one-off counterpart to `SecureStoreMigration.run` for keys it can't see.
    static func loadUserProfile(forKey key: String) -> UserProfile? {
        if let saved = try? secureStore.value(UserProfile.self, forKey: key) {
            return saved
        }
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return nil
        }
        try? secureStore.setValue(saved, forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        return saved
    }

    // MARK: - Onboarding → ARIA handoff

    var needsForgePrep: Bool {
        AriaForgePrepHandoff.needsPrep(isOnboarded: isOnboarded)
    }

    func markOnboardingInterviewComplete() {
        AriaForgePrepHandoff.markInterviewComplete()
    }

    func finishForgePrep() {
        isOnboarded = true
        AriaForgePrepHandoff.clearInterviewComplete()
    }
    
}

extension AppStore {
    /// Keep both health and calendar reasons when they fail in the same launch.
    func recordLifeIngestError(_ message: String?) {
        lastLifeIngestError = LifeIngestError.combine(existing: lastLifeIngestError, incoming: message)
    }

    /// Calculate weekly workout frequency
    var weeklyWorkoutFrequency: Int {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        
        return workoutHistory.filter { history in
            guard let date = ISO8601DateFormatter().date(from: history.date) else { return false }
            return date >= weekAgo && date <= now
        }.count
    }
    
    /// Get readiness trend (improving, declining, stable)
    enum ReadinessTrend {
        case improving, stable, declining
    }
    
    var readinessTrend: ReadinessTrend {
        // Compare current readiness with 7-day average
        let recentScores = sleepData.prefix(7).map { $0.score }
        guard !recentScores.isEmpty else { return .stable }
        
        let average = Double(recentScores.reduce(0, +)) / Double(recentScores.count)
        let difference = Double(readiness.overall) - average
        
        if difference > 5 {
            return .improving
        } else if difference < -5 {
            return .declining
        } else {
            return .stable
        }
    }
    
    /// Check if user should train today based on readiness
    var shouldTrainToday: Bool {
        readiness.overall >= 50
    }
    
    /// Get recommended intensity for today
    var recommendedIntensity: WorkoutIntensity {
        if readiness.overall >= 80 {
            return .high
        } else if readiness.overall >= 65 {
            return .moderate
        } else {
            return .low
        }
    }
}
