# Cloudflare public and playback gateway

The Worker provides match metadata, protected HLS/DASH playback, source
browsing, and a Supabase relay for the Admin app.

## Routes

- `GET /health` reports configured capabilities.
- `GET /matches` returns match metadata and stream counts, with the existing GitHub mirror fallback when the live backend is unavailable.
- `GET /matches/:matchId/streams` returns current protected playback links. A successful empty list is authoritative.
- `GET|HEAD /p/:session/...` proxies playback manifests, segments, and ClearKey material using authenticated encrypted sessions.
- `/sources/:source/matches` and `/sources/:source/streams` serve the supported source browsers.
- `POST /admin/functions/:function` relays the supported Admin Edge Functions with the caller's Authorization header.
- The configured `supabase-api.*` hostname relays the supported Supabase API paths and preserves the caller's authentication.

DASH rewriting resolves BaseURL ancestry and segment references at their XML
scope. Signed relative references preserve root/parent-relative templates and
CDN alternatives. Playback sessions are stateless; no PLAYBACK_TOKENS KV
binding is required. Existing namespaces/data are not deleted.

The feed can contain direct fallback lines that do not require protected
headers or keys. Current protected links are fetched on demand. Successful
zero-count responses revoke cached lines; only failed requests use fallback.

## Deploy

`.github/workflows/deploy-cloudflare-public-api.yml` uses these repository
secrets:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`
- `SUPABASE_PUBLISHABLE_KEY`

Protected playback also requires the existing Worker secret
`PLAYBACK_BACKEND_SECRET`, matching the private gateway setting in Supabase.
Keep that value out of client builds and version control. The deployment
workflow preserves existing Worker secrets; it does not create the private
Supabase gateway setting.

Set `PUBLIC_API_BASE=https://YOUR-WORKER.workers.dev` in repository variables
for builds that override the app's configured default. See
[review fixes](../../docs/REVIEW_FIXES.md) for backend migration and release
order.

## Verification

```bash
node scripts/test_protected_dash_proxy.mjs
node scripts/test_supabase_relay.mjs
node scripts/test_public_gateway.mjs
```

Run these from the repository root. From this directory,
`npx wrangler deploy --dry-run` validates the bundle without deployment.
