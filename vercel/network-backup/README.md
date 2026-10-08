# NCA network backup

Production URL: https://nca-network-backup-test.vercel.app

The linked private repository `nyeinchanaung75299-eng/nca-network-backup-test`
auto-deploys its `main` branch. This directory is the reviewable source copy.
Deploy it with Node.js 24 in Singapore, using the included Vercel configuration.
No service-role key, playback secret, or OAuth credential belongs in this project.

The proxy forwards only fixed public API/source routes, authenticated Admin
functions, and Supabase Auth/Data/Storage endpoints to the existing Cloudflare
Worker. JWTs, publishable keys, methods, request bodies, and REST count headers
are preserved. Original Supabase authentication, Admin checks, and RLS remain
the authority. Request URLs, passwords, JWTs, stream keys, and response bodies
are never logged. Protected manifest/media URLs stay on the Vercel origin.

`/service-health` checks public service reachability from Vercel. It does not
verify Google Drive accounts, PostHog event delivery, or ChatGPT plugin OAuth.
Google Drive is not configured as an integration in the NCA application.

Metadata requests are bounded; media streams keep running after headers arrive.
Hobby function duration and transfer quotas still apply. Continuous FLV has a
300-second function connection ceiling; HLS/DASH use separate short requests.
Supabase WebSocket Realtime is not relayed by this HTTP proxy. Viewer metadata
continues to refresh by polling when the selected backend is Vercel.

ATOM mobile data with VPN off verified health, matches, stream API, DASH manifest
(HTTP 200) and a media sample (HTTP 206) on 2026-10-08 before app integration.
