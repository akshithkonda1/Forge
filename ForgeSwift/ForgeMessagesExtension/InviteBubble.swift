import ForgeCore
import Foundation
import Messages
import UIKit

// ============================================================
// MARK: - Bubble composition
// ============================================================

/// Turns a `PartnerInvitePayload` into the `MSMessage` that sits in a transcript.
///
/// Everything here ends up rendered into a chat bubble, which means: visible on a
/// lock screen, included in an iCloud backup, present in a screenshot, and synced
/// to every device on both Apple IDs. So the bubble says who is asking and what
/// state the invite is in — never what is being tracked. Someone reading over a
/// shoulder learns that two people share something in Forge.
enum InviteBubble {

    /// Build the message. Reuses `session` when one exists so the bubble updates
    /// **in place** rather than stacking a second card in the transcript: a
    /// revoked invite that still sits above a live-looking "Accept" is exactly
    /// the confusion `MSSession` exists to prevent.
    static func message(for payload: PartnerInvitePayload, session: MSSession?) -> MSMessage {
        let message = session.map { MSMessage(session: $0) } ?? MSMessage()
        message.url = payload.url

        let layout = MSMessageTemplateLayout()
        layout.image = cardImage(for: payload)
        layout.caption = payload.bubbleCaption
        layout.subcaption = payload.bubbleSubcaption
        message.layout = layout

        // Read aloud by VoiceOver in the transcript, and used as the fallback in
        // contexts that cannot render the layout at all.
        message.summaryText = payload.bubbleCaption
        message.accessibilityLabel = "\(payload.bubbleCaption). \(payload.effectiveStatus.caption)."
        return message
    }

    // ------------------------------------------------------------
    // MARK: Card art
    // ------------------------------------------------------------

    /// Drawn rather than shipped as an asset so the card can carry the invite's
    /// current state. A single static image would go on looking like a live
    /// offer after the invite lapsed.
    private static func cardImage(for payload: PartnerInvitePayload) -> UIImage {
        let size = CGSize(width: 300, height: 190)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: size)

            let colors = gradient(for: payload.effectiveStatus)
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors.map(\.cgColor) as CFArray,
                                         locations: [0, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: CGPoint(x: 0, y: 0),
                                      end: CGPoint(x: size.width, y: size.height),
                                      options: [])
            }

            // A soft off-centre bloom, so the card reads as lit rather than as a
            // flat swatch at bubble size.
            cg.saveGState()
            cg.setBlendMode(.plusLighter)
            if let bloom = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [UIColor.white.withAlphaComponent(0.20).cgColor,
                                               UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                      locations: [0, 1]) {
                cg.drawRadialGradient(bloom,
                                      startCenter: CGPoint(x: size.width * 0.24, y: size.height * 0.28),
                                      startRadius: 0,
                                      endCenter: CGPoint(x: size.width * 0.24, y: size.height * 0.28),
                                      endRadius: size.width * 0.62,
                                      options: [])
            }
            cg.restoreGState()

            let glyph = UIImage(systemName: payload.effectiveStatus.isActionable
                                ? "heart.text.square.fill"
                                : "checkmark.seal.fill")?
                .withTintColor(.white.withAlphaComponent(0.94), renderingMode: .alwaysOriginal)
            if let glyph {
                let side: CGFloat = 46
                glyph.draw(in: CGRect(x: 22, y: 22, width: side, height: side))
            }

            draw(payload.bubbleCaption,
                 in: CGRect(x: 22, y: rect.height - 84, width: rect.width - 44, height: 30),
                 font: .systemFont(ofSize: 17, weight: .semibold),
                 color: .white)

            draw(payload.effectiveStatus.caption,
                 in: CGRect(x: 22, y: rect.height - 54, width: rect.width - 44, height: 24),
                 font: .systemFont(ofSize: 13, weight: .medium),
                 color: .white.withAlphaComponent(0.78))
        }
    }

    /// Warm ember while the invite is live; deliberately drained once it is not,
    /// so a dead invite is distinguishable from a live one at a glance in a
    /// scrolling transcript, without reading the caption.
    private static func gradient(for status: PartnerInvitePayload.Status) -> [UIColor] {
        switch status {
        case .pending:
            return [UIColor(red: 1.00, green: 0.30, blue: 0.00, alpha: 1),
                    UIColor(red: 0.77, green: 0.23, blue: 0.00, alpha: 1)]
        case .accepted, .updated:
            return [UIColor(red: 0.16, green: 0.55, blue: 0.42, alpha: 1),
                    UIColor(red: 0.08, green: 0.32, blue: 0.28, alpha: 1)]
        case .revoked, .expired:
            return [UIColor(red: 0.26, green: 0.26, blue: 0.29, alpha: 1),
                    UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1)]
        }
    }

    private static func draw(_ text: String,
                             in rect: CGRect,
                             font: UIFont,
                             color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
}
