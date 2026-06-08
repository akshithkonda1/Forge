# Production client configuration

Wire the Next.js and Swift clients after Terraform deploy. No hand-editing of plists or env files is required.

## 1. Export Terraform output

From `terraform` after `terraform apply`:

```bash
terraform output -json client_configuration > ../../client-configuration.json
```

The JSON shape matches [`client-configuration.example.json`](../client-configuration.example.json).

## 2. Generate client files

From the repo root (after `terraform apply`):

```bash
./scripts/wire_clients.sh
# or manually:
npm run config:export && npm run config:generate
```

After a GitHub **deploy-chain** Phase 3 run, download the **forge-client-configuration** workflow artifact instead.

This writes (both gitignored):

| Output | Purpose |
|--------|---------|
| `clients/web/.env.production.local` | Next.js production build env |
| `ForgeSwift/Config/Forge-Production.xcconfig` | iOS Release archive settings |

Validate without writing:

```bash
python3 backend/tools/generate_client_config.py --input client-configuration.example.json --dry-run
```

## 3. Web production build

```bash
cd clients/web
cp .env.example .env.local          # local dev only
npm install
npm run build                       # uses .env.production.local when present
```

Required production variables (generated automatically):

- `NEXT_PUBLIC_API_URL`
- `NEXT_PUBLIC_COGNITO_REGION`
- `NEXT_PUBLIC_COGNITO_CLIENT_ID`
- `NEXT_PUBLIC_COGNITO_USER_POOL_ID`

When Cognito vars are present, the web app requires sign-in after onboarding and attaches JWTs to all API requests. Do **not** set `NEXT_PUBLIC_ALLOW_DEMO_FALLBACK` in production builds.

## 4. iOS Release archive

Debug builds use [`Forge-Debug.xcconfig`](../ForgeSwift/Config/Forge-Debug.xcconfig) (`FORGE_USE_AUTH=false`, localhost API).

Release builds include optional [`Forge-Production.xcconfig`](../ForgeSwift/Config/Forge-Production.xcconfig) via `#include?` in [`Forge-Release.xcconfig`](../ForgeSwift/Config/Forge-Release.xcconfig).

```bash
# After running the generator
xcodebuild build \
  -workspace Forge.xcworkspace \
  -scheme ForgeSwift \
  -configuration Release \
  -destination 'generic/platform=iOS'
```

Release builds with auth enabled but missing API URL or Cognito client ID show a configuration error screen instead of silently hitting localhost. See [`APIConfig.swift`](../ForgeSwift/ForgeSwift/APIConfig.swift).

Template reference: [`Forge-Production.xcconfig.example`](../ForgeSwift/Config/Forge-Production.xcconfig.example).

## 5. CI / GitHub Actions secrets

Store the same values as build secrets so CI can generate config before client builds:

- API base URL
- Cognito region, user pool ID, web client ID, iOS client ID

## 6. After clients are wired

1. Add your production web origin to `allowed_origins` in Terraform tfvars.
2. Smoke test deployed API: `terraform output -raw healthcheck_url`
3. Sign up on web and iOS, then verify dashboard, lifestyle, and ARIA routes.

Local development remains unchanged — see [`DEV.md`](DEV.md).