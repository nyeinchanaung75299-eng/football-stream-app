# Cloudflare public fallback API

Optional fresh public-data fallback for the Viewer.

It does not proxy video and does not bypass ISP, geo, DRM, DNS, or stream-host access controls.

Endpoint:
- GET /matches

Security:
- Uses only the Supabase publishable key.
- Removes Referer, Origin, ClearKey IDs/data, WebView URLs, and protected stream lines.
- Caches sanitized public data briefly at Cloudflare.

Deploy:
1. Copy wrangler.toml.example to wrangler.toml.
2. Set SUPABASE_PUBLISHABLE_KEY as a Worker secret.
3. Deploy the Worker.
4. Build Viewer with:
   --dart-define=PUBLIC_API_BASE=https://YOUR-WORKER.workers.dev

Viewer fallback order:
Supabase -> Cloudflare public API (if configured) -> GitHub safe mirror.
