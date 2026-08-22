import Foundation
import Combine
import HealthKit
import ActivityKit
import ForgeCore

extension MenstrualHealthStore {

    func pushAriaTags() {
        if settings.enabled, settings.shareWithAria {
            AriaContextStore.shared.applyCycleSnapshot(snapshot)
            AriaContextStore.shared.applyPeriodCoachingPreferences(coachingPreferences)
        } else {
            AriaContextStore.shared.clearCycleTags()
        }
        let ariaPeople: [(SupportedPerson, MenstrualCycleSnapshot)] = consentedPeople.compactMap { person in
            guard person.settings.shareWithAria else { return nil }
            return (person, personSnapshots[person.id] ?? .empty)
        }
        AriaContextStore.shared.applySupportedPeople(ariaPeople)
    }

    func ariaContextLines() -> [String] {
        var lines: [String] = []
        if settings.enabled, settings.shareWithAria {
            lines.append("Self cycle phase: \(snapshot.phase.label)")
            if let d = snapshot.dayInCycle {
                lines.append("Self day in cycle: \(d)")
            }
            lines.append(snapshot.trainingNote)
            if coachingPreferences.sampleCount > 0 {
                let directive = coachingPreferences.coachingDirective
                if !directive.isEmpty { lines.append(directive) }
            }
        }
        for person in consentedPeople where person.settings.shareWithAria {
            let snap = personSnapshots[person.id] ?? .empty
            let who = person.role.shortLabel
            lines.append("\(who) (\(person.displayName)) phase: \(snap.phase.label)")
            if let d = snap.dayInCycle {
                lines.append("\(who) (\(person.displayName)) day in cycle: \(d)")
            }
            if let brief = personBriefs[person.id] {
                lines.append("\(person.displayName): \(brief.headline)")
                lines.append(brief.communicationTip)
            }
        }
        if consentedPeople.contains(where: { $0.settings.shareWithAria }) {
            lines.append(PartnerSupportBrief.disclaimer)
        }
        return lines
    }

    // MARK: Persist

    /// Refresh evaluation + local ARIA brief after a user action label.
    func refreshAnalyst(lastAction: String? = nil, isPartner: Bool = false) {
        let snap = isPartner ? partnerSnapshot : snapshot
        let set = isPartner
            ? MenstrualTrackingSettings(
                enabled: partnerSettings.enabled,
                shareWithAria: partnerSettings.shareWithAria,
                averageCycleOverride: partnerSettings.averageCycleOverride,
                averagePeriodOverride: partnerSettings.averagePeriodOverride,
                typicalLutealDays: partnerSettings.typicalLutealDays,
                usesHormonalContraception: partnerSettings.usesHormonalContraception,
                notes: partnerSettings.notes,
                highAccuracyMode: false,
                confirmedPeriodEndDayKey: partnerSettings.confirmedPeriodEndDayKey
            )
            : settings
        let logSet = isPartner ? partnerLogs : logs
        let eval = CycleDataEvaluator.evaluate(
            snapshot: snap,
            settings: set,
            logs: logSet,
            feedback: isPartner ? [] : predictionFeedback,
            lastAction: lastAction,
            isPartner: isPartner
        )
        lastEvaluation = eval
        lastAriaBrief = CycleAriaAnalyst.localBrief(
            evaluation: eval,
            snapshot: snap,
            lastAction: lastAction,
            isPartner: isPartner
        )
    }

    func ariaChatPromptForCycle(isPartner: Bool = false) -> String? {
        let share = isPartner ? partnerSettings.shareWithAria : settings.shareWithAria
        guard share else { return nil }
        let ctx = CycleAriaAnalyst.makeContext(
            snapshot: isPartner ? partnerSnapshot : snapshot,
            evaluation: lastEvaluation,
            settings: settings,
            lastAction: nil,
            isPartner: isPartner
        )
        return CycleAriaAnalyst.chatPrompt(context: ctx, evaluation: lastEvaluation)
    }
}
