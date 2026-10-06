import Foundation

/// Hobby Fit v1. Mentality is derived from the hobby path already computed
/// (social band, people-energy, working tendency). The enum stays on the
/// structured field. Speech uses the speak phrase only.
///
/// Lifestyle coach. Not a diagnosis. A dismissal is never cited.
public enum HobbyFit {

    public enum Signal: String, Sendable, Equatable {
        case quiet
        case open
        case drainedSocial = "drained_social"
        case restored
    }

    public enum Kind: String, Sendable, Equatable {
        case creative, social, outdoor, solo, learning
    }

    public enum Interest: String, Sendable, Equatable {
        case low, medium, high
    }

    public struct Hobby: Sendable, Equatable, Identifiable {
        public var id: String
        public var label: String
        public var kind: Kind
        public var interest: Interest
        public var lastEngagedAt: String?

        public init(
            id: String,
            label: String,
            kind: Kind,
            interest: Interest,
            lastEngagedAt: String? = nil
        ) {
            self.id = id
            self.label = label
            self.kind = kind
            self.interest = interest
            self.lastEngagedAt = lastEngagedAt
        }
    }

    public static func signal(
        socialBand: HobbyPathEngine.SocialBand,
        peopleEnergy: HobbyPathEngine.PeopleEnergy,
        working: UserWorkingModel.Snapshot
    ) -> Signal {
        if socialBand == .burnedOut { return .drainedSocial }
        if socialBand == .reserved { return .quiet }
        if working.tendency == .rebuilding || working.stance == .rebuildTrust {
            return .restored
        }
        if peopleEnergy == .open || socialBand == .sociable { return .open }
        if peopleEnergy == .thin,
           working.predictedFeel == .flat
            || working.tendency == .overreacher
            || working.tendency == .weekendDrop {
            return .drainedSocial
        }
        if peopleEnergy == .thin { return .quiet }
        return .restored
    }

    public static func speak(_ signal: Signal) -> String {
        switch signal {
        case .quiet: return "quiet stretch"
        case .open: return "up for a little more"
        case .drainedSocial: return "lots on lately"
        case .restored: return "a calmer patch"
        }
    }

    public static func canonLine(
        signal: Signal,
        curious: Bool = false,
        skipGroups: Bool = false
    ) -> String {
        if signal == .drainedSocial, skipGroups {
            return "You've had a lot on. Want me to skip group stuff for now and pick one quiet thing for tonight?"
        }
        if signal == .quiet, curious {
            return "Quiet stretch lately, and honestly it suits you. If you get curious, pottery nights tend to be small, and nobody judges a lumpy bowl. No pressure either way."
        }
        switch signal {
        case .quiet:
            return "It's been a quieter stretch. Want to try something low-key with one other person this week, or keep it solo for now? Both count."
        case .drainedSocial:
            return "Lots on lately. Something solo might hit better tonight, like cooking just for you, a good book or a headphones walk."
        case .open:
            return "Up for a little more, if you want it. A small plan with one person counts — so does keeping it light."
        case .restored:
            return "A calmer patch. Keep the free-day you already like, or leave the calendar alone. Both count."
        }
    }

    /// Only after a cool-down. Dismissals use ``dismissalLine``.
    public static func coolDownLine(label: String) -> String {
        guard let clean = sanitizeLabel(label) else { return "" }
        if clean.lowercased() == "hike club" {
            return "Hike club's still around if you ever want another look. It's not going anywhere."
        }
        return "\(clean)'s still around if you ever want another look. It's not going anywhere."
    }

    /// A dismissal never counts against the user and is never cited.
    public static func dismissalLine(label: String) -> String {
        _ = label
        return ""
    }

    public static func hobbies(from living: [LivingHobby]) -> [Hobby] {
        var out: [Hobby] = []
        for hobby in living {
            guard out.count < 8 else { break }
            let kind: Kind
            let interest: Interest
            switch hobby {
            case .cooking, .making, .music:
                kind = .creative
                interest = .medium
            case .outdoors:
                kind = .outdoor
                interest = .medium
            case .reading, .games, .gym:
                kind = .solo
                interest = .medium
            case .rest:
                kind = .solo
                interest = .low
            }
            out.append(Hobby(id: hobby.rawValue, label: hobby.title, kind: kind, interest: interest))
        }
        return out
    }

    public static func normalize(
        label raw: String,
        id hinted: String? = nil,
        kind rawKind: String? = nil,
        interest rawInterest: String? = nil,
        lastEngagedAt: String? = nil
    ) -> Hobby? {
        guard let label = sanitizeLabel(raw) else { return nil }
        let slug = slugify(label)
        let id: String
        if let hinted, hinted.range(of: "^[a-z0-9_]{1,32}$", options: .regularExpression) != nil {
            id = hinted
        } else {
            id = slug
        }
        guard !id.isEmpty else { return nil }
        let kind = Kind(rawValue: rawKind ?? "") ?? inferredKind(label)
        let interest = Interest(rawValue: rawInterest ?? "") ?? .medium
        let engaged = validDate(lastEngagedAt)
        return Hobby(id: id, label: label, kind: kind, interest: interest, lastEngagedAt: engaged)
    }

    public static func speechIsClean(_ text: String) -> Bool {
        let lower = text.lowercased()
        let banned = [
            "introvert", "isolated", "anxious", "feeling steadier",
            "social tank", "restorative", "energy's higher",
            "drained_social", "mentality_signal",
        ]
        if banned.contains(where: { lower.contains($0) }) { return false }
        if lower.range(of: #"\brestored\b"#, options: .regularExpression) != nil { return false }
        return true
    }

    static func sanitizeLabel(_ raw: String) -> String? {
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        if collapsed.contains("@") || collapsed.contains("http") || collapsed.contains(where: \.isNumber) {
            return nil
        }
        let kept = collapsed.split(separator: " ").filter { token in
            let lower = token.lowercased()
            return !lower.hasPrefix("partner_") && !lower.hasPrefix("cycle:")
                && !lower.hasPrefix("support_cycle:")
        }
        var text = kept.joined(separator: " ")
        if text.count > 48 { text = String(text.prefix(48)).trimmingCharacters(in: .whitespaces) }
        guard !text.isEmpty else { return nil }
        return text
    }

    private static func slugify(_ label: String) -> String {
        let lowered = label.lowercased()
        let mapped = lowered.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : "_"
        }
        let slug = String(mapped).split(separator: "_").joined(separator: "_")
        return String(slug.prefix(32))
    }

    private static func inferredKind(_ label: String) -> Kind {
        let lower = label.lowercased()
        if ["hike", "trail", "outdoor", "outside", "walk"].contains(where: { lower.contains($0) }) {
            return .outdoor
        }
        if ["class", "course", "learn", "study", "language"].contains(where: { lower.contains($0) }) {
            return .learning
        }
        if ["club", "group", "team", "friends"].contains(where: { lower.contains($0) }) {
            return .social
        }
        if ["read", "book", "solo", "alone", "home"].contains(where: { lower.contains($0) }) {
            return .solo
        }
        return .creative
    }

    private static func validDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard raw.range(
            of: #"^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2})?Z?)?$"#,
            options: .regularExpression
        ) != nil else { return nil }
        return raw
    }
}
