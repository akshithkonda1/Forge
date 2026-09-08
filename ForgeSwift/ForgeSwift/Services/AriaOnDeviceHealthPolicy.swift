import Foundation
import ForgeCore

/// How ARIA is allowed to touch health data.
///
/// Wearables (Oura, Garmin, Apple Watch, and anything else that writes to
/// Apple Health) are ingested by *Apple Health*. Forge does not scrape vendor
/// clouds. ARIA reads that ledger on this iPhone, forms an opinion, and
/// answers. It does not keep a second live copy of the HealthKit warehouse
/// on Forge servers.
///
/// Off-device is only:
/// - Claude / Grok for language (the user message, never the HealthKit ledger)
/// - the user account database
///
/// If a future path must send a coaching hint off-device, it travels over
/// TLS and must not be stored after the model reads it. Cycle and other
/// reproductive fields are never that hint.
enum AriaOnDeviceHealthPolicy {

    static let wearableLedgerLine =
        "Wearables write to Apple Health. ARIA reads that ledger on this iPhone — it does not scrape Oura, Garmin, or any vendor account."

    static let remoteInferenceLine =
        "Claude and Grok never receive your HealthKit samples. They see what you type. Health stays on this device."

    static func isHealthLedgerTag(_ tag: String) -> Bool {
        let t = tag.lowercased()
        if t.hasPrefix("cycle:") || t.hasPrefix("cycle_phase:") || t.hasPrefix("cycle_day:")
            || t.hasPrefix("cycle_privacy:") || t.hasPrefix("partner_cycle:")
            || t.hasPrefix("partner_phase:") || t.hasPrefix("partner_day:")
            || t.hasPrefix("partner_name:") || t.hasPrefix("support_cycle:") {
            return true
        }
        return false
    }

    /// Context Claude/Grok are allowed to see: coaching prefs and conversation,
    /// not sleep/HRV/cycle/clinical samples from Apple Health.
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
        out.clinicalData = nil
        if var layer = out.medicationLayer {
            layer.onFile = []
            layer.archetypes = Array(Set(layer.mentioned.map(\.archetype))).sorted()
            layer.diseases = Array(Set(layer.mentioned.map(\.disease))).sorted()
            out.medicationLayer = layer.isEmpty ? nil : layer
        }
        out.lifestyle.cyclePhaseDirective = nil
        out.lifestyle.tags = out.lifestyle.tags
            .filter { !isHealthLedgerTag($0) && !$0.hasPrefix("med_onfile:") }
            .map { tag in
                tag.hasPrefix("calendar:") ? (FakeCalendarPack.isAllowedIngestTag(tag) ? tag : nil) : tag
            }
            .compactMap { $0 }
        out.lifestyle.recentPatterns = out.lifestyle.recentPatterns.filter { pattern in
            let p = pattern.lowercased()
            return !p.hasPrefix("cycle:") && !p.contains("cycle_phase")
        }
        out.profile.constraints = out.profile.constraints.filter { line in
            let l = line.lowercased()
            return !l.contains("menstru") && !l.contains("luteal") && !l.contains("follicular")
                && !l.contains("ovulat") && !l.hasPrefix("cycle")
                && !l.hasPrefix("med:health:") && !l.hasPrefix("med:saved:")
        }
        return out
    }
}
