# NCA performance optimization review (2026-11-02)

This branch is a conservative, **not yet deployed** improvement based on
production observations and a code audit. It does not merge the separate
SportScore test PR #105 and does not change Cola TV's upstream data source.

## Observed baseline

These are *one-off event aggregates*, not controlled comparisons.

| Recorded event, past 7 days | Sample size | P50 | P95 |
| --- | ---: | ---: | ---: |
| Web playback started (startup_ms) | 71 | 4,153 ms | 13,810 ms |
| Android playback started | 77 | 1,527 ms | 9,019 ms |
| Web match feed loaded | 148 | 1,272 ms | 3,607 ms |
| Android match feed loaded | 73 | 1,478 ms | 3,064 ms |

Supabase 24-hour function logs showed `soco-links` with 40 HTTP 500
responses from 1,129 calls; this branch does not claim to fix provider errors.

## Implemented

1. **Home list:** speculative protected-line metadata lookups reduced from six
   to two. They start after a short delay and do not launch while the player
   is opening. A WATCH tap still performs the authoritative live lookup.
2. **Backup requests:** slightly longer metadata source hedges (600 ms for
   featured matches; 650 ms for source-browser authoritative requests).
   Failover remains enabled; emergency mirror hedging retains 300 ms.
3. **Short metadata cache:** eight-second process-local cache and in-flight
   sharing by source for public source-match metadata only. A manual refresh
   bypasses it. Do not use it for playback URLs, auth sessions, DRM keys or
   stream selection. Server-side match/stream responses retain their original
   freshness and no-store rules.
4. **Web player:** initialize Shaka polyfills / capability checks only once,
   not on every line switch. Preserve all existing buffer, DRM and recovery
   settings. Record per-attempt engine/attach/manifest timings, plus actual
   first decoded frame when supported by the browser.
5. **Web entry:** measure elapsed time to Flutter's first rendered frame,
   with a separate error-stage report.
6. **Maintenance:** run independent stale-match and expired-link cleanup in
   parallel. Routine stream health recheck eligibility changes from ten
   minutes to fifteen; batch maximum from 16 to 12. Admin `force` still
   overrides the age requirement, not the bounded batch size.
7. **Verification:** shared iOS player regenerated; Node syntax and
   performance-guard checks added to CI; separate read-only PR test workflow
   added for Flutter analyze/test.

## Existing optimizations intentionally retained

- Player engine prewarm while the line chooser is open.
- Adaptive bitrate already enabled for Shaka playback; changing player
  buffer goals without a network A/B test risks more rebuffering.
- In-flight coalescing in the Cloudflare public worker.
- Five-minute last-known-good public API host ordering.
- Existing expiring URL checks, failovers, playback watchdogs and database
  protection.
- No blanket caching of public featured matches: stale deletion/zero-stream
  metadata must remain authoritative.

## Before production

1. PR CI passes (Node shared-player + existing player tests, Flutter analyze,
   Flutter widget tests).
2. Real-device Web DASH startup and Android playback tested on both good and
   restricted mobile networks. Verify first-frame, buffering, failed-line
   count and source quality are not worse than baseline.
3. Manually edit/remove a published stream and ensure the Viewer never
   resurrects a removed link.
4. Check source-browser hard refresh bypasses short cache.
5. Inspect `soco-links` 500s with provider traces separately. These are
   not removed by reducing frontend duplicate requests.
6. If rollout slows blocked networks, revert the hedge delay changes first,
   then prefetch-count change.

**No performance gain is guaranteed until real-world comparative tests.**
