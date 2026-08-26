import Foundation
import Combine
import UIKit
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

extension AppStore {

    /// Enough transcript for real continuity, small enough to stay cheap to
    /// store and to summarize into the prompt context.
    private static let maxPersistedMessages = 80

    private static let xpPerChatLevel = 100

    /// Verbatim turns that ride with every remote/local prompt.
    private static let recentTurnWindow = 10

    /// Cap for durable memory anchors persisted independently of the transcript.
    private static let maxDurableAnchors = 12

    var chatXPProgress: Double { Double(chatXP % Self.xpPerChatLevel) / Double(Self.xpPerChatLevel) }

    var chatXPToNextLevel: Int { Self.xpPerChatLevel - (chatXP % Self.xpPerChatLevel) }

    private struct ChatSessionDocument: Codable {
        var version: Int
        var messages: [ChatMessage]
        var xp: Int
        var level: Int
        var durableAnchors: [String]
        var updatedAt: Date
    }

    /// Awards XP and returns `true` when the award crossed a level boundary,
    /// so the caller can fire the celebration without owning the numbers.
    @discardableResult
    func awardChatXP(_ amount: Int) -> Bool {
        guard amount > 0 else { return false }
        chatXP += amount
        let newLevel = (chatXP / Self.xpPerChatLevel) + 1
        guard newLevel > chatLevel else {
            persistChatSession()
            return false
        }
        chatLevel = newLevel
        persistChatSession()
        return true
    }

    /// Records a standing fact ARIA should remember across sessions (goal, injury, preference).
    func rememberDurable(_ anchor: String) {
        let trimmed = anchor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        durableMemoryAnchors.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        durableMemoryAnchors.insert(trimmed, at: 0)
        if durableMemoryAnchors.count > Self.maxDurableAnchors {
            durableMemoryAnchors = Array(durableMemoryAnchors.prefix(Self.maxDurableAnchors))
        }
        persistChatSession()
    }

    private func persistChatSession() {
        let recent = Array(chatMessages.suffix(Self.maxPersistedMessages))
        let doc = ChatSessionDocument(
            version: 3,
            messages: recent,
            xp: chatXP,
            level: max(1, chatLevel),
            durableAnchors: durableMemoryAnchors,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(doc) else { return }
        UserDefaults.standard.set(data, forKey: Self.chatSessionKey)
        // Keep legacy XP keys warm for any older readers.
        UserDefaults.standard.set(chatXP, forKey: Self.chatXPKey)
        UserDefaults.standard.set(chatLevel, forKey: Self.chatLevelKey)
        if let anchors = try? JSONEncoder().encode(durableMemoryAnchors) {
            UserDefaults.standard.set(anchors, forKey: Self.durableMemoryKey)
        }
    }

    /// Back-compat alias used throughout the chat pipeline.
    private func persistChatHistory() { persistChatSession() }

    func restoreChatHistory() {
        // Preferred: single v3 session document.
        if let data = UserDefaults.standard.data(forKey: Self.chatSessionKey),
           let doc = try? JSONDecoder().decode(ChatSessionDocument.self, from: data) {
            chatMessages = doc.messages
            chatXP = max(0, doc.xp)
            // Level is always derived from XP so the two never drift.
            chatLevel = max(1, doc.level, (chatXP / Self.xpPerChatLevel) + 1)
            durableMemoryAnchors = doc.durableAnchors
            return
        }

        // Migrate v2 transcript array + separate XP keys.
        if let data = UserDefaults.standard.data(forKey: Self.chatHistoryKeyLegacyV2)
            ?? UserDefaults.standard.data(forKey: Self.chatHistoryKeyLegacyV1),
           let saved = try? JSONDecoder().decode([ChatMessage].self, from: data),
           !saved.isEmpty {
            chatMessages = saved
            chatXP = max(0, UserDefaults.standard.integer(forKey: Self.chatXPKey))
            chatLevel = max(1, UserDefaults.standard.integer(forKey: Self.chatLevelKey), (chatXP / Self.xpPerChatLevel) + 1)
            if let anchorData = UserDefaults.standard.data(forKey: Self.durableMemoryKey),
               let anchors = try? JSONDecoder().decode([String].self, from: anchorData) {
                durableMemoryAnchors = anchors
            }
            persistChatSession()
            UserDefaults.standard.removeObject(forKey: Self.chatHistoryKeyLegacyV2)
            UserDefaults.standard.removeObject(forKey: Self.chatHistoryKeyLegacyV1)
            return
        }

        // First launch, or a transcript we can no longer decode.
        // Opening line comes from seedAriaWelcomeFromOnboarding after the interview.
        chatMessages = []
        chatLevel = max(1, (chatXP / Self.xpPerChatLevel) + 1)
        if let anchorData = UserDefaults.standard.data(forKey: Self.durableMemoryKey),
           let anchors = try? JSONDecoder().decode([String].self, from: anchorData) {
            durableMemoryAnchors = anchors
        }
    }

    /// Wipes the transcript and momentum — used by sign-out / reset flows.
    func clearChatHistory() {
        chatMessages = []
        chatXP = 0
        chatLevel = 1
        durableMemoryAnchors = []
        streamingMessageId = nil
        streamingVisibleCount = 0
        UserDefaults.standard.removeObject(forKey: Self.chatSessionKey)
        UserDefaults.standard.removeObject(forKey: Self.chatHistoryKeyLegacyV2)
        UserDefaults.standard.removeObject(forKey: Self.chatHistoryKeyLegacyV1)
        UserDefaults.standard.removeObject(forKey: Self.chatXPKey)
        UserDefaults.standard.removeObject(forKey: Self.chatLevelKey)
        UserDefaults.standard.removeObject(forKey: Self.durableMemoryKey)
    }

    /// Progressive reveal of the latest ARIA reply — feels like streaming even
    /// when the backend returns a full message. Does not mutate stored content.
    func beginStreamingReveal(for messageId: String, fullLength: Int) {
        streamingMessageId = messageId
        streamingVisibleCount = min(24, fullLength)
        Task { @MainActor in
            let step = max(3, fullLength / 40)
            while streamingMessageId == messageId, streamingVisibleCount < fullLength {
                try? await Task.sleep(nanoseconds: 18_000_000)
                streamingVisibleCount = min(fullLength, streamingVisibleCount + step)
            }
            if streamingMessageId == messageId {
                streamingMessageId = nil
                streamingVisibleCount = 0
            }
        }
    }

    func visibleContent(for message: ChatMessage) -> String {
        guard streamingMessageId == message.id, streamingVisibleCount > 0 else {
            return message.content
        }
        let content = message.content
        let end = min(streamingVisibleCount, content.count)
        let idx = content.index(content.startIndex, offsetBy: end)
        if idx == content.endIndex { return content }

        // Reveal by word, not by character. The counter still advances in small
        // character steps — that is what keeps the ramp smooth and length-
        // independent — but the text shown is cut back to the last completed
        // word. Watching "recover" arrive as "reco", "recov", "recove" reads as
        // a rendering glitch; whole words arriving in sequence reads as
        // thinking.
        //
        // Source-agnostic on purpose: this is the same reveal whether the string
        // came from `LocalTestingOrchestrator`, the offline generator, or a real
        // streaming backend, so none of them needs its own presentation path.
        let shown = content[..<idx]
        if let lastBreak = shown.lastIndex(where: { $0 == " " || $0 == "\n" }) {
            return String(content[..<lastBreak])
        }
        // Still inside the very first word — show the partial rather than an
        // empty bubble, which would collapse the layout and then jump.
        return String(shown)
    }

    // MARK: - Onboarding Persistence

    /// Replaces mock chat with a personalized ARIA first message after onboarding.
    func seedAriaWelcomeFromOnboarding(message: String, suggestedActions: [String] = []) {
        let welcome = ChatMessage(
            id: "aria-onboarding-\(UUID().uuidString.prefix(8))",
            role: .trainer,
            content: message,
            timestamp: Date(),
            confidence: 0.92,
            suggestedActions: suggestedActions.isEmpty
                ? ["Show today's plan", "How does readiness work?", "Adjust my goals"]
                : suggestedActions
        )
        chatMessages = [welcome]
        lastSuggestedActions = welcome.suggestedActions ?? []
        persistChatHistory()
    }

    // MARK: - Workout Actions

    func addMessage(_ message: ChatMessage) {
        chatMessages.append(message)
        persistChatHistory()
    }

    /// First time in this tab: a live yes/no conversation, not a tour.
    func startAriaFirstBondIfNeeded() {
        if ariaFirstBondForceReplay {
            ariaFirstBondForceReplay = false
            beginAriaFirstBond()
            return
        }
        if hasCompletedAriaUseOnboarding {
            isInAriaFirstBond = false
            return
        }
        let alreadyTalked = chatMessages.contains { $0.role == .user && !AriaFirstBond.isBondMessageID($0.id) }
        if alreadyTalked {
            completeAriaUseOnboarding()
            return
        }
        if chatMessages.contains(where: { $0.id == AriaFirstBond.openingID }) {
            isInAriaFirstBond = true
            return
        }
        beginAriaFirstBond()
    }

    private func bondContext() -> AriaFirstBond.Context {
        AriaFirstBond.Context(
            name: userProfile.name,
            snapshot: AriaFirstHealthBriefing.snapshot(from: self),
            goal: userProfile.fitnessGoals.first?.label,
            cycleAvailable: AriaCoachAgentRouter.cycleAvailable()
        )
    }

    private func beginAriaFirstBond() {
        let turn = AriaFirstBond.start(bondContext())
        ariaFirstBondBeat = turn.next
        isInAriaFirstBond = true
        let msg = ChatMessage(
            id: AriaFirstBond.openingID,
            role: .trainer,
            content: turn.message,
            timestamp: Date(),
            confidence: 0.94,
            suggestedActions: turn.replies,
            coachAgent: AriaCoachAgent.aria.rawValue
        )
        if chatMessages.contains(where: { $0.role == .user }) {
            chatMessages.append(msg)
        } else {
            chatMessages = [msg]
        }
        lastSuggestedActions = turn.replies
        beginStreamingReveal(for: msg.id, fullLength: msg.content.count)
        persistChatHistory()
    }

    private func completeAriaFirstBond() {
        completeAriaUseOnboarding()
        let nextLevel = min(10, AriaContextStore.shared.context.relationshipLevel + 1)
        AriaContextStore.shared.applyUpdates(["relationship_level": nextLevel])
        AriaContextStore.shared.addInsight("We started. First conversation.")
        rememberDurable("ARIA is a lifestyle coach — not a doctor, not a game. She reads Apple Health.")
    }

    /// Send a message through ARIA (remote when available, local fallback).
    func sendMessage(_ text: String, ariaPayload: String? = nil) async {
        if isInAriaFirstBond, !hasCompletedAriaUseOnboarding {
            let turn = AriaFirstBond.advance(
                beat: ariaFirstBondBeat,
                userText: text,
                context: bondContext()
            )
            if !(turn.finishes && turn.message.isEmpty) {
                let userMessage = ChatMessage(
                    id: UUID().uuidString,
                    role: .user,
                    content: text,
                    timestamp: Date()
                )
                chatMessages.append(userMessage)
                isGeneratingResponse = true
                try? await Task.sleep(nanoseconds: 380_000_000)
                let reply = ChatMessage(
                    id: AriaFirstBond.replyIDPrefix + UUID().uuidString,
                    role: .trainer,
                    content: turn.message,
                    timestamp: Date(),
                    confidence: 0.93,
                    suggestedActions: turn.replies,
                    coachAgent: AriaCoachAgent.aria.rawValue
                )
                chatMessages.append(reply)
                lastSuggestedActions = turn.replies
                ariaFirstBondBeat = turn.next
                isGeneratingResponse = false
                beginStreamingReveal(for: reply.id, fullLength: reply.content.count)
                persistChatHistory()
                if turn.finishes {
                    completeAriaFirstBond()
                }
                return
            }
            completeAriaFirstBond()
        }

        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: text,
            timestamp: Date()
        )
        chatMessages.append(userMessage)
        isGeneratingResponse = true
        let outbound = ariaPayload ?? text

        do {
            // Learn theme preference from chat ("train like Solo Leveling", locks, etc.).
            applyTrainingThemeIfDetected(from: outbound)
            // Learn voice dials ("be hype", "just the facts", "keep it short", …).
            applyVoicePreferenceIfDetected(from: outbound)
            // Learn partner/daughter/family support context from plain language.
            applySupportContextIfDetected(from: outbound)

            let plan = AriaCoachAgentRouter.plan(
                message: outbound,
                context: AriaCoachAgentRouter.context(pinned: pinnedCoachAgent)
            )
            lastRoutedCoachAgent = plan.primary.kind
            lastCoachWorkers = plan.workers

            var aria = try await AriaService.shared.sendMessage(
                outbound,
                store: self,
                localGenerator: responseGenerator,
                voiceMode: ariaVoiceMode,
                agent: plan.primary.kind,
                agents: plan.backendIds
            )
            let extras = await AriaCoachAgentRouter.supportingBriefs(
                plan: plan,
                store: self,
                primaryText: aria.message
            )
            if !extras.isEmpty {
                aria.message += "\n\n" + extras.joined(separator: "\n")
            }

            lastSuggestedActions = aria.suggestedActions ?? []

            // If ARIA built a session, surface it as today's plan.
            if let card = aria.toRichCardData(), card.type == .workoutPlan {
                adoptWorkoutFromRichCard(card)
            }

            // Harvest durable facts from this exchange (goal language, injuries, etc.).
            harvestDurableMemory(userText: text, ariaText: aria.message)

            let trainerMessage = ChatMessage(
                id: UUID().uuidString,
                role: .trainer,
                content: aria.message,
                timestamp: Date(),
                richCard: aria.toRichCardData(),
                confidence: aria.confidence,
                suggestedActions: aria.suggestedActions,
                memoryReference: aria.memoryReference,
                confidenceReason: aria.confidenceReason,
                coachAgent: plan.primary.kind.rawValue
            )
            chatMessages.append(trainerMessage)
            beginStreamingReveal(for: trainerMessage.id, fullLength: trainerMessage.content.count)
        } catch {
            let errorMessage = ChatMessage(
                id: UUID().uuidString,
                role: .trainer,
                content: "Sorry, I'm having trouble processing that right now. Can you try again?",
                timestamp: Date()
            )
            chatMessages.append(errorMessage)
            print("Error generating ARIA response: \(error)")
        }

        isGeneratingResponse = false
        persistChatHistory()
    }

    /// Lightweight durable-memory extraction — production-minded, no LLM required.
    private func harvestDurableMemory(userText: String, ariaText: String) {
        let lower = userText.lowercased()
        let patterns: [(String, String)] = [
            ("i want to", "User goal: "),
            ("my goal is", "User goal: "),
            ("i'm training for", "User goal: "),
            ("im training for", "User goal: "),
            ("i have a", "User note: "),
            ("i'm dealing with", "User note: "),
            ("im dealing with", "User note: "),
            ("injury", "Injury context: "),
            ("hurt my", "Injury context: "),
            ("prefer", "Preference: "),
            ("don't like", "Preference: "),
            ("do not like", "Preference: "),
        ]
        for (needle, prefix) in patterns {
            guard lower.contains(needle) else { continue }
            let snippet = String(userText.prefix(140))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            rememberDurable(prefix + snippet)
            break
        }
        // Confidence tags from ARIA that look like standing truths.
        if ariaText.lowercased().contains("i'll remember") || ariaText.lowercased().contains("noted:") {
            rememberDurable("ARIA noted: " + String(ariaText.prefix(120)))
        }
    }

    /// One-shot ARIA insight for non-chat surfaces (e.g. Lifestyle cards).
    /// Uses the same remote-first path as `sendMessage` (with on-device fallback)
    /// but does NOT append to the chat transcript. Returns nil only if both the
    /// remote call and local generation throw — callers should fall back to their
    /// existing local content in that case.
    func ariaInsight(prompt: String, voiceMode: Bool = false) async -> AriaResponse? {
        try? await AriaService.shared.sendMessage(
            prompt,
            store: self,
            localGenerator: responseGenerator,
            voiceMode: voiceMode,
            mode: "insight"
        )
    }

    /// Compresses pre-window history into a few "memory anchors" — what the user
    /// asked for, durable standing facts, live biometrics, and ARIA insights —
    /// instead of replaying the whole transcript on every turn.
    private func conversationMemoryAnchors() -> String? {
        var anchors: [String] = []

        // Always pin live biometrics so sleep/readiness/training stay tight.
        anchors.append(CrossZoneConsistency.memoryAnchorLine(for: CrossZoneConsistency.snapshot(from: self)))

        if !durableMemoryAnchors.isEmpty {
            anchors.append(
                "Durable memory: " + durableMemoryAnchors.prefix(6).joined(separator: " | ")
            )
        }

        let olderCount = max(0, chatMessages.count - Self.recentTurnWindow)
        if olderCount > 0 {
            let older = chatMessages.prefix(olderCount)
            let userThemes = older
                .filter { $0.role == .user }
                .suffix(3)
                .map { $0.content.prefix(110).trimmingCharacters(in: .whitespacesAndNewlines) }
            if !userThemes.isEmpty {
                anchors.append("Earlier the user asked about: " + userThemes.joined(separator: " | "))
            }
            anchors.append("\(olderCount) earlier turns omitted for brevity.")
        }

        let insights = AriaContextStore.shared.context.lastInsights.prefix(3)
        if !insights.isEmpty {
            anchors.append("Standing insights: " + insights.joined(separator: " | "))
        }

        return anchors.isEmpty ? nil : anchors.joined(separator: "\n")
    }

    /// The conversational slice that rides along with every remote ARIA call:
    /// recent turns verbatim, everything older compressed into anchors.
    func conversationContextPayload() -> ARIAContextPayload.ConversationDomain {
        let recent = chatMessages.suffix(Self.recentTurnWindow).map {
            ARIAContextPayload.ConversationDomain.Turn(
                role: $0.role.rawValue,
                content: String($0.content.prefix(600))
            )
        }
        return .init(
            recentTurns: Array(recent),
            summary: conversationMemoryAnchors(),
            totalTurns: chatMessages.count
        )
    }

    /// Legacy method for backward compatibility - converts to async
    /// Builds a full `TrainerContext` including living ARIA tags/constraints + cycle.
    func makeTrainerContext() -> TrainerContext {
        let ctx = AriaContextStore.shared.context
        let cycleStore = MenstrualHealthStore.shared
        // Read-only by design: this is called from SwiftUI computed properties, and
        // mutating published cycle state from inside a view update is not allowed.
        // The cycle store is refreshed on launch, on Home's task, and after every log.
        let cycle: MenstrualCycleSnapshot? = {
            guard cycleStore.settings.enabled, cycleStore.settings.shareWithAria else { return nil }
            return cycleStore.snapshot
        }()
        let roster: [(settings: PartnerCycleSettings, snapshot: MenstrualCycleSnapshot)] =
            cycleStore.consentedPeople.compactMap { person in
                guard person.settings.shareWithAria else { return nil }
                return (person.settings, cycleStore.personSnapshots[person.id] ?? .empty)
            }
        let activePerson = cycleStore.selectedPerson.flatMap { person in
            roster.first(where: { $0.settings.partnerName == person.settings.partnerName
                && $0.settings.supportRole == person.settings.supportRole })
        } ?? roster.first
        return TrainerContext(
            userProfile: userProfile,
            readiness: readiness,
            dailyMetrics: dailyMetrics,
            sleepData: sleepData,
            workoutHistory: workoutHistory,
            currentTime: Date(),
            conversationHistory: Array(chatMessages.suffix(Self.recentTurnWindow)),
            totalMessageCount: chatMessages.count,
            conversationSummary: conversationMemoryAnchors(),
            lifestyleTags: ctx.lifestyleTags,
            constraints: ctx.constraints + (HealthKitManager.shared.clinicalSummary?.ariaConstraintLines() ?? []),
            cycleSnapshot: cycle,
            partnerCycleSnapshot: activePerson?.snapshot,
            partnerCycleSettings: activePerson?.settings,
            supportedPeople: roster
        )
    }
}
