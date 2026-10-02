import ForgeCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// ============================================================
// MARK: - Share extension
// ============================================================
//
// Privacy contract
// ----------------
// What ARIA sees: nothing directly. If — and only if — Settings → Life
// Context has Messages on *and* "Remember life context" on, and the user taps
// Remember here, the extracted facts are sealed to the app's Curve25519 public
// key and dropped in the app group inbox; the app opens them later and on-device
// ARIA reads the brief. No network, ever: this target has no URLSession and no
// entitlement beyond the app group.
// What stays on-device: the shared text, in this process's memory, for one
// share. With Messages off it is not even loaded. Extraction runs here
// (`MessageContextEngine`), the user reviews the facts, and the process ends;
// the text is never written, cached, logged, or handed to the app. This
// extension can seal a box but cannot open one — the private key lives only in
// the app's Keychain.

/// Principal class (Info.plist `NSExtensionPrincipalClass`). Code-only.
final class ShareViewController: UIViewController {

    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let root = ShareRootView(model: model) { [weak self] in
            self?.finish()
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        model.start(items: extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? [])
    }

    private func finish() {
        model.discard()
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

// ------------------------------------------------------------
// MARK: Model
// ------------------------------------------------------------

/// Half a megabyte of text is a very long conversation; anything beyond it is
/// not read.
private let maxBytes = 512 * 1024

@MainActor
final class ShareModel: ObservableObject {

    enum Phase: Equatable {
        case loading
        case messagesOff
        case nothingShared
        case nothingFound
        case review
        case saved(Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var facts: [LifeContextFact] = []
    /// Remember is offered only when both switches allow it and the app has
    /// published its inbox key.
    @Published private(set) var canRemember = false

    private let defaults = UserDefaults(suiteName: LifeContextSettings.suiteName)
    private var publicKey: Data?

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: LifeContextSettings.suiteName)
    }

    func start(items: [NSExtensionItem]) {
        let settings = LifeContextSettings.load(from: defaults)
        guard settings.messagesEnabled else {
            // Checked before any attachment is loaded: with Messages off,
            // Forge reads nothing.
            phase = .messagesOff
            return
        }
        publicKey = LifeContextSettings.inboxPublicKey(in: defaults)
        let rememberAllowed = settings.rememberEnabled && publicKey != nil && Self.containerURL != nil
        Task {
            let texts = await Self.loadTexts(from: items)
            guard !texts.isEmpty else {
                phase = .nothingShared
                return
            }
            let key = Self.hashKey()
            let provider = ShareExtensionProvider(texts: texts, hashKey: key)
            do {
                let turns = try await provider.fetchTurns(since: .distantPast)
                let engine = MessageContextEngine(hashKey: key)
                let extracted = await Task.detached(priority: .userInitiated) {
                    engine.extract(from: turns)
                }.value
                facts = extracted
                canRemember = rememberAllowed
                phase = extracted.isEmpty ? .nothingFound : .review
            } catch {
                phase = .failed("Forge couldn't read that. Nothing was kept.")
            }
        }
    }

    /// The user tapped Remember: seal the facts to the app and forget them here.
    func remember() {
        guard canRemember, let publicKey, let container = Self.containerURL, !facts.isEmpty else { return }
        do {
            try LifeContextInbox.deposit(facts, toPublicKey: publicKey, container: container)
            phase = .saved(facts.count)
        } catch {
            phase = .failed("Forge couldn't save that. Nothing was kept.")
        }
        facts = []
    }

    func discard() {
        facts = []
    }

    /// This extension's own keyed-hash secret, so sharing the same
    /// conversation twice dedupes. If the Keychain is unavailable a one-off
    /// key is used for this share — dedup degrades, privacy does not.
    private static func hashKey() -> LifeContextHashKey {
        let store = KeychainStore(service: "com.forge.ForgeSwift.lifeContext.share")
        return (try? LifeContextHashKey.loadOrCreate(in: store, account: LifeContextVault.hashKeyAccount))
            ?? LifeContextHashKey.generate()
    }

    // MARK: Loading (memory only)

    nonisolated static func loadTexts(from items: [NSExtensionItem]) async -> [String] {
        var texts: [String] = []
        for item in items {
            for provider in item.attachments ?? []
            where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = await loadText(from: provider), !text.isEmpty {
                    texts.append(text)
                }
            }
            if texts.isEmpty, let attributed = item.attributedContentText?.string, !attributed.isEmpty {
                texts.append(String(attributed.prefix(maxBytes)))
            }
        }
        return texts
    }

    nonisolated static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: text(from: item))
            }
        }
    }

    nonisolated static func text(from item: NSSecureCoding?) -> String? {
        if let string = item as? String {
            return String(string.prefix(maxBytes))
        }
        if let data = item as? Data {
            return String(decoding: data.prefix(maxBytes), as: UTF8.self)
        }
        if let url = item as? URL, url.isFileURL {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: maxBytes) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        return nil
    }
}

// ------------------------------------------------------------
// MARK: View
// ------------------------------------------------------------

struct ShareRootView: View {
    @ObservedObject var model: ShareModel
    let finish: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeDS.Spacing.lg) {
                    content
                }
                .padding(ForgeDS.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ForgePalette.background.ignoresSafeArea())
            .navigationTitle("Forge Life Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { finish() }
                        .foregroundColor(ForgePalette.ember)
                        .accessibilityLabel("Close without keeping anything")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Reading on this iPhone…")
                .tint(ForgePalette.ember)
                .foregroundColor(ForgePalette.textSecondary)
                .accessibilityLabel("Reading on this iPhone")
        case .messagesOff:
            note(
                "Messages is off",
                "Turn it on in Forge → Settings → Life Context to share conversations. Nothing was read."
            )
            doneButton
        case .nothingShared:
            note("No text found", "Forge reads plain text — select the messages, then share. Nothing was kept.")
            doneButton
        case .nothingFound:
            note("Nothing to learn here", "Forge found no plans, trips or signals in this conversation. Nothing was kept.")
            doneButton
        case .review:
            review
        case .saved(let count):
            note(
                "Remembered",
                "\(count) fact\(count == 1 ? "" : "s") sealed for Forge on this iPhone. Open Forge → Settings → Life Context → What Forge knows to review or delete."
            )
            doneButton
        case .failed(let reason):
            note("Nothing kept", reason)
            doneButton
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.md) {
            Text("Forge read this conversation on this iPhone and found:")
                .font(.system(size: 14))
                .foregroundColor(ForgePalette.textSecondary)
            ForEach(model.facts) { fact in
                VStack(alignment: .leading, spacing: 3) {
                    Text(fact.summary)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ForgePalette.textPrimary)
                    Text("\(fact.kind.displayName) · \(fact.confidenceBand.rawValue.capitalized) confidence")
                        .font(.system(size: 12))
                        .foregroundColor(ForgePalette.textTertiary)
                }
                .padding(ForgeDS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: ForgeDS.Radius.md, style: .continuous)
                        .fill(ForgePalette.surface)
                )
                .accessibilityElement(children: .combine)
            }
            Text(model.canRemember
                 ? "Only these short facts are kept — never the messages. They're encrypted for Forge and stay on this iPhone."
                 : "\"Remember life context\" is off in Forge, so nothing will be kept. Turn it on in Forge → Settings → Life Context.")
                .font(.system(size: 12))
                .foregroundColor(ForgePalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if model.canRemember {
                Button {
                    model.remember()
                } label: {
                    Text("Remember")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: ForgeDS.Radius.md, style: .continuous)
                                .fill(ForgePalette.ember)
                        )
                }
                .accessibilityLabel("Remember these facts")
                .accessibilityHint("Seals them for Forge on this iPhone")
            }
            Button {
                finish()
            } label: {
                Text(model.canRemember ? "Discard" : "Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ForgePalette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: ForgeDS.Radius.md, style: .continuous)
                            .fill(ForgePalette.surfaceElevated)
                    )
            }
            .accessibilityLabel(model.canRemember ? "Discard these facts" : "Done")
        }
    }

    private var doneButton: some View {
        Button {
            finish()
        } label: {
            Text("Done")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: ForgeDS.Radius.md, style: .continuous)
                        .fill(ForgePalette.ember)
                )
        }
        .accessibilityLabel("Done")
    }

    private func note(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ForgePalette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.system(size: 14))
                .foregroundColor(ForgePalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
