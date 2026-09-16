import Foundation

/// How ARIA talks as a friend. Same four beats as onboarding Tone —
/// lifestyle-coach voice, never a clinician.
public enum AriaCompanionTone: String, Codable, CaseIterable, Sendable {
    case checkIn
    case space
    case patterns
    case peer

    public var title: String {
        switch self {
        case .checkIn: return "Check-in"
        case .space: return "Space"
        case .patterns: return "Patterns"
        case .peer: return "Honest peer"
        }
    }

    public var line: String {
        switch self {
        case .checkIn:
            return "I'll check in — trainer flavor when you want it, friend first."
        case .space:
            return "I'll give you space and still be here."
        case .patterns:
            return "I'll notice patterns with you — not to judge."
        case .peer:
            return "I'll be an honest peer. Kind, and I won't flinch."
        }
    }
}

/// How often ARIA asks how life is going. Local only — no remote scheduler.
public enum AriaCheckInCadence: String, Codable, CaseIterable, Sendable {
    case off
    case weekly
    case daily

    public var title: String {
        switch self {
        case .off: return "Off"
        case .weekly: return "Weekly"
        case .daily: return "A short daily hello"
        }
    }

    public var detail: String {
        switch self {
        case .off: return "I won't nudge a check-in. You can still open one from Settings."
        case .weekly: return "About once a week, when you're in chat."
        case .daily: return "A lighter hello most days, still on this phone."
        }
    }

    /// Nil means never due.
    public var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .weekly: return 6 * 24 * 60 * 60
        case .daily: return 20 * 60 * 60
        }
    }
}

/// On-device ARIA controls: memory folders, living persona, tone, check-ins.
/// Default is remember-everything so existing installs do not change until
/// someone opens the screen.
public struct AriaCompanionPreferences: Codable, Equatable, Sendable {
    public var memoryEnabled: Bool
    public var disabledCategories: [String]
    public var personaEnabled: Bool
    public var tone: AriaCompanionTone
    public var checkInCadence: AriaCheckInCadence

    public static let `default` = AriaCompanionPreferences(
        memoryEnabled: true,
        disabledCategories: [],
        personaEnabled: true,
        tone: .checkIn,
        checkInCadence: .weekly
    )

    public init(
        memoryEnabled: Bool = true,
        disabledCategories: [String] = [],
        personaEnabled: Bool = true,
        tone: AriaCompanionTone = .checkIn,
        checkInCadence: AriaCheckInCadence = .weekly
    ) {
        self.memoryEnabled = memoryEnabled
        self.disabledCategories = disabledCategories
        self.personaEnabled = personaEnabled
        self.tone = tone
        self.checkInCadence = checkInCadence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .memoryEnabled) ?? true
        disabledCategories = try c.decodeIfPresent([String].self, forKey: .disabledCategories) ?? []
        personaEnabled = try c.decodeIfPresent(Bool.self, forKey: .personaEnabled) ?? true
        tone = try c.decodeIfPresent(AriaCompanionTone.self, forKey: .tone) ?? .checkIn
        checkInCadence = try c.decodeIfPresent(AriaCheckInCadence.self, forKey: .checkInCadence) ?? .weekly
    }

    public func isCategoryEnabled(_ category: AriaKnowledgeCategory, kind: String = "") -> Bool {
        guard memoryEnabled else { return false }
        let folder = category.managedFolder(kind: kind)
        return !disabledCategories.contains(folder.rawValue)
    }

    public func allowsAutoFiling(category: AriaKnowledgeCategory, kind: String = "") -> Bool {
        isCategoryEnabled(category, kind: kind)
    }

    public func allowsAutoFiling(_ fact: AriaKnowledgeFact) -> Bool {
        allowsAutoFiling(category: fact.category, kind: fact.kind)
    }

    public func allowsCoaching(category: AriaKnowledgeCategory, kind: String = "") -> Bool {
        isCategoryEnabled(category, kind: kind)
    }

    public func allowsCoaching(_ fact: AriaKnowledgeFact) -> Bool {
        allowsCoaching(category: fact.category, kind: fact.kind)
    }
}

public enum AriaCompanionPreferencesStore: Sendable {
    public static let defaultsKey = "forge.aria.companionPreferences.v1"

    public static func load(defaults: UserDefaults = .standard) -> AriaCompanionPreferences {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(AriaCompanionPreferences.self, from: data) else {
            return .default
        }
        return decoded
    }

    public static func save(_ prefs: AriaCompanionPreferences, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}

/// Calendar titles, attendees, and places never belong in ARIA memory —
/// kinds and days-until only. Partner/cycle prefixes never land in the vault,
/// tags, or recentPatterns. User add/edit goes through the same gate.
///
/// Denied lifestyle prefixes mirror `routes/aria.py` `_DENIED_LIFESTYLE`.
public enum AriaFactPrivacy: Sendable {
    public static let privacyLine =
        "On this phone. Calendar titles, people on the invite, places, and partner or cycle chips never land here. I don't share this off-device."

    /// Same prefixes Python inbound refuses. `partner_` covers partner_name /
    /// partner_phase / partner_day / partner_cycle.
    public static let deniedLifestylePrefixes: [String] = [
        "partner_",
        "support_cycle:",
        "partner_name:",
        "partner_phase:",
        "partner_day:",
        "partner_cycle:",
        "cycle:fertile",
        "cycle:tww",
        "cycle:goal:trying",
        "cycle:bleeding",
        "cycle:condition",
    ]

    public static func isDeniedLifestyleToken(_ token: String) -> Bool {
        let lower = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        return deniedLifestylePrefixes.contains { lower.hasPrefix($0) }
    }

    public static func sanitizeSummary(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let stripped = tokens.compactMap { token -> String? in
            let piece = String(token)
            let lower = piece.lowercased()
            if piece.contains("@") { return nil }
            if lower.hasPrefix("calendar:title:") { return nil }
            if lower.hasPrefix("calendar:attendee:") { return nil }
            if lower.hasPrefix("calendar:place:") { return nil }
            if lower.hasPrefix("calendar:location:") { return nil }
            if isDeniedLifestyleToken(piece) { return nil }
            return piece
        }
        text = stripped.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .contains(where: { isDeniedLifestyleToken(String($0)) }) {
            return ""
        }

        let original = raw.lowercased()
        let hadCalendarPrefix = original.contains("calendar:title")
            || original.contains("calendar:place")
            || original.contains("calendar:location")
            || original.contains("calendar:attendee")
        if hadCalendarPrefix || looksLikeCalendarLeak(text) {
            if let days = SpokenEventParser.daysUntilWedding(in: text)
                ?? SpokenEventParser.daysUntilWedding(in: raw) {
                return "Wedding in \(days) day\(days == 1 ? "" : "s") — you told me."
            }
            let lower = text.lowercased()
            let kinds = FakeCalendarEvent.Kind.allCases.filter { lower.contains($0.rawValue) }
            if !kinds.isEmpty {
                return "This week: \(kinds.map(\.spokenLabel).joined(separator: ", "))."
            }
            if lower.contains("wedding") {
                return "A wedding — you told me."
            }
            return ""
        }
        return text
    }

    public static func looksLikeCalendarLeak(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("@") { return true }
        if lower.contains("attendee") { return true }
        if lower.contains("calendar:title") { return true }
        if lower.contains("calendar:place") { return true }
        if lower.contains("calendar:location") { return true }
        if streetPattern(in: lower) { return true }
        return false
    }

    private static func streetPattern(in lower: String) -> Bool {
        let markers = [" street", " st.", " avenue", " ave", " road", " rd.", " boulevard", " blvd"]
        guard markers.contains(where: { lower.contains($0) }) else { return false }
        return lower.contains { $0.isNumber }
    }
}

/// Deterministic editor for ARIA memory + persona + voice prefs.
/// SwiftUI holds this; tests drive it with a suite UserDefaults.
public struct AriaMemoryControls: Equatable {
    public var ledger: AriaKnowledgeLedger
    public var persona: QualityOfLifePersona
    public var interviewCompleted: Bool
    public var prefs: AriaCompanionPreferences

    public init(
        ledger: AriaKnowledgeLedger = AriaKnowledgeLedger(),
        persona: QualityOfLifePersona = .balanced,
        interviewCompleted: Bool = false,
        prefs: AriaCompanionPreferences = .default
    ) {
        self.ledger = ledger
        self.persona = persona
        self.interviewCompleted = interviewCompleted
        self.prefs = prefs
    }

    public static func load(defaults: UserDefaults = .standard) -> AriaMemoryControls {
        AriaMemoryControls(
            ledger: AriaKnowledgeLedgerStore.load(defaults: defaults),
            persona: QualityOfLifeLivingStore.loadPersona(defaults: defaults),
            interviewCompleted: QualityOfLifeLivingStore.hasCompletedInterview(defaults: defaults),
            prefs: AriaCompanionPreferencesStore.load(defaults: defaults)
        )
    }

    public func listedFacts(in category: AriaKnowledgeCategory) -> [AriaKnowledgeFact] {
        ledger.facts(inManaged: category)
    }

    public func coachingFacts(in category: AriaKnowledgeCategory) -> [AriaKnowledgeFact] {
        guard prefs.allowsCoaching(category: category) else { return [] }
        return ledger.facts(inManaged: category)
    }

    public var memoryStatusLine: String {
        if !prefs.memoryEnabled { return "Memory off" }
        let n = ledger.facts.count
        if n == 0 { return "Nothing stored yet" }
        return n == 1 ? "1 note" : "\(n) notes"
    }

    /// Toggle use/surface only. Stored notes stay until the user deletes them.
    public mutating func setMemoryEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        prefs.memoryEnabled = enabled
        AriaCompanionPreferencesStore.save(prefs, defaults: defaults)
    }

    public mutating func setCategory(_ category: AriaKnowledgeCategory, enabled: Bool, defaults: UserDefaults = .standard) {
        let folder = category.managedFolder()
        var next = Set(prefs.disabledCategories)
        if enabled {
            next.remove(folder.rawValue)
        } else {
            next.insert(folder.rawValue)
        }
        prefs.disabledCategories = AriaKnowledgeCategory.managedCases
            .map(\.rawValue)
            .filter { next.contains($0) }
        AriaCompanionPreferencesStore.save(prefs, defaults: defaults)
    }

    /// User-authored note. Writes even when memory is off so the vault stays editable.
    @discardableResult
    public mutating func addFact(
        category: AriaKnowledgeCategory,
        summary: String,
        defaults: UserDefaults = .standard
    ) -> AriaKnowledgeFact? {
        let cleaned = AriaFactPrivacy.sanitizeSummary(summary)
        guard !cleaned.isEmpty else { return nil }
        let fact = AriaKnowledgeFact(
            category: category.managedFolder(),
            kind: "user",
            summary: cleaned,
            source: "user"
        )
        ledger.file(fact)
        AriaKnowledgeLedgerStore.save(ledger, defaults: defaults)
        return fact
    }

    @discardableResult
    public mutating func updateFact(id: String, summary: String, defaults: UserDefaults = .standard) -> Bool {
        let ok = ledger.updateSummary(id: id, summary: summary)
        if ok { AriaKnowledgeLedgerStore.save(ledger, defaults: defaults) }
        return ok
    }

    public mutating func deleteFact(id: String, defaults: UserDefaults = .standard) {
        ledger.remove(id: id)
        AriaKnowledgeLedgerStore.save(ledger, defaults: defaults)
    }

    public mutating func clearFolder(_ category: AriaKnowledgeCategory, defaults: UserDefaults = .standard) {
        ledger.removeAll(inManaged: category)
        AriaKnowledgeLedgerStore.save(ledger, defaults: defaults)
    }

    public mutating func clearAllMemory(defaults: UserDefaults = .standard) {
        ledger.clearAll()
        AriaKnowledgeLedgerStore.save(ledger, defaults: defaults)
    }

    public mutating func setPersonaEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        prefs.personaEnabled = enabled
        AriaCompanionPreferencesStore.save(prefs, defaults: defaults)
    }

    public mutating func savePersona(_ next: QualityOfLifePersona, defaults: UserDefaults = .standard) {
        persona = next
        QualityOfLifeLivingStore.savePersona(next, defaults: defaults)
        QualityOfLifeLivingStore.markInterviewCompleted(defaults: defaults)
        interviewCompleted = true
    }

    public mutating func clearPersona(defaults: UserDefaults = .standard) {
        persona = .balanced
        interviewCompleted = false
        QualityOfLifeLivingStore.clearPersona(defaults: defaults)
    }

    public mutating func setTone(_ tone: AriaCompanionTone, defaults: UserDefaults = .standard) {
        prefs.tone = tone
        AriaCompanionPreferencesStore.save(prefs, defaults: defaults)
    }

    public mutating func setCheckInCadence(_ cadence: AriaCheckInCadence, defaults: UserDefaults = .standard) {
        prefs.checkInCadence = cadence
        AriaCompanionPreferencesStore.save(prefs, defaults: defaults)
    }
}

/// VoiceOver copy + Reduce Motion contract for the vault screen.
/// Strings stay in ForgeCore so XCTest can lock them without spinning SwiftUI.
public enum AriaMemoryAccess: Sendable {
    public static let rememberMeLabel = "Remember me"
    public static let rememberMeHint =
        "Off does not delete notes. ARIA stops using them until you turn this back on."
    public static let personaLabel = "Who you are"
    public static let personaHint =
        "Off does not forget who you are. ARIA stops using the living profile until you turn this back on."
    public static let folderUseHint = "Off does not delete notes in this folder."
    public static let updatePersonaLabel = "Update who I am"
    public static let tellPersonaLabel = "Tell ARIA who you are"
    public static let forgetPersonaLabel = "Forget who I am"
    public static let forgetPersonaHint =
        "Clears the living profile. Folder notes stay until you delete them."
    public static let saveNoteLabel = "Save note"
    public static let cancelEditorLabel = "Cancel"
    public static let noteFieldLabel = "Note"
    public static let folderPickerLabel = "Folder"
    public static let howITalkHeader = "How I talk"
    public static let checkInsHeader = "Check-ins"

    public static func rememberMeValue(isOn: Bool) -> String { isOn ? "On" : "Off" }

    public static func folderUseLabel(_ folder: AriaKnowledgeCategory) -> String {
        "ARIA may use \(folder.title)"
    }

    public static func addNoteLabel(folder: AriaKnowledgeCategory) -> String {
        "Add a note in \(folder.title)"
    }

    public static func editNoteLabel(folder: AriaKnowledgeCategory, summary: String) -> String {
        "Edit \(folder.title) note, \(clipped(summary))"
    }

    public static func deleteNoteLabel(folder: AriaKnowledgeCategory, summary: String) -> String {
        "Delete \(folder.title) note, \(clipped(summary))"
    }

    public static func toneLabel(_ tone: AriaCompanionTone, selected: Bool) -> String {
        selected ? "Tone, \(tone.title), selected" : "Tone, \(tone.title)"
    }

    public static func checkInLabel(_ cadence: AriaCheckInCadence, selected: Bool) -> String {
        selected ? "Check-in, \(cadence.title), selected" : "Check-in, \(cadence.title)"
    }

    public static func personaActionLabel(interviewCompleted: Bool) -> String {
        interviewCompleted ? updatePersonaLabel : tellPersonaLabel
    }

    /// Vault screens freeze transitions when Reduce Motion is on.
    public static func shouldAnimate(reduceMotion: Bool) -> Bool { !reduceMotion }

    private static func clipped(_ summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80))
    }
}
