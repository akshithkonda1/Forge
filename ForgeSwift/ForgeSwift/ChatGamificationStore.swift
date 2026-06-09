import Foundation
import SwiftUI

// MARK: - State

struct ChatGamificationState: Codable, Equatable {
    var xp: Int = 0
    var level: Int = 1
    var messageReactions: [String: String] = [:]
    var chatStreakDays: Int = 0
    var lastChatDate: String = ""
    var totalMessagesSent: Int = 0
    var totalReactions: Int = 0
    var lifetimeXP: Int = 0
}

enum ChatXPAwardReason: String, Codable {
    case messageSent
    case longMessage
    case reactionAdded
    case dailyStreak
    case trainerMilestone
}

// MARK: - Store

@MainActor
final class ChatGamificationStore: ObservableObject {
    static let shared = ChatGamificationStore()

    @Published private(set) var xp: Int = 0
    @Published private(set) var level: Int = 1
    @Published var showXPBurst = false
    @Published var lastXPGain = 0
    @Published var showLevelUp = false
    @Published private(set) var chatStreakDays = 0

    private var state = ChatGamificationState()
    private var saveTask: Task<Void, Never>?
    private let xpPerLevel = 100

    private init() {
        load()
    }

    var xpProgress: Double { Double(xp % xpPerLevel) / Double(xpPerLevel) }
    var xpToNext: Int { xpPerLevel - (xp % xpPerLevel) }

    func reaction(for messageId: String) -> String? {
        state.messageReactions[messageId]
    }

    func awardMessageSent(wordCount: Int) {
        registerChatDay()
        state.totalMessagesSent += 1
        let base = wordCount > 5 ? 15 : 10
        award(xp: base, reason: wordCount > 5 ? .longMessage : .messageSent)
        scheduleSave()
        scheduleBackendSync()
    }

    func awardReaction(messageId: String, emoji: String?) {
        if let emoji {
            let previous = state.messageReactions[messageId]
            state.messageReactions[messageId] = emoji
            if previous == nil {
                state.totalReactions += 1
                award(xp: 3, reason: .reactionAdded)
            }
        } else {
            state.messageReactions.removeValue(forKey: messageId)
        }
        scheduleSave()
        scheduleBackendSync()
    }

    func awardTrainerMilestone() {
        award(xp: 25, reason: .trainerMilestone)
        scheduleSave()
        scheduleBackendSync()
    }

    private func registerChatDay() {
        let today = Self.dayKey(for: Date())
        if state.lastChatDate == today { return }

        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()),
           state.lastChatDate == Self.dayKey(for: yesterday) {
            state.chatStreakDays += 1
        } else if state.lastChatDate.isEmpty {
            state.chatStreakDays = 1
        } else {
            state.chatStreakDays = 1
        }

        state.lastChatDate = today
        chatStreakDays = state.chatStreakDays

        if state.chatStreakDays > 1 {
            award(xp: min(50, state.chatStreakDays * 5), reason: .dailyStreak)
        }
    }

    private func award(xp amount: Int, reason: ChatXPAwardReason) {
        _ = reason
        lastXPGain = amount
        state.xp += amount
        state.lifetimeXP += amount
        xp = state.xp

        withAnimation(FDS.Spring.hero) { showXPBurst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(FDS.Spring.standard) { self.showXPBurst = false }
        }
        checkLevelUp()
    }

    private func checkLevelUp() {
        let newLevel = (state.xp / xpPerLevel) + 1
        if newLevel > state.level {
            state.level = newLevel
            level = newLevel
            choreographedHaptic(.milestone)
            withAnimation(FDS.Spring.hero) { showLevelUp = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                withAnimation(FDS.Spring.standard) { self.showLevelUp = false }
            }
        }
    }

    private func load() {
        guard let saved = ForgePersistence.loadChatGamification() else { return }
        state = saved
        xp = saved.xp
        level = saved.level
        chatStreakDays = saved.chatStreakDays
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            ForgePersistence.saveChatGamification(state)
        }
    }

    private func scheduleBackendSync() {
        Task {
            try? await ForgeRepository.shared.syncChatGamification(state)
        }
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}