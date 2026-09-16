import Foundation
import Combine
import ForgeCore

/// Settings-facing editor for ARIA memory, persona, tone, and check-ins.
/// Writes through `AriaMemoryControls` — the local ForgeCore contract.
@MainActor
final class AriaMemoryControlsViewModel: ObservableObject {
    @Published var controls: AriaMemoryControls
    @Published var draftSummary = ""
    @Published var draftCategory: AriaKnowledgeCategory = .lifestyle
    @Published var editingID: String?
    @Published var addError: String?

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.controls = AriaMemoryControls.load(defaults: defaults)
    }

    func reload() {
        controls = AriaMemoryControls.load(defaults: defaults)
        addError = nil
    }

    var memoryOn: Bool { controls.prefs.memoryEnabled }

    func setMemoryEnabled(_ enabled: Bool) {
        controls.setMemoryEnabled(enabled, defaults: defaults)
    }

    func isFolderOn(_ folder: AriaKnowledgeCategory) -> Bool {
        controls.prefs.isCategoryEnabled(folder)
    }

    func setFolder(_ folder: AriaKnowledgeCategory, enabled: Bool) {
        controls.setCategory(folder, enabled: enabled, defaults: defaults)
    }

    func facts(in folder: AriaKnowledgeCategory) -> [AriaKnowledgeFact] {
        controls.listedFacts(in: folder)
    }

    func beginAdd(to folder: AriaKnowledgeCategory = .lifestyle) {
        editingID = nil
        draftCategory = folder.managedFolder()
        draftSummary = ""
        addError = nil
    }

    func beginEdit(_ fact: AriaKnowledgeFact) {
        editingID = fact.id
        draftCategory = fact.managedFolder
        draftSummary = fact.summary
        addError = nil
    }

    @discardableResult
    func commitDraft() -> Bool {
        let text = draftSummary
        if let id = editingID {
            guard controls.updateFact(id: id, summary: text, defaults: defaults) else {
                addError = Self.privacyRefusal
                return false
            }
        } else {
            guard controls.addFact(category: draftCategory, summary: text, defaults: defaults) != nil else {
                addError = Self.privacyRefusal
                return false
            }
        }
        draftSummary = ""
        editingID = nil
        addError = nil
        return true
    }

    func delete(_ fact: AriaKnowledgeFact) {
        controls.deleteFact(id: fact.id, defaults: defaults)
    }

    func setPersonaEnabled(_ enabled: Bool) {
        controls.setPersonaEnabled(enabled, defaults: defaults)
        let tags = enabled ? QualityOfLifeLivingStore.livingTags(defaults: defaults) : []
        AriaContextStore.shared.applyLivingCharacterTags(tags)
    }

    func clearPersona() {
        controls.clearPersona(defaults: defaults)
        AriaContextStore.shared.applyLivingCharacterTags([])
    }

    func setTone(_ tone: AriaCompanionTone) {
        controls.setTone(tone, defaults: defaults)
    }

    func setCheckInCadence(_ cadence: AriaCheckInCadence) {
        controls.setCheckInCadence(cadence, defaults: defaults)
    }

    static let privacyRefusal =
        "I can't store places, invites, addresses, or partner/cycle chips. Kinds and days-until only."
}
