import Foundation
import ForgeCore

// Dummy orchestra only. Compiled out of production builds with
// FORGE_DUMMY_ORCHESTRA — see AriaDummyOrchestra.swift.
#if FORGE_DUMMY_ORCHESTRA

/// A scripted week of messages so the Life Context pipeline can be exercised
/// without anyone's real conversations.
///
/// Privacy contract
/// ----------------
/// What ARIA sees: the facts the engine extracts from this script, exactly as
/// for a real share — and only after the tester taps Remember.
/// What stays on-device: the script is fixed English text written for testing;
/// it names no real person, and its contacts are keyed hashes like any other.
/// Nothing here is cached or written.
struct SyntheticMessageProvider: MessageIngestionProvider {
    let displayName = "Synthetic conversation (Debug)"
    let hashKey: LifeContextHashKey
    var now: Date = Date()

    func fetchTurns(since: Date) async throws -> [MessageTurn] {
        let friend = MessageTurn.Sender.them(ContactID(hashing: "forge.synthetic.friend", key: hashKey))
        let colleague = MessageTurn.Sender.them(ContactID(hashing: "forge.synthetic.colleague", key: hashKey))
        let script: [(sender: MessageTurn.Sender, text: String, minutesAgo: Double)] = [
            (friend, "Want to grab dinner Friday at 7?", 180),
            (.me, "Yes! See you then", 175),
            (.me, "My flight lands Thursday at 6pm", 170),
            (colleague, "Can you send me the deck by Thursday?", 120),
            (.me, "Yep, will do", 118),
            (.me, "Work has been insane, I'm so overwhelmed and stressed", 115),
            (friend, "My sister's wedding is Saturday, you're coming right?", 60),
            (.me, "Definitely, can't wait", 58),
            (friend, "We should get coffee sometime", 30),
            (.me, "maybe!", 29),
        ]
        return script
            .map { MessageTurn(sender: $0.sender, text: $0.text, timestamp: now.addingTimeInterval(-$0.minutesAgo * 60)) }
            .filter { $0.timestamp >= since }
    }
}

#endif
