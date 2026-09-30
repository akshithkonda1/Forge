# ARIA Scout

The agentic, always-on research computer ARIA calls when a turn needs the open web.

```
iPhone (Dummy) ──Cognito JWT──▶ API Gateway  POST /scout/research
                                   │ injects x-scout-key + x-forge-user (JWT sub)
                                   ▼
                  EC2 t4g.small: Caddy :443 → Scout :8088 → SearXNG
                                              └─▶ Grok 4.7 on Bedrock
```

One research call: **plan** searches → **search** (SearXNG: Google, Bing, DuckDuckGo,
Brave, Wikipedia, PubMed) → **rank** (public health and peer review first, shops and
social last) → **read** (SSRF-safe `web_ingest.fetch_https`) → **synthesize** (Grok) →
**cross-check** (every point must cite a page Scout read). Grok off or failing → the
deterministic rules brain answers instead. Briefs are cached 6 h, so a repeat question
costs no Bedrock tokens.

## What leaves the phone

Only a scrubbed keyword query (`privacy.scrub_query`, mirrored on iOS by
`AriaQueryPrivacy`): no names, numbers, contacts, health samples or location. Scout
re-scrubs on arrival. The brief it returns is untrusted outside data: callers never
write it into sleep, training or nutrition fields or durable memory.

## Turn it on

```bash
cd backend/infra
export TF_VAR_scout_shared_key="$(openssl rand -hex 32)"   # never commit this
terraform apply -var enable_scout=true -var spend_guard_limit_usd=45
terraform output scout_research_url
```

- Grok needs Bedrock model access for `global.xai.grok-4.7` in the account. The Scout
  box enables Bedrock for itself only; the Lambda's `aria_bedrock_enabled` stays as is.
- Cost at on-demand prices: about $17/month before tokens (t4g.small, 16 GB gp3, public
  IPv4). The default $25 spend guard covers the whole stack, so raise it.
- TLS comes from Caddy on `<elastic-ip>.sslip.io` unless you set `scout_domain`.
- No SSH. Use SSM Session Manager.
- Google often rate-limits data-center IPs. SearXNG keeps answering from the other
  engines, and each brief lists the engines that responded.

## Run locally

```bash
python -m unittest backend.tests.test_scout          # offline, all fakes
SCOUT_SHARED_KEY=dev python -m backend.scout         # rules brain unless ARIA_BEDROCK_ENABLED=true
```

To point the Python Dummy at Scout: `FORGE_DUMMY_WEB=1 FORGE_SCOUT_URL=https://…/scout/research FORGE_SCOUT_TOKEN=<Cognito access token>`.
