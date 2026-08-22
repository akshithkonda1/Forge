import Foundation
import Combine
import HealthKit
import ActivityKit
import ForgeCore

extension MenstrualHealthStore {

    func updateSettings(_ mutate: (inout MenstrualTrackingSettings) -> Void) {
        var s = settings
        mutate(&s)
        settings = s
        persistSettings()
        recompute()
        pushAriaTags()
        Task { await ForgeNotificationScheduler.syncCycleNotifications(settings: settings, snapshot: snapshot) }
    }

    func updateCondition(_ condition: CycleCondition) {
        updateSettings { $0.condition = condition }
    }

    func updatePartnerSettings(_ mutate: (inout PartnerCycleSettings) -> Void) {
        updatePersonSettings(selectedPersonId, mutate)
    }

    /// Mutate one supported person. `nil` id uses (or creates) the selected row.
    func updatePersonSettings(_ personId: String?, _ mutate: (inout PartnerCycleSettings) -> Void) {
        if supportedPeople.isEmpty {
            var s = PartnerCycleSettings.default
            mutate(&s)
            let person = SupportedPerson.make(settings: s)
            supportedPeople = [person]
            selectedPersonId = person.id
        } else {
            let id = personId ?? selectedPersonId ?? supportedPeople[0].id
            guard let idx = supportedPeople.firstIndex(where: { $0.id == id }) else { return }
            mutate(&supportedPeople[idx].settings)
            supportedPeople[idx].updatedAt = Date()
        }
        persistPeople()
        syncSelectedProjection()
        recomputePartner()
        pushAriaTags()
    }

    /// Surfaces the cycle surface for female profiles, but never *behind the user's back*:
    /// tracking only auto-enables once the privacy contract has been acknowledged.
    /// Previously this flipped `enabled` on without `privacyAcknowledged`, which skipped
    /// the consent card entirely and left the acknowledgement flag permanently false.
    func enableForFemaleProfileIfNeeded(gender: Gender) {
        guard gender == .female, !settings.enabled, settings.privacyAcknowledged else { return }
        updateSettings {
            $0.enabled = true
            $0.shareWithAria = true
        }
    }

    /// Auto-enable cycle tracking for female/intersex biological sex captured during onboarding.
    func enableForBiologicalSexIfNeeded(_ sex: BiologicalSex) {
        guard sex.cycleAutoEnabled, !settings.enabled else { return }
        updateSettings {
            $0.enabled = true
            $0.privacyAcknowledged = true
            $0.shareWithAria = true
        }
    }

    /// Surface partner tracking for users who may support a female partner (any gender).
    func enablePartnerTrackingIfAppropriate(gender: Gender) {
        // Soft suggest only — do not auto-enable without consent flag.
        _ = gender
    }

    func updateCycleGoal(_ goal: CycleGoal) {
        updateSettings { $0.cycleGoal = goal }
    }

    // MARK: Logging
}
