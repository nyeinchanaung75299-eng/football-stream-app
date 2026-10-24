# Cloudflare public API and protected playback

The Worker provides current Viewer metadata, read-only source extraction,
protected video playback, and authenticated Admin/Supabase relay routes. The
GitHub mirror remains a metadata-only fallback. On networks where Cloudflare
hosts cannot be reached, the existing Vercel backup forwards these routes;
it is still needed for the verified ATOM network path.

## Endpoints

- `GET /health`
- `GET /matches` — published featured match metadata and safe line counts
- `GET /matches/:matchId/streams` — current eligible protected playback URLs
- `GET /sources/:source/matches` and `POST /sources/:source/streams` — read-only
  Soco/YYZB/Fawa/Cola source browsing
- `GET|HEAD /p/:session/...` — encrypted session validation, upstream header
  handling, HLS/DASH manifest rewriting, and media streaming
- `POST /admin/functions/:function` — forwards the signed Admin session; the
  function rechecks authentication and the current Admin role
- Supabase relay host — preserves Auth/REST/Storage/function request access
  controls and headers

## Loading and health checks

Stream configuration uses `get_stream_metadata_for_gateway` to retrieve both
match eligibility and lines in one gateway-secret-gated DB request. A valid
published match with no lines returns an authoritative empty list; a missing
or unpublished match returns 404. During rollout, a missing new RPC falls back
to the previous two bounded queries. Timeouts and other backend errors do not
trigger that compatibility path.

Metadata and manifest reads have deadlines and a 2 MiB size cap. Protected
media has a header deadline, but no fixed body lifetime timer: continuous FLV
and media segments stay streamed, and client cancellation reaches upstream.
Live manifests retain `no-store`; these changes do not cache stale/deleted
lines or change media transport priorities.

Viewer source extraction sets `skip_probe` so a slow backup candidate does
not delay returning every extracted line. Such lines are marked `unknown`,
not `healthy`. Admin extraction without that flag and explicit health actions
still probe upstream headers plus the first non-empty body chunk. A stalled,
empty, or failed first chunk is failed; a late first chunk is slow. These
reachability checks do not prove segment availability, decryption, decoding,
first-frame speed, or uninterrupted device playback.

## Security

The static GitHub mirror stores no stream URLs, ClearKey material,
Referer/Origin headers, or WebView URLs. Upstream playback URLs and headers
stay inside encrypted, expiring sessions. Configured ClearKey pairs are
returned only through the existing authorized gateway playback path.

The Worker uses `SUPABASE_PUBLISHABLE_KEY` plus the private
`PLAYBACK_BACKEND_SECRET`. The gateway RPC checks the secret before reading
match eligibility or private stream configuration. A publishable key alone
does not authorize those reads. Admin tokens continue to be validated by
Supabase Auth, current profile roles, and RLS; no service-role key is added
to a Viewer, APK, Web build, or relay request.

## Deploy

Apply the `gateway_stream_metadata` migration before deploying the Worker.
The compatibility path keeps older databases working during rollout. Deploy
the updated `soco-links`, `stream-health`, and `football-score-sync` functions
with their shared `../_shared/stream_probe.mjs` module. Retain the existing
function JWT/cron/Admin verification settings.

The Worker workflow is `.github/workflows/deploy-cloudflare-public-api.yml`.
Existing deployment secrets are `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_PUBLISHABLE_KEY`, and
`PLAYBACK_BACKEND_SECRET`. Builds use the existing `PUBLIC_API_BASE` and
network-backup configuration. No new playback secret or signing key is
required by these loading changes.


## Optional Admin Browser Run stream detection (Free-only)

The Admin Web `Browser Network Detect` mode calls authenticated
`POST /admin/stream-detect-browser`. Unlike the basic HTML scanner,
the Browser Run binding can observe media URL requests from a short headless
Chromium page visit. This is not a DRM/access-control bypass and cannot
guarantee that a player which requires a physical Play click will start.

**Free-usage safety:** Do not enable browser scanning merely because the
Cloudflare account connection is authorized. First verify **Workers Free**
under the Cloudflare Workers plans page. Cloudflare limits Browser Run on
Workers Free to 10 minutes per UTC day. Confirm this on the actual account;
an OAuth plugin may not have Billing Read permission. Only after verifying
Free, set the Worker plain-text variable
`ENABLE_FREE_BROWSER_DETECT=true`. Otherwise leave it unset; the endpoint
returns a descriptive 503 without launching a browser.

`wrangler.toml` declares `[browser] binding = "BROWSER"` and
`nodejs_compat`. Deploy via Wrangler (preserving existing Supabase
publishable key and playback secrets), do not upload bare JS without the
browser binding. The Admin Web retains HTML Scan as a zero-browser-minute
fallback and uses the existing Supabase Admin access token; no database
migrations or paid Supabase services are needed. Browser requests return
URL/type/page-origin hints only; never return cookies, Authorization headers,
response bodies or DRM keys.

Test using only a page that you own or are explicitly authorized to inspect.
The backend checks the Supabase Admin role, requires explicit authorization
confirmation, rate-limits to two browser sessions per minute per client
in each Worker isolate, observes for about 12 seconds and always closes the
browser session. Isolate-local limits are **not a global daily billing cap**:
the Workers Free plan's hard provider quota is essential.

### Troubleshooting

- `browser_disabled`: enable the flag **only after** confirming Free.
- `browser_unavailable`: browser binding missing in deployed Worker.
- `browser_scan_failed`: site blocks browser, needs interactive Play/login
  or the Cloudflare Browser Run daily quota is exhausted.
- Zero results: the page may not issue detectable media requests without
  user interaction, or may use DRM. Do not repeatedly spend browser minutes
  on the same URL without changing the test scenario.
