# Review fixes

This change addresses the review of `70f2a95`. It is intended for review and
testing before production release.

| Area | Result |
| --- | --- |
| Last stream deleted | Successful empty/count-zero responses revoke cached lines; failed requests retain fallback behavior. |
| Web/iOS recovery | Recoverable or handled Shaka errors preserve playback; critical errors and the stall watchdog still trigger recovery. |
| Player Back | Exits browser/native fullscreen and releases the orientation lock. |
| Big Match publish | An Admin-only transaction validates and publishes the complete selection before replacing the previous featured set. Failed batches roll back; deletion tombstones stay deleted. |
| Admin visibility | All includes non-deleted inactive, draft, and unfeatured matches. |
| DASH paths | Resolves nested BaseURL ancestry and root/parent-relative segments through authenticated proxy references. |
| Admin stream editing | Pending queries hide old actions; active native/WebView lines require valid HTTP(S) URLs. |
| Android selection | Manual line selection cancels queued fallback; old-player callbacks cannot overwrite the new selection. |
| Admin sessions | Restored/new sessions require a current Admin role before showing the dashboard. |
| Source destinations | Cached target queries preserve presets while loading. |
| APK installer | Download body stalls time out; cancel/back stops the request and removes incomplete files. |
| Fixture deduplication | Preserves Unicode team names and uses provider IDs when names are missing. |
| Health checks | Filters due links before limiting and checks null/oldest timestamps first. |
| Setup | Bootstrap and additive migration include deleted_at; Worker example uses src/index.js. |
| Cleanup | Removes legacy PlayerPage, unused helpers/constants, and the unused KV binding declaration. |

The embedded iOS player asset, current source endpoints, dependencies,
historical migrations, status.json freshness logic, and maintenance-only
football-score-sync remain. The KV namespace and its data are untouched.
Timestamp-only Web rebuild optimization is deferred.

## Release order

1. Apply `supabase/migrations/20261006194419_publish_featured_fixtures_atomically.sql`.
2. Deploy the changed football-fixtures and football-score-sync Edge Functions.
3. Deploy the Worker with its existing secrets.
4. Release the Admin and Viewer APK/Web builds.

The new Admin app calls the RPC and must not ship before its migration. These
steps have not been applied to production by this review branch.

## Verification

```bash
python3 scripts/generate_embedded_player.py --check
node scripts/test_web_player.mjs
node scripts/test_protected_dash_proxy.mjs
node scripts/test_supabase_relay.mjs
node scripts/test_public_gateway.mjs
node scripts/test_backend_regressions.mjs
```

`scripts/test_atomic_publish.sql` and `scripts/test_atomic_publish_concurrency.py`
must run only against a disposable database named `football_backend_test`.
They test authorization, rollback, concurrent replacement, and concurrent
soft deletion. The regression workflow provisions PostgreSQL 17 for this.

Run `flutter analyze --no-fatal-infos` and `flutter test` in both app directories.
The APK workflow additionally compiles Android and the iOS simulator target.
Playback on physical Android/iOS devices remains a release validation step.
