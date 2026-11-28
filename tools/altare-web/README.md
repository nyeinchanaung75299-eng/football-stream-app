# NCA Viewer Web on Altare

This project serves the published Flutter Viewer Web build from its own static
assets. It downloads the GitHub release bundle once per build and verifies the
size, SHA-256 and source commit before installing it. Update the two Git refs in
`release.json` when you want to deploy a newer published Viewer Web bundle.

| Altare App Hosting field | Value |
| --- | --- |
| App name | `nca-viewer-web` |
| GitHub repository | `nyeinchanaung75299-eng/football-stream-app` |
| Branch | `altare-web` |
| Root directory | `tools/altare-web` |
| Runtime | Node.js 24 |
| Install command | `npm ci` |
| Build command | `npm run build` |
| Start command | `npm start` |
| Health-check path | `/health` |

The app binds to `0.0.0.0` using Altare's `PORT`. It requires outbound
HTTPS to GitHub at build time. Start it locally with the same commands and
open `http://localhost:3000/`.

Check the deployed URL on ATOM with VPN disabled before giving it to viewers.
Each visit through the Altare URL serves the Viewer shell, JS, WASM, fonts, and
other bundled assets from Altare. The compiled app uses its existing API and
playback endpoints. Compare Web delivery usage for `nca25-web` and relay usage
for `nca25-live-relay` individually after directing viewers to the new URL.
