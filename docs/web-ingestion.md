# Web data ingestion

**Issue:** [#365](https://github.com/akshithkonda1/Forge/issues/365) — WS3, design first plus a draft Lambda prototype.  
**Owners (issue):** Mira (backend / ARIA), Wren (web client), Sable (iOS share path); Pike for infra review.  
**Status:** Draft prototype. `POST /ingest/url` lives on the existing catch-all Lambda (`ANY /{proxy+}`). The future public path is `POST /v1/ingest/url`. No Terraform, no Bedrock, dummy ARIA stays default.

Forge users should be able to bring a web page into the app — a workout plan, a recipe, an article — and have it become **structured, typed data** ARIA can reason over. This document is the contract for that path: what we accept, how we extract, what we return, and how (and how *not*) that data reaches coach context and memory.

---

## 1. Use cases

| Example the user shares | What we want out | ARIA domain it should feed |
|---|---|---|
| Strength blog or trainer site with an `ExercisePlan` | Name, duration, intensity, exercise type, work pattern | `training` |
| Recipe page (`Recipe` JSON-LD is common) | Name, ingredients, steps, times, yield, nutrition labels | `nutrition` |
| How-to / mobility / cook-along (`HowTo`) | Title, ordered steps, tools, supplies | `lifestyle` (or `training` / `nutrition` when the type is obvious) |
| Article / news / blog with no useful schema | Title + readable text excerpt | `lifestyle` as untrusted source text |
| A page that is not HTML, or is a private/metadata URL | Typed error. Nothing persisted. | — |

Out of scope for this draft: PDFs, images, login-gated HTML, client-side rendered SPAs with no server HTML, third-party scrape APIs, and any UI (iOS share sheet, chat paste, web form). Those clients will call this endpoint later.

This is **not** a health-sample ingest. Web pages never become sleep, HRV, readiness, vitals, or clinical chart rows. `gather_user_context` stays ground truth from the account (or empty). A blog post is not the user's body.

---

## 2. Input paths

All paths converge on one authenticated POST. Identity is the Cognito JWT `sub` already enforced by API Gateway + `extract_user_id`. Body `user_id` is ignored.

```
iOS share sheet  ──┐
                   ├──► POST /ingest/url          (today; same Lambda)
Chat: paste a URL ─┤    POST /v1/ingest/url       (alias; future public base)
Web app (later)  ──┘         │
                             ▼
                   SSRF-safe HTTPS fetch
                             │
                   readable text + JSON-LD
                             │
                   typed IngestUrlResponse
                             │
              ┌──────────────┼────────────────┐
              ▼              ▼                ▼
     next /ai/chat      optional STM     never: coach_context
     (client attaches   (opt-in, gated   biometrics, clinical
      ariaFeed)          by Rowan)        data, invented metrics
```

| Path | Who builds it | What they send | When |
|---|---|---|---|
| iOS share sheet | Sable | The shared URL only. No page HTML, no cookies from Safari. | After this prototype |
| Chat: paste a URL | Mira / existing chat UI | Same body as share sheet. Chat must not treat the URL as a user instruction to fetch from the device. | After this prototype |
| Web app | Wren | Same `IngestUrlRequest`. | Later; not a TestFlight blocker |

Server-side fetch is mandatory. The phone and the browser must not upload scraped HTML (size, trust, and “what origin did this come from” all get worse). The Lambda fetches, validates, extracts, and returns JSON.

---

## 3. Extraction approach

Stdlib only. The production Lambda is already **stdlib + lazy boto3**. No BeautifulSoup, no Playwright, no Mercury/Readability service, no paid extract API.

1. **HTTPS GET** with SSRF rules (section 6). One hop’s body, capped.
2. **JSON-LD.** Parse every `<script type="application/ld+json">`. Walk `@graph` and arrays. Normalize `@type` (`Recipe`, `https://schema.org/Recipe`, `["Recipe"]` all count). First match wins, in this order:
   - `Recipe`
   - `ExercisePlan`
   - `HowTo`
   - `Article` / `NewsArticle` / `BlogPosting`
3. **Readable text.** `html.parser` walk: keep `title`, `h1`–`h3`, `p`, `li`, `article`. Drop `script`, `style`, `noscript`, `svg`, `template`. Collapse whitespace. Cap the excerpt.
4. **Kind.** Schema type if present, else `generic` with title + excerpt.

We do **not** execute JavaScript, follow `<iframe>`, load images, or interpret microdata/`<meta itemprop>` in this draft. Open graph tags are ignored unless they also appear as JSON-LD. If a site only hydrates in the browser, extraction will be thin — that is an accepted prototype limit, not a reason to add a headless browser (cost, SSRF surface, Lambda time).

Untrusted-page rule (same spirit as `security.isolate_user_message`): extracted prose is **data**, never instructions. Prompt-injection strings inside a recipe are stripped by the existing sanitizer before anything is stored or attached to ARIA.

---

## 4. Typed output

Wire shapes live in `shared/api-contracts.ts` and are returned by `POST /ingest/url`.

```
IngestUrlRequest { url, persistMemory? }
IngestUrlResponse {
  url, finalUrl, title, kind,
  extract: RecipeExtract | ExercisePlanExtract | HowToExtract | ArticleExtract | GenericExtract,
  readableText, schemaTypes,
  ariaFeed: { domain, summary, facts, untrusted: true, sourceUrl },
  memoryCandidate: { text, category, folder, persisted }
}
```

| `kind` | Extract fields (subset) | `ariaFeed.domain` | Memory folder (Rowan) |
|---|---|---|---|
| `recipe` | name, ingredients, instructions, times, yield, nutrition labels | `nutrition` | `healthHistory` |
| `exercise-plan` | name, activityDuration, exerciseType, intensity, workPattern | `training` | `goals` |
| `how-to` | name, steps, totalTime, supply, tool | `lifestyle` | `lifestyle` |
| `article` | headline, description, author, text | `lifestyle` | `lifestyle` |
| `generic` | title, text | `lifestyle` | `lifestyle` |

`untrusted: true` is required. Callers must not fold this object into `AriaContext.sleep` / `training` / `nutrition` numeric fields. Those fields stay measured or null.

Errors use the existing `{ message, code? }` envelope:

| HTTP | `code` | When |
|---|---|---|
| 400 | `invalid_url` | Missing / non-https / credentials in URL / non-443 |
| 400 | `blocked_target` | Private, loopback, link-local, metadata, or mixed public+private DNS |
| 400 | `redirect_limit` | More than three hops |
| 400 | `unsupported_media` | Content-Type not on the allowlist |
| 400 | `payload_too_large` | Header or body over the byte cap |
| 401 | — | No Cognito principal (authorizer / `extract_user_id`) |
| 429 | — | Per-user ingest rate limit |
| 502 | `fetch_failed` | TLS / timeout / non-2xx after a safe hop |

---

## 5. How results feed ARIA — and the redaction rules we will not break

Two existing packages already define what ARIA is allowed to know:

### 5.1 `coach_context.gather_user_context`

This is the bounded block `AI_SECURITY_DIRECTIVE` clause 3 points at: **only stored account data or empty**. It is why dummy/demo fixtures are gated and why a stranger’s sleep must never appear as the reader’s. Web ingestion **must not** write into the profile, `SLEEP#`, `WORKOUT#`, `PLAN#`, or readiness rows that this function reads. A shared workout page is not “today’s plan” until a later, explicit product decision (open question).

### 5.2 `UserContext` + Rowan memory

`UserContext` is companion memory (goals, constraints, life facts, last insights) — **not a clinical chart**. Short-term items (`MemoryItem`) expire. Calendar ingest already refuses titles and stops entirely when `editable_memory.auto_ingest_allowed` is false (`memory_enabled` off; **off ≠ delete**).

Inbound chat already strips:

- partner / cycle tokens (`partner_name:`, `cycle:fertile`, …) via `sanitize_user_memory_text` / `_DENIED_LIFESTYLE`
- calendar titles (persisted as “Busy window” only)
- invented QoL scores

Web ingest reuses those exact gates:

1. Page text is run through `sanitize_user_text` (length + control chars) and `sanitize_user_memory_text` (partner/cycle/calendar-title tokens).
2. Default **does not persist**. The response always includes a `memoryCandidate`. `persistMemory: true` writes a short-term `MemoryItem` with `source: "web"` **only if** `auto_ingest_allowed` is true **and** the mapped folder is not in `disabled_folders`.
3. We never call `record_life_fact` from a URL. A page is not “training for a first 10k” until the user (or a later confirmed-promote path) says so.
4. We never write `clinical_data`, medications, allergies, or vitals from a page.
5. Domain permissions still apply on the **next** `/ai/chat` turn. If `nutrition` is denied, a recipe `ariaFeed` must not be attached (client + future chat glue). The ingest route itself does not invent a permission grant.
6. `restricted_domains` / `apply_permissions` stay the redaction mechanism. Ingest does not bypass them by stuffing prose into `lifestyle.tags`.

### 5.3 What the prototype returns for orchestration

`ariaFeed` is the typed hook for the dummy (default) orchestrator and a future live path:

- `domain` — which `AriaDataDomain` this may inform
- `summary` — one short sanitized sentence
- `facts` — structured bullets (ingredients, steps, duration), already sanitized
- `untrusted: true`
- `sourceUrl` — final URL after safe redirects

The client (when built) should send this as a **sidecar** on the next chat turn, not as forged `recent_metrics`. Dummy ARIA can quote it as “you shared a page about …”. No Bedrock call is made by ingest.

---

## 6. SSRF and fetch policy

Implemented in `services/web_ingest.py`. Fail closed.

| Rule | Detail |
|---|---|
| Scheme | `https` only. `http`, `file`, `gopher`, `//` rejected. |
| Port | 443 only. |
| Userinfo | `https://user:pass@host/` rejected. |
| DNS then IP | `getaddrinfo` every hop. **Any** blocked A/AAAA fails the whole target (no “use the public one”). |
| Blocked IPs | Private, loopback, link-local, multicast, reserved, unspecified, non-global. IPv4-mapped IPv6 is unwrapped then re-checked. Named metadata: `169.254.169.254`, `169.254.170.2`, `fd00:ec2::254`. |
| Hostnames | `localhost`, `metadata`, `metadata.google.internal` rejected before DNS. |
| Pin | TLS connect goes to the resolved IP; SNI + `Host` stay the original hostname. |
| Redirects | Manual, max 3. Re-validate scheme/port/host/DNS/IPs on each `Location`. Relative locations resolved against the current URL. |
| Cookies | Never sent. `Set-Cookie` is discarded. No cookie jar. No `Authorization` / `Referer` forwarding. |
| Size | `Content-Length` over 512 KiB rejected. Body read in chunks; abort over 512 KiB. |
| Time | 8s socket timeout per hop. |
| Content-Type | Allowlist: `text/html`, `application/xhtml+xml`, `text/plain`, `application/ld+json`. Missing or other types → `unsupported_media`. |
| UA | `ForgeIngest/0.1` + `Accept` for the allowlist only. |

No Terraform / security-group change is required: this is application-level SSRF on the existing Lambda. Egress is whatever the function already has.

---

## 7. Cost and runtime

- One short HTTPS GET inside the existing API Lambda. Free-tier Lambda + API Gateway is enough at share-sheet volume.
- No new tables, buckets, NAT, or Bedrock.
- Rate limit: 20 ingest calls / user / hour (`enforce_user_rate_limit`), same pattern as `/ai/chat`.

---

## 8. Open questions for Akshith

1. **Persist default.** Should a shared URL ever write STM without an explicit confirm tap, or is `persistMemory` always a second step after the user sees the extract?
2. **First-class objects.** Do we later materialize a `Recipe` into a meal log, or an `ExercisePlan` into `PLAN#{date}` / `WorkoutPlan`? Doing that would change `gather_user_context` and needs a product rule so a stranger’s blog cannot become “today’s workout.”
3. **Domain allowlist.** Any public HTTPS page, or only a first-party list (so we do not fetch arbitrary attacker URLs from every share)?
4. **Paywalls / SPAs.** Fail closed (current), or a “paste the text” fallback in chat?
5. **Copyright / retention.** Keep a short excerpt (current cap) or structured fields only? How long may STM web notes live (today: 14-day default STM horizon)?
6. **`/v1` cutover.** Introduce the prefix for this route only (alias already registered) or wait for Mira’s full `/v1` contract bump?
7. **Permissions UX.** If the user has `nutrition` off, should ingest refuse recipes (403) or return the extract and let chat drop `ariaFeed`?
8. **Share-sheet trust.** Is the iOS extension allowed to send a client-side readable excerpt as a hint, or URL-only forever?
9. **Non-English / non-schema.org.** Do we add more `@type` aliases, or stay on Recipe / ExercisePlan / HowTo / Article?
10. **Images and PDFs.** Later milestone, or never on this endpoint (cycle PDFs already have a different, presigned path)?
11. **Abuse budget.** 20/hour enough for a coach who shares five tabs, or do we want a daily cap too?
12. **Confirm-before-ARIA.** Who owns the “ARIA may use this page” toggle — Sable on iOS, Wren on web, or a server flag on the candidate?

---

## 9. Prototype map

| Piece | Where |
|---|---|
| This design | `docs/web-ingestion.md` |
| Fetch + extract | `backend/infra/lambda/services/web_ingest.py` |
| HTTP route | `backend/infra/lambda/routes/ingest.py` (`POST /ingest/url`, `POST /v1/ingest/url`) |
| Wire types | `shared/api-contracts.ts` |
| Tests (no live network) | `backend/tests/test_web_ingest.py` + `backend/tests/fixtures/web_ingest/` |
