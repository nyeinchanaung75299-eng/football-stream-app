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
   to two. A cancelable 900ms timer defers them until after first render,
   cancels on page disposal/refresh and skips while the player is opening.
   WATCH always performs the authoritative live lookup.
2. **Backup requests:** retain the original 400ms featured-match and 300ms
   source-browser hedges. Tests showed delaying them can change fallback
   behavior under restricted networks, so duplicate-request reduction should
   rely on the Worker’s existing in-flight coalescing instead.
3. **Metadata freshness:** trial 8-second source cache was removed after
   Flutter tests proved that it can incorrectly keep matches after a
   successful empty update. Preserve the authoritative empty response and
   existing public EPG cache; do not cache stream URLs, auth sessions or keys.
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

## Deeper follow-up: measured phases and source failures

The 7-day Web DASH startup median was ~4.15 seconds (P95 ~14.03
seconds; 65 playback-start events). This measures **player startup after source
selection**, not user WATCH tap to video. Engine-loading substage telemetry had
only one example in that baseline; do not attribute the delay to engine
downloading alone.

Additional instrumentation now measures:

- Home WATCH tap -> protected line list resolved (`stream sources loaded`,
  `resolution_ms`) and line-selection duration (`stream selected.chooser_ms`).
- Web playback started -> engine, attach, and manifest timings, with actual
  video frame timing where supported.
- Web playback failures -> `attempt_ms`, including slow startup timeouts that
  successful-playback averages omit.
- Initial Web navigation -> Flutter first frame (`viewer web startup.elapsed_ms`)
  plus HTML request TTFB, instead of starting the clock after HTML parsing.

Also bounded the **Fawa** fallback path to a shared 13.5-second budget
and maximum five seconds per attempted Fawa origin: previously three sequential
10-second origin timeouts could outlast the 16-second public API caller.
The prior fallback order remains unchanged. The `soco-links` function now logs
only a sanitized source/action/failure category and returns generic 502
provider errors; it never logs private upstream stream URLs or keys. It does
not automatically retry or mask failed providers.

Provider error logs and the new metrics have not yet been measured in
production. Some changes are instrumentation, not guaranteed speed gains.

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
4. Verify a successful empty source response clears the previous match list
   immediately (the abandoned short-cache experiment failed this test).
5. Inspect `soco-links` 500s with provider traces separately. These are
   not removed by reducing frontend duplicate requests.
6. If rollout slows blocked networks, revert the speculative prefetch
   change first; all original source-hedge delays are preserved.

**No performance gain is guaranteed until real-world comparative tests.**
