import Foundation

/// Privacy contract for menstrual / family-support cycle data.
/// Single source of truth for UI, ARIA disclaimers, and coaching context.
enum CyclePrivacy {
    static let title = "Your cycle data is private"

    /// Short line for chips / home module.
    static let shortPromise =
        "Sealed on this iPhone. Apple Health is the ledger. They only see how to help if you invite them in iMessage."

    /// Full user-facing policy (lifestyle product language).
    static let policy = """
    Cycle tracking is private by design.

    • Logs live on this iPhone (Cycle Vault + Apple Cycle Tracking). Wearables \
    write to Apple Health; ARIA reads that ledger here — it does not scrape Oura, Garmin, or vendor clouds.
    • ARIA forms its opinion on this device. Claude and Grok never receive your cycle samples, \
    BBT, OPKs, or day-level logs. If a language model runs off-device, it sees what you type, not the warehouse.
    • Forge does not keep a reproductive database. Account storage is the user record, not your chart.
    • We do not sell cycle data. We do not use it for advertising. We do not license it \
    to third parties for their own products or training sets.
    • Support-person data requires consent / caregiver care. Invites are iPhone + iMessage only.

    This is lifestyle coaching, not medical care or birth control.
    """

    /// Compact bullets for privacy cards.
    static let bullets: [(icon: String, text: String)] = [
        ("lock.shield.fill", "Cycle Vault + Apple Health on this iPhone — not a Forge database"),
        ("applewatch", "ARIA reads wearables from Apple Health. Nothing scraped from vendor accounts"),
        ("message.fill", "Support invites: iPhone + iMessage only. SMS is not valid access"),
        ("xmark.seal.fill", "Never sold, never used for ads, never resold to third parties"),
        ("hand.raised.fill", "Lifestyle guidance only — not diagnosis or contraception"),
    ]

    /// Injected into ARIA system/context so the model is constrained.
    static let ariaDirective = """
    CYCLE PRIVACY LAW (mandatory):
    Cycle and reproductive context is highly sensitive and stays on this iPhone. \
    You may read it only to personalize coaching for this user in this on-device conversation. \
    You must not invent secondary uses, ask to export for marketing, or treat it as shareable content. \
    Never sell, train on, or store cycle data on Forge servers. \
    If the user has not enabled cycle tracking, do not assume phase details.

    \(SexualHealthCoach.ariaDirective)
    """

    static let partnerExtra = """
    Support-person cycle logs are entered by the user with consent (or caregiver care). \
    You can support more than one person — a partner and a daughter are separate, \
    with their own role and notes. Same privacy rules: coaching the user only — never sold or reused.
    """
}
