# Failure-only video relay

Viewer 9.8.10 starts protected event video on the owned Cloudflare route. Original
direct provider URLs remain unchanged. Only a real player failure or an eight
second initial no-progress deadline switches that same line to the nca25 Vercel
relay. The normal Vercel startup and recovery deadlines then apply.

The opaque token, query, headers and explicit per-line keys are preserved. No
upstream URL is decoded or exposed. Incoming fallback metadata is discarded;
only the existing allowlisted protected route can generate a fallback. The route
is internal to a selectable line and never adds a duplicate chooser row.

Android Media3, browser playback and native iOS retain their selected route for
that line during the play session. A new session tries Cloudflare again, allowing
a newly enabled VPN to reduce Vercel transfer. A paused/backgrounded player keeps
its existing lifecycle handling. When both routes fail, normal real-line fallback
continues. Closed sessions and stale playback callbacks cannot restart a route.

Channels retain their existing policy: normal playback excludes Vercel; the
explicit Try another connection action uses Vercel for that play attempt.
Metadata/link extraction requests keep their existing routing and still incur
small Vercel requests. This change reduces video transfer when Cloudflare works;
it cannot reduce relay transfer on a network where only Vercel is reachable.
The static website CDN entry stays in place. No automatic VPN detection or paid
service is required. Admin 2.5.15 is rebuilt with the existing functionality and
signing continuity checks.

Validation: 130 Viewer tests, 153 Admin tests, 66 shared Web player checks, native
source-session checks and existing performance guards pass locally. The Web suite
also covers a failing active route and stale decoder events (67 checks total).
Analyzer findings are existing informational deprecations. Real ColaTV HLS video
advanced five seconds at 1280x720 in both browser scenarios: healthy Cloudflare
made 12 media requests and zero Vercel media requests; a blocked Cloudflare route
fell back to Vercel and continued playing. These are controlled browser tests,
not a physical phone VPN comparison or an overall billing percentage.
