# NCA Telegram bots: secure setup

Bot usernames:
- Public Viewer: https://t.me/NCAFootballViewer_bot
- Private Admin: https://t.me/NCAPrivate_bot

The deployed bots require private credentials configured through your secret manager. Never put a token or password in chat, GitHub issues, source code, or a public URL.

## Implemented

- Viewer: /start, /today, /live, /schedule, /channels. Uses published football match metadata from NCA Supabase; no playback credentials.
- Private Admin: /whoami, /start, /health, /status, /bein, /build and beIN channel buttons. Reads safe channel names, EPG IDs, stream *types* and health counts; never sends MPD URLs, key IDs, key data, referers, license URLs, service credentials or bearer tokens.
- Admin accepts only private chats from a numeric Telegram user ID on a server-side allowlist. /whoami alone displays the caller's own ID to help pair.
- Telegram webhook secret is checked on every POST. Supabase gateway JWT verification is disabled only for these bot endpoints, because Telegram sends a separate webhook secret.
- Private Admin management actions require its allowlist and confirmation.
- Viewer Today/Live/Schedule queries apply the time window before pagination. Each match has a Watch link and an explicit **Remind me** action; `/reminders` manages subscriptions and `/unsubscribe` cancels them.
- Channel options in Viewer include **Report broken line**, opening the Viewer bot to choose a line and confirm. Reports are visible in Admin **Health → flag icon** and private bot `/reports`.
- Both webhooks lease `update_id` in server-only storage. Completed updates are acknowledged without repeating commands; failed deliveries can retry.

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

## Reminder delivery and retention

Apply migration `20261106205045_channel_health_and_viewer_tools.sql` before deploying these bot functions. It schedules a once-per-minute Viewer reminder pulse, authenticated by its own private Vault secret. Up to 20 due reminders are handled per pulse, with a delivery lease and retry; blocked chats are unsubscribed. Telegram timeouts can have ambiguous delivery outcomes, so notifications use at-least-once delivery. Viewers must choose each match; there is no automatic mass subscription.

Reminders are sent approximately ten minutes before kickoff, subject to scheduler and Telegram availability. Subscribing within ten minutes schedules the next available pulse. Watch links bring the selected published match to the top of the Viewer; playback still requires a tap.

Update records and old reminders expire after seven days; line reports after 30 days. Only channel IDs are stored locally for Viewer favorites/recent channels. No playback URLs or keys are included in reports, reminders, or browser history storage.

Private Admin channel/readiness alerts remain separate from Viewer reminders. Daily Viewer digests are not implemented. GitHub Pages and existing VPN/non-VPN routing are preserved. The verified catalog currently contains 169 channels and 169 lines.
