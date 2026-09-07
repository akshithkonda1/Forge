/** First-meet ARIA copy. Lockstep with `AriaMeetCopy` on iOS. */
export const ARIA_INTRO = {
  eyebrow: "Adaptive Recovery Interactive Assistant",
  title: "This is ARIA",
  lead: "I was designed for Forge — I power how you train, recover, and live the day.",
  pairingForbidden: "FORGE × ARIA",
  capabilities: [
    {
      title: "Train today",
      body: "What to do with the body you woke up with — not a plan from last week.",
    },
    {
      title: "Recovery",
      body: "Last night, load, and when to back off before you cook yourself.",
    },
    {
      title: "What's in the way",
      body: "Talk. You don't have to know the question. I'll stay with it.",
    },
    {
      title: "Plans that fit",
      body: "I coach the life you already have — not a spreadsheet of you.",
    },
  ],
  talkCta: "Talk with ARIA",
  continueCta: "Continue",
  skipCta: "Look around first",
} as const;
