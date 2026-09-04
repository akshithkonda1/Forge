import Foundation
import Combine
import UIKit
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

extension AppStore {

    /// Detects fandom/theme requests and persists preference for future plans.
    func applyTrainingThemeIfDetected(from text: String) {
        guard let theme = AriaThemeResolver.detect(in: text) else { return }
        let lock = AriaThemeResolver.isThemePreferenceLock(text)
        // Always remember an explicit franchise ask; locks force persist even if already set.
        if lock || userProfile.trainingTheme != theme {
            setTrainingTheme(theme, source: "chat")
        }
    }

    /// Soft-learns who the user supports (partner, daughter, family) from chat.
    func applySupportContextIfDetected(from text: String) {
        // Instant adaptation from any relationship label/name in the message.
        _ = AriaPersonRegistry.shared.adapt(to: text)
        AriaPersonRegistry.shared.bootstrapFromPartnerSettingsIfNeeded()

        guard let mention = AriaRelationalCoach.detectSupportMention(in: text) else {
            // Still learn dynamics / archetype / speech for active person
            if let id = AriaPersonRegistry.shared.activePersonId {
                AriaPersonRegistry.shared.learnDynamics(from: text, personId: id)
            }
            // Global archetype teaching without an active person name
            if AriaPersonalArchetype.detect(in: text) != nil || text.lowercased().contains("she talks")
                || text.lowercased().contains("he talks") || text.lowercased().contains("texts short") {
                if let id = AriaPersonRegistry.shared.activePersonId {
                    AriaPersonRegistry.shared.learnDynamics(from: text, personId: id)
                }
            }
            return
        }
        AriaRelationalCoach.applyMentionIfNeeded(mention, store: MenstrualHealthStore.shared)
        if let id = AriaPersonRegistry.shared.activePersonId {
            AriaPersonRegistry.shared.learnDynamics(from: text, personId: id)
        }
        // Natural consent phrases unlock full coaching.
        let lower = text.lowercased()
        if lower.contains("she said it's okay") || lower.contains("she is okay")
            || lower.contains("with her consent") || lower.contains("she knows")
            || lower.contains("we're okay tracking") || lower.contains("as her dad")
            || lower.contains("as her father") || lower.contains("i'm her parent") {
            MenstrualHealthStore.shared.updatePartnerSettings {
                $0.consentAcknowledged = true
                $0.enabled = true
                $0.shareWithAria = true
            }
            AriaContextStore.shared.addInsight(
                "Support consent acknowledged in chat — relational coaching unlocked."
            )
        }
        // Period start for them: "her period started today"
        if lower.contains("period started") || lower.contains("started her period")
            || lower.contains("on her period") && (lower.contains("today") || lower.contains("now")) {
            if MenstrualHealthStore.shared.partnerSettings.consentAcknowledged {
                MenstrualHealthStore.shared.logPartnerPeriodStart(flow: .medium)
            }
        }
    }

    /// Sticky voice dials from natural language so ARIA can be steered mid-conversation.
    func applyVoicePreferenceIfDetected(from text: String) {
        let lower = text.lowercased()
        var tags: [String] = []
        if lower.contains("be hype") || lower.contains("hype me") || lower.contains("pump me") {
            tags.append("voice:hype")
        }
        if lower.contains("be gentle") || lower.contains("softer") || lower.contains("be soft") {
            tags.append("voice:soft")
        }
        if lower.contains("just the facts") || lower.contains("data mode") || lower.contains("be clinical")
            || lower.contains("talk data") || lower.contains("numbers only") {
            tags.append("voice:clinical")
        }
        if lower.contains("talk street") || lower.contains("be casual") || lower.contains("less formal") {
            tags.append("voice:street")
        }
        if lower.contains("in character") || lower.contains("full theme") || lower.contains("mythic") {
            tags.append("voice:mythic")
        }
        if lower.contains("keep it short") || lower.contains("tl;dr") || lower.contains("be brief") {
            tags.append("voice:tight")
        }
        if lower.contains("go deep") || lower.contains("in detail") || lower.contains("explain more") {
            tags.append("voice:expansive")
        }
        if lower.contains("be funny") || lower.contains("lighten up") {
            tags.append("voice:playful")
        }
        if lower.contains("no bs") || lower.contains("be blunt") || lower.contains("be real") {
            tags.append("voice:blunt")
        }
        if lower.contains("reset voice") || lower.contains("normal voice") || lower.contains("default voice") {
            AriaContextStore.shared.clearVoicePreferenceTags()
            return
        }
        guard !tags.isEmpty else { return }
        AriaContextStore.shared.setVoicePreferenceTags(tags)
    }

    func setTrainingTheme(_ theme: AriaTrainingTheme, source: String = "settings") {
        let changed = userProfile.trainingTheme != theme
        userProfile.trainingTheme = theme
        AriaContextStore.shared.setTrainingTheme(theme)
        guard changed else {
            objectWillChange.send()
            return
        }
        AriaContextStore.shared.addInsight(
            "Training theme set to \(theme.label) via \(source)."
        )
        rebuildTodayPlanFromLife()
        objectWillChange.send()
    }
}
