import ForgeCore
import Messages
import SwiftUI
import UIKit

// ============================================================
// MARK: - Messages app extension
// ============================================================

/// Forge's iMessage app. It does one thing: carry a support invite into a
/// conversation, and keep the resulting bubble honest afterwards.
///
/// **It is not a second copy of the cycle UI.** This target cannot read a
/// `MenstrualCycleSnapshot`, a `PartnerCycleDigest`, or anything a user logs —
/// it compiles `PartnerInvitePayload.swift` and nothing else from the app. The
/// only cycle-adjacent thing it ever holds is a CloudKit share URL, which is
/// inert without an Apple ID CloudKit has already accepted.
///
/// It is also **not gated**. No StoreKit, no receipt check, no entitlement flag
/// — see the note on `InviteRootView`.
final class MessagesViewController: MSMessagesAppViewController {

    private var host: UIHostingController<InviteRootView>?
    private var scene: InviteScene = .composeEmpty

    // ------------------------------------------------------------
    // MARK: Lifecycle
    // ------------------------------------------------------------

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        installHost()
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        resolveScene(for: conversation)
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        resolveScene(for: conversation)
        // A tap on a bubble is a request to read it, and the compact sheet is
        // too short for the disclosure lists that make the invite legible.
        requestPresentationStyle(.expanded)
    }

    override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        super.didReceive(message, conversation: conversation)
        resolveScene(for: conversation)
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        // The compact and expanded layouts differ enough that the scene has to
        // be re-rendered, not just resized.
        render()
    }

    override func didStartSending(_ message: MSMessage, conversation: MSConversation) {
        super.didStartSending(message, conversation: conversation)
        // Consumed on send. The staged invite is a one-shot: leaving it in place
        // would let the same invite be dropped into a second conversation
        // without the owner ever choosing that second person.
        PartnerInviteHandoff.clear()
    }

    // ------------------------------------------------------------
    // MARK: Scene resolution
    // ------------------------------------------------------------

    /// Decide once what this extension is looking at. Everything downstream
    /// reads the result rather than re-deriving it.
    private func resolveScene(for conversation: MSConversation) {
        if let message = conversation.selectedMessage, let url = message.url {
            guard let payload = PartnerInvitePayload(url: url) else {
                scene = .composeEmpty
                render()
                return
            }
            guard payload.isReadable else {
                scene = .unreadable
                render()
                return
            }
            // Sender identity comes from Messages, not from the payload. A
            // payload field would be attacker-controlled by whoever crafted the
            // URL; the participant identifier is not.
            let isMine = message.senderParticipantIdentifier == conversation.localParticipantIdentifier
            scene = isMine
                ? .sent(payload,
                        revoked: PartnerInviteRevocation.wasRevoked(shareURL: payload.shareURL))
                : .received(payload,
                            accepted: PartnerInviteAcceptance.hasAccepted(shareURL: payload.shareURL))
        } else if let staged = PartnerInviteHandoff.staged() {
            scene = .composeStaged(staged)
        } else {
            scene = .composeEmpty
        }
        render()
    }

    // ------------------------------------------------------------
    // MARK: Actions
    // ------------------------------------------------------------

    private func actions() -> InviteActions {
        InviteActions(
            insert: { [weak self] payload in self?.insert(payload) },
            sendStatusUpdate: { [weak self] status in self?.sendStatusUpdate(status) },
            openApp: { [weak self] in self?.openApp() },
            open: { [weak self] url in self?.open(url) },
            requestExpanded: { [weak self] in self?.requestPresentationStyle(.expanded) },
            isCompact: presentationStyle == .compact
        )
    }

    /// Put the invite card in the input field. It does **not** send — an
    /// extension cannot, and should not be able to. The user taps send.
    private func insert(_ payload: PartnerInvitePayload) {
        guard let conversation = activeConversation else { return }
        let message = InviteBubble.message(for: payload, session: MSSession())
        conversation.insert(message) { [weak self] error in
            guard error == nil else { return }
            DispatchQueue.main.async { self?.dismiss() }
        }
    }

    /// Replace the existing bubble in place rather than adding a new one, by
    /// reusing the selected message's `MSSession`. Without this the transcript
    /// accumulates cards and the oldest — still reading "Accept" — stays
    /// tappable long after the invite stopped being live.
    private func sendStatusUpdate(_ status: PartnerInvitePayload.Status) {
        guard let conversation = activeConversation,
              let selected = conversation.selectedMessage,
              let url = selected.url,
              let payload = PartnerInvitePayload(url: url) else { return }

        let message = InviteBubble.message(for: payload.updating(status: status),
                                           session: selected.session ?? MSSession())
        conversation.insert(message) { [weak self] error in
            guard error == nil else { return }
            DispatchQueue.main.async { self?.dismiss() }
        }
    }

    private func openApp() {
        let isUpdate: Bool = {
            switch scene {
            case .sent(let payload, _), .received(let payload, _), .composeStaged(let payload):
                return payload.status == .updated
            default:
                return false
            }
        }()
        let path = isUpdate ? "cycle/period-finished" : "cycle/sharing"
        open(URL(string: "\(PartnerInvitePayload.scheme)://\(path)")!)
    }

    /// Hands off to the system. For an accept this is the CloudKit share URL, so
    /// iOS — not Forge — runs the acceptance and decides whether this Apple ID
    /// may hold the share at all.
    private func open(_ url: URL) {
        extensionContext?.open(url, completionHandler: nil)
    }

    // ------------------------------------------------------------
    // MARK: Hosting
    // ------------------------------------------------------------

    private func installHost() {
        let controller = UIHostingController(rootView: InviteRootView(scene: scene, actions: actions()))
        controller.view.backgroundColor = .clear
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        host = controller
    }

    private func render() {
        host?.rootView = InviteRootView(scene: scene, actions: actions())
    }
}
