# NCA Telegram bots: secure setup

Bot usernames:
- Public Viewer: https://t.me/NCAFootballViewer_bot
- Private Admin: https://t.me/NCAPrivate_bot

**Status:** source code and tests only until private credentials are configured through your own secret manager. No token or password is required in a chat message, GitHub issue, pull request, or public URL.

## Implemented (read-only)

- Viewer: /start, /today, /live, /schedule, /channels. Uses published football match metadata from NCA Supabase; no playback credentials.
- Private Admin: /whoami, /start, /health, /status, /bein, /build and beIN channel buttons. Reads safe channel names, EPG IDs, stream *types* and health counts; never sends MPD URLs, key IDs, key data, referers, license URLs, service credentials or bearer tokens.
- Admin accepts only private chats from a numeric Telegram user ID on a server-side allowlist. /whoami alone displays the caller's own ID to help pair.
- Telegram webhook secret is checked on every POST. Supabase gateway JWT verification is disabled only for these bot endpoints, because Telegram sends a separate webhook secret.
- No database mutations from these commands.

## Configure secrets in Supabase Dashboard

Open Supabase Dashboard > project woggzixprvyjnfjzsglz > Edge Functions > Secrets. Add:

1. TG_VIEWER_BOT_TOKEN — BotFather token for @NCAFootballViewer_bot
2. TG_VIEWER_WEBHOOK_SECRET — a unique random string of letters, digits, underscores or dashes
3. TG_ADMIN_BOT_TOKEN — BotFather token for @NCAPrivate_bot
4. TG_ADMIN_WEBHOOK_SECRET — a DIFFERENT unique random string
5. TG_ADMIN_USER_IDS — comma-separated numeric Telegram user IDs allowed to use the Admin bot

The Edge Functions use existing server-only SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. NEVER put the service-role key or any of the five secrets in Flutter Web, GitHub source files, or Telegram messages.

For first-time pairing, configure the four bot tokens/secrets, deploy both functions and register webhooks, then privately send /whoami to @NCAPrivate_bot. Copy the numeric ID from your *own Telegram chat* into TG_ADMIN_USER_IDS. The bot responds to /whoami even before allowlisting.


## One-click setup from the Admin website (recommended)

After saving the four BotFather/webhook secrets to Edge Functions Secrets:

1. Open https://nyeinchanaung75299-eng.github.io/football-stream-app/admin/ and sign in as an authorized Admin.
2. From **Controls**, scroll to **Telegram Integration → Connect Telegram Bots**.
3. Tap **CONNECT TELEGRAM BOTS**. The server verifies your Supabase session, checks `profiles.role = admin`, privately verifies both BotFather usernames, then registers both Telegram webhooks. No token is sent to your browser or to GitHub.
4. Open @NCAFootballViewer_bot and send `/start`.
5. Open @NCAPrivate_bot and send `/whoami`. Add the returned *numeric user ID* as `TG_ADMIN_USER_IDS` in Supabase Secrets (not the username or chat link). Then send `/health` or `/bein`.
6. If the connection reports a missing/invalid secret, review the four saved secret names, check that webhook secret values are **different random 32–128 character strings** (not names of other secrets), and repeat the button.

Connection uses a separate `telegram-connect` Edge Function, accessible only after a validated NCA Admin session and role lookup. The Vercel Supabase relay passes the existing Admin JWT unchanged. It does not grant Admin access based on a Telegram username. The connect action is safe to repeat.

## Deploy and register

Deploy the two functions via CLI or the Supabase Dashboard:
- supabase functions deploy telegram-viewer --project-ref woggzixprvyjnfjzsglz --no-verify-jwt
- supabase functions deploy telegram-admin --project-ref woggzixprvyjnfjzsglz --no-verify-jwt

From a trusted local device, use scripts/register_nca_telegram_webhooks.mjs with all four TG_..._BOT_TOKEN and TG_..._WEBHOOK_SECRET environment variables set privately. The script registers both HTTPS webhook URLs using Telegram Bot API setWebhook and prints only status, never tokens.

Validate:
- Viewer: /start, /today, /live
- Admin: /whoami; update allowlist; /start, /health, /bein, /build
- Test a different Telegram account: private Admin metadata must not be returned.

Use Telegram getWebhookInfo to troubleshoot if necessary. NEVER paste tokenized Bot API URLs into chat/screenshots.

## Not implemented yet

Automatic match push alerts, viewer subscription storage and daily scheduled reports are NOT enabled yet. They need explicit viewer opt-in, de-duplication, scheduling and rate limits. Do not claim notifications are live until those parts pass end-to-end tests. Current first phase is interactive, read-only bots.

GitHub Pages, Vercel-first public APIs, existing Admin roles and 169 TV channels stay unchanged.
