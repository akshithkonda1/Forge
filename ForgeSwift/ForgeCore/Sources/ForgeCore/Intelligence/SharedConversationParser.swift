import Foundation

// ============================================================
// MARK: - Shared conversation parser
// ============================================================
//
// Privacy contract
// ----------------
// What ARIA / the backend sees: nothing from this file. It turns text the user
// explicitly handed to Forge (Share Sheet) into `MessageTurn`s for the engine.
// What stays on-device: the text, in memory, for one `parse` call. Speaker
// names are replaced by a keyed `ContactID` the moment they are read — no
// name, handle or number survives into a turn — and phone numbers and email
// addresses are stripped from message text by `MessageTurn`'s initializer.
// Nothing is cached, logged, or written.
//
// Formats understood, one message per line:
//   "Sam: dinner friday?"                       (copied / typed)
//   "[10/2/26, 7:41:03 PM] Sam: dinner friday?"  (WhatsApp export, iOS)
//   "10/2/26, 7:41 PM - Sam: dinner friday?"     (WhatsApp export, Android)
// Lines without a speaker continue the previous message; text with no
// speakers at all becomes one message from an unknown sender, so only plans,
// events and travel can be read from it — health, stress and commitments are
// only ever taken from the user's own messages.

public struct SharedConversationParser: Sendable {

    /// Speaker names that mean the user. Compared case-insensitively.
    public var selfAliases: Set<String>
    public var maxTurns: Int
    public var maxCharacters: Int

    private let hashKey: LifeContextHashKey

    public static let defaultSelfAliases: Set<String> = ["me", "myself", "you (me)"]

    public init(
        hashKey: LifeContextHashKey,
        selfAliases: Set<String> = SharedConversationParser.defaultSelfAliases,
        maxTurns: Int = 2_000,
        maxCharacters: Int = 200_000
    ) {
        self.hashKey = hashKey
        self.selfAliases = Set(selfAliases.map { $0.lowercased() })
        self.maxTurns = maxTurns
        self.maxCharacters = maxCharacters
    }

    private static let bracketed = try? NSRegularExpression(
        pattern: #"^\[([^\]]{6,40})\]\s*([^:\[\]]{1,40}):\s+(.*)$"#
    )
    private static let dashed = try? NSRegularExpression(
        pattern: #"^(\d{1,4}[./-]\d{1,2}[./-]\d{1,4},?\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp]\.?[Mm]\.?)?)\s+-\s+([^:]{1,40}):\s+(.*)$"#
    )
    private static let named = try? NSRegularExpression(
        pattern: #"^([A-Za-z][A-Za-z .'\-]{0,30}):\s+(.+)$"#
    )
    /// "Label:" prefixes that are not a person.
    private static let notSpeakers: Set<String> = [
        "note", "notes", "ps", "p.s", "re", "fyi", "update", "todo", "to do", "subject", "reminder", "edit",
    ]
    /// WhatsApp's own system lines.
    private static let systemMarkers = ["end-to-end encrypted", "<media omitted>", "this message was deleted"]

    /// `sharedAt` stamps every message whose own timestamp cannot be read; each
    /// gets one more second so order survives.
    public func parse(_ text: String, sharedAt: Date) -> [MessageTurn] {
        let bounded = String(text.prefix(max(0, maxCharacters)))
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        var drafts: [(sender: MessageTurn.Sender, text: String, timestamp: Date?)] = []

        for rawLine in bounded.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lowered = line.lowercased()
            if Self.systemMarkers.contains(where: { lowered.contains($0) }) { continue }

            if let parsed = speakerLine(line, detector: detector) {
                drafts.append((sender: sender(for: parsed.speaker), text: parsed.message, timestamp: parsed.timestamp))
            } else if let last = drafts.indices.last {
                drafts[last].text += "\n" + line
            } else {
                let unknown = MessageTurn.Sender.them(ContactID(hashing: "forge.unknown.sender", key: hashKey))
                drafts.append((sender: unknown, text: line, timestamp: nil))
            }
            if drafts.count >= maxTurns { break }
        }

        var turns: [MessageTurn] = []
        turns.reserveCapacity(drafts.count)
        for (offset, draft) in drafts.enumerated() {
            let fallback = sharedAt.addingTimeInterval(TimeInterval(offset))
            turns.append(MessageTurn(sender: draft.sender, text: draft.text, timestamp: draft.timestamp ?? fallback))
        }
        return turns
    }

    private func sender(for speaker: String) -> MessageTurn.Sender {
        let name = speaker.trimmingCharacters(in: .whitespaces).lowercased()
        if selfAliases.contains(name) { return .me }
        return .them(ContactID(hashing: name, key: hashKey))
    }

    private func speakerLine(
        _ line: String,
        detector: NSDataDetector?
    ) -> (speaker: String, message: String, timestamp: Date?)? {
        let range = NSRange(location: 0, length: (line as NSString).length)
        for regex in [Self.bracketed, Self.dashed] {
            guard let regex, let match = regex.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges == 4 else { continue }
            let stamp = substring(line, match.range(at: 1))
            let speaker = substring(line, match.range(at: 2))
            let message = substring(line, match.range(at: 3))
            guard !speaker.isEmpty, !message.isEmpty else { continue }
            return (speaker, message, timestamp(from: stamp, detector: detector))
        }
        if let regex = Self.named, let match = regex.firstMatch(in: line, options: [], range: range),
           match.numberOfRanges == 3 {
            let speaker = substring(line, match.range(at: 1))
            let message = substring(line, match.range(at: 2))
            // "Note: buy milk" and "PS: …" are not people; three words is the
            // most a speaker label is allowed to be.
            let words = speaker.split(separator: " ")
            if words.count <= 3, !message.isEmpty, !Self.notSpeakers.contains(speaker.lowercased()) {
                return (speaker, message, nil)
            }
        }
        return nil
    }

    /// An export's own timestamp. It carries an explicit date, so it does not
    /// depend on today's clock.
    private func timestamp(from stamp: String, detector: NSDataDetector?) -> Date? {
        guard let detector else { return nil }
        let range = NSRange(location: 0, length: (stamp as NSString).length)
        return detector.firstMatch(in: stamp, options: [], range: range)?.date
    }

    private func substring(_ line: String, _ range: NSRange) -> String {
        guard range.location != NSNotFound else { return "" }
        return (line as NSString).substring(with: range).trimmingCharacters(in: .whitespaces)
    }
}
