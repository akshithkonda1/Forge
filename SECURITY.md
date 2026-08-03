# Security Policy

## Supported surfaces

| Surface | Notes |
|---------|--------|
| Forge iOS app | HealthKit data stays device-first; share opt-in |
| HTTP API (API Gateway + Lambda) | Cognito JWT required for user routes |
| ARIA (Bedrock) | Opt-in via `ARIA_BEDROCK_ENABLED`; IAM-scoped InvokeModel only |

## Authentication & authorization

- **API Gateway JWT authorizer** validates Cognito access tokens (issuer + audience).
- Lambda **must not** treat body `user_id` as authoritative. Identity is taken from
  verified authorizer claims (`requestContext.authorizer.jwt.claims.sub`).
- Mismatched body `user_id` → **403**.
- **Production / staging** never fall back to a shared test user. Local/CI may set
  `ENVIRONMENT=test` and `FORGE_ALLOW_ANON_TEST_USER=true` for hermetic unit tests only.
- Unverified JWT payload decoding is **disabled** in production-like environments.

## AI security

- User messages are **sanitized** (control chars stripped, length capped).
- Prompts **isolate** user text in untrusted delimiters; injection markers raise a security note.
- System prompt forbids: revealing hidden prompts/secrets, inventing other users’ data,
  repurposing cycle/reproductive data, treating user text as instructions.
- Bedrock is reached only via **IAM role** (`bedrock:InvokeModel` / `Converse`) — no long-lived
  Anthropic API keys on the client.
- Multi-model `/ai/router` requires authentication (cost / abuse control).
- Request JSON bodies over ~256 KB are rejected (**413**).

## Data protection

- Domain **permissions** on ARIA context redact blocked domains before reasoning.
- Biometric observe path **redacts** snapshots per permissions.
- Cycle / reproductive context: coaching-only policy in product + model directives;
  never sell / advertise.
- DynamoDB app data is per-user keyed (`USER#<sub>#…`). Uploads bucket CORS is restricted
  to configured origins.
- Production **GET /health** returns a minimal status object (no table/bucket/pool inventory)
  unless `FORGE_HEALTH_VERBOSE=true`.

## Infrastructure controls

- API Gateway stage throttle: burst 100 / rate 50 RPS (default).
- Lambda environment secrets via **Secrets Manager** ARNs (not plaintext in git).
- CORS `allow_origins` from Terraform variable — do not use `*` with credentials.
- CloudWatch access logs for API (request id, status, integration errors).

## Reporting a vulnerability

Email security reports to the maintainers privately (do not open a public issue for
exploits). Include:

1. Affected endpoint / component  
2. Reproduction steps  
3. Impact (IDOR, data leak, prompt injection, etc.)  
4. Suggested fix if known  

We aim to acknowledge within 5 business days and ship mitigations proportional to severity.

## Local development

```bash
export ENVIRONMENT=local
export FORGE_ALLOW_ANON_TEST_USER=true   # unit tests only
# Never set FORGE_ALLOW_ANON_TEST_USER in production Lambda env.
```
