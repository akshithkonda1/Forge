import Foundation
import ForgeCore

/// How ARIA is allowed to touch health data.
///
/// Wearables write to Apple Health. Forge reads that ledger on this device.
/// Health data always stays on device, never goes to a server.
///
/// Off-device is only:
/// - Claude / Grok for language (the user message, never the HealthKit ledger)
/// - the user account database (email for Cognito)
/// - TTS of what ARIA already decided to say
enum AriaOnDeviceHealthPolicy {

    static let wearableLedgerLine = ForgePrivacyCopy.healthStaysOnDevice

    static let remoteInferenceLine = ForgePrivacyCopy.healthStaysOnDevice

    /// Prefix of the Life Context brief in `lifestyle.recentPatterns`.
    static let lifeContextBriefPrefix = "life_context_brief: "
    static let lifeOpsBriefPrefix = "life_ops_brief: "

    /// Reminders counts, shared-conversation facts, and the Life Ops digest
    /// (calendar + reminder load). Built fresh for this payload and never
    /// written into `context`, so none of it is persisted. On-device ARIA
    /// reads it; AriaOnDeviceHealthPolicy strips it before /ai/chat.
    static func isOnDeviceOnlyLifeContext(_ value: String) -> Bool {
        let v = value.lowercased()
        return v.hasPrefix("reminders:")
            || v.hasPrefix("life_context")
            || v.hasPrefix("life_ops")
            || v.hasPrefix("scout_gap:")
    }

    static func isHealthLedgerTag(_ tag: String) -> Bool {
        let t = tag.lowercased()
        if t.hasPrefix("cycle:") || t.hasPrefix("cycle_phase:") || t.hasPrefix("cycle_day:")
            || t.hasPrefix("cycle_privacy:") || t.hasPrefix("partner_cycle:")
            || t.hasPrefix("partner_phase:") || t.hasPrefix("partner_day:")
            || t.hasPrefix("partner_name:") || t.hasPrefix("support_cycle:")
            || t.hasPrefix("scout_gap:")
            || t.hasPrefix("qol:") || t.hasPrefix("steps:") || t.hasPrefix("protein:")
            || t.hasPrefix("hydration:") || t.hasPrefix("recovery:") || t.hasPrefix("sleep")
            || t.hasPrefix("hrv") || t.hasPrefix("ingest:") {
            return true
        }
        return false
    }

    /// Context Claude/Grok are allowed to see: coaching prefs and conversation,
    /// not sleep/HRV/cycle/clinical samples from Apple Health, and not names.
    static func strippedForRemoteInference(_ payload: ARIAContextPayload) -> ARIAContextPayload {
        var out = payload
        out.sleep = ARIAContextPayload.SleepDomain()
        out.readiness = ARIAContextPayload.ReadinessDomain()
        out.training = ARIAContextPayload.TrainingDomain()
        out.activity = ARIAContextPayload.ActivityDomain()
        out.chronotype = ARIAContextPayload.ChronotypeDomain()
        out.body = ARIAContextPayload.BodyDomain()
        out.nutrition = ARIAContextPayload.NutritionDomain()
        out.progress = ARIAContextPayload.ProgressDomain()
        out.aging = nil
        out.clinicalData = nil
        if var layer = out.medicationLayer {
            layer.onFile = []
            layer.archetypes = Array(Set(layer.mentioned.map(\.archetype))).sorted()
            layer.diseases = Array(Set(layer.mentioned.map(\.disease))).sorted()
            out.medicationLayer = layer.isEmpty ? nil : layer
        }
        out.lifestyle.cyclePhaseDirective = nil
        out.lifestyle.tags = out.lifestyle.tags
            .filter { !isHealthLedgerTag($0) && !$0.hasPrefix("med_onfile:") && !isOnDeviceOnlyLifeContext($0) }
            .map { tag in
                tag.hasPrefix("calendar:") ? (FakeCalendarPack.isAllowedIngestTag(tag) ? tag : nil) : tag
            }
            .compactMap { $0 }
        out.lifestyle.recentPatterns = out.lifestyle.recentPatterns.filter { pattern in
            let p = pattern.lowercased()
            return !p.hasPrefix("cycle:") && !p.contains("cycle_phase") && !isOnDeviceOnlyLifeContext(pattern)
                && !p.hasPrefix("scout_gap:")
        }
        out.profile.constraints = out.profile.constraints.filter { line in
            let l = line.lowercased()
            return !l.contains("menstru") && !l.contains("luteal") && !l.contains("follicular")
                && !l.contains("ovulat") && !l.hasPrefix("cycle")
                && !l.hasPrefix("med:health:") && !l.hasPrefix("med:saved:")
                && !l.contains("scout_gap")
        }
        return out
    }
}
