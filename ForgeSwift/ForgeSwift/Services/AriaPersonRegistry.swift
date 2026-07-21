import Foundation
import Combine

/// Multi-person relationship registry. ARIA switches adaptation instantly when a
/// label or name is mentioned (“my wife”, “Maya”, “my daughter”).
@MainActor
final class AriaPersonRegistry: ObservableObject {
    static let shared = AriaPersonRegistry()

    @Published private(set) var people: [AriaKnownPerson]
    @Published private(set) var activePersonId: String?

    private let defaults = UserDefaults.standard
    private let peopleKey = "forge.aria.knownPeople.v1"
    private let activeKey = "forge.aria.activePersonId.v1"

    private init() {
        if let data = defaults.data(forKey: peopleKey),
           let decoded = try? JSONDecoder().decode([AriaKnownPerson].self, from: data) {
            people = decoded
        } else {
            people = []
        }
        activePersonId = defaults.string(forKey: activeKey)
    }

    /// Call once when app/store is ready (avoids init-time circular deps).
    func bootstrapFromPartnerSettingsIfNeeded() {
        guard people.isEmpty else { return }
        syncFromPartnerSettingsIfNeeded()
    }

    var activePerson: AriaKnownPerson? {
        if let id = activePersonId {
            return people.first { $0.id == id }
        }
        return people.first { $0.isActive } ?? people.first
    }

    var activeAdaptation: AriaPersonAdaptation? {
        activePerson?.adaptation
    }

    // MARK: Resolve from chat (instant)

    /// Parse message → activate matching person or create from label. Returns adaptation.
    @discardableResult
    func adapt(to text: String) -> AriaPersonAdaptation? {
        let lower = text.lowercased()
        let mention = AriaRelationalCoach.detectSupportMention(in: text)
        let labels = AriaRelationshipLabel.allMentioned(in: text)

        // 1) Name match against known people
        for person in people {
            let n = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty, lower.contains(n.lowercased()) {
                setActive(person.id)
                learnDynamics(from: text, personId: person.id)
                return person.adaptation
            }
        }

        // 2) Label match
        if let mention {
            let person = upsert(
                name: mention.name ?? "",
                label: mention.relationshipLabel,
                role: mention.role
            )
            setActive(person.id)
            learnDynamics(from: text, personId: person.id)
            return person.adaptation
        }

        if let first = labels.first {
            let person = upsert(name: "", label: first.rawValue, role: first.role)
            setActive(person.id)
            learnDynamics(from: text, personId: person.id)
            return person.adaptation
        }

        // 3) Fall back to active / partner settings
        if let active = activePerson {
            return active.adaptation
        }
        return nil
    }

    func adaptationForCurrentPartnerSettings(_ settings: PartnerCycleSettings) -> AriaPersonAdaptation {
        if let match = people.first(where: {
            (!$0.name.isEmpty && $0.name.lowercased() == settings.partnerName.lowercased())
                || $0.primaryLabel.lowercased() == settings.relationshipLabel.lowercased()
        }) {
            return match.adaptation
        }
        return AriaPersonAdaptation.resolve(
            labelRaw: settings.relationshipLabel,
            name: settings.partnerName.isEmpty ? nil : settings.partnerName
        )
    }

    // MARK: Upsert / learn

    @discardableResult
    func upsert(name: String, label: String, role: CycleSupportRole? = nil) -> AriaKnownPerson {
        let parsed = AriaRelationshipLabel.parse(from: label)
        let resolvedRole = role ?? parsed.role
        let nameKey = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let idx = people.firstIndex(where: {
            (!nameKey.isEmpty && $0.name.lowercased() == nameKey.lowercased())
                || (nameKey.isEmpty && $0.primaryLabel.lowercased() == label.lowercased() && $0.name.isEmpty)
        }) {
            var p = people[idx]
            if !nameKey.isEmpty { p.name = nameKey }
            p.primaryLabel = label.isEmpty ? parsed.rawValue : label
            p.role = resolvedRole
            // Re-default dynamics only if label family changed drastically
            if AriaRelationshipLabel.parse(from: people[idx].primaryLabel).role != resolvedRole {
                p.dynamics = .defaults(for: parsed)
            }
            people[idx] = p
            persist()
            return p
        }

        var person = AriaKnownPerson.make(name: nameKey, label: label.isEmpty ? parsed.rawValue : label)
        person.role = resolvedRole
        people.append(person)
        persist()
        AriaContextStore.shared.addInsight(
            "Learned relationship: \(person.adaptation.who) — \(person.adaptation.supportStance)"
        )
        return person
    }

    func setActive(_ id: String, mirrorToPartnerCycle: Bool = true) {
        activePersonId = id
        defaults.set(id, forKey: activeKey)
        if let p = people.first(where: { $0.id == id }) {
            for i in people.indices {
                people[i].isActive = people[i].id == id
            }
            persist()
            if mirrorToPartnerCycle {
                // Mirror into partner cycle settings for cycle/support features
                var s = MenstrualHealthStore.shared.partnerSettings
                s.enabled = true
                s.partnerName = p.name
                s.relationshipLabel = p.primaryLabel
                s.supportRole = p.role
                if !s.shareWithAria { s.shareWithAria = true }
                MenstrualHealthStore.shared.updatePartnerSettings { $0 = s }
            }
            AriaContextStore.shared.applyActivePerson(p)
        }
    }

    func addUserTag(_ tag: String, personId: String? = nil) {
        let id = personId ?? activePersonId
        guard let id, let idx = people.firstIndex(where: { $0.id == id }) else { return }
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if !people[idx].dynamics.userTags.contains(clean) {
            people[idx].dynamics.userTags.append(clean)
            people[idx].dynamics.lastUpdated = Date()
            persist()
        }
    }

    func learnDynamics(from text: String, personId: String) {
        guard let idx = people.firstIndex(where: { $0.id == personId }) else { return }
        let lower = text.lowercased()
        var d = people[idx].dynamics
        var speech = people[idx].speech
        var archetype = people[idx].archetype
        var changed = false

        if lower.contains("long distance") || lower.contains("long-distance") {
            d.proximity = .longDistance; changed = true
        }
        if lower.contains("we live together") || lower.contains("same house") {
            d.proximity = .together; changed = true
        }
        if lower.contains("needs space") || lower.contains("needs time alone") || lower.contains("leave her alone") {
            d.conflictStyle = .needsSpace; d.communication = .sparse; changed = true
        }
        if lower.contains("hates when i say calm") || lower.contains("don't say calm down")
            || lower.contains("hates calm down") {
            if !d.userTags.contains("never say calm down") {
                d.userTags.append("never say calm down")
            }
            if !speech.triggerPhrases.contains("calm down") {
                speech.triggerPhrases.append("calm down")
            }
            changed = true
        }
        if lower.contains("we're close") || lower.contains("very close") {
            d.closeness = min(1, d.closeness + 0.1); changed = true
        }
        if lower.contains("fighting a lot") || lower.contains("always fighting") || lower.contains("rough patch") {
            d.tension = min(1, d.tension + 0.15); d.conflictStyle = .escalates; changed = true
        }
        if lower.contains("she likes direct") || lower.contains("be direct") || lower.contains("straight with her") {
            d.communication = .direct; changed = true
        }
        if lower.contains("soft with her") || lower.contains("gentle with her") || lower.contains("be gentle") {
            d.communication = .soft; changed = true
        }
        if lower.contains("we repair fast") || lower.contains("we make up quick") {
            d.conflictStyle = .repairFast; changed = true
        }

        // Archetype teaching
        if let arch = AriaPersonalArchetype.detect(in: text) {
            archetype = arch
            changed = true
            AriaContextStore.shared.addInsight(
                "Archetype for \(people[idx].name.isEmpty ? people[idx].primaryLabel : people[idx].name): \(arch.label) — \(arch.tagline)"
            )
        }
        // Explicit "she's more of a guardian"
        if lower.contains("archetype") || lower.contains("personality type") || lower.contains("she's a ")
            || lower.contains("he's a ") || lower.contains("they're a ") || lower.contains("type of person") {
            if let arch = AriaPersonalArchetype.detect(in: text) {
                archetype = arch
                changed = true
            }
        }

        // Speech style teaching
        if AriaSpeechStyleProfile.learn(from: text, into: &speech) {
            changed = true
        }

        // Teachable tags: "remember she hates X"
        if lower.contains("remember she") || lower.contains("remember he") || lower.contains("remember they")
            || lower.contains("note that") || lower.contains("always remember") {
            if let tag = extractRememberClause(from: text) {
                if !d.userTags.contains(tag) {
                    d.userTags.append(tag)
                    changed = true
                }
            }
        }

        if changed {
            d.lastUpdated = Date()
            speech.lastUpdated = Date()
            people[idx].dynamics = d
            people[idx].speech = speech
            people[idx].archetype = archetype
            persist()
        }
    }

    func setArchetype(_ archetype: AriaPersonalArchetype, personId: String? = nil) {
        let id = personId ?? activePersonId
        guard let id, let idx = people.firstIndex(where: { $0.id == id }) else { return }
        people[idx].archetype = archetype
        // Refresh speech defaults lightly without wiping learned phrases
        var speech = people[idx].speech
        let refreshed = AriaSpeechStyleProfile.defaults(
            for: AriaRelationshipLabel.parse(from: people[idx].primaryLabel),
            archetype: archetype
        )
        speech.formality = refreshed.formality
        speech.pace = refreshed.pace
        speech.humor = refreshed.humor
        speech.emotionalExpressiveness = refreshed.emotionalExpressiveness
        people[idx].speech = speech
        persist()
    }

    private func extractRememberClause(from text: String) -> String? {
        let lower = text.lowercased()
        for prefix in ["remember she ", "remember he ", "remember they ", "note that ", "always remember "] {
            if let r = lower.range(of: prefix) {
                let rest = String(lower[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let clipped = rest.split(separator: ".").first.map(String.init) ?? rest
                if clipped.count > 3 && clipped.count < 80 { return clipped }
            }
        }
        return nil
    }

    private func syncFromPartnerSettingsIfNeeded() {
        let p = MenstrualHealthStore.shared.partnerSettings
        guard p.enabled || !p.partnerName.isEmpty || p.relationshipLabel != "partner" else { return }
        if people.isEmpty {
            let person = upsert(name: p.partnerName, label: p.relationshipLabel, role: p.supportRole)
            setActive(person.id)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(people) {
            defaults.set(data, forKey: peopleKey)
        }
    }
}

// MARK: - Context store hook

extension AriaContextStore {
    func applyActivePerson(_ person: AriaKnownPerson) {
        var tags = context.lifestyleTags.filter {
            !$0.hasPrefix("person:") && !$0.hasPrefix("rel_label:") && !$0.hasPrefix("rel_dyn:")
        }
        let adapt = person.adaptation
        tags.append("person:active")
        tags.append("rel_label:\(adapt.label.rawValue)")
        tags.append("rel_role:\(adapt.role.rawValue)")
        if !person.name.isEmpty {
            let safe = person.name.lowercased().replacingOccurrences(of: " ", with: "_").prefix(20)
            tags.append("person_name:\(safe)")
        }
        tags.append("rel_dyn:closeness:\(Int(adapt.dynamics.closeness * 100))")
        tags.append("rel_dyn:tension:\(Int(adapt.dynamics.tension * 100))")
        tags.append("rel_dyn:comm:\(adapt.dynamics.communication.rawValue)")
        tags.append("rel_dyn:conflict:\(adapt.dynamics.conflictStyle.rawValue)")
        tags.append("person_archetype:\(adapt.archetype.rawValue)")
        tags.append("person_speech:\(adapt.speech.length.rawValue)_\(adapt.speech.formality.rawValue)")
        context.lifestyleTags = Array(Set(tags)).sorted()
        context.lastInsights.insert(
            "Active lens: \(adapt.who) · \(adapt.archetype.label) · \(adapt.speech.coachingSummary)",
            at: 0
        )
        if context.lastInsights.count > 15 {
            context.lastInsights = Array(context.lastInsights.prefix(15))
        }
        context.lastUpdated = Date()
        persist()
    }
}
