import Foundation
import ForgeCore

/// The Share Sheet as a `MessageIngestionProvider`: the user selected text in
/// a conversation (or an exported chat) and handed it to Forge, on purpose.
///
/// Privacy contract
/// ----------------
/// What ARIA sees: nothing from this type. Its turns go straight into
/// `MessageContextEngine` inside this extension; only the resulting facts can
/// leave it, sealed to the app, and only after the user taps Remember with
/// "Remember life context" on.
/// What stays on-device: the shared text, in this extension's memory only.
/// The buffer is one-shot — `fetchTurns` empties it as it reads — so the
/// provider never holds text past that call, and nothing is written, cached,
/// or logged. Speaker names become keyed `ContactID`s inside
/// `SharedConversationParser`; phone numbers and emails are stripped by
/// `MessageTurn`.
final class ShareExtensionProvider: MessageIngestionProvider {
    let displayName = "Shared via Share Sheet"

    private var texts: [String]
    private let parser: SharedConversationParser
    private let sharedAt: Date

    init(texts: [String], hashKey: LifeContextHashKey, sharedAt: Date = Date()) {
        self.texts = texts
        self.parser = SharedConversationParser(hashKey: hashKey)
        self.sharedAt = sharedAt
    }

    func fetchTurns(since: Date) async throws -> [MessageTurn] {
        let buffered = texts
        texts = []
        return buffered
            .flatMap { parser.parse($0, sharedAt: sharedAt) }
            .filter { $0.timestamp >= since }
    }
}
