import Foundation
import ForgeCore

/// Layer 1 bridge — talks to ARIA backend with graceful local fallback.
@MainActor
final class AriaService: ObservableObject {
    static let shared = AriaService()

    @Published private(set) var isLocalFallback = false
    /// Tester session on the SimRunner dummy path — never a production instance.
    @Published private(set) var isTestReady = false
    /// Set when the backend answered with a failure the user should know about —
    /// signed out, server error, rate limited. Nil when Forge is simply
    /// unreachable, because that is what offline mode is already saying.
    @Published private(set) var lastRemoteError: String?

    var baseURL: URL {
        if let saved = UserDefaults.standard.string(forKey: Self.baseURLKey),
           let url = URL(string: saved), !saved.isEmpty {
            return url
        }
        return ForgeAuthClient.shared.config.apiBaseURL
    }

    /// Continue-as-tester (debug, non-prod) stays on the dummy orchestra —
    /// same idea as SimRunner: no production ARIA instance.
    static var shouldUseTestReadyDummy: Bool {
        let client = ForgeAuthClient.shared
        guard client.canUseDevOverride else { return false }
        if client.session?.mode == .devOverride { return true }
        // Device Hub / loopback: don't wait on a tester tap or a Mac localhost.
        return ForgeAuthPolicy.isXcodeDeviceHubLaunch || client.config.apiIsLoopback
    }

    private static let baseURLKey = "forge.api.baseURL"
    private let contextStore = AriaContextStore.shared

    private init() {}

    func setBaseURL(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: Self.baseURLKey)
        WatchAriaConfigBridge.sync()
    }

    func sendMessage(
        _ text: String,
        store: AppStore,
        localGenerator: TrainerResponseGenerator,
        voiceMode: Bool = false,
        mode: String? = nil,
        agent: AriaCoachAgent = .aria,
        agents: [String]? = nil
    ) async throws -> AriaResponse {
        let isInsight = mode == "insight"
        // Full chat may read structured records. Lifestyle cards must not.
        if !isInsight, HealthKitManager.shared.hasStructuredRecordsAccess {
            _ = await HealthKitManager.shared.fetchClinicalRecordsSummary()
        }
        let domainContext = contextStore.buildARIAContext(from: store)
        let legacyMetrics = contextStore.buildRichContext(from: store).recentMetrics

        // Device Hub / dev-override / loopback testers stay on the fast,
        // deterministic dummy orchestra, checked before the general local-
        // testing path below. This has to come first: `canUseDevOverride`
        // (and therefore this whole branch) is hard-gated to DEBUG builds
        // that are not production-like, so it can never fire for a real
        // shipped build — but *within* that DEBUG/Xcode scope, checking
        // `AriaOperatingMode.current.isLocalTesting` first would always win,
        // since that mode is never anything but `.localTesting` today (no
        // production ARIA instance is provisioned yet). That silently routed
        // every Device Hub run through the on-device model instead of the
        // fast, predictable dummy responses Device Hub automation actually
        // needs, and made `AriaDummyOrchestrator` permanently unreachable.
        if Self.shouldUseTestReadyDummy {
            isTestReady = true
            isLocalFallback = true
            lastRemoteError = nil
            return await AriaDummyOrchestrator.reply(text: text, store: store, agent: agent)
        }

        // The one place `AriaOperatingMode` is consulted. Nothing below this
        // line runs in local testing: no request is built, `postChat` is never
        // called, and `isLocalFallback` puts the offline badge on screen so a
        // local answer can never be mistaken for a backend one.
        //
        // This is a *chosen* mode, which is the whole distinction from the old
        // `try?` that swallowed a 500 and dressed the failure up as coaching.
        // A deliberate local reply and a hidden remote failure look identical
        // in the transcript; only one of them is honest.
        if AriaOperatingMode.current.isLocalTesting {
            isTestReady = false
            isLocalFallback = true
            lastRemoteError = nil
            return try await LocalTestingOrchestrator.shared.reply(
                to: text,
                store: store,
                agent: agent,
                agents: agents
            )
        }
        isTestReady = false

        let request = AriaChatRequest(
            userId: contextStore.context.userId,
            message: text,
            context: domainContext,
            recentMetrics: legacyMetrics,
            permissions: DataPermissionsStore.shared.payloadIfRestricted(),
            voiceMode: voiceMode || store.ariaVoiceMode,
            mode: mode,
            agent: agent.backendId,
            agents: agents
        )

        // Deliberately not `try?`. A transport failure means the user is
        // offline and local generation is the best available answer; a 401 or a
        // 500 is Forge's problem, and dressing it as a coaching reply is how it
        // stays invisible. The two get different treatment below.
        var remoteFailure: ForgeAPI.Failure?
        var remoteResponse: AriaResponse?
        do {
            remoteResponse = try await postChat(request)
        } catch let failure as ForgeAPI.Failure {
            remoteFailure = failure
        } catch {
            remoteFailure = .transport(error)
        }

        if let remote = remoteResponse {
            isLocalFallback = false
            lastRemoteError = nil
            if let updates = remote.contextUpdates {
                contextStore.applyUpdates(updates)
            }
            var response = remote
            if response.memoryReference == nil {
                response.memoryReference = contextStore.memoryReference(for: text)
            }
            // Backend prose without a card still gets a concrete themed plan card.
            if AriaThemeResolver.isPlanRequest(text), response.richCard == nil {
                let plan = AriaPlanEngine.evaluate(input: text, context: store.makeTrainerContext())
                if plan.shouldPersistTheme {
                    store.setTrainingTheme(plan.theme, source: "chat")
                }
                store.todayWorkout = plan.workoutPlan
                response.richCard = Self.payload(from: plan.richCard)
                if response.suggestedActions == nil {
                    response.suggestedActions = plan.suggestedActions
                }
                // Prefer engine narrative when the remote reply is thin.
                if response.message.count < 80 {
                    response.message = plan.narrative
                }
            }
            return response
        }

        // Surface anything that is not "you are offline". The banner is the
        // only thing standing between a broken deployment and a product that
        // looks like it works.
        lastRemoteError = (remoteFailure?.deservesOfflineFallback == false)
            ? remoteFailure?.userMessage
            : nil

        isLocalFallback = true
        return try await generateLocally(
            text: text,
            store: store,
            generator: localGenerator,
            rich: contextStore.buildRichContext(from: store),
            agent: agent
        )
    }

    func fetchProactiveMessage(store: AppStore) async -> String? {
        contextStore.refreshProactiveInsight(from: store)
        return contextStore.lastProactiveInsight
    }

    private func postChat(_ payload: AriaChatRequest) async throws -> AriaResponse {
        let url = baseURL.appendingPathComponent("ai/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        // ForgeAPI attaches the token, refreshes a single 401, and throws a
        // typed failure on anything non-2xx instead of returning it.
        let (data, _) = try await ForgeAPI.send(request)
        return try JSONDecoder().decode(AriaResponse.self, from: data)
    }

    private func generateLocally(
        text: String,
        store: AppStore,
        generator: TrainerResponseGenerator,
        rich: AriaRichContext,
        agent: AriaCoachAgent = .aria
    ) async throws -> AriaResponse {
        let trainerContext = store.makeTrainerContext()

        // Prefer the dynamic plan engine for any training / theme request so
        // Solo Leveling (and siblings) always get a real themed session.
        let local: TrainerResponse
        let lower = text.lowercased()
        let isCycle = lower.contains("period") || lower.contains("cycle") || lower.contains("luteal")
            || lower.contains("follicular") || lower.contains("ovulat") || lower.contains("pms")
            || lower.contains("girlfriend") || lower.contains("wife") || lower.contains("partner cycle")
            || lower.contains("support her") || lower.contains("her period") || lower.contains("her pms")
            || lower.contains("daughter") || lower.contains("as a dad") || lower.contains("as a father")
            || lower.contains("my kid") || lower.contains("my child")
            || AriaRelationalCoach.mentionsSupportContext(lower)
            || lower.contains("show up for") || lower.contains("help me support")
        let isEmotional = AriaEmotionalSupportCoach.isEmotionalSupportQuery(text, context: trainerContext)
        let isArchetype = AriaArchetypeIntent.parse(text) != nil
        if isArchetype {
            local = try await RuleBasedResponseGenerator().generateResponse(for: text, context: trainerContext)
        } else if isEmotional, !AriaThemeResolver.isPlanRequest(text) || lower.contains("feel") || lower.contains("fight") {
            local = try await RuleBasedResponseGenerator().generateResponse(for: text, context: trainerContext)
        } else if AriaThemeResolver.isPlanRequest(text) {
            let plan = AriaPlanEngine.evaluate(input: text, context: trainerContext)
            if plan.shouldPersistTheme {
                store.setTrainingTheme(plan.theme, source: "plan_engine")
            }
            store.todayWorkout = plan.workoutPlan
            local = TrainerResponse(
                content: plan.narrative,
                richCard: plan.richCard,
                suggestedActions: plan.suggestedActions,
                confidence: 0.93
            )
        } else if isCycle {
            // Force rule-based cycle path for accuracy when user asks about menstruation.
            local = try await RuleBasedResponseGenerator().generateResponse(for: text, context: trainerContext)
        } else {
            local = try await generator.generateResponse(for: text, context: trainerContext)
        }

        let memory = contextStore.memoryReference(for: text)

        var message = local.content
        if let memory, local.confidence >= 0.85 {
            message = "\(memory)\n\n\(local.content)"
        }

        return AriaResponse(
            message: message,
            richCard: local.richCard.flatMap(Self.payload(from:)),
            suggestedActions: local.suggestedActions,
            contextUpdates: ["relationship_level": min(10, rich.relationshipLevel + 1)],
            confidence: local.confidence,
            memoryReference: memory
        )
    }

    static func payload(from card: RichCardData) -> RichCardPayload? {
        switch card.type {
        case .workoutPlan:
            return RichCardPayload(
                type: "workout_plan",
                title: card.workoutName,
                workoutName: card.workoutName,
                durationMinutes: card.workoutDuration
            )
        case .dataChart:
            return RichCardPayload(
                type: "data_chart",
                title: card.chartTitle,
                values: card.chartValues,
                insight: card.chartInsight
            )
        }
    }
}

enum AriaServiceError: Error {
    case badResponse
}

// MARK: - Onboarding guide (interview → first session)

/// Local scripts for ARIA-led onboarding handoff into live chat.
enum AriaOnboardingGuide {

    /// First hook on the welcome carousel — learning, not eavesdropping.
    static let welcomeTitle = "ARIA is already learning."

    static func firstSessionScript(profile: OnboardingProfile, healthConnected: Bool) -> String {
        let name = profile.trimmedName.isEmpty ? "there" : profile.firstName
        let goal = profile.fitnessGoals.first?.label.lowercased() ?? "general fitness"
        let workouts = profile.preferredWorkouts.prefix(2).map(\.label).joined(separator: " & ")
        let style = profile.coachingStyle
        let sleep = profile.sleepBand.map { " Sleep: \($0.label.lowercased())." } ?? ""
        let theme = profile.trainingTheme
        let themeLine: String = {
            guard theme != .classic else { return "" }
            return " Lens: \(theme.label)."
        }()
        let healthLine = healthConnected
            ? " Recovery is already in the loop."
            : " Connect Apple Health anytime and I'll fold recovery in."

        switch style {
        case .driven:
            return "\(name) — standards first. Week one targets \(goal)\(workouts.isEmpty ? "" : " through \(workouts)").\(sleep)\(themeLine)\(healthLine)"
        case .balanced:
            return "\(name), first block balances work and recovery around \(goal)\(workouts.isEmpty ? "" : ", favoring \(workouts)").\(sleep)\(themeLine)\(healthLine)"
        case .supportive:
            return "\(name), we make this doable from day one — small wins toward \(goal).\(sleep)\(themeLine)\(healthLine)"
        case .scientist:
            return "\(name) — load and recovery will map back to \(goal). I'll explain the why.\(sleep)\(themeLine)\(healthLine)"
        case .elite:
            return "\(name), readiness and output pointed at \(goal).\(sleep)\(themeLine)\(healthLine)"
        }
    }

    static func mood(for style: OnboardingCoachingStyle) -> ARIAMood {
        switch style {
        case .driven, .elite: return .energized
        case .supportive: return .pushed
        case .scientist: return .focused
        case .balanced: return .calm
        }
    }

    static func welcomeChatMessage(profile: OnboardingProfile, healthConnected: Bool) -> String {
        var message = firstSessionScript(profile: profile, healthConnected: healthConnected)
        message += "\n\nOpen chat anytime — I'm already tracking the context we built together in onboarding."
        message += "\n\nOne human thing: if there's a partner, wife, or daughter whose cycle days you try to show up for, tell me in plain words. A lot of people do — I'll keep it practical and never clinical for them."
        if profile.guidanceOnlyMode {
            message += "\n\nReminder: for any conditions you shared, I only provide lifestyle guidance — not diagnosis, treatment, or medical solutions."
        }
        return message
    }
}

// MARK: - Data permissions

/// User-controlled, per-domain grants for what ARIA may use. Persisted locally
/// and sent with each request; the server redacts denied domains before
/// reasoning. Default is allow-all so nothing changes until the user opts out.
final class DataPermissionsStore: ObservableObject {
    static let shared = DataPermissionsStore()

    static let domains: [String] = [
        "sleep", "readiness", "activity", "training", "chronotype",
        "body", "nutrition", "profile", "progress", "lifestyle",
        "clinical_data",
    ]

    @Published private(set) var grants: [String: Bool]

    private let defaults = UserDefaults.standard
    private let storageKey = "forge.aria.dataPermissions"

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Bool] {
            var merged = saved
            for domain in Self.domains where merged[domain] == nil { merged[domain] = true }
            grants = merged
        } else {
            grants = Dictionary(uniqueKeysWithValues: Self.domains.map { ($0, true) })
        }
    }

    func isAllowed(_ domain: String) -> Bool { grants[domain] ?? true }

    func setAllowed(_ allowed: Bool, for domain: String) {
        grants[domain] = allowed
        defaults.set(grants, forKey: storageKey)
    }

    var restrictedDomains: [String] { Self.domains.filter { grants[$0] == false } }

    func payloadIfRestricted() -> [String: Bool]? {
        restrictedDomains.isEmpty ? nil : grants
    }
}

// MARK: - Body model ingestion (/ai/observe)

extension AriaService {
    func observationSamples(from store: AppStore) -> [HealthSample] {
        let now = ISO8601DateFormatter().string(from: Date())
        let metrics = store.dailyMetrics
        var samples: [HealthSample] = [
            HealthSample(type: "hrv", value: Double(metrics.hrv), unit: "ms", timestamp: now, source: "apple-health"),
            HealthSample(type: "resting-heart-rate", value: Double(metrics.restingHR), unit: "bpm", timestamp: now, source: "apple-health"),
            HealthSample(type: "steps", value: Double(metrics.steps), unit: "count", timestamp: now, source: "apple-health"),
            HealthSample(type: "active-calories", value: Double(metrics.activeCalories), unit: "kcal", timestamp: now, source: "apple-health"),
        ]
        if let sleep = store.sleepData.first {
            samples.append(HealthSample(type: "sleep-stage", value: Double(sleep.deepMinutes), unit: "min", timestamp: sleep.date, source: "apple-health", stage: "deep"))
            samples.append(HealthSample(type: "sleep-stage", value: Double(sleep.remMinutes), unit: "min", timestamp: sleep.date, source: "apple-health", stage: "rem"))
            samples.append(HealthSample(type: "sleep-stage", value: Double(sleep.lightMinutes), unit: "min", timestamp: sleep.date, source: "apple-health", stage: "light"))
            samples.append(HealthSample(type: "sleep", value: sleep.totalHours * 60, unit: "min", timestamp: sleep.date, source: "apple-health"))
        }
        return samples
    }

    func observe(store: AppStore, message: String? = nil) async throws -> ObserveResponse {
        if Self.shouldUseTestReadyDummy {
            let samples = observationSamples(from: store)
            return ObserveResponse(
                classification: ClassificationSummary(accepted: samples.count, rejected: 0),
                snapshot: BodySnapshot(
                    confidence: store.readiness.overall > 0 ? 0.82 : 0.4,
                    observationCount: samples.count,
                    sources: ["apple-health"],
                    systems: [
                        "recovery": SystemStateDTO(
                            system: "recovery",
                            status: store.readiness.overall >= 70 ? "ready" : "protect",
                            summary: "Readiness \(store.readiness.overall)",
                            confidence: 0.8
                        )
                    ],
                    derived: [
                        "hrv": BiometricEstimate(
                            name: "hrv",
                            value: Double(store.dailyMetrics.hrv),
                            state: store.dailyMetrics.hrv >= 50 ? "ok" : "low",
                            confidence: 0.8,
                            method: "local-day",
                            detail: "Today's HRV on this phone"
                        ),
                        "steps": BiometricEstimate(
                            name: "steps",
                            value: Double(store.dailyMetrics.steps),
                            state: "ok",
                            confidence: 0.8,
                            method: "local-day",
                            detail: "Today's steps"
                        )
                    ],
                    anomalies: []
                ),
                restrictedDomains: DataPermissionsStore.shared.restrictedDomains.isEmpty
                    ? nil
                    : DataPermissionsStore.shared.restrictedDomains,
                ariaResponse: nil
            )
        }

        let request = ObserveRequest(
            userId: contextStore.context.userId,
            samples: observationSamples(from: store),
            includeStored: true,
            ageYears: nil,
            permissions: DataPermissionsStore.shared.payloadIfRestricted(),
            message: message,
            voiceMode: nil
        )

        let url = baseURL.appendingPathComponent("ai/observe")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, _) = try await ForgeAPI.send(urlRequest)
        return try JSONDecoder().decode(ObserveResponse.self, from: data)
    }
}