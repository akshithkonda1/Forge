import Foundation
import Combine
import HealthKit
import ActivityKit
import ForgeCore

extension MenstrualHealthStore {

    var selectedPerson: SupportedPerson? {
        if let selectedPersonId,
           let person = supportedPeople.first(where: { $0.id == selectedPersonId }) {
            return person
        }
        return supportedPeople.first
    }

    var consentedPeople: [SupportedPerson] {
        supportedPeople.filter { $0.settings.enabled && $0.settings.consentAcknowledged }
    }

    /// Period / luteal first, then the selected consented person.
    var mostTimelyPerson: SupportedPerson? {
        let live = consentedPeople
        if let bleeding = live.first(where: { (personSnapshots[$0.id] ?? .empty).stage == .period }) {
            return bleeding
        }
        if let luteal = live.first(where: { (personSnapshots[$0.id] ?? .empty).phase == .luteal }) {
            return luteal
        }
        if let selected = selectedPerson, live.contains(where: { $0.id == selected.id }) {
            return selected
        }
        return live.first
    }

    func selectPerson(_ id: String) {
        guard supportedPeople.contains(where: { $0.id == id }) else { return }
        selectedPersonId = id
        persistSelectedPerson()
        syncSelectedProjection()
        pushAriaTags()
    }

    @discardableResult
    func addSupportedPerson(
        name: String,
        role: CycleSupportRole,
        relationshipLabel: String? = nil,
        consentAcknowledged: Bool = false,
        cloudKitOwnerID: String? = nil
    ) -> SupportedPerson {
        var settings = PartnerCycleSettings.default
        settings.enabled = true
        settings.partnerName = name
        settings.supportRole = role
        settings.relationshipLabel = relationshipLabel
            ?? role.suggestedLabels.first
            ?? role.shortLabel.lowercased()
        settings.shareWithAria = true
        settings.consentAcknowledged = consentAcknowledged
        let person = SupportedPerson.make(settings: settings, cloudKitOwnerID: cloudKitOwnerID)
        supportedPeople.append(person)
        selectedPersonId = person.id
        persistPeople()
        persistSelectedPerson()
        syncSelectedProjection()
        recomputePartner()
        pushAriaTags()
        return person
    }

    func removeSupportedPerson(_ id: String) {
        supportedPeople.removeAll { $0.id == id }
        personSnapshots[id] = nil
        personBriefs[id] = nil
        if selectedPersonId == id {
            selectedPersonId = supportedPeople.first?.id
        }
        persistPeople()
        persistSelectedPerson()
        syncSelectedProjection()
        recomputePartner()
        pushAriaTags()
    }

    /// Select an existing row, or add one. Never overwrite a partner into a daughter.
    func activateOrCreatePerson(name: String, label: String, role: CycleSupportRole) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = supportedPeople.first(where: { person in
            if !trimmed.isEmpty {
                return person.settings.partnerName.lowercased() == trimmed.lowercased()
                    || person.displayName.lowercased() == trimmed.lowercased()
            }
            return person.settings.resolvedRole == role
                && person.settings.relationshipLabel.lowercased() == label.lowercased()
        }) {
            if !trimmed.isEmpty, existing.settings.partnerName.isEmpty {
                updatePersonSettings(existing.id) { $0.partnerName = trimmed }
            }
            selectPerson(existing.id)
            return
        }
        _ = addSupportedPerson(
            name: trimmed,
            role: role,
            relationshipLabel: label,
            consentAcknowledged: false
        )
    }

    func personBound(to cloudKitOwnerID: String) -> SupportedPerson? {
        supportedPeople.first { $0.cloudKitOwnerID == cloudKitOwnerID }
    }

    /// Bind incoming CloudKit shares to local people. Creates a row when the
    /// share does not match anyone — never dumps a daughter onto the partner.
    func adoptReceivedDigests(_ incoming: [PartnerCycleSharing.ReceivedDigest]) {
        var changed = false
        for received in incoming {
            let records = supportedPeople.map {
                SupportedPersonMatch.Record(
                    name: $0.settings.partnerName.isEmpty ? $0.displayName : $0.settings.partnerName,
                    role: $0.settings.resolvedRole.rawValue,
                    cloudID: $0.cloudKitOwnerID
                )
            }
            if let idx = SupportedPersonMatch.bindIndex(
                people: records,
                incomingName: received.ownerName,
                incomingRole: received.role.rawValue,
                incomingCloudID: received.id
            ) {
                if supportedPeople[idx].cloudKitOwnerID != received.id {
                    supportedPeople[idx].cloudKitOwnerID = received.id
                    supportedPeople[idx].updatedAt = Date()
                    changed = true
                }
                if supportedPeople[idx].settings.partnerName.isEmpty {
                    supportedPeople[idx].settings.partnerName = received.ownerName
                    changed = true
                }
                continue
            }
            var s = PartnerCycleSettings.default
            s.enabled = true
            s.consentAcknowledged = true
            s.partnerName = received.ownerName
            s.supportRole = received.role
            s.relationshipLabel = received.role.suggestedLabels.first
                ?? received.role.shortLabel.lowercased()
            s.shareWithAria = true
            if received.digest.periodFinished {
                s.confirmedPeriodEndDayKey = received.digest.periodFinishedDayKey
            }
            let person = SupportedPerson.make(settings: s, cloudKitOwnerID: received.id)
            supportedPeople.append(person)
            if selectedPersonId == nil { selectedPersonId = person.id }
            changed = true
        }
        guard changed else { return }
        persistPeople()
        persistSelectedPerson()
        syncSelectedProjection()
        recomputePartner()
        pushAriaTags()
    }

    // MARK: Partner logging (never HealthKit — the supported person is not the device owner)

    // ------------------------------------------------------------
    // MARK: Supported-person resolution

    /// Which supported person a partner-side write belongs to.
    ///
    /// Three fallbacks, narrowest first: an explicit id when it names someone we
    /// actually hold, then the selected person, then the only person there is.
    /// Returning nil rather than inventing an id matters — callers create a
    /// person on nil, and guessing here would silently attach a daughter's period
    /// log to a partner's record.
    private func resolvedPersonId(_ explicit: String?) -> String? {
        if let explicit, supportedPeople.contains(where: { $0.id == explicit }) {
            return explicit
        }
        if let selected = selectedPersonId, supportedPeople.contains(where: { $0.id == selected }) {
            return selected
        }
        return supportedPeople.first?.id
    }

    /// Strip the fields a supporter has no business recording about someone else.
    ///
    /// Basal temperature, ovulation tests and cervical mucus are the fertility
    /// tracking triad: together they predict conception windows, and they are
    /// measurements only the person themselves can take. A supporter logging
    /// "she started today, she's in pain" is support; a supporter accumulating a
    /// fertility profile of another adult is surveillance, which is the line this
    /// feature is explicitly built not to cross.
    ///
    /// Flow, symptoms and pain stay: they are what being useful to someone on
    /// day two actually requires.
    private func sanitizedPartnerLog(_ log: CycleDayLog) -> CycleDayLog {
        var clean = log
        clean.bbtCelsius = nil
        clean.ovulationTest = nil
        clean.mucus = nil
        clean.updatedAt = Date()
        return clean
    }

    func upsertPartnerLog(_ log: CycleDayLog, personId: String? = nil) {
        let id = resolvedPersonId(personId)
        guard let id, let pidx = supportedPeople.firstIndex(where: { $0.id == id }) else {
            var s = PartnerCycleSettings.default
            s.enabled = true
            let person = SupportedPerson.make(settings: s, logs: [sanitizedPartnerLog(log)])
            supportedPeople = [person]
            selectedPersonId = person.id
            persistPeople()
            persistSelectedPerson()
            syncSelectedProjection()
            recomputePartner()
            pushAriaTags()
            return
        }
        var entry = sanitizedPartnerLog(log)
        if let idx = supportedPeople[pidx].logs.firstIndex(where: { $0.dayKey == entry.dayKey }) {
            var merged = supportedPeople[pidx].logs[idx]
            merged.flow = entry.flow
            merged.symptoms = entry.symptoms
            if let n = entry.notes { merged.notes = n }
            merged.source = "manual"
            merged.updatedAt = Date()
            supportedPeople[pidx].logs[idx] = merged
        } else {
            supportedPeople[pidx].logs.append(entry)
        }
        supportedPeople[pidx].logs.sort { $0.dayKey < $1.dayKey }
        if supportedPeople[pidx].logs.count > 800 {
            supportedPeople[pidx].logs = Array(supportedPeople[pidx].logs.suffix(800))
        }
        supportedPeople[pidx].updatedAt = Date()
        persistPeople()
        syncSelectedProjection()
        recomputePartner()
        pushAriaTags()
    }

    func logPartnerPeriodStart(
        on dayKey: String = CycleDayKey.key(),
        flow: MenstrualFlowLevel = .medium,
        personId: String? = nil
    ) {
        let id = resolvedPersonId(personId)
        let snap = id.flatMap { personSnapshots[$0] } ?? partnerSnapshot
        if let predicted = snap.nextPeriod?.medianDayKey,
           let err = CycleDayKey.daysBetween(predicted, dayKey),
           abs(err) <= 21 {
            lastModelUpdateMessage = "Support model updated · error \(err >= 0 ? "+" : "")\(err) days"
        }
        if let id, let idx = supportedPeople.firstIndex(where: { $0.id == id }),
           supportedPeople[idx].settings.confirmedPeriodEndDayKey != nil {
            supportedPeople[idx].settings.confirmedPeriodEndDayKey = nil
            supportedPeople[idx].updatedAt = Date()
            persistPeople()
        }
        upsertPartnerLog(CycleDayLog(dayKey: dayKey, flow: flow, source: "manual"), personId: id)
    }

    /// The supported person's period is over. Closes the episode and returns the support
    /// brief from period-care coaching to everyday support on the same tap.
    @discardableResult
    func logPartnerPeriodEnd(on dayKey: String = CycleDayKey.key(),
                             personId: String? = nil,
                             propagate: Bool = true) -> String {
        // Resolve who this is about before touching anything. Without this the
        // body referenced `id`, `idx` and `person` that were never bound — the
        // function did not compile, and neither did the app.
        guard let id = resolvedPersonId(personId),
              let idx = supportedPeople.firstIndex(where: { $0.id == id }) else {
            return "No one to update yet."
        }
        var person = supportedPeople[idx]

        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: person.logs)
        let startKey = episodes.last?.startDayKey ?? partnerSnapshot.lastPeriodStartDayKey ?? dayKey

        var endLog = person.logs.first(where: { $0.dayKey == dayKey }) ?? CycleDayLog(dayKey: dayKey)
        if !endLog.flow.isBleeding { endLog.flow = .light }
        endLog.source = "manual"
        endLog.updatedAt = Date()

        person.settings.confirmedPeriodEndDayKey = dayKey
        person.updatedAt = Date()
        supportedPeople[idx] = person
        persistPeople()
        upsertPartnerLog(endLog, personId: id)

        let days = (CycleDayKey.daysBetween(startKey, dayKey) ?? 0) + 1
        let name = person.displayName
        let msg = "\(name)'s period finished · \(max(1, days)) day\(days == 1 ? "" : "s") · back to everyday support"
        lastModelUpdateMessage = msg
        refreshAnalyst(lastAction: "partner_period_ended", isPartner: true)
        if propagate {
            Task {
                let ownerID = PartnerCycleSharing.shared.receivedDigests.first?.id ?? ""
                _ = await PartnerCycleSharing.shared.reportPeriodFinishedFromSupport(
                    ownerID: ownerID,
                    dayKey: dayKey
                )
                PartnerCycleSharing.shared.stageSupportUpdateForMessages()
            }
        }
        return msg
    }

    /// Pull CloudKit. If they marked finished, both sides show it.
    func syncSharedPeriodFinished() async {
        let incoming = await PartnerCycleSharing.shared.fetchSharedDigest()
        for received in incoming where received.digest.periodFinished {
            if partnerSettings.enabled,
               partnerSettings.confirmedPeriodEndDayKey == nil
                || partnerSnapshot.stage == .period {
                _ = logPartnerPeriodEnd(
                    on: received.digest.periodFinishedDayKey ?? CycleDayKey.key(),
                    propagate: false
                )
            }
        }
        if settings.enabled, !snapshot.periodEndConfirmed || snapshot.isCurrentlyBleeding {
            if let dayKey = await PartnerCycleSharing.shared.applyRemotePeriodFinishedIfNeeded() {
                _ = logPeriodEnd(on: dayKey)
            }
        }
    }

    /// User says period started today (feedback + log).
    @discardableResult
    func confirmPeriodStartedToday(flow: MenstrualFlowLevel = .medium) -> String {
        let key = CycleDayKey.key()
        logPeriodStart(on: key, flow: flow)
        updateSettings { $0.overdueWidenDays = 0 }
        let msg = lastModelUpdateMessage ?? "Period logged · model refreshed"
        return msg
    }

    /// Manual early/late correction: period came `days` before (negative) or after (positive) prediction.
    @discardableResult
    func confirmPeriodOffsetFromPrediction(daysFromPredicted: Int, flow: MenstrualFlowLevel = .medium) -> String {
        guard let predicted = lastAdvertisedNextPeriodMedian ?? snapshot.nextPeriod?.medianDayKey,
              let actual = CycleDayKey.addDays(predicted, daysFromPredicted) else {
            let key = CycleDayKey.key()
            logPeriodStart(on: key, flow: flow)
            return lastModelUpdateMessage ?? "Period logged"
        }
        logPeriodStart(on: actual, flow: flow)
        updateSettings { $0.overdueWidenDays = 0 }
        return lastModelUpdateMessage ?? "Model updated · error \(daysFromPredicted >= 0 ? "+" : "")\(daysFromPredicted) days"
    }

    /// Still no period past window — widen forecast, lower certainty, keep history.
    @discardableResult
    func reportStillNoPeriod() -> String {
        updateSettings {
            $0.overdueWidenDays = min(10, $0.overdueWidenDays + 2)
        }
        recompute()
        let msg = "Window widened · still waiting (confidence tempered)"
        lastModelUpdateMessage = msg
        return msg
    }

    func logPartnerToday(
        flow: MenstrualFlowLevel? = nil,
        symptoms: [CycleSymptom]? = nil,
        notes: String? = nil,
        personId: String? = nil
    ) {
        let id = resolvedPersonId(personId)
        let key = CycleDayKey.key()
        let existingLogs = id.flatMap { pid in supportedPeople.first(where: { $0.id == pid })?.logs } ?? partnerLogs
        var existing = existingLogs.first(where: { $0.dayKey == key }) ?? CycleDayLog(dayKey: key)
        if let flow { existing.flow = flow }
        if let symptoms { existing.symptoms = symptoms }
        if let notes { existing.notes = notes }
        existing.source = "manual"
        existing.updatedAt = Date()
        upsertPartnerLog(existing, personId: id)
    }

    // MARK: Engine

    func recomputePartner() {
        var snaps: [String: MenstrualCycleSnapshot] = [:]
        var briefs: [String: PartnerSupportBrief] = [:]
        for person in supportedPeople {
            let engineSettings = MenstrualTrackingSettings(
                enabled: person.settings.enabled && person.settings.consentAcknowledged,
                shareWithAria: person.settings.shareWithAria,
                averageCycleOverride: person.settings.averageCycleOverride,
                averagePeriodOverride: person.settings.averagePeriodOverride,
                typicalLutealDays: person.settings.typicalLutealDays,
                usesHormonalContraception: person.settings.usesHormonalContraception,
                notes: person.settings.notes,
                confirmedPeriodEndDayKey: person.settings.confirmedPeriodEndDayKey
            )
            let snap = MenstrualCycleEngine.evaluate(
                logs: person.logs,
                settings: engineSettings
            )
            snaps[person.id] = snap
            if person.settings.enabled, person.settings.consentAcknowledged {
                briefs[person.id] = PartnerSupportCoach.brief(
                    snapshot: snap,
                    settings: person.settings
                )
            }
        }
        personSnapshots = snaps
        personBriefs = briefs
        syncSelectedProjection()
    }

    // MARK: Sharing

    /// The user's own cycle, reduced to what a supporter is allowed to see.
    ///
    /// Derived on demand rather than stored, so it cannot drift from `snapshot`
    /// and there is no second copy of reproductive state to keep in sync or
    /// forget to clear. `PartnerCycleDigest.init(redacting:)` is the only
    /// crossing point, and this is the only thing that calls it.
    var supporterDigest: PartnerCycleDigest {
        PartnerCycleDigest(redacting: snapshot)
    }
}
