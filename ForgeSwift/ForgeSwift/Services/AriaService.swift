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
            return try await LocalTestingOrchestrator.shared.reply(to: text, store: store)
        }

        if Self.shouldUseTestReadyDummy {
            isTestReady = true
            isLocalFallback = true
            lastRemoteError = nil
            return AriaDummyOrchestrator.reply(text: text, store: store, agent: agent)
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

        if text.hasPrefix("[DEEP RESEARCH]") {
            return AriaResponse(
                message: AriaResearchBrief.write(question: text, sleepHistory: store.sleepData, readiness: store.readiness.overall),
                richCard: nil,
                suggestedActions: ["What should I do tonight?", "Build today's plan", "How does this change training?"],
                contextUpdates: ["relationship_level": min(10, rich.relationshipLevel + 1)],
                confidence: 0.86,
                memoryReference: contextStore.memoryReference(for: text)
            )
        }

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

    private static func payload(from card: RichCardData) -> RichCardPayload? {
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

    static func firstSessionScript(profile: OnboardingProfile, healthConnected: Bool) -> String {
        let name = profile.trimmedName.isEmpty ? "there" : profile.firstName
        let goal = profile.fitnessGoals.first?.label.lowercased() ?? "general fitness"
        let workouts = profile.preferredWorkouts.prefix(2).map(\.label).joined(separator: " & ")
        let style = profile.coachingStyle
        let sleep = profile.sleepBand.map { " Sleep rhythm: \($0.label.lowercased())." } ?? ""
        let interests = profile.freeTimeInterests.prefix(2).map(\.label).joined(separator: " & ")
        let lifeLine = interests.isEmpty ? "" : " Outside training you lean into \(interests)."
        let theme = profile.trainingTheme
        let themeLine: String = {
            guard theme != .classic else { return "" }
            return " Training lens: \(theme.label) — \(theme.tagline)"
        }()
        let healthLine = healthConnected
            ? " Recovery signals are already in the loop."
            : " Connect Apple Health anytime and I'll fold recovery into every call."
        let guidanceLine = profile.guidanceOnlyMode
            ? " Guidance mode is on for the conditions you shared — structure and pacing only, never medical advice."
            : " I'm your lifestyle coach, not a doctor."

        switch style {
        case .driven:
            return "\(name) — standards first. Week one targets \(goal)\(workouts.isEmpty ? "" : " through \(workouts)"). Show up. Execute. Earn progression.\(sleep)\(lifeLine)\(themeLine)\(healthLine)\(guidanceLine)"
        case .balanced:
            return "\(name), your first block balances progressive work with recovery around \(goal)\(workouts.isEmpty ? "" : ", favoring \(workouts)"). Clear sessions, room to breathe.\(sleep)\(lifeLine)\(themeLine)\(healthLine)\(guidanceLine)"
        case .supportive:
            return "\(name), we make this doable from day one. Small wins toward \(goal), clear next steps.\(sleep)\(lifeLine)\(themeLine)\(healthLine)\(guidanceLine)"
        case .scientist:
            return "\(name) — intensity, volume, and recovery will map back to \(goal). I'll explain the why.\(sleep)\(lifeLine)\(themeLine)\(healthLine)\(guidanceLine)"
        case .elite:
            return "\(name), performance is a system: readiness, output, recovery, adaptation — pointed at \(goal).\(sleep)\(lifeLine)\(themeLine)\(healthLine)\(guidanceLine)"
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

/// Local structured brief when the chat backend is offline. Remote ARIA
/// still gets the same prompt and writes a fuller answer.
enum AriaResearchBrief {
    static func write(question: String, sleepHistory: [SleepData], readiness: Int) -> String {
        let sleep = sleepHistory.first
        let sleepLine = sleep.map {
            "Last night was \(EnergySchedule.durationLabel($0.totalHours)), score \($0.score)."
        } ?? "No last-night sleep is on file."
        let debt = EnergySchedule.make(from: sleepHistory)?.debtHeadline ?? "Sleep need is still learning."
        let asked = question
            .replacingOccurrences(of: "[DEEP RESEARCH]", with: "")
            .replacingOccurrences(of: "Question:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        What we know
        Readiness is \(readiness). \(sleepLine) \(debt)

        What the evidence says
        Recovery, training load, and the next session should be read together — a single score is not a diagnosis. I will not invent studies you cannot check.

        What to do this week
        Keep the next hard session on a high-energy window. Protect the wind-down you already have. Ask me for a plan if you want the session written out.

        What we should not claim
        This brief is lifestyle coaching from your Forge data, not medical advice.

        \(asked.isEmpty ? "" : "You asked: \(asked.prefix(180))")
        """
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