import Foundation

/// Layer 1 bridge — talks to ARIA backend with graceful local fallback.
@MainActor
final class AriaService: ObservableObject {
    static let shared = AriaService()

    @Published private(set) var isLocalFallback = false

    var baseURL: URL {
        if let saved = UserDefaults.standard.string(forKey: Self.baseURLKey),
           let url = URL(string: saved) {
            return url
        }
        return URL(string: "http://127.0.0.1:3001")!
    }

    private static let baseURLKey = "forge.api.baseURL"
    private let contextStore = AriaContextStore.shared

    private init() {}

    func setBaseURL(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: Self.baseURLKey)
    }

    func sendMessage(
        _ text: String,
        store: AppStore,
        localGenerator: TrainerResponseGenerator,
        voiceMode: Bool = false
    ) async throws -> AriaResponse {
        let domainContext = contextStore.buildARIAContext(from: store)
        let legacyMetrics = contextStore.buildRichContext(from: store).recentMetrics
        let request = AriaChatRequest(
            userId: contextStore.context.userId,
            message: text,
            context: domainContext,
            recentMetrics: legacyMetrics,
            permissions: DataPermissionsStore.shared.payloadIfRestricted(),
            voiceMode: voiceMode || store.ariaVoiceMode
        )

        if let remote = try? await postChat(request) {
            isLocalFallback = false
            if let updates = remote.contextUpdates {
                contextStore.applyUpdates(updates)
            }
            var response = remote
            if response.memoryReference == nil {
                response.memoryReference = contextStore.memoryReference(for: text)
            }
            return response
        }

        isLocalFallback = true
        return try await generateLocally(
            text: text,
            store: store,
            generator: localGenerator,
            rich: contextStore.buildRichContext(from: store)
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AriaServiceError.badResponse
        }
        return try JSONDecoder().decode(AriaResponse.self, from: data)
    }

    private func generateLocally(
        text: String,
        store: AppStore,
        generator: TrainerResponseGenerator,
        rich: AriaRichContext
    ) async throws -> AriaResponse {
        let trainerContext = TrainerContext(
            userProfile: store.userProfile,
            readiness: store.readiness,
            dailyMetrics: store.dailyMetrics,
            sleepData: store.sleepData,
            workoutHistory: store.workoutHistory,
            currentTime: Date(),
            conversationHistory: store.chatMessages
        )

        let local = try await generator.generateResponse(for: text, context: trainerContext)
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
        let healthLine = healthConnected
            ? " Recovery signals are already in the loop."
            : " Connect HealthKit anytime and I'll fold recovery into every call."
        let guidanceLine = profile.guidanceOnlyMode
            ? " Guidance mode is on for the conditions you shared — structure and pacing only, never medical advice."
            : " I'm your lifestyle coach, not a doctor."

        switch style {
        case .driven:
            return "\(name) — standards first. Week one targets \(goal)\(workouts.isEmpty ? "" : " through \(workouts)"). Show up. Execute. Earn progression.\(sleep)\(lifeLine)\(healthLine)\(guidanceLine)"
        case .balanced:
            return "\(name), your first block balances progressive work with recovery around \(goal)\(workouts.isEmpty ? "" : ", favoring \(workouts)"). Clear sessions, room to breathe.\(sleep)\(lifeLine)\(healthLine)\(guidanceLine)"
        case .supportive:
            return "\(name), we make this doable from day one. Small wins toward \(goal), clear next steps.\(sleep)\(lifeLine)\(healthLine)\(guidanceLine)"
        case .scientist:
            return "\(name) — intensity, volume, and recovery will map back to \(goal). I'll explain the why.\(sleep)\(lifeLine)\(healthLine)\(guidanceLine)"
        case .elite:
            return "\(name), performance is a system: readiness, output, recovery, adaptation — pointed at \(goal).\(sleep)\(lifeLine)\(healthLine)\(guidanceLine)"
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

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AriaServiceError.badResponse
        }
        return try JSONDecoder().decode(ObserveResponse.self, from: data)
    }
}