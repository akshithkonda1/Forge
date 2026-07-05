import Foundation
import Observation
import ForgeCore

// MARK: - ARIAWatchService
//
// Two tiers, per the watch ARIA strategy:
//
//  INSTANT (this file, on-device): greeting + practice recommendation via
//  ForgeCore's rule/template engine. Zero network, zero latency, private
//  by construction. This is what Home and the complications render.
//
//  DEEPER (async, optional): a lightweight call to the backend
//  (`POST {base}/watch/aria/suggest`) for a richer debrief after a
//  session. Token-gated, 10s timeout, and every failure falls back to the
//  local template — the wrist experience never blocks on the network.

@MainActor
@Observable
final class ARIAWatchService {

    private(set) var greeting: String = "Loading your day…"
    private(set) var recommendation: MindfulnessRecommendation?
    private(set) var lastContext: WatchARIAContext?

    private let defaults = UserDefaults(suiteName: WatchSnapshotStore.appGroupID)
    private enum Keys {
        // Written by the iOS app when the user signs in; absent = local-only.
        static let baseURL = "forge.aria.baseURL"
        static let authToken = "forge.aria.authToken"
        static let userName = "forge.user.firstName"
    }

    // MARK: Instant tier

    /// Rebuilds greeting + recommendation from current signals and mirrors
    /// them into the shared snapshot so complications update within the
    /// <2s target (WatchSnapshotStore.save reloads widget timelines).
    func refresh(health: WatchHealthKitManager, context: ContextEngine, sessionsToday: Int) {
        let ariaContext = health.makeARIAContext(
            mode: context.currentMode,
            minutesInMode: context.minutesInCurrentMode,
            profile: context.profile,
            sessionsCompletedToday: sessionsToday,
            sleepFactors: context.todaySleepFactors
        )
        lastContext = ariaContext
        greeting = MindfulnessSuggestionEngine.greeting(
            for: ariaContext,
            userName: defaults?.string(forKey: Keys.userName)
        )
        let suggestion = MindfulnessSuggestionEngine.suggest(for: ariaContext)
        recommendation = suggestion

        WatchSnapshotStore.update { snapshot in
            snapshot.recommendedPractice = suggestion.practice
            snapshot.recommendedDuration = suggestion.duration
            snapshot.recommendationReason = suggestion.reason
        }
    }

    // MARK: Deeper tier

    struct DebriefRequest: Encodable {
        var context: WatchARIAContext
        var practice: String
        var minutes: Double
        var heartRateSettleBPM: Double?
    }

    private struct DebriefResponse: Decodable {
        var message: String
    }

    /// Asks the backend for a personalized debrief. Returns nil on any
    /// failure or missing configuration — callers always have the local
    /// debrief already rendered, so this only ever upgrades the copy.
    func deeperDebrief(
        practice: PracticeType,
        minutes: Double,
        heartRateSettleBPM: Double?
    ) async -> String? {
        guard
            let base = defaults?.string(forKey: Keys.baseURL),
            let token = defaults?.string(forKey: Keys.authToken),
            let context = lastContext,
            let url = URL(string: base)?.appending(path: "watch/aria/suggest")
        else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let payload = DebriefRequest(
            context: context,
            practice: practice.rawValue,
            minutes: minutes,
            heartRateSettleBPM: heartRateSettleBPM
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let message = try JSONDecoder().decode(DebriefResponse.self, from: data).message
            // SimRunner-style guard even on backend copy: keep it short and
            // strip anything empty rather than rendering a blank card.
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}
