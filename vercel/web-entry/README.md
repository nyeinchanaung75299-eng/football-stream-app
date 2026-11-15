# NCA web entry

A static Vercel CDN entry for the existing Viewer and Admin builds on GitHub Pages.
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

Validation: verify Viewer/Admin HTML, versioned bootstrap, compiled main bundle,
local CanvasKit/WASM and cache headers; perform a fresh browser startup with the
original GitHub Pages hostname blocked on the client. Physical phone VPN-off
startup must be confirmed separately from this controlled browser test.
