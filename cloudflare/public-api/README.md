# Cloudflare public fallback API

Fresh public-data fallback for the Viewer when a user's network cannot reach
the Supabase hostname directly.

It does **not** proxy video and does not bypass ISP, geo, DRM, DNS, or
stream-host access controls.

## Endpoints

- `GET /health`
- `GET /matches` — match metadata only, plus a safe `stream_count`
- `GET /matches/:matchId/streams` — safe direct public lines, fetched on demand

## Security

The static GitHub mirror is metadata-only. It stores no stream URLs, ClearKey
material, Referer/Origin headers, or WebView URLs.

The Worker uses the Supabase publishable key to fetch current public data.
`/matches/:matchId/streams` returns only active direct lines that do not require
ClearKey, custom Referer/Origin, WebView, or obvious signed/tokenized URLs.

Protected lines remain available only through the normal direct Supabase path
when that path is reachable.

## Deploy

The repository includes
`.github/workflows/deploy-cloudflare-public-api.yml`.

Add these GitHub repository secrets:
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`
- `SUPABASE_PUBLISHABLE_KEY`

Then run **Deploy Cloudflare Public API**.

After deployment, set this GitHub repository variable:
- `PUBLIC_API_BASE=https://YOUR-WORKER.workers.dev`

Android and Web builds already pass `PUBLIC_API_BASE` into Flutter.

Viewer fallback order:
1. Direct Supabase
2. Cloudflare public API
3. Metadata-only GitHub mirror

When a fallback match is opened, its safe stream lines are requested on demand
from the Cloudflare API rather than stored in GitHub.
