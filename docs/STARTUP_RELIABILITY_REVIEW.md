# Web and APK startup review — 2026-10-08

Reviewed the current `main` revision `a678f017ca826acd3489c0561e50e83a108433e9`, including the latest iPhone line/quality controls, Viewer and Admin startup, public API metadata, connected Supabase configuration, and build workflows.

## Confirmed problems fixed

- Viewer waited for optional backend, saved theme, and analytics setup before rendering. It now renders immediately, then completes that setup in the background. Delayed theme loading cannot overwrite a selection made by the user.
- Admin now displays connection progress and a retryable timeout/error instead of holding back the entire app until backend initialization completes. Restored sessions still require an admin role; that check has a deadline.
- Live and source-tab refreshes could lose visible matches or throw an unhandled future error. Requests now coalesce and preserve the last successful list on failure. A successful empty response still clears old matches.
- Default builds tried only the first live API domain. They now use the configured live backup domains when necessary, without enabling the optional stale mirror fallback.
- Back during line loading could dismiss the spinner and later pop the page beneath it. Loading now owns its dialog route; cancellation prevents the chooser from opening. All-failed requests show retry guidance instead of pretending there are no lines.
- Successful `streams: []` now corrects the card's advertised count to zero. A failed request preserves the count rather than marking configured streams unavailable.
- Failed APK downloads no longer risk popping another page. The progress dialog owns its route and duplicate downloads are blocked. The existing body idle timeout and SHA-256 verification remain in place.
- Admin edit loading errors now show Retry. Reload callbacks no longer return a Future from `setState`.
- A failed match-count query could yield HTTP 200 with zero playable lines. Nonempty matches now require a successful count response; matches and counts load in parallel. JSON deadlines include body consumption. Empty matches remain authoritative.
- The Supabase relay health probe now uses Auth health and requires success. The REST root can reject valid publishable keys and is unsuitable for this health check.
- Web builds host their rendering assets with the app. The Viewer shows a lightweight startup shell and working Retry when bootstrap fails or is slow. Release IDs also stamp the compiled entrypoint, preventing a new bootstrap from loading an old cached `main.dart.js`.
- Worker CI preserves dashboard variables with `--keep-vars`.

## Validation

- 14 Viewer Flutter tests and 3 Admin Flutter tests passed.
- 38 existing Web player checks, 13 protected HLS/DASH checks, 6 relay checks, and 5 public-feed checks passed: 79 automated checks total.
- Flutter analysis found no errors or warnings; remaining findings are existing API deprecation notices.
- Viewer release Web compilation passed. The shared Safari/WKWebView player asset remains byte-identical to the reviewed revision; the user's latest playback and rotation controls are preserved.
- Real Chromium fault scenarios passed: primary API failure with a live backup, blocked external renderer CDN, versioned entrypoint loading, and bootstrap failure with Retry.
- All three configured live API domains returned HTTP 200 during read-only checks. Supabase RLS restricts direct stream-link access to admins. No database schema or policy was changed by this review.

Local first-frame measurements are not directly comparable with the public website because network and hosting conditions differ. Build success also does not prove long playback stability on a physical phone. This review used Chromium, Flutter widget tests, backend checks, and CI builds; it did not test every provider stream or a physical iPhone/Android device.

## Remaining priorities

1. **Stable Android signing for in-app updates.** The last successful APK workflow skipped publishing the updater manifest because the four signing secrets were absent. Configure `NCA_KEYSTORE_B64`, `NCA_KEYSTORE_PASSWORD`, `NCA_KEY_ALIAS`, and `NCA_KEY_PASSWORD` with the original signing key used by existing installations. A different key cannot update those APKs in place.
2. **Provider availability.** Recent backend logs included HTTP 500 responses from `soco-links`. This is separate from rendering/player startup. Reproduce a specific failing line and inspect the provider response before changing working playback logic; provider/network failures can still interrupt a stream.
3. **Database performance as link volume grows.** The advisor reports an unindexed `stream_links.match_id` foreign key. Measure relevant queries before adding a targeted index. The public count view intentionally exposes counts while underlying stream links stay private; its security-definer advisor finding is not by itself proof of leaked stream URLs.
4. **CI and dependency maintenance.** Avoid full Web builds for timestamp-only feed updates where freshness publishing can remain intact. Plan dependency deprecation updates and reproducible version locking separately from this runtime fix.

Database indexing guidance: <https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys>.
