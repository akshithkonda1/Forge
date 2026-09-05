import Foundation

/// Privacy contract for menstrual / family-support cycle data.
/// Single source of truth for UI, ARIA disclaimers, and coaching context.
enum CyclePrivacy {
    static let title = "Your cycle data is private"

    /// Short line for chips / home module.
    static let shortPromise =
        "Sealed in Cycle Vault on this iPhone. They only see how to help if you invite them in iMessage."

    /// Full user-facing policy (lifestyle product language).
    static let policy = """
    Cycle tracking is private by design.

    • Data stays under your control on this device.
    • ARIA and Forge may read cycle context only when you turn on “Share with ARIA,” \
    and only to coach you (training, recovery, and how you support someone you love).
    • We do not sell cycle data. We do not use it for advertising. We do not license it \
    to third parties for their own products or training sets.
    • Backend intelligence (including models on AWS Bedrock) is used as a private processor \
    for your request — not as a right to keep, resell, or repurpose your reproductive data.
    • You can stop sharing with ARIA anytime. Support-person data requires consent / caregiver care.

    This is lifestyle coaching, not medical care or birth control.
    """

    /// Compact bullets for privacy cards.
    static let bullets: [(icon: String, text: String)] = [
        ("lock.shield.fill", "Cycle Vault — keychain-wrapped archive on this iPhone"),
        ("eye.fill", "ARIA / Forge read only when you opt in to coach you"),
        ("message.fill", "Support invites: iPhone + iMessage only. SMS is not valid access"),
        ("xmark.seal.fill", "Never sold, never used for ads, never resold to third parties"),
        ("hand.raised.fill", "Lifestyle guidance only — not diagnosis or contraception"),
    ]

    /// Injected into ARIA system/context so the model is constrained.
    static let ariaDirective = """
    CYCLE PRIVACY LAW (mandatory):
    Cycle and reproductive context is highly sensitive. You may read it only to personalize \
    coaching for this user in this conversation. You must not invent secondary uses, ask to \
    export for marketing, or treat it as shareable content. Never sell, train on, or store \
    cycle data beyond what the product already holds for the user’s own coaching. \
    If the user has not shared cycle data with ARIA, do not assume phase details.

    \(SexualHealthCoach.ariaDirective)
    """

    static let partnerExtra = """
    Support-person cycle logs are entered by the user with consent (or caregiver care). \
    You can support more than one person — a partner and a daughter are separate, \
    with their own role and notes. Same privacy rules: coaching the user only — never sold or reused.
    """
}
