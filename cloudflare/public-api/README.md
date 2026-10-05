# Cloudflare public fallback API

Fresh public-data fallback for the Viewer when the Supabase hostname is not
directly reachable from a user's ISP/network.

It does not proxy video and does not bypass ISP, geo, DRM, DNS, or stream-host
access controls.

Endpoints:
- GET /health
- GET /matches
- GET /matches/:matchId/streams

Security:
- /matches is metadata-only and returns a safe stream_count.
- It never returns stream URLs, ClearKey data, Referer/Origin, or WebView URLs.
- /matches/:matchId/streams returns only direct active lines that do not need
  ClearKey, custom Referer/Origin, or WebView.
- Protected lines remain on the direct Supabase path when that path is available.
- Only the Supabase publishable key is used by this Worker.

Deploy:
1. Add GitHub repository secrets CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID.
2. Run the GitHub workflow "Deploy Cloudflare Public API".
3. Copy the resulting workers.dev URL.
4. Add a GitHub repository variable PUBLIC_API_BASE with that URL.
5. Re-run the Android and Web builds.

The Viewer build workflows pass PUBLIC_API_BASE into Flutter automatically.
