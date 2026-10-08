# Network transport candidate

`nca-network-backup.pages.dev` is an isolated Cloudflare Pages Advanced Mode
transport test. Its `PUBLIC_API` service binding forwards read-only Viewer
requests to the existing `football-public-api` Worker. The original request
origin stays intact so encrypted playback URLs, manifests and media keep the
Pages hostname. API credentials and playback secrets remain in the original
Worker.

The candidate allows only health, match metadata, protected stream metadata
and existing encrypted `/p/` playback paths. Admin actions, arbitrary proxy
targets and write methods are rejected. `/backend-health` checks the existing
Supabase relay through the same service binding.

The project was created through the Cloudflare Pages API using `project.json`.
The Direct Upload deployment uses an empty asset manifest, `_routes.json`
with `{"version":1,"include":["/*"],"exclude":[]}`, and `_worker.js` as an
`application/javascript+module` multipart file. This project does not alter
the original Worker's bindings, deployments or custom domains.

The browser test page is `user_app/web/network-check.html`. It lists each
candidate individually, applies a 12-second deadline through response-body
reading, checks HLS/DASH media access, and samples only the first media chunk.
Copyable results exclude playback URLs, encrypted tokens and ClearKey data.
VPN state is supplied by the user; the page does not infer it.

Initial server-side verification passed health, match metadata and backend
health with HTTP 200. beIN sports DASH returned a manifest with HTTP 200 and
an initialization sample with HTTP 206 (1,024 bytes), both on the Pages host.
WebKit and Chromium fixture checks passed success, empty-stream, wrong-host
and invalid-JSON cases. ATOM VPN-off reachability still requires device
results; neither an API response nor an initialization sample establishes
continuous playback reliability. Viewer runtime endpoint selection has not
been changed by this test.

Vercel was also inspected. Its connected token could read the user profile,
but access to the user's default team returned HTTP 403. No Vercel project
or deployment was created.
