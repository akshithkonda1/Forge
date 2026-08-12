import ForgeCore
import SwiftUI

// ============================================================
// MARK: - What the extension is showing
// ============================================================

/// The extension has exactly five things it can be doing, and which one is
/// decided once by `MessagesViewController` from the conversation. Resolving it
/// up front — rather than letting each subview re-derive "am I the sender?" from
/// participant identifiers — is what keeps the sender's controls off the
/// supporter's screen.
enum InviteScene: Equatable {
    /// The app has staged an invite and it is ready to send.
    case composeStaged(PartnerInvitePayload)
    /// Nothing staged. The only move is to go set it up in the app.
    case composeEmpty
    /// A bubble we sent, being looked at again.
    case sent(PartnerInvitePayload)
    /// A bubble someone sent us. `accepted` comes from what CloudKit actually
    /// confirmed, never from having tapped the button.
    case received(PartnerInvitePayload, accepted: Bool)
    /// A payload from a newer version of the app than this extension.
    case unreadable
}

/// Everything the SwiftUI layer can ask the host controller to do. Passed in
/// rather than reached for, so the views stay previewable and have no way to
/// touch `MSConversation` directly.
struct InviteActions {
    var insert: (PartnerInvitePayload) -> Void = { _ in }
    var sendStatusUpdate: (PartnerInvitePayload.Status) -> Void = { _ in }
    var openApp: () -> Void = {}
    var open: (URL) -> Void = { _ in }
    var requestExpanded: () -> Void = {}
    var isCompact: Bool = true
}

// ============================================================
// MARK: - Root
// ============================================================

/// Everything below is available to every Forge user. There is no purchase
/// check, no subscription check and no entitlement gate anywhere in this target,
/// and there should not be one: sharing a support signal with a partner is how
/// the feature works, not an upsell. If a paywall is ever wanted, it belongs
/// around something else.
struct InviteRootView: View {
    let scene: InviteScene
    let actions: InviteActions

    var body: some View {
        ZStack {
            InviteBackground()
            content
                .padding(.horizontal, actions.isCompact ? 18 : 26)
                .padding(.vertical, actions.isCompact ? 14 : 26)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch scene {
        case .composeStaged(let payload):
            ComposeStagedView(payload: payload, actions: actions)
        case .composeEmpty:
            ComposeEmptyView(actions: actions)
        case .sent(let payload):
            SentView(payload: payload, actions: actions)
        case .received(let payload, let accepted):
            ReceivedView(payload: payload, accepted: accepted, actions: actions)
        case .unreadable:
            UnreadableView(actions: actions)
        }
    }
}

// ============================================================
// MARK: - Scenes
// ============================================================

private struct ComposeStagedView: View {
    let payload: PartnerInvitePayload
    let actions: InviteActions

    var body: some View {
        InviteLayout(
            icon: "heart.text.square.fill",
            title: "Invite your \(payload.roleLabel.lowercased())",
            // States the boundary in the same breath as the offer, so nobody
            // sends this without knowing what it hands over.
            subtitle: "They'll see how to show up for you. Not your logs.",
            actions: actions
        ) {
            if !actions.isCompact {
                DisclosureLists()
            }
        } primary: {
            InviteButton(title: "Add to message", icon: "paperplane.fill") {
                actions.insert(payload)
            }
        } secondary: {
            // Sending is a two-step action by design: inserting only fills the
            // input field, and the user still taps send. Saying so avoids the
            // "did that already go?" pause.
            Text("Adds a card to your message. You still tap send.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }
}

private struct ComposeEmptyView: View {
    let actions: InviteActions

    var body: some View {
        InviteLayout(
            icon: "lock.open.rotation",
            title: "Set this up in Forge",
            // The honest reason, not a shrug. Choosing who sees this is a
            // decision that deserves the full screen it gets in the app.
            subtitle: "Choosing who to share with — and what they see — happens in the app.",
            actions: actions
        ) {
            EmptyView()
        } primary: {
            InviteButton(title: "Open Forge", icon: "arrow.up.forward.app.fill") {
                actions.openApp()
            }
        } secondary: {
            Text("Come back here once it's ready and the invite will be waiting.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }
}

private struct SentView: View {
    let payload: PartnerInvitePayload
    let actions: InviteActions

    var body: some View {
        InviteLayout(
            icon: icon,
            title: title,
            subtitle: subtitle,
            actions: actions
        ) {
            EmptyView()
        } primary: {
            InviteButton(title: "Manage in Forge", icon: "slider.horizontal.3") {
                actions.openApp()
            }
        } secondary: {
            // Revocation is one tap, in the app, and total. Stated here because
            // the moment someone wonders is the moment they're looking at this.
            Text("You can stop sharing at any time. They just stop seeing updates.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }

    private var icon: String {
        switch payload.effectiveStatus {
        case .pending:  return "clock.badge.questionmark"
        case .accepted: return "checkmark.seal.fill"
        case .revoked:  return "hand.raised.slash.fill"
        case .expired:  return "hourglass"
        }
    }

    private var title: String {
        switch payload.effectiveStatus {
        case .pending:  return "Waiting on them"
        case .accepted: return "They're following along"
        case .revoked:  return "Sharing stopped"
        case .expired:  return "That invite lapsed"
        }
    }

    private var subtitle: String {
        switch payload.effectiveStatus {
        case .pending:  return "The invite is sent. Nothing is shared until they accept."
        case .accepted: return "They see a general picture, updated by your device."
        case .revoked:  return "They no longer receive anything."
        case .expired:  return "Send a new one from Forge whenever you like."
        }
    }
}

private struct ReceivedView: View {
    let payload: PartnerInvitePayload
    let accepted: Bool
    let actions: InviteActions

    var body: some View {
        InviteLayout(
            icon: accepted ? "checkmark.seal.fill" : "hand.wave.fill",
            title: accepted
                ? "You're following along"
                : "\(payload.fromDisplayName) wants your support",
            subtitle: accepted
                ? "Open Forge any time to see how to show up."
                : "You'll get a general picture — enough to be useful, and no more.",
            actions: actions
        ) {
            if !actions.isCompact { SupporterExpectations() }
        } primary: {
            if accepted {
                // The acceptance is real and confirmed, so offering to say so is
                // reporting a fact rather than an intention.
                InviteButton(title: "Let them know", icon: "arrow.up.message.fill") {
                    actions.sendStatusUpdate(.accepted)
                }
            } else if payload.effectiveStatus.isActionable {
                InviteButton(title: "Accept in Forge", icon: "arrow.up.forward.app.fill") {
                    actions.open(payload.acceptURL)
                }
            } else {
                InviteButton(title: "Open Forge", icon: "arrow.up.forward.app.fill") {
                    actions.openApp()
                }
            }
        } secondary: {
            Text(accepted
                 ? "They chose what you can see, and can change it whenever."
                 : payload.effectiveStatus.isActionable
                   ? "Accepting opens Forge. They can stop sharing at any time."
                   : payload.effectiveStatus.caption)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }
}

private struct UnreadableView: View {
    let actions: InviteActions

    var body: some View {
        InviteLayout(
            icon: "arrow.triangle.2.circlepath",
            title: "Update Forge to open this",
            // Refusing to render is the right answer: a bubble that guesses at a
            // newer payload could show "accepted" for an invite that was pulled.
            subtitle: "This invite was made by a newer version than the one on this device.",
            actions: actions
        ) {
            EmptyView()
        } primary: {
            InviteButton(title: "Open Forge", icon: "arrow.up.forward.app.fill") {
                actions.openApp()
            }
        } secondary: {
            EmptyView()
        }
    }
}

// ============================================================
// MARK: - Shared chrome
// ============================================================

/// One layout for every scene. The extension appears at two very different
/// heights — keyboard-sized and near-full-screen — and a per-scene layout would
/// mean five chances to overflow the compact one.
private struct InviteLayout<Detail: View, Primary: View, Secondary: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let actions: InviteActions
    @ViewBuilder var detail: Detail
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    var body: some View {
        VStack(spacing: actions.isCompact ? 12 : 22) {
            if !actions.isCompact {
                InviteGlyph(name: icon)
            }

            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    if actions.isCompact {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Brand.ember)
                    }
                    Text(title)
                        .font(actions.isCompact
                              ? .system(size: 17, weight: .semibold)
                              : .system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        // Two lines of a long name beat a truncated one; the
                        // compact sheet has the room for it and nothing else does.
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(subtitle)
                    .font(actions.isCompact ? .footnote : .callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            detail

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                primary
                secondary
                if actions.isCompact {
                    Button(action: actions.requestExpanded) {
                        Label("More", systemImage: "chevron.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .accessibilityLabel("Show more detail")
                }
            }
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The two lists side by side. Putting what is withheld next to what is shared —
/// rather than in a policy screen nobody opens — is the only way the promise is
/// legible at the moment it matters.
private struct DisclosureLists: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureColumn(
                title: "They'll see",
                tint: Brand.ember,
                icon: "eye.fill",
                items: ["Roughly where you are in your cycle",
                        "Whether your energy is low, steady or high",
                        "A rough sense of when the next one is due",
                        "One line on how to show up today"]
            )
            DisclosureColumn(
                title: "They won't",
                tint: .white.opacity(0.35),
                icon: "eye.slash.fill",
                items: ["Fertile days or ovulation timing",
                        "Whether you're trying to conceive",
                        "Symptoms, flow, moods, tests",
                        "Anything you log day to day"]
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SupporterExpectations: View {
    var body: some View {
        DisclosureColumn(
            title: "What you'll get",
            tint: Brand.ember,
            icon: "sparkles",
            items: ["A general read on how they're doing",
                    "One clear suggestion for today",
                    "Nothing they log, ever",
                    "Updates stop the moment they say so"]
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DisclosureColumn: View {
    let title: String
    let tint: Color
    let icon: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .textCase(.uppercase)
                .tracking(0.6)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(tint.opacity(0.5))
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
    }
}

private struct InviteGlyph: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 76, height: 76)
            .background(
                Circle().fill(
                    LinearGradient(colors: [Brand.ember, Brand.emberDark],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
            )
            .shadow(color: Brand.ember.opacity(0.35), radius: 20, y: 8)
            .accessibilityHidden(true)
    }
}

private struct InviteButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.ember, Brand.emberDark],
                                             startPoint: .leading,
                                             endPoint: .trailing))
                )
        }
        .buttonStyle(.plain)
    }
}

/// A still gradient, not an animated one. The extension is a keyboard-height
/// sheet a user is in for four seconds, and ambient motion here would read as
/// jitter rather than as welcome.
private struct InviteBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.06, green: 0.06, blue: 0.08),
                                Color(red: 0.11, green: 0.08, blue: 0.09)],
                       startPoint: .top,
                       endPoint: .bottom)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Brand.ember.opacity(0.16))
                    .frame(width: 260, height: 260)
                    .blur(radius: 90)
                    .offset(x: 80, y: -110)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The two brand colours this target needs, restated locally.
///
/// Importing `Theme.swift` would drag the app's design system — and everything
/// it imports — into an extension that has a hard memory ceiling, to get two
/// hex values. `FF4D00` matches `ForgeColor.ember`.
private enum Brand {
    static let ember = Color(red: 1.00, green: 0.30, blue: 0.00)
    static let emberDark = Color(red: 0.77, green: 0.23, blue: 0.00)
}
