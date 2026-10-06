import Foundation

// ============================================================
// MARK: - Your people
// ============================================================

/// A lightweight people graph for lifestyle coaching.
///
/// Not a CRM and not a clinical social history. The user opts in, then
/// confirms a few people. ARIA remembers a first name, a coach label, and
/// an optional on-device contact id. Phone numbers, emails, and the rest
/// of the address book are never stored and never enter a prompt.
public enum PeopleDirectory {

    public static let maxPeople = 8

    public enum Relation: String, Codable, CaseIterable, Sendable {
        case partner
        case roommate
        case trainingBuddy = "training_buddy"
        case family
        case coworker
        case friend

        public var title: String {
            switch self {
            case .partner: return "partner"
            case .roommate: return "roommate"
            case .trainingBuddy: return "training buddy"
            case .family: return "family"
            case .coworker: return "coworker"
            case .friend: return "friend"
            }
        }
    }

    public enum ContactsAccess: String, Codable, Sendable {
        case notAsked = "not_asked"
        case denied
        case granted
    }

    public struct Person: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        /// On-device Contacts identifier. Never copied into ARIA tags.
        public var contactIdentifier: String?
        public var firstName: String
        public var relation: Relation

        public init(id: String = UUID().uuidString, contactIdentifier: String? = nil, firstName: String, relation: Relation) {
            self.id = id
            self.contactIdentifier = contactIdentifier
            self.firstName = firstName
            self.relation = relation
        }
    }

    public struct Directory: Codable, Equatable, Sendable {
        public var optedIn: Bool
        public var contactsAccess: ContactsAccess
        public var people: [Person]

        public init(optedIn: Bool = false, contactsAccess: ContactsAccess = .notAsked, people: [Person] = []) {
            self.optedIn = optedIn
            self.contactsAccess = contactsAccess
            self.people = people
        }

        /// What coaching may see. Denied or not opted in is an empty graph.
        public var coachingPeople: [Person] {
            guard optedIn else { return [] }
            return Array(people.prefix(PeopleDirectory.maxPeople))
        }

        public var ariaTags: [String] {
            guard optedIn else { return [] }
            var tags = ["people:count:\(coachingPeople.count)"]
            for person in coachingPeople {
                tags.append("people:\(person.firstName):\(person.relation.rawValue)")
            }
            return tags
        }

        public var spokenLine: String {
            guard optedIn else {
                return "I don't have your people yet. That's fine — name them in Lifestyle if you want. I keep a first name and a label on this phone, not a phone number."
            }
            guard !coachingPeople.isEmpty else {
                return "You're opted in, and the list is empty. Add a first name in Lifestyle, or leave it blank."
            }
            let listed = coachingPeople.map { "\($0.firstName) (\($0.relation.title))" }.joined(separator: ", ")
            return "Your people: \(listed). A quieter week leaves them off the calendar. A reserved week can stretch toward one of them later — not a stranger, and not a diagnosis."
        }
    }

    /// First name only. Rejects emails, numbers, and anything that looks like contact PII.
    public static func admit(
        rawName: String,
        relation: Relation = .friend,
        contactIdentifier: String? = nil
    ) -> Person? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerAll = trimmed.lowercased()
        if lowerAll.contains("@") || lowerAll.contains("http") || trimmed.rangeOfCharacter(from: .decimalDigits) != nil {
            return nil
        }
        let token = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .punctuationCharacters) ?? ""
        guard (1...24).contains(token.count) else { return nil }
        let lower = token.lowercased()
        if lower.contains("@") || lower.contains("http") || lower.contains("://") { return nil }
        if token.contains(":") { return nil }
        if token.rangeOfCharacter(from: .decimalDigits) != nil { return nil }
        let id = contactIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedId = (id?.isEmpty == false) ? id : nil
        return Person(contactIdentifier: storedId, firstName: token, relation: relation)
    }

    public static func isQuestion(_ text: String) -> Bool {
        let lower = text.lowercased()
        let phrases = [
            "who are your people",
            "who are my people",
            "my people",
            "your people",
            "name my people",
            "who matters to me",
        ]
        return phrases.contains { lower.contains($0) }
    }

    /// Extra coaching when a confirmed person should shape the hobby path.
    public static func hobbySuffix(path: HobbyPathEngine.Path, people: [Person]) -> String {
        guard let person = people.first else { return "" }
        switch path {
        case .openGently:
            return " If you want company later, \(person.firstName) (\(person.relation.title)) is someone you already named — not a stranger."
        case .restoreQuiet:
            return " Leave \(person.firstName) off the calendar this week."
        case .keepRhythm, .explore:
            return ""
        }
    }

    public static func promptLine(for directory: Directory) -> String {
        let people = directory.coachingPeople
        guard directory.optedIn else { return "" }
        guard !people.isEmpty else { return "People: none named yet." }
        let listed = people.map { "\($0.firstName) (\($0.relation.title))" }.joined(separator: ", ")
        return "People: \(listed)."
    }
}

public enum PeopleDirectoryStore {
    public static let storageKey = "forge.people.directory.v1"

    public static func load(defaults: UserDefaults = .standard) -> PeopleDirectory.Directory {
        guard let data = defaults.data(forKey: storageKey),
              let directory = try? JSONDecoder().decode(PeopleDirectory.Directory.self, from: data) else {
            return PeopleDirectory.Directory()
        }
        return directory
    }

    public static func save(_ directory: PeopleDirectory.Directory, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(directory) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// Forget the graph. iOS Contacts permission is revoked in Settings, not here.
    public static func forget(defaults: UserDefaults = .standard) {
        var directory = load(defaults: defaults)
        directory.optedIn = false
        directory.people = []
        save(directory, defaults: defaults)
    }
}
