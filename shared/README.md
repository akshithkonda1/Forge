# FORGE Shared

Shared API contracts for the Forge clients and backend.

Current source of truth:

- `api-contracts.ts` defines the Phase 1 client-unblocking API shapes and the first normalized health ingestion payloads.
- `readiness.json` is the Home readiness chrome contract (Peak / Good / Fair / Low).
- `design-tokens.json` is the cross-client color, type, spacing, motion, and UX contract. Home is the look.

Keep this package focused on cross-client contracts. Client-only view state should stay in the web or iOS app, and backend-only persistence details should stay under `backend/infra/lambda`.
