import Foundation

/// Deterministic lifestyle data quality evaluation — not medical diagnosis.
enum CycleDataEvaluator {

    static func evaluate(
        snapshot: MenstrualCycleSnapshot,
        settings: MenstrualTrackingSettings,
        logs: [CycleDayLog],
        feedback: [CyclePredictionFeedback],
        lastAction: String? = nil,
        isPartner: Bool = false
    ) -> CycleDataEvaluation {
        var issues: [CycleEvalIssue] = []

        if snapshot.cyclesObserved < 3 {
            issues.append(.sparseCycles)
        }
        if snapshot.irregularityFlag || snapshot.cycleLengthMAD >= 4 {
            issues.append(.highVariability)
        }
        if settings.usesHormonalContraception {
            issues.append(.hormonalSimplified)
        }
        if settings.overdueWidenDays > 0 {
            issues.append(.overdueWindow)
        }
        if feedback.count < 2 {
            issues.append(.lowFeedback)
        }

        // Spotting-only recent day without clear medium+ flow
        if let today = logs.last(where: { $0.dayKey == snapshot.asOfDayKey }),
           today.flow == .spotting {
            issues.append(.spottingAmbiguous)
        }

        // LH vs BBT conflict: an LH surge was used, but the temperature series around it
        // never actually confirmed a sustained rise.
        //
        // The old inner test was `ovulationMethod != "bbt_shift"` *inside* a branch that
        // already required `ovulationMethod == "lh_surge"` — always true, so this fired for
        // every user with an OPK and six temperatures regardless of whether the signals
        // disagreed. Now it compares the real temperatures on both sides of the estimate.
        if snapshot.ovulationMethod == "lh_surge",
           let ovulationDay = snapshot.ovulationDayInCycle,
           let cycleStart = snapshot.lastPeriodStartDayKey {
            let temps: [(day: Int, celsius: Double)] = logs.compactMap { log in
                guard let t = log.bbtCelsius, t > 35.0, t < 38.5,
                      let offset = CycleDayKey.daysBetween(cycleStart, log.dayKey) else { return nil }
                return (offset + 1, t)
            }
            let before = temps.filter { $0.day < ovulationDay }.map(\.celsius)
            let after = temps.filter { $0.day > ovulationDay }.map(\.celsius)
            if before.count >= 3, after.count >= 3 {
                let preMean = before.reduce(0, +) / Double(before.count)
                let postMean = after.reduce(0, +) / Double(after.count)
                // A real post-ovulatory shift is ~+0.2 °C. Less than half of that after an
                // LH surge is a genuine disagreement worth surfacing.
                if postMean - preMean < 0.10 {
                    issues.append(.signalConflictLhBbt)
                }
            }
        }

        if settings.highAccuracyMode, !settings.usesHormonalContraception {
            let nearFertile = snapshot.phase == .fertileWindow
                || snapshot.phase == .ovulation
                || (snapshot.dayInCycle.map { d in
                    guard let fs = snapshot.fertileStartDayInCycle else { return false }
                    return d >= fs - 2 && d <= (snapshot.fertileEndDayInCycle ?? fs + 2)
                } ?? false)
            if nearFertile {
                let recent = logs.suffix(5)
                if !recent.contains(where: { $0.bbtCelsius != nil }) {
                    issues.append(.missingBbtInWindow)
                }
                if !recent.contains(where: { $0.ovulationTest != nil }) {
                    issues.append(.missingOpkInWindow)
                }
            }
        }

        if isPartner, snapshot.cyclesObserved < 2 {
            issues.append(.partnerSparse)
        }

        // Unique issues
        var seen = Set<String>()
        issues = issues.filter { seen.insert($0.rawValue).inserted }

        let grade = grade(from: snapshot, issues: issues, feedbackCount: feedback.count, settings: settings)
        let trust: String = {
            switch grade {
            case .highSignal, .solid: return "high"
            case .mixed: return "medium"
            case .noisy, .sparse: return "low"
            }
        }()

        let understood: String = {
            if let action = lastAction, !action.isEmpty {
                return "I registered: \(action). Engine phase \(snapshot.phase.label)"
                    + (snapshot.dayInCycle.map { " · day \($0)" } ?? "")
                    + "."
            }
            if snapshot.trackingEnabled {
                return "Reading your cycle as \(snapshot.phase.label)"
                    + (snapshot.dayInCycle.map { " on day \($0)" } ?? "")
                    + " with \(snapshot.cyclesObserved) observed cycles."
            }
            return "Cycle tracking is off or empty."
        }()

        let summary = issues.isEmpty
            ? "Data quality looks \(grade.label.lowercased()) for lifestyle timing estimates."
            : issues.prefix(2).map(\.lifestyleCopy).joined(separator: " ")

        var actions: [String] = []
        if issues.contains(.sparseCycles) || issues.contains(.lowFeedback) {
            actions.append("confirm_period_start")
        }
        if issues.contains(.missingBbtInWindow) { actions.append("log_bbt") }
        if issues.contains(.missingOpkInWindow) { actions.append("log_opk_optional") }
        if issues.contains(.spottingAmbiguous) { actions.append("clarify_flow") }
        if issues.contains(.overdueWindow) { actions.append("wait_and_log_start") }
        if actions.isEmpty { actions.append("keep_logging") }

        let teaching: String = {
            switch grade {
            case .sparse:
                return "Confirm period starts so personal median and MAD can form. Accuracy is earned over cycles — not assumed."
            case .noisy, .mixed:
                return "We keep prediction windows honest when variability or signal conflict is high. Optional BBT/OPK can sharpen mid-cycle labels."
            case .solid:
                return "Solid personal history. Keep confirming starts so bias correction stays current."
            case .highSignal:
                return "High-signal path (history + mid-cycle clues). Still lifestyle estimates — not medical care or automatic birth control."
            }
        }()

        return CycleDataEvaluation(
            qualityGrade: grade,
            issues: issues,
            trustForPrediction: trust,
            userFacingSummary: summary,
            recommendedActions: actions,
            understoodSummary: understood,
            teachingSummary: teaching
        )
    }

    private static func grade(
        from snap: MenstrualCycleSnapshot,
        issues: [CycleEvalIssue],
        feedbackCount: Int,
        settings: MenstrualTrackingSettings
    ) -> CycleQualityGrade {
        if snap.cyclesObserved < 2 { return .sparse }
        if issues.contains(.highVariability), snap.cyclesObserved < 6 { return .noisy }
        let highSignal = (snap.ovulationMethod == "lh_surge" || snap.ovulationMethod == "bbt_shift")
            && snap.cyclesObserved >= 4
            && feedbackCount >= 3
            && snap.cycleLengthMAD < 3.5
        if highSignal, !settings.usesHormonalContraception { return .highSignal }
        if snap.cyclesObserved >= 4, snap.cycleLengthMAD < 3.5, feedbackCount >= 2 {
            return issues.count <= 1 ? .solid : .mixed
        }
        if snap.cyclesObserved >= 3 { return .mixed }
        return .noisy
    }
}
