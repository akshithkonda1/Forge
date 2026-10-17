# Decision 001: Launch codes for free access

**Status:** Decided (design only). Not built.
**Decided by:** Akshith
**Date:** 2026-10-17
**Timing:** Ships when the paywall is activated, planned right after beta testing. Do not build the paywall now.

## Decision

When the paywall is live, a user can open the paywall screen and enter a launch code. The paywall recognizes that user and grants free access tied to the code, for example free beta access or free lifetime access.

- **The code links to the account, not the device.** Access follows the user across reinstalls and new phones when they sign in.
- Redeeming a code grants an entitlement on the account. The entitlement type is set by the code (for example `beta_free` or `lifetime_free`).
- The paywall screen gets a simple "Have a launch code?" entry point. There is no hidden gesture and no device fingerprinting.

## Standing decision: founding users

Akshith and Anu are founding users. They get **free lifetime access** through launch codes.

## Open questions

1. **Single-use or reusable?** Is each code good for exactly one account, or can one code serve a group (for example a beta cohort) up to a cap?
2. **Revocable?** Can a code or the entitlement it granted be revoked (abuse, leaked code, refund)? If yes, does revocation take away access already granted, or only stop new redemptions?
3. **Account changes.** Does access transfer if the account changes, for example merged accounts or a switched sign-in method (Sign in with Apple, email, and so on)? Which identity is the anchor?
4. **Meter Scout handoffs separately from ARIA chats?** Scout is the research agent ARIA hands complex cases to (for example, dementia studies for a user with Asperger's). Each handoff is far more expensive than a chat, and a heavy researcher could burn through them fast. Should the paywall give Scout its own allowance (for example, a weekly handoff count) separate from ARIA chats? And do launch-code and lifetime users get unlimited Scout or a fair-use cap? The cost pass on PR #471 models one Scout handoff per user per week; see `backend/infra/COST.md` for the numbers.

## Constraints

- No health data is involved in code redemption, and none is sold or used for advertising (Apple guideline 5.1.3).
- Store only what's needed: the code, the account id, the entitlement type and the redemption time.
- Paid and public copy follow the existing rules: no prices or seats until a signed, non-localhost TestFlight build exists.
