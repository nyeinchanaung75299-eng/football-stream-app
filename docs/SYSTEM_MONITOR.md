# Admin System Health

The second bottom tab is **System Health**. **Controls** keeps the existing match
and stream management screens. Connection checks remain available inside System Health.

## Available without additional service keys

- Supabase: actual authenticated database reads, match/active-line counts and latency.
- Streams: stored health results, last check time, stale checks, consecutive and
  lifetime failure counters, and upstream-host warnings.
- GitHub Actions: latest main-branch Web and APK/iOS workflow runs, including
  queued/running/failed builds. Public API results are cached for five minutes.
- JSON/CSV summary copy: aggregate counts/status without stack traces, session IDs,
  playback URLs, DRM keys or provider credentials.

Failure counters start when the monitoring migration is installed. The existing
scheduled maintenance and manual health checks update the same counters through
a database trigger. Three fresh consecutive failures raise an alert. Successful
checks reset the streak; unknown results interrupt it. Checks older than 20
minutes are stale. No automatic disabling is performed. These checks verify
upstream reachability, not continuous video playback.

## Connect account data

Open **System Health → Connect services**. Use the setup link for the service,
create a narrowly scoped credential, and paste it into the masked field. No
credential needs to be sent in chat or added to the Flutter build. Read access is
tested before the connection is saved.

- **PostHog**: current NCA project **646885**, US region. Create a personal API key
  restricted to this project with **query:read**.
  [API authentication](https://posthog.com/docs/api/overview).
  The public phc_ ingest key cannot read monitoring data.
  The dashboard reads captured exceptions, playback-line failures, buffering
  events and Admin API failures for the last 24 hours. It shows distinct PostHog
  person counts, app/platform breakdowns, grouped issues and sanitized stack
  context. Anonymous installations can count separately. Buffering is not a
  crash; absent telemetry is not proof of a crash-free app.
  Flutter exception capture does not cover every native process crash.
  Session recording is currently off. No replay is fabricated or enabled.
  The issue link opens available PostHog event context.
  Loading/playback timing shows sample counts, median and p95 by app/platform:
  video startup, initial buffering, buffering during playback, source-line
  resolution and Admin function requests. Startup finishes when the player
  reports a first frame or advancing media time; it is not a visual measurement
  from the user's screen. Initial buffering is separate from mid-playback stalls.
  Paused/background time is excluded from native recovery guards. Only new
  clients with measured duration properties contribute to these timing rows;
  older events do not become zero-duration samples. Missing timing is shown as
  no data or unavailable, while the existing error counts stay visible. This
  optional query does not require reconnecting an existing query:read key.
- **Cloudflare**: account **a072aef61b3053983e84755527ef8f39**,
  Worker **football-public-api**. Create an account-scoped API token with
  **Account Analytics: Read**. Requests, runtime errors, subrequests and CPU/
  wall-time p50/p99 are fetched from GraphQL. CPU and wall time are converted
  from microseconds to milliseconds. Runtime errors are not HTTP 4xx/5xx counts.
  HTTP status/endpoint/upstream logs require Workers Logs and remain in the
  linked Worker dashboard; the monitor does not report invented zeros.
- **Vercel**, optional: project **nca-network-backup-test**, NCA team. The token
  must have access to that team/project. The ChatGPT connector currently returns
  403 for this team; the app connection is separate. The adapter reads recent
  production deployment states and commit/time details. Runtime logs open in
  the Vercel dashboard, subject to plan/account access.
- **Google Drive**, optional: supply an archive folder ID and OAuth JSON with
  client_id, client_secret and refresh_token, authorized with at least
  drive.metadata.readonly for the folder. Recent archive metadata is read from
  Drive. It is not a live error monitor. Copy the summary/CSV and save the report
  to your folder. No automatic Drive upload is performed.

Missing connections show **NOT CONFIGURED**. Denied access and timeout/rate-limit
failures are distinct from successful queries returning zero events. Collection
time and cached state are displayed. Queries refresh only while the tab/app is
visible, with one request at a time. Other providers use a one-minute server cache.

## Backend and security

The system-monitor Supabase Edge Function is an authenticated Admin-only API.
Supabase Auth /user verifies each JWT. The current profiles.role is rechecked
using the caller's RLS context before server credentials are used. User-editable
metadata is never used for authorization.

Provider secrets are AES-GCM encrypted with a random nonce and provider-specific
authenticated data. A key derived from the server-only service-role credential
encrypts them. Rotating that credential requires reconnecting providers. The
credential/cache tables are inaccessible to anon and authenticated through REST.
Only the Edge Function returns whitelisted summaries. The save RPC is security
invoker, executable only by service_role, and replaces credentials/cache atomically.

The Cloudflare/Vercel allowlists include system-monitor, preserving the VPN-free
route. The app sends its existing Admin JWT. No privileged provider key is
embedded in APK/Web JS. Provider endpoints are fixed and IDs validated.

Deploy migration 20261009043306_admin_system_monitor.sql and the system-monitor
Edge Function before Admin. Gateway JWT verification is disabled for compatibility
with current signing keys; the function itself verifies Auth and Admin role.
Anonymous access is denied.

## Validation

Node security tests cover missing/forged sessions, current non-Admin roles,
sanitized data, encryption, wrong scopes/ingest keys, stale reads, tamper/provider
swap rejection and stale/repeated stream failures. Flutter tests cover hidden-tab
requests, counts/unconfigured states, polling disposal and sanitized exports.
The timing expansion has its own PageStorage key so scrolling or refreshing
after connecting PostHog cannot overwrite the parent list's scroll position.
Existing player, HLS/DASH and relay regression checks remain in CI.
