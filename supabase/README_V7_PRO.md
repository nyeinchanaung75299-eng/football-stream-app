# Supabase V7 Pro source

This folder is intentionally included in the GitHub package.

Included:
- `functions/football-fixtures/index.ts`
- `functions/football-score-sync/index.ts`
- `functions/stream-health/index.ts`
- schema and upgrade SQL files

Important:
- The GitHub APK workflow builds the Flutter apps only.
- Deploy/configure Supabase functions separately when ready.
- Never commit API_FOOTBALL_KEY, CRON_SECRET, SUPABASE_SERVICE_ROLE_KEY, or other private secrets.
