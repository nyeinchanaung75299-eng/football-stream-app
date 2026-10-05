# V9.1 production reliability

Repository changes:

- GitHub mirror is now metadata-only. It stores no stream URL, ClearKey data,
  Referer/Origin headers, or WebView URL.
- Cloudflare fallback API now exposes /health, metadata-only /matches, and
  on-demand /matches/:id/streams for safe direct public lines.
- Viewer resolves fallback stream lines on demand instead of storing them in
  GitHub.
- Build workflows accept the PUBLIC_API_BASE repository variable.
- Added a manual Cloudflare deploy workflow.
- Added an automatic stream-health workflow scheduled every 10 minutes. It
  activates after SUPABASE_CRON_SECRET is added as a GitHub repository secret.
- Added Supabase CLI config so stream-health and football-score-sync can use
  their own admin/cron authentication without gateway JWT verification.
- HLS-first ordering and player line failover remain enabled.

Still requires account-side setup:
1. Deploy the updated Supabase functions/config.
2. Add SUPABASE_CRON_SECRET to GitHub if scheduled health checks are wanted.
3. Deploy the Cloudflare Worker, set PUBLIC_API_BASE, then rebuild Viewer.
