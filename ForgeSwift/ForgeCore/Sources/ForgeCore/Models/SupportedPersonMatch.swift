import Foundation

/// Pure matching for “who is this incoming share?”.
///
/// Lives in ForgeCore so CI can lock the rule that used to be implicit and
/// wrong: never attach a daughter's digest to the partner slot just because
/// the local store only held one person.
public enum SupportedPersonMatch {

    public struct Record: Equatable, Sendable {
        public let name: String
        public let role: String
        public let cloudID: String?

        public init(name: String, role: String, cloudID: String? = nil) {
            self.name = name
            self.role = role
            self.cloudID = cloudID
        }
    }

    public static func normalizeName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Same human, or one side still unlabeled. Partner vs daughter is never
    /// compatible — that is the failure this type exists to prevent.
    public static func rolesCompatible(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a == "other" || b == "other" { return true }
        return false
    }

    /// Index of the local person this CloudKit share belongs to, or `nil`.
    ///
    /// CloudKit owner id wins. Name+role is only a fallback when the local
    /// row has no id yet (typed in before the invite was accepted). An empty
    /// incoming id never matches the first person — that was the old bug.
    public static func bindIndex(
        people: [Record],
        incomingName: String,
        incomingRole: String,
        incomingCloudID: String
    ) -> Int? {
        let cloudID = incomingCloudID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cloudID.isEmpty else { return nil }

        if let i = people.firstIndex(where: { $0.cloudID == cloudID }) {
            return i
        }

        let name = normalizeName(incomingName)
        guard !name.isEmpty else { return nil }

        return people.firstIndex { person in
            (person.cloudID == nil || person.cloudID?.isEmpty == true)
                && normalizeName(person.name) == name
                && rolesCompatible(person.role, incomingRole)
        }
    }
}
