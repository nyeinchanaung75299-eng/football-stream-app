# Cloudflare public fallback API

Fresh public-data fallback for the Viewer.

It does **not** proxy video and does not bypass ISP, geo, DRM, DNS, or stream-host access controls.

Endpoints:
- `GET /matches`
- `GET /health`

Fallback inside the Worker:
1. Supabase public REST API, when `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are configured.
2. Sanitized GitHub mirror.

Security:
- Removes Referer, Origin, ClearKey IDs/data, WebView URLs, and protected lines.
- Refuses to mirror obvious signed/tokenized stream URLs.
- Caches sanitized public data briefly at Cloudflare.

## Deploy

The repository includes `.github/workflows/deploy-cloudflare-public-api.yml`.

Add these GitHub repository secrets:
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

Optional for fresher data:
- `SUPABASE_PUBLISHABLE_KEY`

Then run **Deploy Cloudflare Public API**.

After deployment, set the GitHub repository variable:
- `PUBLIC_API_BASE=https://YOUR-WORKER.workers.dev`

Android/Web builds automatically pass that value to Flutter.

Viewer fallback order:
Supabase -> Cloudflare public API -> GitHub safe mirror.
