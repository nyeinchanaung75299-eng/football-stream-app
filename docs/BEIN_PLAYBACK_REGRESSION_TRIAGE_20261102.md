# NCA beIN playback regression diagnosis — Nov 2 2026

## Observations
- User reports beIN channels were playable the previous day and now fail after an update.
- Player PR #108 restored pre-#106 Web player; real-device report still times out. A successful rollback/deploy is **not** the same as working playback.
- The beIN database entries have not changed since the merge, but stale last-checked health records only indicate the first bytes were previously reachable.
- These facts do **not** prove the DRM has changed. Confirm whether failure occurs in the protected proxy response, manifest retrieval, or actual media playback before changing source or DRM settings.

## This PR
1. **Admin reachability UI:** differentiate initial-byte `REACHABLE` from media playback, and mark missing/older-than-two-hour checks `STALE`. Never present old stored healthy as current evidence of playable video. No DB changes.
2. **Player UX:** replace misleading “A compatible HLS line is needed” for any failed DASH attempt with a neutral “No other working line” message, preserving existing playback and recovery logic. Sync generated shared player.
3. **Cloudflare observability:** log only safe HTTP status, request phase (manifest/segment), known stream-type class and error category when proxy requests fail. No upstream URL, encrypted token, DRM keys or request headers are logged. Response behavior unchanged.
4. Tests for freshness and accurate error presentation.

## Scope & safeguards
- **No attempt to bypass DRM, replay access controls or fetch new protected links.**
- No database mutation or changes to streaming credentials, player configuration, media headers or proxy URL rewriting.
- Do not merge until CI passes. After deployment, use sanitized proxy failure counts and real device tests to locate the fault.
- The root-cause playback fix remains **unconfirmed** until actual media successfully starts.
