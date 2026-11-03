# NCA Viewer Cloudflare mirror

`https://nca.nyeinchanaung.us.ci/` is the VPN-free alternate entry point for
the Viewer. The Worker fetches the deployed GitHub Pages files at the edge, so
clients do not need a direct connection to `github.io`.

The root path maps to `/football-stream-app/`. Static assets keep that base
path so the same Flutter Web build and service worker work on both hosts.
