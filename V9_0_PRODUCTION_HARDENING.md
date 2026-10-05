# V9.0 production hardening

Implemented:
- Viewer fallback chain: Supabase -> optional public API -> safe GitHub mirror.
- GitHub mirror no longer stores ClearKey data, Referer/Origin headers, WebView URLs, or protected stream lines.
- Added a Cloudflare Worker scaffold for a fresh sanitized public match API.
- Existing HLS-first ordering and player line failover remain enabled.
- stream-health Edge Function now supports one-link, match-wide, and cron/bulk checks.
- Admin Live Links shows health + latency and adds TEST ALL / per-server checks.
- Added stricter RLS migration so public stream-link reads require an active published match.

Still requires platform deployment:
- Deploy the updated stream-health Edge Function.
- Run supabase/upgrade_v9_hardening.sql.
- To use Cloudflare fallback, deploy cloudflare/public-api and build with PUBLIC_API_BASE.

No service-role/API-Football/cron secret is added to GitHub.
