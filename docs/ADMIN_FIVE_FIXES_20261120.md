# Admin five fixes — 2.5.25 / Viewer 9.8.14

1. Store/edit original team logo URLs. Recognized legacy team-logo relay URLs
   are converted to their original Sofascore URL; image delivery still uses the
   independent gateway and existing failover. Migration preserves source names,
   custom badges, line credentials and deletion state.
2. Remove dependency READ_MEDIA / external-storage permissions from both final
   APKs via manifest-merger removal rules. Keep INTERNET, network state and
   REQUEST_INSTALL_PACKAGES for the existing private-cache signed APK updater.
   Developer-verification and installer warnings can still appear.
3. Repository line menu adds Telegram sharing. Whole-match sharing includes a
   selectable preview, copy and text-file export. Existing available URL,
   Referer/Origin and ClearKey fields are retained; unrelated row/account fields
   are excluded. Telegram chat selection and Send remain user actions. Large
   messages use a file without truncation; browser file-share/download fallback
   and manual copy stay available. No new backend relay or bot is used.
4. Ordinary Live Links text fields retain autocorrect off, with suggestions
   enabled to avoid Flutter's Android VISIBLE_PASSWORD flag and OEM secure IME.
5. Passive all-frame resource observation handles late iframe media requests.
   Top-document identity and active frame membership reject stale reports;
   native requests retain their actual public Referer/Origin. Restored resource
   callback rescans only the current document. Repeated passive observations do
   not postpone quick-select quiet timers. Unverified/MSE/ambiguous candidates
   remain available for manual selection; live verification is still required
   for automatic selection. No cookies, session secrets or media segments are
   extracted by the observer.

Validation includes full Admin and Viewer Flutter suites, targeted clock-free
resource session tests, Node resource observer tests, controlled Chromium
cross-origin iframe capture/detachment, small-phone sharing layout, Android
manifest transformation and final APK permission gates, disposable Postgres
migration/RLS/import/backfill tests, static analysis and release signing gates.

The real PlayerBee URL `/charlie/bayern-munchen-vs-koln/3757` is a published
CricHD Watch link. Its Cloudflare verification did not complete in the cloud
browser. Controlled browser coverage is not a physical Android/PlayerBee success
claim. Real phone keyboard switching, Telegram delivery and that protected
player must be checked on the updated Admin APK.
