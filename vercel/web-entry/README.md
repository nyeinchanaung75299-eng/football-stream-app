# NCA web entry

A static Vercel CDN entry for the existing Viewer and Admin builds on GitHub Pages.

Production entrypoints:

- Viewer: https://nca25-web.vercel.app/
- Admin: https://nca25-web.vercel.app/admin/
The phone connects to this Vercel origin for HTML, Flutter JavaScript, local
CanvasKit/WASM, fonts and player assets. Vercel fetches the fixed public Pages
origin server-side; it never accepts a caller-supplied destination.

The `/football-stream-app/` prefix is preserved so Flutter base URLs, Admin
assets, cache stamps, same-origin mirrors and release metadata keep working.
Root and `/admin/` shortcuts redirect to their respective entrypoints. The CDN
respects the upstream public asset caching policy; versioned bootstrap and main
bundle queries continue to carry the build stamp.

There are no Functions, runtime dependencies, database credentials or Admin
sessions in this project. Source API and video routing remain in the existing
app build and `nca25-live-relay` project. Static delivery still consumes Vercel
request/transfer quotas. New Pages releases appear through the same entry after
normal cache revalidation; this project requires no Flutter rebuild.

Validation on 2026-11-15: fresh Chromium contexts with the original GitHub
Pages hostname and owned Cloudflare API hosts blocked reached the Viewer first
frame in 3382 ms and the Admin login first frame in 2921 ms. Both loaded HTML,
bootstrap, compiled main bundle, local CanvasKit/WASM and fonts with HTTP 200
and no browser errors. Root and Admin shortcuts resolved successfully. These
are controlled connection measurements, not physical phone timings or a check
of authenticated Admin mutations.

A normal asset GET returned `Cache-Control: max-age=600`; the observed
`x-vercel-cache` values were `MISS`, so a Vercel cache hit has not been established.
Physical phone VPN-off startup must be confirmed separately.
